import XCTest
@testable import VelovCore

final class GuestTests: XCTestCase {
    private func defaults() -> (UserDefaults, String) {
        let name = "guest-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return (defaults, name)
    }

    func testASessionWinsOverAStoredGuestChoice() {
        XCTAssertEqual(StartMode(hasSession: true, guest: true), .session)
        XCTAssertEqual(StartMode(hasSession: true, guest: false), .session)
        XCTAssertEqual(StartMode(hasSession: false, guest: true), .guest)
        XCTAssertEqual(StartMode(hasSession: false, guest: false), .signedOut)
    }

    func testTheGuestChoiceAndFavouritesStayOnThePhoneWithoutCredentials() {
        let (defaults, name) = defaults()
        let store = GuestStore(defaults: defaults)
        XCTAssertFalse(store.isOn)
        store.remember(true)
        store.setFavorite(2002, true)
        store.setFavorite(3001, true)
        store.setFavorite(2002, true)
        XCTAssertEqual(store.setFavorite(3001, false), [2002])

        let reopened = GuestStore(defaults: UserDefaults(suiteName: name)!)
        XCTAssertTrue(reopened.isOn)
        XCTAssertEqual(reopened.favorites, [2002])
        XCTAssertEqual(Set(defaults.persistentDomain(forName: name)?.keys.map { $0 } ?? []), [GuestStore.modeKey, GuestStore.favoritesKey])

        reopened.remember(false)
        XCTAssertFalse(store.isOn)
        XCTAssertEqual(store.favorites, [2002], "signing in keeps the favourites kept on this phone")
    }

    func testUnreadableFavouritesAreDropped() {
        let (defaults, _) = defaults()
        defaults.set([2002, "x", -1, 2002, 0, 7001], forKey: GuestStore.favoritesKey)
        XCTAssertEqual(GuestStore(defaults: defaults).favorites, [2002, 7001])
        defaults.set("2002", forKey: GuestStore.favoritesKey)
        XCTAssertEqual(GuestStore(defaults: defaults).favorites, [])
    }

    func testWhatAGuestSeesNeedsNoAccount() async throws {
        let server = MockServer { call, _ in
            let url = call.url
            if url.hasSuffix("/client_tokens") { return .json(["accessToken": "app"]) }
            if url.contains("station_information") { return .json(UpstreamTests.information) }
            if url.contains("station_status") { return .json(UpstreamTests.status) }
            if url.contains("/bikes?") { return .json([["id": "bike-uuid", "number": 20449, "stationNumber": 2002, "standNumber": 4, "status": "AVAILABLE"]]) }
            return .status(404)
        }
        let api = VelovAPI(transport: server.transport, pause: noPause)
        _ = try await api.stations()
        let bikes = try await api.stationBikes(2002)
        let bike = try await api.bike(20449)
        XCTAssertEqual(bikes.map(\.number), [20449])
        XCTAssertEqual(bike?.number, 20449)

        let reads = server.calls.filter { !$0.url.hasSuffix("/client_tokens") }
        XCTAssertEqual(reads.count, 4)
        XCTAssertTrue(reads.allSatisfy { $0.method == "GET" && $0.header("Identity") == nil && !$0.url.contains("/accounts") })
        XCTAssertEqual(reads.filter { $0.url.contains("/bikes?") }.map { $0.header("Authorization") }, ["Taknv1 app", "Taknv1 app"])
    }

    func testAnAccountRequestWithoutASessionNeverLeavesThePhone() async {
        let server = MockServer { _, _ in .status(200) }
        let session = SessionManager(store: InMemoryStore(), http: server.transport)
        do { _ = try await session.identity(); XCTFail("no identity without a session") } catch {}
        XCTAssertTrue(server.calls.isEmpty)
    }
}
