import Foundation

// lib/stats.ts: trip statistics, a pure aggregation of the whole history.

public enum StatsRules {
    /// Vélo’v gives no distance: the straight line between the two stations, lengthened for the streets.
    public static let detourFactor = 1.3
    /// Order of magnitude for a petrol car in town, in grams of CO₂ per km.
    public static let co2GramsPerKm = 200.0
    public static let maxPages = 50
    static let top = 5
    static let durationBuckets: [(label: String, max: Double)] = [("0-5", 5), ("5-10", 10), ("10-20", 20), ("20-30", 30), ("30+", .infinity)]
}

public enum StatsPeriod: String, CaseIterable, Sendable, Hashable {
    case days30 = "30d"
    case months12 = "12m"
    case all
}

public struct StatsBucket: Equatable, Sendable {
    /// "2026-10-29" or "2026-10".
    public var key: String
    public var minutes: Int
    public var trips: Int
    /// The points balance at the end of the bucket; nil without the points history.
    public var balance: Double?
    public init(key: String, minutes: Int, trips: Int, balance: Double?) { self.key = key; self.minutes = minutes; self.trips = trips; self.balance = balance }
}

public struct StationCount: Equatable, Sendable {
    public var number: Int?
    public var name: String
    public var count: Int
}

public struct PairCount: Equatable, Sendable {
    public var from: String
    public var to: String
    public var count: Int
}

public struct DurationCount: Equatable, Sendable {
    public var label: String
    public var count: Int
}

public struct DistanceEstimate: Equatable, Sendable {
    /// Sum over `known` trips; `unknown`: no station, or a station no longer in the open data.
    public var metres: Double
    public var known: Int
    public var unknown: Int
}

public struct BikeTypeCounts: Equatable, Sendable {
    public var mechanical: Int
    public var electrical: Int
    public var unknown: Int
}

public struct StatsRecords: Equatable, Sendable {
    public struct Longest: Equatable, Sendable { public var minutes: Int; public var startedAt: Date?; public var from: String?; public var to: String? }
    public struct BusiestDay: Equatable, Sendable { public var day: String; public var trips: Int; public var minutes: Int }
    public struct Streak: Equatable, Sendable { public var days: Int; public var from: String; public var to: String }
    public struct FavouriteBike: Equatable, Sendable { public var number: Int; public var count: Int; public var type: BikeType }

    public var longest: Longest?
    public var busiestDay: BusiestDay?
    public var streak: Streak?
    public var bike: FavouriteBike?
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
    public var withoutStations: Int
    public var unit: Unit
    public var buckets: [StatsBucket]
    /// Seven rows, Monday first, of 24 hours (Paris time).
    public var heatmap: [[Int]]
    public var bikeTypes: BikeTypeCounts
    public var durations: [DurationCount]
    public var starts: [StationCount]
    public var ends: [StationCount]
    public var pairs: [PairCount]
    public var records: StatsRecords
}

public struct Stats: Equatable, Sendable {
    public var days30: PeriodStats
    public var months12: PeriodStats
    public var all: PeriodStats
    /// false: a page of history failed or the page cap was hit, so older trips may be missing.
    public var complete: Bool
    public var pointsAvailable: Bool
    public var generatedAt: Date

    public subscript(period: StatsPeriod) -> PeriodStats {
        switch period {
        case .days30: days30
        case .months12: months12
        case .all: all
        }
    }
}

/// A dated points movement: earned positive, spent negative.
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
    public var complete: Bool
    public var now: Date
    public init(trips: [Trip], coords: [Int: GeoPoint], movements: [StatsMovement]?, balance: Double?, complete: Bool, now: Date) {
        self.trips = trips; self.coords = coords; self.movements = movements; self.balance = balance; self.complete = complete; self.now = now
    }
}

/// Reads a paged list once, page after page: stops at the first empty page, at a page that brings nothing new
/// (a server that ignores `page` repeats itself), or after `maxPages`. A failure after the first page keeps what was read.
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

/// Metres: nil without both stations or their coordinates, 0 for a loop back to the same station.
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
    /// "2026-10-29".
    public var day: String
    /// "2026-10".
    public var month: String
    public var hour: Int
    /// Monday 0.
    public var weekday: Int
}

