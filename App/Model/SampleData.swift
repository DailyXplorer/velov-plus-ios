import Foundation
import VelovCore

/// Fictional account data around public Lyon stations, for snapshots and previews only.
enum SampleData {
    static let now = Date()
    static func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }

    static let stations: [Station] = [
        Station(id: "2002", number: 2002, name: "Bellecour / St Exupéry", address: "Place Bellecour", lat: 45.7578, lon: 4.8320, mechanical: 6, electrical: 3, stands: 11, open: true),
        Station(id: "2010", number: 2010, name: "Confluence / Darse", address: "", lat: 45.7413, lon: 4.8183, mechanical: 2, electrical: 1, stands: 17, open: true),
        Station(id: "1001", number: 1001, name: "Opéra", address: "", lat: 45.7676, lon: 4.8363, mechanical: 0, electrical: 0, stands: 20, open: true),
        Station(id: "1002", number: 1002, name: "Terreaux / Hôtel de Ville", address: "", lat: 45.7672, lon: 4.8336, mechanical: 8, electrical: 2, stands: 4, open: true),
        Station(id: "3001", number: 3001, name: "Part-Dieu", address: "", lat: 45.7606, lon: 4.8594, mechanical: 12, electrical: 5, stands: 9, open: true),
        Station(id: "7002", number: 7002, name: "Jean Macé", address: "", lat: 45.7456, lon: 4.8420, mechanical: 4, electrical: 0, stands: 14, open: true),
        Station(id: "2004", number: 2004, name: "Ampère / Victor Hugo", address: "", lat: 45.7531, lon: 4.8290, mechanical: 1, electrical: 4, stands: 8, open: true),
        Station(id: "6003", number: 6003, name: "Brotteaux", address: "", lat: 45.7672, lon: 4.8590, mechanical: 3, electrical: 3, stands: 12, open: true),
        Station(id: "1003", number: 1003, name: "Saint-Paul", address: "", lat: 45.7663, lon: 4.8270, mechanical: 5, electrical: 1, stands: 6, open: true),
        Station(id: "7001", number: 7001, name: "Guillotière", address: "", lat: 45.7553, lon: 4.8422, mechanical: 0, electrical: 2, stands: 15, open: true),
        Station(id: "2007", number: 2007, name: "Perrache", address: "", lat: 45.7493, lon: 4.8262, mechanical: 7, electrical: 0, stands: 3, open: true),
        Station(id: "4001", number: 4001, name: "Croix-Rousse", address: "", lat: 45.7745, lon: 4.8320, mechanical: 2, electrical: 6, stands: 10, open: true)
    ]
    static var byNumber: [Int: Station] { Dictionary(uniqueKeysWithValues: stations.map { ($0.number, $0) }) }

    static func trip(_ id: String, _ from: Int, _ to: Int, hoursAgo: Double, minutes: Double, price: Double, type: BikeType, bike: Int, earned: Double = 0, litigious: Bool = false, rated: Bool? = true) -> Trip {
        let start = ago(hoursAgo)
        let distance = Int(haversine(byNumber[from]!.point, byNumber[to]!.point).rounded())
        return Trip(id: id, startedAt: start, endedAt: start.addingTimeInterval(minutes * 60), startStation: byNumber[from]!.name, endStation: byNumber[to]!.name,
                    startStationNumber: from, endStationNumber: to, startStand: 4, endStand: 12, distance: distance, bikeNumber: bike, bikeType: type,
                    duration: minutes, price: price, fullPrice: price, discount: 0, pointsEarned: earned, pointsSpent: 0, litigious: litigious, isRated: rated,
                    token: "TK\(id.uppercased())0000000000", origin: 4)
    }

    static let trips: [Trip] = [
        trip("a1", 2002, 3001, hoursAgo: 1.5, minutes: 14, price: 0, type: .electrical, bike: 20449, earned: 5, rated: false),
        trip("a2", 3001, 1002, hoursAgo: 26, minutes: 18, price: 0, type: .mechanical, bike: 11872),
        trip("a3", 1002, 2004, hoursAgo: 50, minutes: 37, price: 100, type: .electrical, bike: 20117, litigious: true),
        trip("a4", 2004, 7002, hoursAgo: 75, minutes: 9, price: 0, type: .mechanical, bike: 10533),
        trip("a5", 7002, 2002, hoursAgo: 98, minutes: 12, price: 0, type: .mechanical, bike: 12204),
        trip("a6", 2002, 4001, hoursAgo: 140, minutes: 24, price: 0, type: .electrical, bike: 20981)
    ]

    static let dashboard = Dashboard(
        // Vélo’v stores names in lower case; the app shows them with `formatName`.
        profile: Profile(firstName: "camille", lastName: "martin", email: "camille@example.com", locked: false, complete: true,
                         phoneNumber: "+33600000000", address: "1 place de l’Exemple", addressComplement: nil, zipCode: "69002", city: "Lyon", country: "FR", favorites: [2002, 3001]),
        rewards: Rewards(balance: 85, total: 1240, autoSpend: true, movements: [
            RewardMovement(id: "m1", date: ago(1.2), label: "Vélo évalué", amount: 5),
            RewardMovement(id: "m2", date: ago(30), label: "Arrivée dans une station vide", amount: 10),
            RewardMovement(id: "m3", date: ago(80), label: "Réservation d’un vélo", amount: -10),
            RewardMovement(id: "m4", date: ago(120), label: "Départ d’une station pleine", amount: 10)
        ], rules: [
            RewardRule(name: "RATE_BIKE", label: "Vélo évalué", points: 5, kind: .earn),
            RewardRule(name: "START_STATION_FULL", label: "Départ d’une station pleine", points: 10, kind: .earn),
            RewardRule(name: "END_STATION_EMPTY", label: "Arrivée dans une station vide", points: 10, kind: .earn),
            RewardRule(name: "PROMOCODE", label: "Invitation d’un proche", points: 50, kind: .spend)
        ]),
        subscription: .current(Subscription(id: "sub-1", title: "Vélo’v Plus 1 an – paiement comptant", type: "LT", validUntil: now.addingTimeInterval(200 * 86_400), active: true, autoRenewal: true, autoRenewalAllowed: true)),
        paymentValid: true,
        receipts: [
            Receipt(subscriptionId: "sub-1", periodId: "p-2", title: "Vélo’v Plus 1 an", start: now.addingTimeInterval(-165 * 86_400), end: now.addingTimeInterval(200 * 86_400)),
            Receipt(subscriptionId: "sub-0", periodId: "p-1", title: "Ticket 24h", start: now.addingTimeInterval(-400 * 86_400), end: now.addingTimeInterval(-399 * 86_400))
        ],
        trips: trips, ongoing: [], bookings: 0, updatedAt: now, warnings: [])

    /// A booking of a sample bike at Bellecour, `minutesLeft` from now.
    static func booking(bike: Int = 20449, minutesLeft: Double = 12.6) -> Booking {
        let station = byNumber[2002]!
        return Booking(id: "bk-sample", stationNumber: station.number, stationName: station.name, standNumber: 2, bikeNumber: bike,
                       endsAt: now.addingTimeInterval(minutesLeft * 60), lat: station.lat, lon: station.lon)
    }

    static let bikes: [Bike] = [
        Bike(number: 20449, type: .electrical, standNumber: 2, statusLabel: "Accroché", rating: .init(value: 92, count: 31, lastAt: ago(5)), batteryPercent: 88, frameId: "FR-0042-2044", lastTripAt: ago(2), lastControlAt: ago(200), nextCheckAt: now.addingTimeInterval(3 * 86_400), lastSignalAt: ago(0.1), nextReviewAt: now.addingTimeInterval(60 * 86_400)),
        Bike(number: 11872, type: .mechanical, standNumber: 5, statusLabel: "Accroché", rating: .init(value: 88, count: 24, lastAt: ago(20)), lastTripAt: ago(6), lastControlAt: ago(300), nextCheckAt: now.addingTimeInterval(86_400)),
        Bike(number: 12204, type: .mechanical, standNumber: 7, statusLabel: "Accroché", rating: .init(value: 79, count: 12, lastAt: ago(40)), lastTripAt: ago(30)),
        Bike(number: 20117, type: .electrical, standNumber: 9, statusLabel: "Accroché", rating: .init(value: 84, count: 9, lastAt: ago(60)), batteryPercent: 46, lastTripAt: ago(14)),
        Bike(number: 10533, type: .mechanical, standNumber: 11, statusLabel: "Accroché", rating: nil, lastTripAt: ago(50)),
        Bike(number: 20981, type: .electrical, standNumber: 13, statusLabel: "Accroché", rating: .init(value: 70, count: 15, lastAt: ago(90)), batteryPercent: 12, lastTripAt: ago(20)),
        Bike(number: 13090, type: .mechanical, standNumber: 15, statusLabel: "Accroché", rating: .init(value: 52, count: 8, lastAt: ago(100)), lastTripAt: ago(120))
    ]
}

