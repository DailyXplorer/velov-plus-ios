import XCTest
@testable import VelovCore

final class SessionBindingTests: XCTestCase {
    final class Ended: @unchecked Sendable {
        private let lock = NSLock()
        private var ended = false
        var value: Bool { lock.withLock { ended } }
        func end() { lock.withLock { ended = true } }
    }

    static let accountId = "0b6e1f6c-1d2e-4f3a-9b8c-7d6e5f4a3b2c"

    func cyclocity(_ ended: Ended, at marker: String, write: Reply = .json(["transactionState": "OK"])) -> MockServer {
        let account = "/accounts/\(Self.accountId)"
        return MockServer { call, _ in
            let url = call.url
            if url.contains(marker) { ended.end() }
            if url.hasSuffix("/client_tokens") { return .json(["accessToken": "app"]) }
            if call.method != "GET" { return write }
            if url.hasSuffix("/accounts/person%40example.com/id") { return .json(Self.accountId) }
            if url.contains("\(account)/subscriptions?periods=CURRENT") {
                return .json([["id": "sub-1", "type": "LT", "isLocked": false, "periods": [["id": "p-1", "renewalDetails": ["autoRenewalValue": false, "autoRenewalBtn": true]]]]])
            }
            if url.hasSuffix("\(account)/subscriptions/sub-1/rentbike") { return .json(true) }
            if url.hasSuffix("/stations/2002") { return .json(["id": "st-uuid", "number": 2002, "open": true, "availabilities": ["main": ["stands": 0]]]) }
            if url.hasSuffix("/bikes?stationNumber=2002") { return .json([["id": "bike-uuid", "number": 20449, "status": "AVAILABLE", "standNumber": 12, "isReserved": false]]) }
            if url.hasSuffix("\(account)/trips/ongoing") { return .json([["id": "t-9", "status": "STARTED", "startStation": 2002, "startDateTime": "2026-10-29T10:00:00"]]) }
            if url.hasSuffix("/rewards/configurations") { return .json([["name": "PROMOCODE", "enable": true, "reward": 50, "type": "VALUATION"]]) }
            if url.hasSuffix("\(account)/rewards") { return .json(["balance": 85]) }
            return .status(404)
        }
    }

    func identity(_ ended: Ended) -> Identity { Identity(accessToken: "user-access", email: "person@example.com", live: { !ended.value }) }
    func api(_ server: MockServer) -> VelovAPI { VelovAPI(transport: server.transport, pause: noPause) }
    func writes(_ server: MockServer) -> [String] { server.calls.filter { $0.method != "GET" && !$0.url.hasSuffix("/client_tokens") }.map(\.url) }

    func testAnUnlockWhoseSessionEndsDuringTheSubscriptionReadIsNeverSent() async {
        let ended = Ended()
        let server = cyclocity(ended, at: "/subscriptions?periods=CURRENT")
        let outcome = await attempt { try await self.api(server).unlock(self.identity(ended), stationNumber: 2002, standNumber: 12, bikeNumber: 20449).outcome }
        XCTAssertEqual(writes(server), [], "no bike is released once the session that confirmed the unlock is gone")
        XCTAssertFalse(outcome.isUncertain, "nothing was sent, so nothing is left to check")
        XCTAssertEqual(server.calls.filter { $0.url.hasSuffix("/trips/ongoing") }.count, 0)
    }

    func testNoWriteIsSentOnceItsSessionEndedDuringThePreflight() async {
        let cases: [(String, @Sendable (VelovAPI, Identity) async throws -> Outcome)] = [
            ("book", { try await $0.book($1, stationNumber: 2002, bikeNumber: 20449).outcome }),
            ("unlock", { try await $0.unlock($1, stationNumber: 2002, standNumber: 12, bikeNumber: 20449).outcome }),
            ("rate", { try await $0.rate($1, tripId: "t-1", bikeNumber: 20449, vote: .recommend) }),
            ("autoSpend", { try await $0.setAutoSpend($1, true).outcome }),
            ("favorite", { try await $0.setFavorite($1, station: 2002, on: true) }),
            ("receipt", { try await $0.receipt($1, subscriptionId: "sub-1", periodId: "p-1").outcome }),
            ("profile", { try await $0.updateProfile($1, ProfileBody(city: "Lyon")) }),
            ("renewal", { try await $0.setAutoRenewal($1, subscriptionId: "sub-1", autoRenewal: true).outcome }),
            ("via", { try await $0.requestExtraTime($1, stationNumber: 2002) }),
            ("contact", { try await $0.contactSupport($1, ContactBody(complaintType: "PAYMENT", message: "Bonjour")) }),
            ("invite", { try await $0.consumePromoCode($1, expectedCost: 50).outcome })
        ]
        for (name, write) in cases {
            let ended = Ended()
            let server = cyclocity(ended, at: "/accounts/person%40example.com/id")
            let outcome = await attempt { try await write(self.api(server), self.identity(ended)) }
            XCTAssertEqual(writes(server), [], name)
            XCTAssertFalse(outcome.isUncertain, name)
            XCTAssertEqual(server.calls.filter { $0.header("Identity") != nil }.count, 1, "\(name): no account read after the session ended")
        }
    }

