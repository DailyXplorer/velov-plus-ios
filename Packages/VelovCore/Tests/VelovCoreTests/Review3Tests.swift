import XCTest
@testable import VelovCore

private actor Steps {
    var items: [String] = []
    func add(_ item: String) { items.append(item) }
}

private final class Ticks: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func tick() -> Date {
        defer { now += 30 }
        return now
    }
}

private func stats(_ balance: Double) -> Stats {
    buildStats(StatsInput(trips: [], coords: [:], movements: [], balance: balance, now: Date(timeIntervalSince1970: 1_800_000_000)))
}

@MainActor
final class Review3Tests: XCTestCase {
    let accountId = "0b6e1f6c-1d2e-4f3a-9b8c-7d6e5f4a3b2c"
    let identity = Identity(accessToken: "user-identity-token", email: "person@example.com")

    func api(_ reply: @escaping @Sendable (Call) -> Reply?) -> VelovAPI {
        let accountId = accountId
        let server = MockServer { call, _ in
            if call.url.hasSuffix("/client_tokens") { return .json(["accessToken": "app"]) }
            if call.url.hasSuffix("/id") { return .json(accountId) }
            return reply(call) ?? .status(404)
        }
        return VelovAPI(transport: server.transport, pause: noPause)
    }

    func journal() -> TechnicalJournal {
        let name = "velov-tests-\(UUID().uuidString)"
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
        return TechnicalJournal(defaults: UserDefaults(suiteName: name)!)
    }

    func testUnreadableBookingsAreNeverProofThatNothingWasBooked() async throws {
        let bodies: [Any] = [[[String: Any]()], ["content": []], [["id": "bk-1"]], [["id": "bk-1", "stationNumber": 2002], ["stationNumber": 2003]], "maintenance"]
        for body in bodies {
            let api = api { $0.url.hasSuffix("/bookings") ? .json(body) : nil }
            do {
                let bookings = try await api.bookings(identity)
                XCTFail("\(body) gave \(bookings)")
            } catch {
                XCTAssertEqual((error as? VelovError)?.code, .unavailable, "\(body)")
            }
        }
        let none = try await api { $0.url.hasSuffix("/bookings") ? .json([]) : nil }.bookings(identity)
        XCTAssertEqual(bookingCheck(none, bike: 7), .unchanged, "only a readable empty list proves nothing was booked")
    }

    func testAMovementWithAnUnknownDirectionOrAnAmbiguousAmountNeverProvesAnInviteWasNotDebited() async throws {
        let movement = { (direction: String?, amount: Any) -> [String: Any] in
            var value: [String: Any] = ["id": "m-1", "createdAt": "2026-10-29T12:00:30", "amount": amount, "reason": "PROMOCODE"]
            if let direction { value["direction"] = direction }
            return value
        }
        let before = DebitBefore(at: date("2026-10-29T12:00:00"), cost: 50)
        let late = date("2026-10-29T12:10:00")
        let ledger = { (row: [String: Any]) async throws -> RewardLedger in
            try await self.api { call in
                call.url.hasSuffix("history?page=0") ? .json(["content": [row]]) : call.url.contains("history?page=") ? .json(["content": []]) : nil
            }.rewardLedger(self.identity)
        }
        for row in [movement("UNKNOWN", 50), movement(nil, 50), movement("debit", 50), movement("DEBIT", -50), movement("CREDIT", -50), movement("CREDIT", "50")] {
            do {
                let read = try await ledger(row)
                XCTAssertNotEqual(inviteDebit(before, ledger: read, now: late), .notDebited, "\(row)")
            } catch {
                XCTAssertTrue(error is ShapeError, "\(row): \(error)")
            }
        }
        let credit = try await ledger(movement("CREDIT", 50))
        XCTAssertEqual(credit.movements.map(\.amount), [50])
        XCTAssertEqual(inviteDebit(before, ledger: credit, now: late), .notDebited)
        let debit = try await ledger(movement("DEBIT", 50))
        XCTAssertEqual(inviteDebit(before, ledger: debit, now: late), .debited)
    }

