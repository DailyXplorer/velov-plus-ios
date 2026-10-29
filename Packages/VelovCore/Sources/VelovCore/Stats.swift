import Foundation

public enum StatsRules {
    public static let detourFactor = 1.3
    public static let co2GramsPerKm = 200.0
    public static let maxPages = 50
    static let top = 5
}

public enum StatsPeriod: String, CaseIterable, Sendable, Hashable {
    case days30 = "30d"
    case months12 = "12m"
    case all
}

public struct StatsBucket: Equatable, Sendable {
    public var key: String
    public var minutes: Int
    public var trips: Int
    public init(key: String, minutes: Int, trips: Int) { self.key = key; self.minutes = minutes; self.trips = trips }
}

public struct StationCount: Equatable, Sendable {
    public var name: String
    public var count: Int
    public init(name: String, count: Int) { self.name = name; self.count = count }
}

public struct DistanceEstimate: Equatable, Sendable {
    public var metres: Double
    public var known: Int
}

public struct BikeTypeCounts: Equatable, Sendable {
    public var mechanical: Int
    public var electrical: Int
    public var unknown: Int
}

public struct StatsRecords: Equatable, Sendable {
    public var longestMinutes: Int?
    public var busiestDayTrips: Int?
    public var streakDays: Int?
    public var bike: Int?
}

public struct PeriodStats: Equatable, Sendable {
    public enum Unit: String, Sendable { case day, month }

    public var trips: Int
    public var minutes: Int
    public var distance: DistanceEstimate
    public var co2Grams: Double
    public var spentCents: Double
    public var savedCents: Double
    public var pointsEarned: Double
    public var unit: Unit
    public var buckets: [StatsBucket]
    public var heatmap: [[Int]]
    public var bikeTypes: BikeTypeCounts
    public var stations: [StationCount]
    public var records: StatsRecords
}

public struct Stats: Equatable, Sendable {
    public var days30: PeriodStats
    public var months12: PeriodStats
    public var all: PeriodStats
    public var balance: Double?
    public var complete: Bool

    public subscript(period: StatsPeriod) -> PeriodStats {
        switch period {
        case .days30: days30
        case .months12: months12
        case .all: all
        }
    }
}

public struct StatsMovement: Equatable, Sendable {
    public var date: Date?
    public var amount: Double
    public init(date: Date?, amount: Double) { self.date = date; self.amount = amount }
}

public struct StatsInput: Sendable {
    public var trips: [Trip]
    public var coords: [Int: GeoPoint]
    public var movements: [StatsMovement]?
    public var balance: Double?
    public var now: Date
    public var complete: Bool
    public init(trips: [Trip], coords: [Int: GeoPoint], movements: [StatsMovement]?, balance: Double?, now: Date, complete: Bool = true) {
        self.trips = trips; self.coords = coords; self.movements = movements; self.balance = balance; self.now = now; self.complete = complete
    }
}

public func collectPages<T>(maxPages: Int = StatsRules.maxPages, id: (T) -> String, _ fetchPage: (Int) async throws -> [T]) async throws -> (items: [T], complete: Bool) {
    var items: [T] = []
    var seen = Set<String>()
    for page in 0..<maxPages {
        let batch: [T]
        do { batch = try await fetchPage(page) } catch {
            if page == 0 { throw error }
            return (items, false)
        }
        let fresh = batch.filter { !seen.contains(id($0)) }
        if fresh.isEmpty { return (items, true) }
        for item in fresh where seen.insert(id(item)).inserted { items.append(item) }
    }
    return (items, false)
}

public func estimateDistance(_ trip: Trip, coords: [Int: GeoPoint]) -> Double? {
    guard let start = trip.startStationNumber, let end = trip.endStationNumber else { return nil }
    if start == end { return 0 }
    guard let from = coords[start], let to = coords[end] else { return nil }
    return haversine(from, to) * StatsRules.detourFactor
}

private let paris = TimeZone(identifier: "Europe/Paris")!
private let french = Locale(identifier: "fr_FR")

private func calendar(_ zone: TimeZone) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar
}

private let parisCalendar = calendar(paris)
private let utcCalendar = calendar(TimeZone(identifier: "UTC")!)

public struct ParisTime: Equatable, Sendable {
    public var day: String
    public var month: String
    public var hour: Int
    public var weekday: Int
}

public func parisTime(_ date: Date) -> ParisTime {
    let parts = parisCalendar.dateComponents([.year, .month, .day, .hour, .weekday], from: date)
    let month = String(format: "%04d-%02d", parts.year!, parts.month!)
    return ParisTime(day: month + String(format: "-%02d", parts.day!), month: month, hour: parts.hour!, weekday: (parts.weekday! + 5) % 7)
}

private func utcDay(_ day: String) -> Date? {
    let parts = day.split(separator: "-").compactMap { Int($0) }
    guard parts.count >= 2 else { return nil }
    return utcCalendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts.count > 2 ? parts[2] : 1, hour: 12))
}

public func shiftDay(_ day: String, _ days: Int) -> String {
    guard let date = utcDay(day), let shifted = utcCalendar.date(byAdding: .day, value: days, to: date) else { return day }
    let parts = utcCalendar.dateComponents([.year, .month, .day], from: shifted)
    return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
}

public func shiftMonth(_ month: String, _ months: Int) -> String {
    guard let date = utcDay(month), let shifted = utcCalendar.date(byAdding: .month, value: months, to: date) else { return month }
    let parts = utcCalendar.dateComponents([.year, .month], from: shifted)
    return String(format: "%04d-%02d", parts.year!, parts.month!)
}

private func range(_ first: String, _ last: String, _ next: (String) -> String) -> [String] {
    var keys: [String] = []
    var key = first
    while key <= last {
        keys.append(key)
        key = next(key)
    }
    return keys
}

