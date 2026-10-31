import XCTest
@testable import VelovCore

final class SessionTests: XCTestCase {
    let renewed = ["access_token": accessToken(expires: Date().addingTimeInterval(1800)), "refresh_token": "new-refresh", "id_token": "new-identity", "expires_in": 1800, "refresh_expires_in": 0] as [String: Any]

    func signedIn(_ store: SecureStore, expires: Date) {
        let tokens = Tokens(accessToken: accessToken(expires: expires), refreshToken: "old-refresh", idToken: "old-identity", expiresIn: 1800, refreshExpiresIn: 0)
        _ = store.write("tokens", try! JSONEncoder().encode(StoredSession(tokens: tokens, obtainedAt: Date())))
    }

    func testTheDeviceIdIsCreatedOnceAndNeverRegenerated() {
        let store = InMemoryStore()
        let first = DeviceIdentity.stable(in: store)
        XCTAssertNotNil(first.wholeMatch(of: /[a-z0-9-]{36}/))
        XCTAssertEqual(DeviceIdentity.stable(in: store), first)
        _ = store.write("device_id", Data("bad id!".utf8))
        XCTAssertNotEqual(DeviceIdentity.stable(in: store), "bad id!")
    }

    func testAValidAccessTokenIsUsedAsIsWithItsAccountEmail() async throws {
        let store = InMemoryStore()
        signedIn(store, expires: Date().addingTimeInterval(600))
        let server = MockServer()
        let identity = try await SessionManager(store: store, http: server.transport).identity()
        XCTAssertEqual(identity.email, "person@example.com")
        XCTAssertEqual(server.calls.count, 0)
    }

    func testTheStoredSessionGivesItsAccountEmailWithoutAnyRequest() async {
        let store = InMemoryStore()
        signedIn(store, expires: Date().addingTimeInterval(-10))
        let server = MockServer()
        let session = SessionManager(store: store, http: server.transport)
        let email = await session.email
        XCTAssertEqual(email, "person@example.com")
        XCTAssertEqual(server.calls.count, 0)
        let none = await SessionManager(store: InMemoryStore(), http: server.transport).email
        XCTAssertNil(none)
    }

    func testTheGuestChoiceForgetsTheStoredTokensWithoutAnyRequest() async {
        let store = InMemoryStore()
        let device = DeviceIdentity.stable(in: store)
        signedIn(store, expires: Date().addingTimeInterval(600))
        let server = MockServer()
        let session = SessionManager(store: store, http: server.transport)
        await session.forget()
        XCTAssertNil(store.read("tokens"))
        XCTAssertEqual(DeviceIdentity.stable(in: store), device)
        XCTAssertEqual(server.calls.count, 0)
        let relaunched = await SessionManager(store: store, http: server.transport).isSignedIn
        XCTAssertEqual(StartMode(hasSession: relaunched, guest: true), .guest)
    }

    func testAKeychainThatKeepsTheTokensIsReportedAsNotForgotten() async {
        let stuck = StuckStore()
        signedIn(stuck, expires: Date().addingTimeInterval(600))
        let server = MockServer()
        let failed = await SessionManager(store: stuck, http: server.transport).forget()
        XCTAssertFalse(failed)
        XCTAssertNotNil(stuck.read("tokens"))
        let store = InMemoryStore()
        signedIn(store, expires: Date().addingTimeInterval(600))
        let forgotten = await SessionManager(store: store, http: server.transport).forget()
        XCTAssertTrue(forgotten)
        let nothingStored = await SessionManager(store: InMemoryStore(), http: server.transport).forget()
        XCTAssertTrue(nothingStored)
        XCTAssertEqual(server.calls.count, 0)
    }

    @MainActor
    func testGuestModeWaitsForTheForgetAndALoginWaitsForAForgetStillOnItsWay() async throws {
        for gone in [true, false] {
            let answer = await Forgetter { gone }.forget()
            XCTAssertEqual(answer, gone)
        }
        let steps = Steps()
        let (started, didStart) = AsyncStream<Void>.makeStream()
        let (release, doRelease) = AsyncStream<Void>.makeStream()
        let forgetter = Forgetter {
            didStart.yield()
            for await _ in release { break }
            await steps.add("forgotten")
            return true
        }
        let forgetting = Task { await forgetter.forget() }
        for await _ in started { break }
        let login = Task { await forgetter.settled(); await steps.add("login") }
        try await Task.sleep(nanoseconds: 50_000_000)
        let early = await steps.list
        XCTAssertEqual(early, [], "a login does not start while a forget is on its way")
        doRelease.yield()
        await login.value
        let forgotten = await forgetting.value
        XCTAssertTrue(forgotten)
        let order = await steps.list
        XCTAssertEqual(order, ["forgotten", "login"])
    }

