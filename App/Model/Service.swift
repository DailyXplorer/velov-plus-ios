import Foundation
import VelovCore

/// What the screens read. The live service talks to Cyclocity; the sample one serves fixtures for snapshots and previews.
protocol VelovService: Sendable {
    func hasSession() async -> Bool
    func signIn(email: String, code: String) async throws
    func logout() async -> Bool
    func dashboard() async throws -> Dashboard
    func stations() async throws -> StationData
    func stationBikes(_ station: Int) async throws -> [Bike]
    func bike(_ number: Int) async throws -> Bike?
    func bookings() async throws -> [Booking]
}

/// Cyclocity directly: tokens in the Keychain, reads with the shared app token. No write in stage 1.
final class LiveService: VelovService {
    private let api: VelovAPI
    private let session: SessionManager

    init() {
        let transport = URLSessionTransport()
        api = VelovAPI(transport: transport)
        session = SessionManager(store: KeychainStore(), http: transport)
    }

    func hasSession() async -> Bool { await session.isSignedIn }
    func signIn(email: String, code: String) async throws { try await session.signIn(email: email, code: code) }
    func logout() async -> Bool { await session.logout() }
    func dashboard() async throws -> Dashboard { try await api.dashboard(try await session.identity()) }
    func stations() async throws -> StationData { try await api.stations() }
    func stationBikes(_ station: Int) async throws -> [Bike] { try await api.stationBikes(station) }
    func bike(_ number: Int) async throws -> Bike? { try await api.bike(number) }
    func bookings() async throws -> [Booking] { try await api.bookings(try await session.identity()) }
}