/// Calendar day, month, hour and weekday (Monday 0) in Lyon.
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

/// Most counted first, ties by name, so the order is stable.
private func top<T>(_ values: [T], count: (T) -> Int, label: (T) -> String, minimum: Int = 1) -> [T] {
    Array(values.filter { count($0) >= minimum }.enumerated().sorted { (left: (offset: Int, element: T), right: (offset: Int, element: T)) -> Bool in
        let (a, b) = (left.element, right.element)
        if count(a) != count(b) { return count(a) > count(b) }
        let order = label(a).compare(label(b), locale: french)
        return order == .orderedSame ? left.offset < right.offset : order == .orderedAscending
    }.map(\.element).prefix(StatsRules.top))
}

private func present(_ text: String?) -> Bool { !(text ?? "").isEmpty }

private func stationTally(_ trips: [Trip], start: Bool) -> [StationCount] {
    var order: [String] = []
    var tally: [String: StationCount] = [:]
    for trip in trips {
        let number = start ? trip.startStationNumber : trip.endStationNumber
        let name = start ? trip.startStation : trip.endStation
        if number == nil && !present(name) { continue }
        let key = number.map { "#\($0)" } ?? name!
        if tally[key] == nil { order.append(key) }
        var entry = tally[key] ?? StationCount(number: number, name: name ?? "Station \(number!)", count: 0)
        entry.count += 1
        tally[key] = entry
    }
    return top(order.map { tally[$0]! }, count: { $0.count }, label: { $0.name })
}