    func testParallelCallersWithAnExpiredTokenShareASingleRefreshThatIsSaved() async throws {
        let store = InMemoryStore()
        signedIn(store, expires: Date().addingTimeInterval(-10))
        let renewed = renewed
        let server = MockServer { _, _ in try? await Task.sleep(nanoseconds: 50_000_000); return .json(renewed) }
        let session = SessionManager(store: store, http: server.transport)
        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0..<3 { group.addTask { try await session.identity().accessToken } }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        XCTAssertEqual(Set(tokens).count, 1)
        XCTAssertEqual(server.calls.count, 1)
        let saved = try JSONDecoder().decode(StoredSession.self, from: store.read("tokens")!)
        XCTAssertEqual(saved.tokens.refreshToken, "new-refresh")
        _ = try await session.identity()
        XCTAssertEqual(server.calls.count, 1)
    }

    func testAFailedRefreshIsNotRememberedAndKeepsTheSession() async throws {
        let store = InMemoryStore()
        signedIn(store, expires: Date().addingTimeInterval(-10))
        let renewed = renewed
        let server = MockServer { _, index in index == 0 ? .status(503) : .json(renewed) }
        let session = SessionManager(store: store, http: server.transport)
        do { _ = try await session.identity(); XCTFail("no error") } catch { XCTAssertEqual((error as? VelovError)?.code, .unavailable) }
        let signedIn = await session.isSignedIn
        XCTAssertTrue(signedIn)
        _ = try await session.identity()
        XCTAssertEqual(server.calls.count, 2)
    }

    func testARefusedRefreshTokenEndsTheSessionButKeepsTheDeviceId() async {
        let store = InMemoryStore()
        let device = DeviceIdentity.stable(in: store)
        signedIn(store, expires: Date().addingTimeInterval(-10))
        let session = SessionManager(store: store, http: MockServer { _, _ in .json(["error": "invalid_grant"], status: 400) }.transport)
        do { _ = try await session.identity(); XCTFail("no error") } catch { XCTAssertEqual((error as? VelovError)?.revoked, true) }
        XCTAssertNil(store.read("tokens"))
        XCTAssertEqual(DeviceIdentity.stable(in: store), device)
    }

    func testLogoutPostsTheRefreshTokenThenDeletesTheTokensAndKeepsTheDeviceId() async {
        let store = InMemoryStore()
        let device = DeviceIdentity.stable(in: store)
        signedIn(store, expires: Date().addingTimeInterval(600))
        let server = MockServer { _, _ in .status(204) }
        let session = SessionManager(store: store, http: server.transport)
        let confirmed = await session.logout()
        XCTAssertTrue(confirmed)
        XCTAssertEqual(parseForm(server.calls[0].body)["refresh_token"], "old-refresh")
        XCTAssertNil(store.read("tokens"))
        XCTAssertEqual(DeviceIdentity.stable(in: store), device)
        signedIn(store, expires: Date().addingTimeInterval(600))
        let answer = await SessionManager(store: store, http: MockServer { _, _ in .status(500) }.transport).logout()
        XCTAssertFalse(answer)
        XCTAssertNil(store.read("tokens"))
    }

    func testARefreshAnsweredAfterLogoutNeverSavesItsTokens() async {
        let store = InMemoryStore()
        signedIn(store, expires: Date().addingTimeInterval(-10))
        let renewed = renewed
        let (started, didStart) = AsyncStream<Void>.makeStream()
        let (release, doRelease) = AsyncStream<Void>.makeStream()
        let server = MockServer { call, _ in
            guard parseForm(call.body)["grant_type"] == "refresh_token" else { return .status(204) }
            didStart.yield()
            for await _ in release { break }
            return .json(renewed)
        }
        let session = SessionManager(store: store, http: server.transport)
        let refresh = Task { try await session.identity() }
        for await _ in started { break }
        let confirmed = await session.logout()
        XCTAssertTrue(confirmed)
        doRelease.yield()
        do { _ = try await refresh.value; XCTFail("the late refresh must not revive the session") } catch {
            XCTAssertEqual((error as? VelovError)?.revoked, true)
        }
        XCTAssertNil(store.read("tokens"))
        let signedIn = await session.isSignedIn
        XCTAssertFalse(signedIn)
    }

    func testASignInUsesTheStoredDeviceIdAndSavesTheTokens() async throws {
        let store = InMemoryStore()
        let device = DeviceIdentity.stable(in: store)
        let server = AuthTests().realm(TestSigner())
        let session = SessionManager(store: store, http: server.transport)
        try await session.signIn(email: "person@example.com", code: "123456")
        XCTAssertEqual(parseForm(server.calls[2].body)["device_id"], device)
        XCTAssertNotNil(store.read("tokens"))
        let identity = try await session.identity()
        XCTAssertEqual(identity.email, "person@example.com")
    }
}

private final class StuckStore: SecureStore, @unchecked Sendable {
    private let kept = InMemoryStore()
    func read(_ key: String) -> Data? { kept.read(key) }
    func write(_ key: String, _ value: Data) -> Bool { kept.write(key, value) }
    func delete(_ key: String) -> Bool { false }
}

private actor Steps {
    private(set) var list: [String] = []
    func add(_ step: String) { list.append(step) }
}
