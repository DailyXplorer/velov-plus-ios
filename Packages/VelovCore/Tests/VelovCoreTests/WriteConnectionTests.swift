import XCTest
@testable import VelovCore

final class Pauses: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Double] = []
    var all: [Double] { lock.withLock { values } }
    var record: @Sendable (Double) async -> Void { { [self] value in lock.withLock { values.append(value) } } }
}

final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private let code: URLError.Code

    init(throwing code: URLError.Code) { self.code = code }

    var requests: [String] { lock.withLock { recorded.map { "\($0.httpMethod ?? "GET") \($0.url!.absoluteString)" } } }

    func send(_ request: URLRequest, followRedirects: Bool) async throws -> HTTPResponse {
        if request.url!.absoluteString.hasSuffix("/client_tokens") { return HTTPResponse(status: 200, body: Data(#"{"accessToken":"app"}"#.utf8)) }
        lock.withLock { recorded.append(request) }
        throw URLError(code)
    }
}

final class SteadyClock: @unchecked Sendable {
    private let lock = NSLock()
    private var now = Date(timeIntervalSince1970: 1_793_380_000)
    var tick: @Sendable () -> Date { { [self] in lock.withLock { defer { now += 0.01 }; return now } } }
}

private final class InvalidationSpy: NSObject, URLSessionDelegate, @unchecked Sendable {
    let invalidated: XCTestExpectation
    init(_ invalidated: XCTestExpectation) { self.invalidated = invalidated }
    func urlSession(_ session: URLSession, didBecomeInvalidWithError error: Error?) { invalidated.fulfill() }
}

func makeJournal(_ test: XCTestCase) -> TechnicalJournal {
    let name = "velov-tests-\(UUID().uuidString)"
    test.addTeardownBlock { UserDefaults().removePersistentDomain(forName: name) }
    return TechnicalJournal(defaults: UserDefaults(suiteName: name)!)
}

extension WriteFlowsTests {
    static let tokens = "https://api.cyclocity.fr/auth/environments/PRD/client_tokens"

    func ongoingReads(_ server: MockServer) -> Int { server.calls.filter { $0.url.hasSuffix("/trips/ongoing") }.count }

    func testAnUnlockSendsItsPostThroughTheWriteTransportOnly() async throws {
        let reads = cyclocity()
        let sent = cyclocity(write: .json(["transactionState": "OK"]))
        let api = VelovAPI(transport: reads.transport, writes: sent.transport, pause: noPause)
        let (outcome, ongoing) = try await api.unlock(identity, stationNumber: 2002, standNumber: 12, bikeNumber: 20449)
        XCTAssertTrue(outcome.ok)
        XCTAssertEqual(sent.calls.map { "\($0.method) \($0.url)" }, ["POST \(Self.tokens)", "POST \(account)/subscriptions/sub-1/trips"])
        XCTAssertEqual(sent.calls.last?.bodyText, #"{"stationNumber":2002,"standNumber":12,"bikeNumber":20449,"typeFrom":"SMARTPHONE"}"#)
        XCTAssertEqual(writes(reads).count, 0, "no write on the pooled read session")
        XCTAssertEqual(ongoingReads(reads), 1)
        XCTAssertEqual(ongoing?.map(\.id), ["t-9"])
    }

    func testEveryAccountWriteGoesThroughTheWriteTransportOnly() async throws {
        let reads = cyclocity()
        let sent = cyclocity(write: .status(204))
        let api = VelovAPI(transport: reads.transport, writes: sent.transport, pause: noPause)
        _ = try await api.book(identity, stationNumber: 2002, bikeNumber: 20449)
        _ = try await api.rate(identity, tripId: "t-1", bikeNumber: 20449, vote: .warn(60))
        _ = try await api.setAutoSpend(identity, false)
        _ = try await api.setFavorite(identity, station: 2002, on: true)
        _ = try await api.setFavorite(identity, station: 2002, on: false)
        _ = try await api.updateProfile(identity, ProfileBody(city: "Lyon"))
        _ = try await api.setAutoRenewal(identity, subscriptionId: "sub-1", autoRenewal: true)
        _ = try await api.requestExtraTime(identity, stationNumber: 2002)
        _ = try await api.contactSupport(identity, ContactBody(complaintType: "PAYMENT", message: "Bonjour"))
        _ = try await api.consumePromoCode(identity, expectedCost: 50)
        _ = try await api.receipt(identity, subscriptionId: "sub-1", periodId: "p-1")
        XCTAssertEqual(reads.calls.filter { $0.method != "GET" }.map(\.url), [], "no POST, PATCH or DELETE on the pooled read session")
        XCTAssertEqual(sent.calls.map { "\($0.method) \($0.url.replacingOccurrences(of: account, with: ""))" }, [
            "POST \(Self.tokens)", "POST /bookings", "POST /trips/t-1/rate", "PATCH /rewards", "POST /stationbookmarks/2002/", "DELETE /stationbookmarks/2002/", "PATCH ",
            "PATCH /subscriptions/sub-1", "POST /subscriptions/sub-1/via", "POST /mail", "POST /rewards/consume/promocode",
            "POST /subscriptions/sub-1/periods/p-1/reports"
        ])
    }

    func testAConnectionLostUnlockIsNeverResentAndIsCheckedWithReadsOnly() async throws {
        let cases: [(URLError.Code, String)] = [
            (.networkConnectionLost, "Connexion perdue après 0\u{a0}s · NSURLErrorNetworkConnectionLost (-1005)"),
            (.timedOut, "Délai dépassé après 0\u{a0}s · NSURLErrorTimedOut (-1001)")
        ]
        for (code, line) in cases {
            let reads = cyclocity { $0.url.hasSuffix("/trips/ongoing") ? .json([]) : nil }
            let lost = FakeTransport(throwing: code)
            let pauses = Pauses()
            let api = VelovAPI(transport: reads.transport, writes: JournalTransport(lost, journal: makeJournal(self), clock: SteadyClock().tick), pause: pauses.record)
            let (outcome, _) = try await api.unlock(identity, stationNumber: 2002, standNumber: 12, bikeNumber: 20449)
            XCTAssertEqual(outcome.httpStatus, 0)
            XCTAssertEqual(outcome.code, "network")
            XCTAssertTrue(outcome.isUncertain)
            XCTAssertEqual(outcome.detail, line)
            let trip = try await api.watchUnlock(identity, bikeNumber: 20449)
            XCTAssertNil(trip)
            XCTAssertEqual(ongoingReads(reads), Reconcile.unlockPolls.count, "every planned check ran")
            XCTAssertEqual(pauses.all, Reconcile.unlockPolls)
            XCTAssertEqual(lost.requests, ["POST \(account)/subscriptions/sub-1/trips"], "never resent")
            XCTAssertEqual(writes(reads).count, 0)
        }
    }

    func testAnUncertainUnlockBecomesStartedWhenTheTripAppears() async throws {
        let polls = CallCounter()
        let reads = cyclocity { call in
            guard call.url.hasSuffix("/trips/ongoing") else { return nil }
            return polls.next() == 0 ? .json([])
                : .json([["id": "t-9", "bikeNumber": 20449, "status": "STARTED", "startStation": 2002, "startDateTime": "2026-10-29T10:00:00"]])
        }
        let lost = FakeTransport(throwing: .networkConnectionLost)
        let pauses = Pauses()
        let api = VelovAPI(transport: reads.transport, writes: lost, pause: pauses.record)
        let (outcome, _) = try await api.unlock(identity, stationNumber: 2002, standNumber: 12, bikeNumber: 20449)
        XCTAssertTrue(outcome.isUncertain)
        let trip = try await api.watchUnlock(identity, bikeNumber: 20449)
        XCTAssertEqual(trip?.id, "t-9")
        XCTAssertEqual(trip?.bikeNumber, 20449)
        XCTAssertEqual(polls.count, 2, "no read after the trip is found")
        XCTAssertEqual(pauses.all, [2, 3])
        XCTAssertEqual(lost.requests.count, 1)
    }

    func testAnUncertainUnlockIsNotConfirmedByAnotherBikesTrip() async throws {
        let reads = cyclocity { call in
            call.url.hasSuffix("/trips/ongoing") ? .json([["id": "t-1", "bikeNumber": 99999, "status": "STARTED", "startStation": 2002, "startDateTime": "2026-10-29T10:00:00"]]) : nil
        }
        let lost = FakeTransport(throwing: .networkConnectionLost)
        let api = VelovAPI(transport: reads.transport, writes: lost, pause: noPause)
        _ = try await api.unlock(identity, stationNumber: 2002, standNumber: 12, bikeNumber: 20449)
        let trip = try await api.watchUnlock(identity, bikeNumber: 20449)
        XCTAssertNil(trip)
        XCTAssertEqual(ongoingReads(reads), Reconcile.unlockPolls.count)
        XCTAssertEqual(lost.requests.count, 1)
    }

    func testOngoingReadFailuresKeepTheUnlockUncertain() async throws {
        for failure in [Reply.status(503), .failure(.timedOut)] {
            let reads = cyclocity { $0.url.hasSuffix("/trips/ongoing") ? failure : nil }
            let lost = FakeTransport(throwing: .networkConnectionLost)
            let api = VelovAPI(transport: reads.transport, writes: lost, pause: noPause)
            let (outcome, _) = try await api.unlock(identity, stationNumber: 2002, standNumber: 12, bikeNumber: 20449)
            XCTAssertTrue(outcome.isUncertain)
            let trip = try await api.watchUnlock(identity, bikeNumber: 20449)
            XCTAssertNil(trip)
            XCTAssertGreaterThanOrEqual(ongoingReads(reads), Reconcile.unlockPolls.count)
            XCTAssertEqual(lost.requests.count, 1)
        }
    }
}

final class WriteConnectionTests: XCTestCase {
    let accountId = "0b6e1f6c-1d2e-4f3a-9b8c-7d6e5f4a3b2c"

    func testFreshConnectionTransportUsesANewSessionPerRequestAndInvalidatesIt() async throws {
        let server = MockServer { call, _ in call.url.hasSuffix("/moved") ? .redirect("https://api.cyclocity.fr/target") : .json(["transactionState": "OK"]) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Mock-Server": server.id]
        let invalidated = expectation(description: "every session is invalidated")
        invalidated.expectedFulfillmentCount = 2
        let spy = InvalidationSpy(invalidated)
        let created = CallCounter()
        let transport = FreshConnectionTransport {
            _ = created.next()
            return URLSession(configuration: configuration, delegate: spy, delegateQueue: nil)
        }
        let first = try await transport.send(makeRequest(URL(string: "https://api.cyclocity.fr/first")!, method: "POST", timeout: 30))
        let second = try await transport.send(makeRequest(URL(string: "https://api.cyclocity.fr/moved")!, method: "POST", timeout: 30))
        XCTAssertEqual(first.status, 200)
        XCTAssertEqual(second.status, 307, "a write never follows a redirect")
        XCTAssertEqual(created.count, 2, "one session per request")
        XCTAssertEqual(server.calls.map(\.url), ["https://api.cyclocity.fr/first", "https://api.cyclocity.fr/moved"])
        await fulfillment(of: [invalidated], timeout: 2)
    }

    func testTheJournalNotesTheConnectionThatCarriedAFailedWrite() async throws {
        let journal = makeJournal(self)
        let server = MockServer { _, _ in .failure(.networkConnectionLost) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Mock-Server": server.id]
        let transport = JournalTransport(FreshConnectionTransport(configuration: configuration), journal: journal)
        let post = makeRequest(URL(string: "https://api.cyclocity.fr/contracts/lyon/accounts/\(accountId)/subscriptions/sub-1/trips")!, method: "POST", timeout: 30)
        do {
            _ = try await transport.send(post)
            XCTFail("no error")
        } catch {
            XCTAssertEqual((error as? NetworkFailure)?.code, -1005)
        }
        let entry = try XCTUnwrap(journal.entries.first)
        XCTAssertEqual(entry.result, "NSURLErrorNetworkConnectionLost (-1005)")
        XCTAssertEqual(entry.connection?.contains("new connection · sent"), true, String(describing: entry.connection))
        XCTAssertTrue(journal.export().contains(" · new connection · sent"))
    }

    func testJournalKeepsWritesAndTheirReadsPastTheReadRing() {
        let journal = makeJournal(self)
        let at = Date(timeIntervalSince1970: 1_793_380_000)
        let base = "https://api.cyclocity.fr/contracts/lyon/accounts/\(accountId)"
        let post = makeRequest(URL(string: "\(base)/subscriptions/sub-1/trips")!, method: "POST", timeout: 30)
        TechnicalJournal.$operation.withValue("unlock:52287") {
            journal.record(post, status: nil, error: -1005, duration: 0.01, at: at.addingTimeInterval(-TechnicalJournal.writeRetention - 60))
        }
        TechnicalJournal.$operation.withValue("unlock:50519") {
            journal.record(makeRequest(URL(string: "\(base)/subscriptions?periods=CURRENT&typeList=ST&typeList=LT&isLocked=false")!, timeout: 8),
                           status: 200, error: nil, duration: 0.2, at: at)
            journal.record(post, status: nil, error: -1005, duration: 0.01, at: at.addingTimeInterval(0.3))
        }
        for index in 0..<300 {
            journal.record(makeRequest(URL(string: "https://api.cyclocity.fr/contracts/lyon/bikes?number=\(index)")!, timeout: 8), status: 200, error: nil,
                           duration: 0.1, at: at.addingTimeInterval(1 + Double(index)))
        }
        let entries = journal.entries
        XCTAssertEqual(entries.filter { $0.operation == nil }.count, TechnicalJournal.capacity, "the read ring stays capped")
        XCTAssertEqual(entries.compactMap(\.operation), ["unlock:50519", "unlock:50519"], "the write and its read survive, the old write is dropped")
        let export = journal.export(timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertTrue(export.contains("POST /contracts/lyon/accounts/•/subscriptions/•/trips · NSURLErrorNetworkConnectionLost (-1005) · 10\u{a0}ms · unlock:50519"), export)
        XCTAssertTrue(export.contains("GET /contracts/lyon/accounts/•/subscriptions?periods=CURRENT&typeList=ST&typeList=LT&isLocked=false · HTTP 200 · 200\u{a0}ms · unlock:50519"))
        XCTAssertEqual(entries.first?.path, "/contracts/lyon/bikes?number=299", "newest first")
    }
}
