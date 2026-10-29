import Foundation

public struct Profile: Equatable, Sendable {
    public var firstName: String
    public var lastName: String
    public var email: String
    public var locked: Bool
    public var complete: Bool
    public var phoneNumber: String?
    public var address: String?
    public var addressComplement: String?
    public var zipCode: String?
    public var city: String?
    public var country: String?
    public var favorites: [Int]

    public init(firstName: String, lastName: String, email: String, locked: Bool, complete: Bool, phoneNumber: String?, address: String?, addressComplement: String?, zipCode: String?, city: String?, country: String?, favorites: [Int]) {
        self.firstName = firstName; self.lastName = lastName; self.email = email; self.locked = locked; self.complete = complete
        self.phoneNumber = phoneNumber; self.address = address; self.addressComplement = addressComplement
        self.zipCode = zipCode; self.city = city; self.country = country; self.favorites = favorites
    }
}

public enum BikeType: String, Equatable, Sendable { case mechanical, electrical, unknown }

public struct Trip: Equatable, Sendable, Identifiable {
    public var id: String
    public var status: String
    public var startedAt: Date?
    public var endedAt: Date?
    public var startStation: String?
    public var endStation: String?
    public var startStationNumber: Int?
    public var endStationNumber: Int?
    public var startStand: Int?
    public var endStand: Int?
    /// Metres, straight line between the two stations.
    public var distance: Int?
    public var bikeNumber: Int?
    public var bikeType: BikeType
    /// Minutes.
    public var duration: Double?
    /// Cents actually paid.
    public var price: Double?
    public var fullPrice: Double?
    public var discount: Double
    public var pointsEarned: Double
    public var pointsSpent: Double
    public var litigious: Bool
    public var isRated: Bool?
    public var token: String?
    public var origin: Double?

    public init(id: String, status: String = "FINISHED", startedAt: Date? = nil, endedAt: Date? = nil, startStation: String? = nil, endStation: String? = nil, startStationNumber: Int? = nil, endStationNumber: Int? = nil, startStand: Int? = nil, endStand: Int? = nil, distance: Int? = nil, bikeNumber: Int? = nil, bikeType: BikeType = .unknown, duration: Double? = nil, price: Double? = nil, fullPrice: Double? = nil, discount: Double = 0, pointsEarned: Double = 0, pointsSpent: Double = 0, litigious: Bool = false, isRated: Bool? = nil, token: String? = nil, origin: Double? = nil) {
        self.id = id; self.status = status; self.startedAt = startedAt; self.endedAt = endedAt
        self.startStation = startStation; self.endStation = endStation; self.startStationNumber = startStationNumber; self.endStationNumber = endStationNumber
        self.startStand = startStand; self.endStand = endStand; self.distance = distance; self.bikeNumber = bikeNumber; self.bikeType = bikeType
        self.duration = duration; self.price = price; self.fullPrice = fullPrice; self.discount = discount
        self.pointsEarned = pointsEarned; self.pointsSpent = pointsSpent; self.litigious = litigious; self.isRated = isRated; self.token = token; self.origin = origin
    }
}

public struct RewardMovement: Equatable, Sendable, Identifiable {
    public var id: String
    public var date: Date?
    public var label: String
    public var amount: Double
    public init(id: String, date: Date?, label: String, amount: Double) { self.id = id; self.date = date; self.label = label; self.amount = amount }
}

public struct RewardRule: Equatable, Sendable {
    public enum Kind: String, Sendable { case earn, spend }
    public var name: String
    public var label: String
    public var points: Double
    public var kind: Kind
    public init(name: String, label: String, points: Double, kind: Kind) { self.name = name; self.label = label; self.points = points; self.kind = kind }
}

public struct Rewards: Equatable, Sendable {
    /// nil: Vélo’v did not answer that read, the page says so instead of showing a default.
    public var balance: Double?
    public var total: Double?
    public var autoSpend: Bool?
    public var movements: [RewardMovement]
    public var rules: [RewardRule]
    public init(balance: Double?, total: Double?, autoSpend: Bool?, movements: [RewardMovement], rules: [RewardRule]) {
        self.balance = balance; self.total = total; self.autoSpend = autoSpend; self.movements = movements; self.rules = rules
    }
}