struct SampleService: VelovService {
    /// The booking the snapshot screens show; none elsewhere.
    var booking: Booking?
    /// The unlock answer is lost, as the uncertain snapshot shows it.
    var failUnlock = false

    func hasSession() async -> Bool { true }
    func signIn(email: String, code: String) async throws {}
    func logout() async -> Bool { true }
    func dashboard() async throws -> Dashboard { SampleData.dashboard }
    func stations() async throws -> StationData { StationData(stations: SampleData.stations, updatedAt: SampleData.now) }
    func stationBikes(_ station: Int) async throws -> [Bike] { SampleData.bikes }
    func bike(_ number: Int) async throws -> Bike? { SampleData.bikes.first { $0.number == number } ?? SampleData.bikes[0] }
    func bookings() async throws -> [Booking] { booking.map { [$0] } ?? [] }

    // Writes answer at once with what Vélo’v would: nothing leaves the device.
    func book(stationNumber: Int, bikeNumber: Int) async throws -> (outcome: Outcome, booking: Booking?) {
        (Outcome(ok: true, httpStatus: 200), SampleData.booking(bike: bikeNumber, minutesLeft: 15))
    }
    func unlock(stationNumber: Int, standNumber: Int, bikeNumber: Int) async throws -> (outcome: Outcome, ongoing: [Trip]?) {
        if failUnlock {
            var lost = Outcome.refusal("network", "Vélo’v ne répond pas. Le vélo est peut-être déverrouillé : regardez la borne avant de réessayer.")
            lost.detail = "TimeoutError"
            return (lost, nil)
        }
        return (Outcome(ok: true, httpStatus: 200, transactionState: "OK"), [])
    }
    func tripCheck() async throws -> TripCheck { TripCheck(ongoing: [], latest: nil) }
    func rate(tripId: String, bikeNumber: Int, vote: RateVote) async throws -> Outcome { Outcome(ok: true, httpStatus: 200) }
    func setAutoSpend(_ value: Bool) async throws -> (outcome: Outcome, autoSpend: Bool?) { (Outcome(ok: true, httpStatus: 200), value) }
    func setFavorite(station: Int, on: Bool) async throws -> Outcome { Outcome(ok: true, httpStatus: 204) }
    func receipt(subscriptionId: String, periodId: String) async throws -> (outcome: Outcome, filename: String?, pdf: Data?) {
        (Outcome(ok: false, httpStatus: 0, code: "sample", message: "Pas de reçu dans les données d’exemple."), nil, nil)
    }
    func updateProfile(_ body: ProfileBody) async throws -> Outcome { Outcome(ok: true, httpStatus: 200) }
    func setAutoRenewal(subscriptionId: String, autoRenewal: Bool) async throws -> AutoRenewalResult {
        AutoRenewalResult(outcome: Outcome(ok: true, httpStatus: 200), autoRenewal: autoRenewal, autoRenewalAllowed: true, verified: true)
    }
    func requestExtraTime(stationNumber: Int) async throws -> Outcome { Outcome(ok: true, httpStatus: 200, transactionState: "OK") }
    func contactSupport(_ body: ContactBody) async throws -> Outcome { Outcome(ok: true, httpStatus: 200) }
    func consumePromoCode(expectedCost: Int) async throws -> PromoResult { PromoResult(outcome: Outcome(ok: true, httpStatus: 200), promoCode: "EXEMPLE-0000") }
}