    func testAWriteIsRefusedBeforeSendingWhenItsRegistryCannotBeSaved() async {
        let operations = Operations(backing: InMemoryOperationBacking(failing: true), account: "person@example.com")
        var sent = 0
        for key in [OperationKey.unlock(7), OperationKey.book(7), OperationKey.rate("t-1"), OperationKey.autoSpend, OperationKey.favorite(2002), OperationKey.profile] {
            let run = await operations.runOnce(key) { sent += 1; return Outcome(ok: true, httpStatus: 200) }
            XCTAssertEqual(run, .unsaved, key)
        }
        XCTAssertEqual(sent, 0)
        XCTAssertFalse(operations.busy())
    }

    func testStatsStartedForOneAccountAreNeverKeptForTheNextOne() async {
        let session = SessionGeneration()
        let cache = StatsScreenCache()
        let (started, didStart) = AsyncStream<Void>.makeStream()
        let (release, doRelease) = AsyncStream<Void>.makeStream()
        let first = Task {
            await cache.load(account: "a@example.com", session: session) {
                didStart.yield()
                for await _ in release { break }
                return stats(1)
            }
        }
        for await _ in started { break }
        session.invalidate()
        cache.clear()
        session.invalidate()
        doRelease.yield()
        let late = await first.value
        XCTAssertNil(late, "the answer for A is dropped")
        XCTAssertNil(cache.get("a@example.com"))
        XCTAssertNil(cache.get("b@example.com"))
        guard case .success(let fresh)? = await cache.load(account: "b@example.com", session: session, { stats(2) }) else { return XCTFail("B reads its own stats") }
        XCTAssertEqual(fresh.balance, 2)
        XCTAssertEqual(cache.get("b@example.com")?.balance, 2)
        XCTAssertNil(cache.get("a@example.com"))
    }

    func testTheStatsScreenCacheChecksAndStoresOnTheMainActorEvenWhenLoadedFromElsewhere() async {
        final class Seen: @unchecked Sendable { var mainThread: [Bool] = [] }
        let seen = Seen()
        let session = SessionGeneration()
        let cache = StatsScreenCache(now: {
            seen.mainThread.append(Thread.isMainThread)
            return Date(timeIntervalSince1970: 1_800_000_000)
        })
        let result = await Task.detached { await cache.load(account: "a", session: session) { stats(3) } }.value
        guard case .success(let loaded)? = result else { return XCTFail("the stats load") }
        XCTAssertEqual(loaded.balance, 3)
        XCTAssertEqual(seen.mainThread, [true], "the generation check and the store run on the main actor, like clear()")
    }

    func testEveryCallerOfASharedRefreshIsCheckedAgainstLogout() async {
        let helper = SessionTests()
        let store = InMemoryStore()
        helper.signedIn(store, expires: Date().addingTimeInterval(-10))
        let renewed = helper.renewed
        let (started, didStart) = AsyncStream<Void>.makeStream()
        let (release, doRelease) = AsyncStream<Void>.makeStream()
        let server = MockServer { call, _ in
            guard parseForm(call.body)["grant_type"] == "refresh_token" else { return .status(204) }
            didStart.yield()
            for await _ in release { break }
            return .json(renewed)
        }
        let session = SessionManager(store: store, http: server.transport)
        let first = Task { try await session.identity() }
        for await _ in started { break }
        let second = Task { try await session.identity() }
        try? await Task.sleep(nanoseconds: 100_000_000)
        _ = await session.logout()
        doRelease.yield()
        for caller in [first, second] {
            do {
                let identity = try await caller.value
                XCTFail("a caller went on with \(identity.email) after logout")
            } catch {
                XCTAssertEqual((error as? VelovError)?.revoked, true)
            }
        }
        XCTAssertNil(store.read("tokens"))
        XCTAssertEqual(server.calls.filter { parseForm($0.body)["grant_type"] == "refresh_token" }.count, 1)
    }