public struct Subscription: Equatable, Sendable {
    public var id: String?
    public var title: String
    public var type: String
    public var validUntil: Date?
    public var active: Bool
    public var autoRenewal: Bool?
    /// `renewalDetails.autoRenewalBtn` of an unlocked subscription: Vélo’v lets the app change the renewal. Absent means no.
    public var autoRenewalAllowed: Bool
    public init(id: String?, title: String, type: String, validUntil: Date?, active: Bool, autoRenewal: Bool?, autoRenewalAllowed: Bool = false) {
        self.id = id; self.title = title; self.type = type; self.validUntil = validUntil; self.active = active; self.autoRenewal = autoRenewal
        self.autoRenewalAllowed = autoRenewalAllowed
    }
}

/// The current subscription, none at all, or a read that failed.
public enum SubscriptionState: Equatable, Sendable {
    case unavailable
    case none
    case current(Subscription)

    public var subscription: Subscription? {
        if case .current(let value) = self { return value }
        return nil
    }
}

/// One paid period of a subscription, whose receipt Vélo’v renders as a PDF.
public struct Receipt: Equatable, Sendable, Identifiable {
    public var subscriptionId: String
    public var periodId: String
    public var title: String
    public var start: Date?
    public var end: Date?
    public var id: String { periodId }
    public init(subscriptionId: String, periodId: String, title: String, start: Date?, end: Date?) {
        self.subscriptionId = subscriptionId; self.periodId = periodId; self.title = title; self.start = start; self.end = end
    }
}

public struct Dashboard: Equatable, Sendable {
    public var profile: Profile
    public var rewards: Rewards
    public var subscription: SubscriptionState
    public var paymentValid: Bool?
    public var receipts: [Receipt]?
    public var trips: [Trip]?
    public var ongoing: [Trip]?
    public var bookings: Int?
    public var updatedAt: Date
    public var warnings: [String]

    public init(profile: Profile, rewards: Rewards, subscription: SubscriptionState, paymentValid: Bool?, receipts: [Receipt]?, trips: [Trip]?, ongoing: [Trip]?, bookings: Int?, updatedAt: Date, warnings: [String]) {
        self.profile = profile; self.rewards = rewards; self.subscription = subscription; self.paymentValid = paymentValid; self.receipts = receipts
        self.trips = trips; self.ongoing = ongoing; self.bookings = bookings; self.updatedAt = updatedAt; self.warnings = warnings
    }
}

public struct Station: Equatable, Sendable, Identifiable, Hashable {
    public var id: String
    public var number: Int
    public var name: String
    public var address: String
    public var lat: Double
    public var lon: Double
    public var mechanical: Int
    public var electrical: Int
    public var stands: Int
    public var open: Bool

    public var bikes: Int { mechanical + electrical }
    public var point: GeoPoint { GeoPoint(lat: lat, lon: lon) }

    public init(id: String, number: Int, name: String, address: String, lat: Double, lon: Double, mechanical: Int, electrical: Int, stands: Int, open: Bool) {
        self.id = id; self.number = number; self.name = name; self.address = address; self.lat = lat; self.lon = lon
        self.mechanical = mechanical; self.electrical = electrical; self.stands = stands; self.open = open
    }
}

public struct StationData: Equatable, Sendable {
    public var stations: [Station]
    public var updatedAt: Date
    public init(stations: [Station], updatedAt: Date) { self.stations = stations; self.updatedAt = updatedAt }
}

public struct Bike: Equatable, Sendable, Identifiable {
    public enum Kind: String, Sendable { case mechanical, electrical, other }
    public struct Rating: Equatable, Sendable {
        /// Out of 100.
        public var value: Double
        public var count: Int
        public var lastAt: Date?
        public init(value: Double, count: Int, lastAt: Date?) { self.value = value; self.count = count; self.lastAt = lastAt }
    }

    public var number: Int
    public var type: Kind
    public var standNumber: Int?
    public var status: String?
    public var statusLabel: String?
    public var isReserved: Bool
    public var rating: Rating?
    public var batteryPercent: Int?
    public var frameId: String?
    public var lastTripAt: Date?
    public var lastControlAt: Date?
    public var nextCheckAt: Date?
    public var lastSignalAt: Date?
    public var nextReviewAt: Date?
    public var id: Int { number }