private func present(_ text: String?) -> Bool { !(text ?? "").isEmpty }

private func favouriteStations(_ trips: [Trip]) -> [StationCount] {
    var order: [String] = []
    var tally: [String: StationCount] = [:]
    for trip in trips {
        for (number, name) in [(trip.startStationNumber, trip.startStation), (trip.endStationNumber, trip.endStation)] {
            if number == nil && !present(name) { continue }
            let key = number.map { "#\($0)" } ?? name!
            if tally[key] == nil { order.append(key) }
            tally[key, default: StationCount(name: name ?? "Station \(number!)", count: 0)].count += 1
        }
    }
    return Array(order.enumerated().map { (offset: $0.offset, station: tally[$0.element]!) }.sorted { left, right in
        if left.station.count != right.station.count { return left.station.count > right.station.count }
        let order = left.station.name.compare(right.station.name, locale: french)
        return order == .orderedSame ? left.offset < right.offset : order == .orderedAscending
    }.map(\.station).prefix(StatsRules.top))
}

private func longestStreak(_ days: [String]) -> Int? {
    var best = 0
    var current = 0
    var previous: String?
    for day in Set(days).sorted() {
        current = previous.map { shiftDay($0, 1) == day } == true ? current + 1 : 1
        best = max(best, current)
        previous = day
    }
    return best > 0 ? best : nil
}

private func minutes(_ trip: Trip) -> Int { Int((trip.duration ?? 0).rounded()) }

public func periodStats(_ period: StatsPeriod, _ input: StatsInput) -> PeriodStats {
    let today = parisTime(input.now)
    let unit: PeriodStats.Unit = period == .days30 ? .day : .month
    let located: [(trip: Trip, at: ParisTime?)] = input.trips.filter { $0.status != "REVERSED" }.map { (trip: $0, at: $0.startedAt.map(parisTime)) }
    var firstMonth = today.month
    for item in located { if let at = item.at, at.month < firstMonth { firstMonth = at.month } }
    let start = switch period {
    case .days30: shiftDay(today.day, -29)
    case .months12: shiftMonth(today.month, -11)
    case .all: firstMonth
    }
    let keyOf = { (at: ParisTime) in unit == .day ? at.day : at.month }
    let inPeriod = located.filter { item in
        guard period != .all else { return true }
        guard let at = item.at else { return false }
        return keyOf(at) >= start
    }
    let trips = inPeriod.map(\.trip)

    let keys = unit == .day ? range(start, today.day) { shiftDay($0, 1) } : range(start, today.month) { shiftMonth($0, 1) }
    var buckets = keys.map { StatsBucket(key: $0, minutes: 0, trips: 0) }
    let bucketIndex = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($1, $0) })
    var heatmap = Array(repeating: Array(repeating: 0, count: 24), count: 7)
    var days: [String: Int] = [:]
    for (trip, at) in inPeriod {
        guard let at else { continue }
        if let index = bucketIndex[keyOf(at)] {
            buckets[index].trips += 1
            buckets[index].minutes += minutes(trip)
        }
        heatmap[at.weekday][at.hour] += 1
        days[at.day, default: 0] += 1
    }

    let distances = trips.compactMap { estimateDistance($0, coords: input.coords) }
    let metres = distances.reduce(0, +)
    var bikeOrder: [Int] = []
    var bikes: [Int: (count: Int, last: Date)] = [:]
    for trip in trips {
        guard let number = trip.bikeNumber else { continue }
        if bikes[number] == nil { bikeOrder.append(number) }
        var bike = bikes[number] ?? (0, .distantPast)
        bike.count += 1
        bike.last = max(bike.last, trip.startedAt ?? .distantPast)
        bikes[number] = bike
    }
    let bike = bikeOrder.max { (left: Int, right: Int) -> Bool in
        let a = bikes[left]!, b = bikes[right]!
        if a.count != b.count { return a.count < b.count }
        return a.last < b.last
    }
    let dated = (input.movements ?? []).compactMap { movement in movement.date.map { (key: keyOf(parisTime($0)), amount: movement.amount) } }
    let earned: Double = input.movements != nil
        ? dated.filter { $0.amount > 0 && (period == .all || $0.key >= start) }.reduce(0) { $0 + $1.amount }
        : trips.reduce(0) { $0 + $1.pointsEarned }

    let count = { (type: BikeType) in trips.filter { $0.bikeType == type }.count }
    let records = StatsRecords(longestMinutes: trips.compactMap { $0.duration }.max().map { Int($0.rounded()) },
                               busiestDayTrips: days.values.max(), streakDays: longestStreak(Array(days.keys)), bike: bike)
    return PeriodStats(
        trips: trips.count, minutes: trips.reduce(0) { $0 + minutes($1) },
        distance: DistanceEstimate(metres: metres.rounded(), known: distances.count),
        co2Grams: (metres / 1000 * StatsRules.co2GramsPerKm).rounded(),
        spentCents: trips.reduce(0) { $0 + max(0, $1.price ?? 0) }, savedCents: trips.reduce(0) { $0 + max(0, $1.discount) }, pointsEarned: earned,
        unit: unit, buckets: buckets, heatmap: heatmap,
        bikeTypes: BikeTypeCounts(mechanical: count(.mechanical), electrical: count(.electrical), unknown: count(.unknown)),
        stations: favouriteStations(trips), records: records)
}

public func buildStats(_ input: StatsInput) -> Stats {
    Stats(days30: periodStats(.days30, input), months12: periodStats(.months12, input), all: periodStats(.all, input),
          balance: input.balance ?? input.movements?.reduce(0) { $0 + $1.amount }, complete: input.complete)
}