private func longestStreak(_ days: [String]) -> StatsRecords.Streak? {
    var best: StatsRecords.Streak?
    var current: StatsRecords.Streak?
    for day in Set(days).sorted() {
        let next = current.flatMap { shiftDay($0.to, 1) == day ? StatsRecords.Streak(days: $0.days + 1, from: $0.from, to: day) : nil }
            ?? StatsRecords.Streak(days: 1, from: day, to: day)
        if best == nil || next.days > best!.days { best = next }
        current = next
    }
    return best
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
    let dated = (input.movements ?? []).compactMap { movement in movement.date.map { (key: keyOf(parisTime($0)), amount: movement.amount) } }
    // The balance at the end of a bucket: today's balance minus what came after, or the running sum when it is unknown.
    let balanceAt = { (key: String) -> Double in
        if let balance = input.balance { return balance - dated.filter { $0.key > key }.reduce(0) { $0 + $1.amount } }
        return dated.filter { $0.key <= key }.reduce(0) { $0 + $1.amount }
    }
    var buckets = keys.map { StatsBucket(key: $0, minutes: 0, trips: 0, balance: input.movements != nil ? balanceAt($0) : nil) }
    let bucketIndex = Dictionary(uniqueKeysWithValues: keys.enumerated().map { ($1, $0) })
    var heatmap = Array(repeating: Array(repeating: 0, count: 24), count: 7)
    var dayOrder: [String] = []
    var days: [String: StatsRecords.BusiestDay] = [:]
    for (trip, at) in inPeriod {
        guard let at else { continue }
        if let index = bucketIndex[keyOf(at)] {
            buckets[index].trips += 1
            buckets[index].minutes += minutes(trip)
        }
        heatmap[at.weekday][at.hour] += 1
        if days[at.day] == nil { dayOrder.append(at.day) }
        var day = days[at.day] ?? StatsRecords.BusiestDay(day: at.day, trips: 0, minutes: 0)
        day.trips += 1
        day.minutes += minutes(trip)
        days[at.day] = day
    }

    let distances = trips.map { estimateDistance($0, coords: input.coords) }
    let metres = distances.reduce(0) { $0 + ($1 ?? 0) }
    let durations = StatsRules.durationBuckets.enumerated().map { index, bucket in
        let low = index > 0 ? StatsRules.durationBuckets[index - 1].max : 0
        return DurationCount(label: bucket.label, count: trips.filter { $0.duration.map { $0 >= low && $0 < bucket.max } ?? false }.count)
    }
    var pairOrder: [String] = []
    var pairs: [String: PairCount] = [:]
    for trip in trips {
        guard let from = trip.startStation, let to = trip.endStation, !from.isEmpty, !to.isEmpty else { continue }
        let key = "\(trip.startStationNumber.map(String.init) ?? from)→\(trip.endStationNumber.map(String.init) ?? to)"
        if pairs[key] == nil { pairOrder.append(key) }
        pairs[key, default: PairCount(from: from, to: to, count: 0)].count += 1
    }
    var bikeOrder: [Int] = []
    var bikes: [Int: (count: Int, type: BikeType, last: Date)] = [:]
    for trip in trips {
        guard let number = trip.bikeNumber else { continue }
        if bikes[number] == nil { bikeOrder.append(number) }
        var bike = bikes[number] ?? (0, trip.bikeType, .distantPast)
        bike.count += 1
        let at = trip.startedAt ?? .distantPast
        if at >= bike.last { bike.last = at; bike.type = trip.bikeType }
        bikes[number] = bike
    }
    let bike = bikeOrder.max { (left: Int, right: Int) -> Bool in
        let a = bikes[left]!, b = bikes[right]!
        if a.count != b.count { return a.count < b.count }
        return a.last < b.last
    }
    let timed = trips.filter { $0.duration != nil }.enumerated().sorted { (left: (offset: Int, element: Trip), right: (offset: Int, element: Trip)) -> Bool in
        let (a, b) = (left.element, right.element)
        if a.duration! != b.duration! { return a.duration! > b.duration! }
        let aAt: Date = a.startedAt ?? .distantPast, bAt: Date = b.startedAt ?? .distantPast
        if aAt != bAt { return aAt > bAt }
        return left.offset < right.offset
    }
    let longest = timed.first?.element
    let busiestDay = dayOrder.map { days[$0]! }.sorted { (a: StatsRecords.BusiestDay, b: StatsRecords.BusiestDay) -> Bool in
        if a.trips != b.trips { return a.trips > b.trips }
        if a.minutes != b.minutes { return a.minutes > b.minutes }
        return a.day > b.day
    }.first
    let earned: Double = input.movements != nil
        ? dated.filter { $0.amount > 0 && (period == .all || $0.key >= start) }.reduce(0) { $0 + $1.amount }
        : trips.reduce(0) { $0 + $1.pointsEarned }

    let known = distances.filter { $0 != nil }.count
    let distance = DistanceEstimate(metres: metres.rounded(), known: known, unknown: distances.count - known)
    let spent: Double = trips.reduce(0) { $0 + max(0, $1.price ?? 0) }
    let saved: Double = trips.reduce(0) { $0 + max(0, $1.discount) }
    let total: Int = trips.reduce(0) { $0 + minutes($1) }
    let withoutStations = trips.filter { !present($0.startStation) && !present($0.endStation) }.count
    let count = { (type: BikeType) in trips.filter { $0.bikeType == type }.count }
    let bikeTypes = BikeTypeCounts(mechanical: count(.mechanical), electrical: count(.electrical), unknown: count(.unknown))
    let favouritePairs = top(pairOrder.map { pairs[$0]! }, count: { $0.count }, label: { "\($0.from) \($0.to)" }, minimum: 2)
    let longestRecord = longest.map { StatsRecords.Longest(minutes: minutes($0), startedAt: $0.startedAt, from: $0.startStation, to: $0.endStation) }
    let bikeRecord = bike.map { StatsRecords.FavouriteBike(number: $0, count: bikes[$0]!.count, type: bikes[$0]!.type) }
    let records = StatsRecords(longest: longestRecord, busiestDay: busiestDay, streak: longestStreak(dayOrder), bike: bikeRecord)
    return PeriodStats(
        trips: trips.count, minutes: total, distance: distance, co2Grams: (metres / 1000 * StatsRules.co2GramsPerKm).rounded(),
        spentCents: spent, savedCents: saved, pointsEarned: earned, withoutStations: withoutStations,
        unit: unit, buckets: buckets, heatmap: heatmap, bikeTypes: bikeTypes, durations: durations,
        starts: stationTally(trips, start: true), ends: stationTally(trips, start: false), pairs: favouritePairs, records: records)
}

public func buildStats(_ input: StatsInput) -> Stats {
    Stats(days30: periodStats(.days30, input), months12: periodStats(.months12, input), all: periodStats(.all, input),
          complete: input.complete, pointsAvailable: input.movements != nil, generatedAt: input.now)
}