    public init(number: Int, type: Kind = .mechanical, standNumber: Int? = nil, status: String? = "AVAILABLE", statusLabel: String? = nil, isReserved: Bool = false, rating: Rating? = nil, batteryPercent: Int? = nil, frameId: String? = nil, lastTripAt: Date? = nil, lastControlAt: Date? = nil, nextCheckAt: Date? = nil, lastSignalAt: Date? = nil, nextReviewAt: Date? = nil) {
        self.number = number; self.type = type; self.standNumber = standNumber; self.status = status; self.statusLabel = statusLabel
        self.isReserved = isReserved; self.rating = rating; self.batteryPercent = batteryPercent; self.frameId = frameId
        self.lastTripAt = lastTripAt; self.lastControlAt = lastControlAt; self.nextCheckAt = nextCheckAt; self.lastSignalAt = lastSignalAt; self.nextReviewAt = nextReviewAt
    }
}

public struct Booking: Equatable, Sendable, Identifiable {
    public var id: String
    public var stationNumber: Int
    public var stationName: String
    public var standNumber: Int?
    public var bikeNumber: Int?
    public var endsAt: Date?
    public var lat: Double?
    public var lon: Double?
    public init(id: String, stationNumber: Int, stationName: String, standNumber: Int?, bikeNumber: Int?, endsAt: Date?, lat: Double?, lon: Double?) {
        self.id = id; self.stationNumber = stationNumber; self.stationName = stationName; self.standNumber = standNumber
        self.bikeNumber = bikeNumber; self.endsAt = endsAt; self.lat = lat; self.lon = lon
    }
}

/// What Vélo’v answered to a state-changing call, raw fields kept for debugging. httpStatus 0: no answer at all.
public struct Outcome: Equatable, Sendable {
    public var ok: Bool
    public var httpStatus: Int
    public var transactionState: String?
    public var code: String?
    public var message: String?
    public var detail: String?
    public init(ok: Bool, httpStatus: Int, transactionState: String? = nil, code: String? = nil, message: String? = nil, detail: String? = nil) {
        self.ok = ok; self.httpStatus = httpStatus; self.transactionState = transactionState; self.code = code; self.message = message; self.detail = detail
    }

    public static func refusal(_ code: String, _ message: String) -> Outcome {
        Outcome(ok: false, httpStatus: 0, code: code, message: message)
    }
}

/// "Je déconseille" carries the rating of the chosen defect: 30 for a serious one, 60 otherwise.
public enum RateVote: Equatable, Sendable {
    case recommend
    case warn(Int)

    /// nil for a combination the official app never sends.
    public static func make(recommended: Bool, rating: Int?) -> RateVote? {
        if recommended { return rating == nil ? .recommend : nil }
        guard let rating, rating == 30 || rating == 60 else { return nil }
        return .warn(rating)
    }

    public var recommended: Bool { self == .recommend }
    public var rating: Int? {
        if case .warn(let value) = self { return value }
        return nil
    }
}

public enum Rules {
    /// A booking holds a bike for 15 minutes and costs 10 points; the server never checks where the user stands, the app keeps 200 m.
    public static let bookingMinutes = 15
    public static let bookingPoints = 10
    public static let releaseDistance = 200.0
    /// Vélo’v caps the address at 38 characters.
    public static let addressMax = 38
    /// The official app offers the rating for 3 hours after the trip ends.
    public static let ratingWindow: TimeInterval = 3 * 3600
}

public func canRate(_ trip: Trip, now: Date = Date()) -> Bool {
    guard let ended = trip.endedAt else { return false }
    return trip.status == "FINISHED" && trip.bikeNumber != nil && trip.isRated == false && now.timeIntervalSince(ended) < Rules.ratingWindow
}

/// "06 12 34 56 78" in France -> "+33612345678"; "0041 79…" -> "+4179…". Anything else is kept as typed, without separators.
public func normalizePhone(_ raw: String, country: String?) -> String {
    let compact = raw.filter { !" \t\n.()-".contains($0) && !$0.isWhitespace }
    if compact.hasPrefix("00") { return "+" + compact.dropFirst(2) }
    if country == "FR", compact.wholeMatch(of: /0[1-9]\d{8}/) != nil { return "+33" + compact.dropFirst() }
    return compact
}