    func testAFollowUpReadAfterTheSessionEndedIsNeverSent() async throws {
        let ended = Ended()
        let unlock = cyclocity(ended, at: "/subscriptions/sub-1/trips")
        let (outcome, ongoing) = try await api(unlock).unlock(identity(ended), stationNumber: 2002, standNumber: 12, bikeNumber: 20449)
        XCTAssertTrue(outcome.ok, "the answer still belongs to the account that sent the write")
        XCTAssertNil(ongoing)
        XCTAssertEqual(unlock.calls.filter { $0.url.hasSuffix("/trips/ongoing") }.count, 0)

        let renewalEnded = Ended()
        let renewal = cyclocity(renewalEnded, at: "/subscriptions/sub-1", write: .status(204))
        let result = try await api(renewal).setAutoRenewal(identity(renewalEnded), subscriptionId: "sub-1", autoRenewal: true)
        XCTAssertEqual(writes(renewal).count, 1)
        XCTAssertFalse(result.verified)
        XCTAssertEqual(renewal.calls.filter { $0.url.contains("/subscriptions?periods=CURRENT") }.count, 1, "the state is not read back for a session that ended")
    }

    func testAnAccountReadIsNeverRetriedOnceItsSessionEnded() async {
        for reply in [Reply.status(503), .status(401)] {
            let ended = Ended()
            let server = MockServer { call, _ in
                if call.url.hasSuffix("/client_tokens") { return .json(["accessToken": "app"]) }
                ended.end()
                return reply
            }
            do { _ = try await api(server).accountId(identity(ended)); XCTFail("\(reply)") } catch {
                XCTAssertEqual((error as? VelovError)?.revoked, true, "\(reply)")
            }
            XCTAssertEqual(server.calls.filter { $0.header("Identity") != nil }.count, 1, "\(reply): a guest never retries with the credentials of the session it left")
        }
    }

    func testAnIdentityIsLiveOnlyWhileItsSessionIsTheStoredOne() async throws {
        let store = InMemoryStore()
        let tokens = Tokens(accessToken: accessToken(expires: Date().addingTimeInterval(600)), refreshToken: "refresh", idToken: "identity", expiresIn: 600, refreshExpiresIn: 0)
        _ = store.write("tokens", try JSONEncoder().encode(StoredSession(tokens: tokens, obtainedAt: Date())))
        let manager = SessionManager(store: store, http: MockServer().transport)
        let identity = try await manager.identity()
        let before = await identity.live()
        XCTAssertTrue(before)
        await manager.forget()
        let after = await identity.live()
        XCTAssertFalse(after, "a guest never sends anything with the credentials of the session it left")
    }

    @MainActor
    func testARefreshAskedAfterTheSessionEndedNeverRunsSoAGuestStaysAGuest() async {
        let session = SessionGeneration(open: false)
        var reads = 0
        let atLaunch = await session.load { () async throws -> String in reads += 1; return "account" }
        XCTAssertNil(atLaunch, "no account is read before a session begins")
        session.begin()
        guard case .success? = await session.load({ () async throws -> String in reads += 1; return "A" }) else { return XCTFail("A reads its account") }
        session.invalidate()
        let late = await session.load { () async throws -> String in
            reads += 1
            throw VelovError.sessionRevoked
        }
        XCTAssertNil(late, "a refresh asked by a renewal answered after the expiry finds no session and so never signs the guest out")
        XCTAssertEqual(reads, 1)
    }

    @MainActor
    func testASlowLogoutLetsNoReadExposeTheLoginAndItsLateAnswerLeavesTheNextSessionAlone() async {
        let session = SessionGeneration(open: false)
        session.begin()
        session.invalidate()
        let (started, didStart) = AsyncStream<Void>.makeStream()
        let (answered, answer) = AsyncStream<Void>.makeStream()
        let logout = Task {
            await session.unchanged { () async -> Bool in
                didStart.yield()
                for await _ in answered { break }
                return true
            }
        }
        for await _ in started { break }
        var reads = 0
        let bookings = await session.load { () async throws -> [Booking] in
            reads += 1
            throw VelovError.sessionRevoked
        }
        XCTAssertNil(bookings, "coming back to the foreground during the logout expires nothing")
        XCTAssertEqual(reads, 0)
        session.begin()
        answer.yield()
        let late = await logout.value
        XCTAssertNil(late, "the late logout answer of A does not sign out the session opened meanwhile")
    }

    func testAnAutoSpendAnswerThatSaysTheOppositeIsNotASuccess() async throws {
        let auth = WriteAuth(accountId: Self.accountId, token: "app", identity: "user-access")
        let opposite = try await Writes.setAutoSpend(auth, true, http: MockServer { _, _ in .json(["autoSpend": false]) }.transport)
        XCTAssertFalse(opposite.outcome.ok)
        XCTAssertTrue(opposite.outcome.isUncertain, "a 2xx that contradicts the change proves nothing")
        XCTAssertNil(opposite.autoSpend)
        for reply in [Reply.status(204), .json(["autoSpend": true])] {
            let done = try await Writes.setAutoSpend(auth, true, http: MockServer { _, _ in reply }.transport)
            XCTAssertTrue(done.outcome.ok, "\(reply)")
            XCTAssertEqual(done.autoSpend, true)
        }
    }

    func testALogoutAnsweredWithAPageIsNotConfirmed() async {
        for (reply, confirmed) in [(Reply.status(204), true), (.status(200), true), (.status(200, body: "<html>Maintenance</html>"), false)] {
            let answer = await endSession(refreshToken: "refresh", idToken: nil, http: MockServer { _, _ in reply }.transport)
            XCTAssertEqual(answer, confirmed, "\(reply)")
        }
    }
}
