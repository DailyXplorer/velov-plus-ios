import Foundation
import VelovCore

protocol VelovService: Sendable {
    func hasSession() async -> Bool
    func signIn(email: String, code: String) async throws
    func logout() async -> Bool
    func dashboard() async throws -> Dashboard
    func stations() async throws -> StationData
    func stationBikes(_ station: Int) async throws -> [Bike]
    func bike(_ number: Int) async throws -> Bike?
    func bookings() async throws -> [Booking]
    func stats() async throws -> Stats

    func book(stationNumber: Int, bikeNumber: Int) async throws -> (outcome: Outcome, booking: Booking?)
    func unlock(stationNumber: Int, standNumber: Int, bikeNumber: Int) async throws -> (outcome: Outcome, ongoing: [Trip]?)
    func tripCheck() async throws -> TripCheck
    func rate(tripId: String, bikeNumber: Int, vote: RateVote) async throws -> Outcome
    func setAutoSpend(_ value: Bool) async throws -> (outcome: Outcome, autoSpend: Bool?)
    func setFavorite(station: Int, on: Bool) async throws -> Outcome
    func receipt(subscriptionId: String, periodId: String) async throws -> (outcome: Outcome, filename: String?, pdf: Data?)
    func updateProfile(_ body: ProfileBody) async throws -> Outcome
    func setAutoRenewal(subscriptionId: String, autoRenewal: Bool) async throws -> AutoRenewalResult
    func requestExtraTime(stationNumber: Int) async throws -> Outcome
    func contactSupport(_ body: ContactBody) async throws -> Outcome
    func consumePromoCode(expectedCost: Int) async throws -> PromoResult
}

final class LiveService: VelovService {
    private let api: VelovAPI
    private let session: SessionManager

    init() {
        let transport = URLSessionTransport()
        api = VelovAPI(transport: transport)
        session = SessionManager(store: KeychainStore(), http: transport)
    }

    private func identity() async throws -> Identity { try await session.identity() }

    func hasSession() async -> Bool { await session.isSignedIn }
    func signIn(email: String, code: String) async throws { try await session.signIn(email: email, code: code) }
    func logout() async -> Bool { await session.logout() }
    func dashboard() async throws -> Dashboard { try await api.dashboard(try await identity()) }
    func stations() async throws -> StationData { try await api.stations() }
    func stationBikes(_ station: Int) async throws -> [Bike] { try await api.stationBikes(station) }
    func bike(_ number: Int) async throws -> Bike? { try await api.bike(number) }
    func bookings() async throws -> [Booking] { try await api.bookings(try await identity()) }
    func stats() async throws -> Stats { try await api.stats(try await identity()) }

    func book(stationNumber: Int, bikeNumber: Int) async throws -> (outcome: Outcome, booking: Booking?) {
        try await api.book(try await identity(), stationNumber: stationNumber, bikeNumber: bikeNumber)
    }
    func unlock(stationNumber: Int, standNumber: Int, bikeNumber: Int) async throws -> (outcome: Outcome, ongoing: [Trip]?) {
        try await api.unlock(try await identity(), stationNumber: stationNumber, standNumber: standNumber, bikeNumber: bikeNumber)
    }
    func tripCheck() async throws -> TripCheck { try await api.tripCheck(try await identity()) }
    func rate(tripId: String, bikeNumber: Int, vote: RateVote) async throws -> Outcome {
        try await api.rate(try await identity(), tripId: tripId, bikeNumber: bikeNumber, vote: vote)
    }
    func setAutoSpend(_ value: Bool) async throws -> (outcome: Outcome, autoSpend: Bool?) { try await api.setAutoSpend(try await identity(), value) }
    func setFavorite(station: Int, on: Bool) async throws -> Outcome { try await api.setFavorite(try await identity(), station: station, on: on) }
    func receipt(subscriptionId: String, periodId: String) async throws -> (outcome: Outcome, filename: String?, pdf: Data?) {
        try await api.receipt(try await identity(), subscriptionId: subscriptionId, periodId: periodId)
    }
    func updateProfile(_ body: ProfileBody) async throws -> Outcome { try await api.updateProfile(try await identity(), body) }
    func setAutoRenewal(subscriptionId: String, autoRenewal: Bool) async throws -> AutoRenewalResult {
        try await api.setAutoRenewal(try await identity(), subscriptionId: subscriptionId, autoRenewal: autoRenewal)
    }
    func requestExtraTime(stationNumber: Int) async throws -> Outcome { try await api.requestExtraTime(try await identity(), stationNumber: stationNumber) }
    func contactSupport(_ body: ContactBody) async throws -> Outcome { try await api.contactSupport(try await identity(), body) }
    func consumePromoCode(expectedCost: Int) async throws -> PromoResult { try await api.consumePromoCode(try await identity(), expectedCost: expectedCost) }
}

func attempt(_ run: () async throws -> Outcome) async -> Outcome {
    do {
        return try await run()
    } catch let error as VelovError {
        return Outcome(ok: false, httpStatus: error.code == .expired ? 401 : 0, code: "local.\(error.code.rawValue)", message: error.message)
    } catch {
        return Outcome(ok: false, httpStatus: 0, code: "network", message: "Le serveur ne répond pas. Actualisez avant de réessayer.")
    }
}
