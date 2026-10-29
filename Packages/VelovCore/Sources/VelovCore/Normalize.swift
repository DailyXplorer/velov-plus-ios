import Foundation

// Cyclocity answers -> app models. Required fields that have the wrong shape make the read fail (a zod `parse`),
// the newer optional ones degrade to nil (`lenient`).

/// A trip as Cyclocity sends it, with the same required and lenient fields as the web client's `rawTrip`.
public struct RawTrip: Sendable {
    let id: String
    let status: String?
    let startDateTime: String?, endDateTime: String?
    let startStation: JSON?, endStation: JSON?
    let startStationName: String?, endStationName: String?
    let startStand: Int?, endStand: Int?
    let bikeNumber: Double?, bikeType: Double?, duration: Double?
    let price: Double?, discount: Double?, reducedPrice: Double?
    let rewardsEarned: Double?, rewardsSpent: Double?
    let litigious: Bool?, isRated: Bool?, token: String?, origin: Double?

    public init(_ value: JSON) throws {
        guard let id = value["id"]?.string else { throw ShapeError("trip id") }
        self.id = id
        if let status = value["status"], status != .null {
            guard let string = status.string else { throw ShapeError("trip status") }
            self.status = string
        } else { self.status = nil }
        startDateTime = try value["startDateTime"].nullishString("startDateTime")
        endDateTime = try value["endDateTime"].nullishString("endDateTime")
        startStation = try Self.scalar(value["startStation"])
        endStation = try Self.scalar(value["endStation"])
        startStationName = try value["startStationName"].nullishString("startStationName")
        endStationName = try value["endStationName"].nullishString("endStationName")
        startStand = value["startStand"]?.int
        endStand = value["endStand"]?.int
        bikeNumber = try value["bikeNumber"].nullishNumber("bikeNumber")
        bikeType = try value["bikeType"].nullishNumber("bikeType")
        duration = try value["duration"].nullishNumber("duration")
        price = value["price"]?.number
        discount = value["discount"]?.number
        reducedPrice = value["reducedPrice"]?.number
        rewardsEarned = value["rewardsEarned"]?.number
        rewardsSpent = value["rewardsSpent"]?.number
        litigious = value["litigious"]?.bool
        isRated = value["isRated"]?.bool
        token = value["token"]?.string
        origin = value["origin"]?.number
    }

    private static func scalar(_ value: JSON?) throws -> JSON? {
        switch value {
        case nil, .null?: return nil
        case .number?, .string?: return value
        default: throw ShapeError("station is neither a number nor a string")
        }
    }

    public static func list(_ value: JSON) throws -> [RawTrip] {
        guard let items = value.array else { throw ShapeError("trips is not a list") }
        return try items.map(RawTrip.init)
    }
}

/// `Number(value)` that is a safe integer, for a non-blank value.
private func stationNumber(_ value: JSON?) -> Int? {
    switch value {
    case .number(let number)?:
        return number.rounded() == number && abs(number) <= 9_007_199_254_740_991 ? Int(number) : nil
    case .string(let string)?:
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let number = Double(trimmed), number.rounded() == number, abs(number) <= 9_007_199_254_740_991 else { return nil }
        return Int(number)
    default:
        return nil
    }
}

private func rawText(_ value: JSON?) -> String? {
    switch value {
    case .number(let number)?: return number.rounded() == number ? String(Int(number)) : String(number)
    case .string(let string)?: return string
    default: return nil
    }
}

public func normalizeTrip(_ value: RawTrip, stations: [Int: Station]) -> Trip {
    let start = stationNumber(value.startStation)
    let end = stationNumber(value.endStation)
    func station(_ name: String?, _ number: Int?, _ raw: JSON?) -> String? {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return stationTitle(name) }
        if let number { return stations[number]?.name ?? "Station \(number)" }
        if let raw = rawText(raw)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty { return "Station \(raw)" }
        return nil
    }
    let from = start.flatMap { stations[$0] }
    let to = end.flatMap { stations[$0] }
    var distance: Int?
    if let from, let to, start != end { distance = Int(haversine(from.point, to.point).rounded()) }
    return Trip(
        id: value.id, status: value.status ?? "FINISHED", startedAt: cyclocityDate(value.startDateTime), endedAt: cyclocityDate(value.endDateTime),
        startStation: station(value.startStationName, start, value.startStation), endStation: station(value.endStationName, end, value.endStation),
        startStationNumber: start, endStationNumber: end, startStand: value.startStand, endStand: value.endStand, distance: distance,
        bikeNumber: value.bikeNumber.flatMap { $0.rounded() == $0 ? Int($0) : nil },
        bikeType: value.bikeType == 1 ? .electrical : value.bikeType == 0 ? .mechanical : .unknown,
        duration: value.duration, price: value.reducedPrice ?? value.price.map { $0 - (value.discount ?? 0) },
        fullPrice: value.price, discount: value.discount ?? 0,
        pointsEarned: value.rewardsEarned ?? 0, pointsSpent: value.rewardsSpent ?? 0,
        litigious: value.litigious == true, isRated: value.isRated, token: value.token, origin: value.origin
    )
}

/// A bike as Cyclocity sends it; only `number` is required, one malformed bike is skipped, not the station.
public struct RawBike: Sendable {
    public let id: String?
    public let number: Int
    public let type: String?
    public let frameId: String?
    public let standNumber: Int?
    public let status: String?
    public let statusLabel: String?
    public let isReserved: Bool?
    public let ratingValue: Double?
    public let ratingCount: Double?
    public let ratingLast: String?
    public let battery: Double?
    public let lastTrip: String?, lastControl: String?, nextCheck: String?, nextReview: String?, lastFrame: String?