    func testAClearedMemoNeverJoinsNorRefillsFromAnOlderLoad() async throws {
        let memo = Memo<String>(ttl: 600)
        let (started, didStart) = AsyncStream<Void>.makeStream()
        let (release, doRelease) = AsyncStream<Void>.makeStream()
        let old = Task {
            try await memo.get("a") {
                didStart.yield()
                for await _ in release { break }
                return "before"
            }
        }
        for await _ in started { break }
        await memo.clear()
        let fresh = try await memo.get("a") { "after" }
        XCTAssertEqual(fresh, "after", "a read after the clear does not join the older one")
        doRelease.yield()
        _ = try await old.value
        let cached = try await memo.get("a") { "third" }
        XCTAssertEqual(cached, "after", "the older answer does not refill the cache")
    }

    func testAStatsInvalidationIsOrderedBeforeTheNextReadAndAnOlderLoadIsReadAgain() async {
        let session = SessionGeneration()
        let cache = StatsScreenCache()
        let steps = Steps()
        let (started, didStart) = AsyncStream<Void>.makeStream()
        let (release, doRelease) = AsyncStream<Void>.makeStream()
        let (gate, openGate) = AsyncStream<Void>.makeStream()
        var calls = 0
        let load = Task {
            await cache.load(account: "a", session: session) { () async throws -> Stats in
                calls += 1
                await steps.add("read \(calls)")
                if calls == 1 {
                    didStart.yield()
                    for await _ in release { break }
                }
                return stats(Double(calls))
            }
        }
        for await _ in started { break }
        cache.clear {
            for await _ in gate { break }
            await steps.add("forget")
        }
        doRelease.yield()
        for _ in 0..<20 { await Task.yield() }
        openGate.yield()
        guard case .success(let result)? = await load.value else { return XCTFail("the read is done again") }
        XCTAssertEqual(result.balance, 2, "the answer started before the invalidation is read again")
        let order = await steps.items
        XCTAssertEqual(order, ["read 1", "forget", "read 2"])
        XCTAssertEqual(cache.get("a")?.balance, 2)
    }

    func testTheContactFormAcceptsEveryMessageTheWebAcceptsWithTheSameByteBudget() {
        XCTAssertEqual(ContactBody.byteLimit, 10_240)
        let euro = ContactBody(complaintType: "TRIP", message: String(repeating: "€", count: 1400))
        XCTAssertEqual(orderedJSON([("complaintType", "TRIP"), ("message", euro.message)]).count, 4237)
        XCTAssertTrue(euro.isValid)
        let cjk = ContactBody(complaintType: "TRIP", message: String(repeating: "漢", count: 1500), tripToken: String(repeating: "T", count: 128))
        let worst = ContactBody(complaintType: "SUBSCRIPTION", message: "a" + String(repeating: "\u{1}", count: 1498) + "a", tripToken: String(repeating: "\"", count: 128))
        for body in [cjk, worst] {
            XCTAssertTrue(body.isValid)
            let bytes = orderedJSON([("complaintType", body.complaintType), ("message", body.message), ("tripToken", body.tripToken)]).count
            XCTAssertGreaterThan(bytes, 4096)
            XCTAssertLessThanOrEqual(bytes, ContactBody.byteLimit)
        }
        XCTAssertFalse(ContactBody(complaintType: "TRIP", message: String(repeating: "x", count: 1501)).isValid)
    }

