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