    public init?(_ value: JSON) {
        guard let number = value["number"]?.int else { return nil }
        self.number = number
        id = value["id"]?.string
        type = value["type"]?.string
        frameId = value["frameId"]?.string
        standNumber = value["standNumber"]?.int
        status = value["status"]?.string
        statusLabel = value["statusLabel"]?.string
        isReserved = value["isReserved"]?.bool
        let rating = value["rating"]
        ratingValue = rating?["value"]?.number
        ratingCount = rating?["count"]?.number
        ratingLast = rating?["lastRatingDateTime"]?.string
        battery = value["battery"]?["percentage"]?.number
        lastTrip = value["lastTripDateTime"]?.string
        lastControl = value["lastControlDateTime"]?.string
        nextCheck = value["nextCheck"]?.string
        nextReview = value["nextReview"]?.string
        lastFrame = value["lastDataFrameDate"]?.string
    }

    public static func list(_ value: JSON) throws -> [RawBike] {
        guard let items = value.array else { throw ShapeError("bikes is not a list") }
        return items.compactMap(RawBike.init)
    }
}

public func normalizeBike(_ value: RawBike) -> Bike {
    let type: Bike.Kind = value.type == "ELECTRICAL" ? .electrical : value.type == "MECHANICAL" ? .mechanical : .other
    var rating: Bike.Rating?
    if let score = value.ratingValue, let count = value.ratingCount, count != 0 {
        rating = Bike.Rating(value: (score * 10).rounded() / 10, count: Int(count), lastAt: cyclocityDate(value.ratingLast))
    }
    let battery = type == .electrical ? value.battery.map { min(100, max(0, Int($0.rounded()))) } : nil
    return Bike(
        number: value.number, type: type, standNumber: value.standNumber, status: value.status, statusLabel: value.statusLabel,
        isReserved: value.isReserved ?? false, rating: rating, batteryPercent: battery,
        frameId: value.frameId.flatMap { $0.isEmpty || $0 == "0" ? nil : $0 },
        lastTripAt: cyclocityDate(value.lastTrip), lastControlAt: cyclocityDate(value.lastControl), nextCheckAt: cyclocityDate(value.nextCheck),
        lastSignalAt: cyclocityDate(value.lastFrame), nextReviewAt: cyclocityDate(value.nextReview)
    )
}

/// GBFS v3 station_information + station_status -> the station list.
public func parseStations(information: JSON, status: JSON) throws -> StationData {
    guard let infos = information["data"]?["stations"]?.array, let statuses = status["data"]?["stations"]?.array else { throw ShapeError("gbfs stations") }
    var availability: [String: JSON] = [:]
    for station in statuses {
        guard let id = station["station_id"]?.string, station["num_docks_available"]?.number != nil else { throw ShapeError("gbfs status") }
        availability[id] = station
    }
    var stations: [Station] = []
    for station in infos {
        guard let id = station["station_id"]?.string, let lat = station["lat"]?.number, let lon = station["lon"]?.number else { throw ShapeError("gbfs information") }
        guard let current = availability[id], let number = Double(id), number.isFinite else { continue }
        let name: String?
        switch station["name"] {
        case .string(let value)?: name = value
        case .array(let names)?: name = names.first { $0["language"]?.string?.hasPrefix("fr") == true }?["text"]?.string ?? names.first?["text"]?.string
        default: throw ShapeError("gbfs name")
        }
        let types = current["vehicle_types_available"]?.array ?? []
        let electrical = types.filter { ($0["vehicle_type_id"]?.string ?? "").range(of: "electri", options: .caseInsensitive) != nil }
            .reduce(0) { $0 + Int($1["count"]?.number ?? 0) }
        let total = Int(current["num_vehicles_available"]?.number ?? current["num_bikes_available"]?.number ?? 0)
        let renting: Bool = current["is_renting"]?.bool ?? ((current["is_renting"]?.number ?? 0) != 0)
        let title = name.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : stationTitle($0) } ?? "Station \(Int(number))"
        stations.append(Station(id: id, number: Int(number), name: title, address: station["address"]?.string ?? "", lat: lat, lon: lon,
                                mechanical: max(0, total - electrical), electrical: electrical, stands: Int(current["num_docks_available"]!.number!), open: renting))
    }
    let updated: Date
    switch status["last_updated"] {
    case .number(let seconds)?: updated = Date(timeIntervalSince1970: seconds)
    case .string(let value)?: updated = cyclocityDate(value) ?? Date()
    default: throw ShapeError("gbfs last_updated")
    }
    return StationData(stations: stations, updatedAt: updated)
}

/// A booking as GET/POST /bookings return it.
public struct RawBooking: Equatable, Sendable {
    public let id: String
    public let stationNumber: Int
    public let standNumber: Int?
    public let bikeId: String?
    public let endTime: String?

    public init?(_ value: JSON) {
        guard let id = value["id"]?.string, let station = value["stationNumber"]?.number else { return nil }
        self.id = id
        stationNumber = Int(station)
        standNumber = value["standNumber"]?.int
        bikeId = value["bikeId"]?.string
        endTime = value["endTime"]?.string
    }
}

public func toBooking(_ value: RawBooking, stations: [Int: Station], bikeNumbers: [String: Int]) -> Booking {
    let station = stations[value.stationNumber]
    return Booking(id: value.id, stationNumber: value.stationNumber, stationName: station?.name ?? "Station \(value.stationNumber)",
                   standNumber: value.standNumber, bikeNumber: value.bikeId.flatMap { bikeNumbers[$0] },
                   endsAt: cyclocityDate(value.endTime), lat: station?.lat, lon: station?.lon)
}