    func testARatingOutcomeHasOneWordingPerCategoryLikeTheWeb() {
        XCTAssertEqual(ratingOutcome(Outcome.refusal("network", "")).message, "Vélo’v ne répond pas. La note a peut-être été enregistrée.")
        XCTAssertEqual(ratingOutcome(Outcome(ok: false, httpStatus: 400, code: "trips.exception.already.rated")).message, "Vélo’v a refusé cette note.")
        XCTAssertEqual(ratingOutcome(Outcome(ok: false, httpStatus: 502)).message, "Vélo’v n’a pas confirmé la note. Elle a peut-être été enregistrée.")
        XCTAssertEqual(ratingOutcome(Outcome(ok: false, httpStatus: 400)).message, "Vélo’v n’a pas confirmé la note. Elle a peut-être été enregistrée.")
        let expired = Outcome(ok: false, httpStatus: 401, code: "local.expired", message: Messages.sessionToRenew)
        XCTAssertEqual(ratingOutcome(expired), expired)
        XCTAssertEqual(ratingOutcome(Outcome(ok: true, httpStatus: 204)), Outcome(ok: true, httpStatus: 204))
    }

    func testANetworkFailureKeepsItsURLErrorCodeNameAndElapsedTime() async {
        XCTAssertEqual(NetworkFailure(code: -1001, elapsed: 30.02).line, "Délai dépassé après 30\u{a0}s · NSURLErrorTimedOut (-1001)")
        XCTAssertEqual(NetworkFailure(code: -1005, elapsed: 2.34).line, "Connexion perdue après 2,3\u{a0}s · NSURLErrorNetworkConnectionLost (-1005)")
        XCTAssertEqual(networkLine(URLError(.notConnectedToInternet)), "Pas de réseau · NSURLErrorNotConnectedToInternet (-1009)")
        XCTAssertEqual(networkLine(URLError(URLError.Code(rawValue: -4242))), "Erreur réseau · NSURLErrorDomain (-4242)")
        XCTAssertEqual(networkLine(CancellationError()), "Erreur réseau · CancellationError")

        let journal = journal()
        let ticks = Ticks()
        let server = MockServer { _, _ in .failure(.timedOut) }
        let transport = JournalTransport(server.transport, journal: journal, clock: { ticks.tick() })
        do {
            _ = try await transport.send(makeRequest(URL(string: "https://api.cyclocity.fr/contracts/lyon/accounts/\(accountId)/trips/ongoing")!, timeout: 8))
            XCTFail("no error")
        } catch {
            XCTAssertEqual(error as? NetworkFailure, NetworkFailure(code: -1001, elapsed: 30))
            XCTAssertEqual(networkLine(error), "Délai dépassé après 30\u{a0}s · NSURLErrorTimedOut (-1001)")
        }
        XCTAssertEqual(journal.entries.map(\.result), ["NSURLErrorTimedOut (-1001)"])
        XCTAssertEqual(journal.entries.first?.duration, 30)

        let release = try? await Writes.release(WriteAuth(accountId: accountId, token: "app", identity: "user"), subscriptionId: "sub-1", stationNumber: 2002,
                                                standNumber: 1, bikeNumber: 20449, http: transport)
        XCTAssertEqual(release?.code, "network")
        XCTAssertEqual(release?.detail, "Délai dépassé après 30\u{a0}s · NSURLErrorTimedOut (-1001)")
    }

    func testTheJournalKeepsTheLastFiftyRequestsWithoutAnyPersonalData() async throws {
        let journal = journal()
        let server = MockServer { call, _ in
            call.url.hasSuffix("/client_tokens") ? .json(["accessToken": "secret-app-token"]) : .json(["firstName": "Ada", "email": "person@example.com", "phoneNumber": "+33612345678"])
        }
        let transport = JournalTransport(server.transport, journal: journal)
        let base = "https://api.cyclocity.fr/contracts/lyon/accounts/\(accountId)"
        let headers = ["Authorization": "Taknv1 secret-app-token", "Identity": "user-identity-token"]
        let requests: [(String?, URLRequest)] = [
            (nil, makeRequest(URL(string: "https://api.cyclocity.fr/auth/environments/PRD/client_tokens")!, method: "POST", body: Data(#"{"code":"vls","key":"secret-app-key"}"#.utf8), timeout: 8)),
            (nil, makeRequest(URL(string: "https://api.cyclocity.fr/contracts/lyon/accounts/person%40example.com/id")!, headers: headers, timeout: 8)),
            (nil, makeRequest(URL(string: "\(base)/trips?status=FINISHED&page=0&size=100")!, headers: headers, timeout: 8)),
            (nil, makeRequest(URL(string: "https://api.cyclocity.fr/contracts/lyon/bikes?stationNumber=2002")!, headers: headers, timeout: 8)),
            ("favorite:2002", makeRequest(URL(string: "\(base)/stationbookmarks/2002/")!, method: "DELETE", headers: headers, timeout: 8)),
            ("unlock:20449", makeRequest(URL(string: "\(base)/subscriptions/sub-9f8e7d/trips")!, method: "POST", headers: headers, body: Data(#"{"bikeNumber":20449}"#.utf8), timeout: 8)),
            ("rate:trip-5a4b", makeRequest(URL(string: "\(base)/trips/trip-5a4b/rate")!, method: "POST", headers: headers, timeout: 8)),
            ("profile", makeRequest(URL(string: base)!, method: "PATCH", headers: headers, body: Data(#"{"phoneNumber":"+33612345678","lastName":"Lovelace"}"#.utf8), timeout: 8)),
            ("invite:\(accountDigest("person@example.com"))", makeRequest(URL(string: "\(base)/rewards/consume/promocode")!, method: "POST", headers: headers, timeout: 8)),
            (nil, makeRequest(URL(string: "https://iam.cyclocity.fr/realms/vls-default/login-actions/authenticate?session_code=abc123XYZ&execution=e1&client_id=vls-web-lyon&tab_id=Tab9")!,
                              method: "POST", body: formBody([("username", "person@example.com"), ("password", "s3cret-pass")]), timeout: 8)),
            (nil, makeRequest(URL(string: "https://velov.grandlyon.com/openid_connect_login?code=secret-code&state=s")!, timeout: 8))
        ]
        for (operation, request) in requests {
            _ = try await TechnicalJournal.$operation.withValue(operation) { try await transport.send(request) }
        }
        let entries = journal.entries
        XCTAssertEqual(entries.count, 10, "only Cyclocity requests are kept")
        XCTAssertEqual(entries.map(\.path), [
            "/realms/vls-default/login-actions/authenticate?session_code=•&execution=•&client_id=•&tab_id=•",
            "/contracts/lyon/accounts/•/rewards/consume/promocode",
            "/contracts/lyon/accounts/•",
            "/contracts/lyon/accounts/•/trips/•/rate",
            "/contracts/lyon/accounts/•/subscriptions/•/trips",
            "/contracts/lyon/accounts/•/stationbookmarks/2002",
            "/contracts/lyon/bikes?stationNumber=2002",
            "/contracts/lyon/accounts/•/trips?status=FINISHED&page=0&size=100",
            "/contracts/lyon/accounts/•/id",
            "/auth/environments/PRD/client_tokens"
        ])
        XCTAssertEqual(entries.map(\.operation), [nil, "invite", "profile", "rate", "unlock:20449", "favorite:2002", nil, nil, nil, nil])
        XCTAssertEqual(Set(entries.map(\.result)), ["HTTP 200"])
        let dump = String(decoding: try JSONEncoder().encode(entries), as: UTF8.self) + journal.export()
        for secret in ["secret-app-token", "secret-app-key", "user-identity-token", "Taknv1", "Authorization", "Identity", "person", "example.com", "%40",
                       "Ada", "Lovelace", "+33612345678", "0612345678", accountId, "sub-9f8e7d", "trip-5a4b", "abc123XYZ", "Tab9", "s3cret-pass", "secret-code",
                       accountDigest("person@example.com")] {
            XCTAssertFalse(dump.contains(secret), secret)
        }

        for index in 0..<60 {
            journal.record(makeRequest(URL(string: "https://api.cyclocity.fr/contracts/lyon/bikes?number=\(index)")!, timeout: 8), status: 200, error: nil,
                           duration: 0.1, at: Date(timeIntervalSince1970: Double(index)))
        }
        XCTAssertEqual(journal.entries.count, TechnicalJournal.capacity)
        XCTAssertEqual(TechnicalJournal.capacity, 50)
        XCTAssertEqual(journal.entries.first?.path, "/contracts/lyon/bikes?number=59", "newest first")
        XCTAssertEqual(journal.entries.last?.path, "/contracts/lyon/bikes?number=10")
        journal.clear()
        XCTAssertEqual(journal.entries, [])
    }

    func testTheJournalExportIsOnePlainLinePerRequestNewestFirst() {
        let journal = journal()
        let at = Date(timeIntervalSince1970: 1_793_275_200)
        TechnicalJournal.$operation.withValue("book:20449") {
            journal.record(makeRequest(URL(string: "https://api.cyclocity.fr/contracts/lyon/accounts/\(accountId)/bookings")!, method: "POST", timeout: 30),
                           status: 201, error: nil, duration: 0.4123, at: at)
        }
        journal.record(makeRequest(URL(string: "https://api.cyclocity.fr/contracts/lyon/accounts/\(accountId)/trips/ongoing")!, timeout: 8),
                       status: nil, error: -1005, duration: 2.5, at: at.addingTimeInterval(65))
        XCTAssertEqual(journal.export(timeZone: TimeZone(identifier: "UTC")!), """
            Journal technique Vélo’v+
            2026-10-29 12:01:05 · GET /contracts/lyon/accounts/•/trips/ongoing · NSURLErrorNetworkConnectionLost (-1005) · 2\u{a0}500\u{a0}ms
            2026-10-29 12:00:00 · POST /contracts/lyon/accounts/•/bookings · HTTP 201 · 412\u{a0}ms · book:20449
            """)
        XCTAssertEqual(redactedOperation("via:\(accountDigest("a@b.c")):trip-1"), "via")
        XCTAssertEqual(redactedOperation("autoRenewal:sub-1"), "autoRenewal")
        XCTAssertEqual(redactedOperation("autoSpend"), "autoSpend")
    }

    func testARatingThatGotNoAnswerKeepsThePlainMessageAndTheNetworkDetail() async throws {
        let ticks = Ticks()
        let server = MockServer { _, _ in .failure(.timedOut) }
        let transport = JournalTransport(server.transport, journal: journal(), clock: { ticks.tick() })
        let sent = ratingOutcome(try await Writes.rate(WriteAuth(accountId: accountId, token: "app", identity: "user"), tripId: "trip-1", bikeNumber: 20449, vote: .warn(2), http: transport))
        XCTAssertEqual(sent.message, Messages.ratingUnconfirmed)
        XCTAssertEqual(sent.detail, "Délai dépassé après 30\u{a0}s · NSURLErrorTimedOut (-1001)")
    }

    func testAPointsCheckThatFailsKeepsTheNetworkFailure() async {
        let ticks = Ticks()
        let accountId = accountId
        let server = MockServer { call, _ in
            if call.url.hasSuffix("/client_tokens") { return .json(["accessToken": "app"]) }
            if call.url.hasSuffix("/id") { return .json(accountId) }
            return .failure(.timedOut)
        }
        let api = VelovAPI(transport: JournalTransport(server.transport, journal: journal(), clock: { ticks.tick() }), pause: noPause)
        do {
            _ = try await api.rewardLedger(identity)
            XCTFail("no error")
        } catch {
            XCTAssertEqual((error as? NetworkFailure)?.line, "Délai dépassé après 30\u{a0}s · NSURLErrorTimedOut (-1001)")
        }
    }
}
