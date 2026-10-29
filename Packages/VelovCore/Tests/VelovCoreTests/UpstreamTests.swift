import XCTest
@testable import VelovCore

final class UpstreamTests: XCTestCase {
    let url = URL(string: "https://api.cyclocity.fr/contracts/lyon/stations/2002")!

    func get(_ url: URL) -> URLRequest { makeRequest(url, headers: ["Accept": "application/json"], timeout: 30) }

    func testAGatewayErrorIsRetriedWithAnEightSecondTimeoutPerAttempt() async throws {
        let server = MockServer { _, index in index == 0 ? .status(502, body: "Bad Gateway") : .json(["ok": true]) }
        let response = try await ReadClient(transport: server.transport, pause: noPause).fetchTransient(get(url))
        XCTAssertEqual(response.json?["ok"]?.bool, true)
        XCTAssertEqual(server.calls.count, 2)
        XCTAssertEqual(server.calls.map(\.request.timeoutInterval), [8, 8])
    }

    func testATimeoutANetworkFailureOrAnotherStatusIsNotRetried() async throws {
        let client = { (server: MockServer) in ReadClient(transport: server.transport, pause: noPause) }
        let timeout = MockServer { _, _ in .failure(.timedOut) }
        do { _ = try await client(timeout).fetchTransient(get(url)); XCTFail("no error") } catch { XCTAssertEqual((error as? URLError)?.code, .timedOut) }
        XCTAssertEqual(timeout.calls.count, 1)
        let offline = MockServer { _, _ in .failure(.cannotConnectToHost) }
        do { _ = try await client(offline).fetchTransient(get(url)); XCTFail("no error") } catch {}
        XCTAssertEqual(offline.calls.count, 1)
        let failing = MockServer { _, _ in .status(500) }
        let status = try await client(failing).fetchTransient(get(url)).status
        XCTAssertEqual(status, 500)
        XCTAssertEqual(failing.calls.count, 1)
    }

    func testTheLastGatewayErrorIsReturnedAfterThreeAttemptsWithAShortBackoff() async throws {
        let pauses = Recorder<Double>()
        let server = MockServer { _, _ in .status(503, body: "Bad Gateway") }
        let response = try await ReadClient(transport: server.transport, pause: { await pauses.add($0) }).fetchTransient(get(url))
        XCTAssertEqual(response.status, 503)
        XCTAssertEqual(server.calls.count, 3)
        let waited = await pauses.values
        XCTAssertEqual(waited, [0.4, 0.8])
    }

    func testOnlyReadsAndTheClientTokenRequestMayGoThroughTheRetryingClient() async throws {
        let server = MockServer { _, _ in .json([:]) }
        let client = ReadClient(transport: server.transport, pause: noPause)
        for method in ["POST", "DELETE", "PUT", "PATCH", "post"] {
            do {
                _ = try await client.fetchTransient(makeRequest(URL(string: "https://api.cyclocity.fr/contracts/lyon/accounts/a/bookings")!, method: method, timeout: 8))
                XCTFail(method)
            } catch { XCTAssert(error is RefusedRetry) }
        }
        XCTAssertEqual(server.calls.count, 0)
        _ = try await client.fetchTransient(makeRequest(URL(string: "https://api.cyclocity.fr/auth/environments/PRD/client_tokens")!, method: "POST", timeout: 8))
        XCTAssertEqual(server.calls.count, 1)
    }

    func tokens(_ values: [String]) -> (AppToken, Counter) {
        let counter = Counter()
        return (AppToken { values[await counter.next()] }, counter)
    }

    func testA401FromAStaleAppTokenRenewsTheTokenAndTriesOnceMore() async throws {
        let (source, counter) = tokens(["stale", "fresh"])
        let server = MockServer { call, _ in .status(call.header("Authorization") == "Taknv1 stale" ? 401 : 200) }
        let response = try await getWithAppToken(ReadClient(transport: server.transport, pause: noPause), source, url) { ["Authorization": "Taknv1 \($0)"] }
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(server.calls.map { $0.header("Authorization") }, ["Taknv1 stale", "Taknv1 fresh"])
        let requested = await counter.count
        XCTAssertEqual(requested, 2)
    }

    func testA401ThatSurvivesAFreshAppTokenIsReturnedAfterOneRetry() async throws {
        let (source, _) = tokens(["first", "second", "third"])
        let server = MockServer { _, _ in .status(401) }
        let response = try await getWithAppToken(ReadClient(transport: server.transport, pause: noPause), source, url) { ["Authorization": "Taknv1 \($0)"] }
        XCTAssertEqual(response.status, 401)
        XCTAssertEqual(server.calls.count, 2)
    }

    func testParallel401sRenewTheAppTokenOnceAndOnlyTheCurrentTokenIsDropped() async throws {
        let (source, counter) = tokens(["stale", "fresh", "unexpected"])
        let server = MockServer { call, _ in .status(call.header("Authorization") == "Taknv1 stale" ? 401 : 200) }
        let client = ReadClient(transport: server.transport, pause: noPause)
        _ = try await source.get()
        let url = url
        let statuses = try await withThrowingTaskGroup(of: Int.self) { group in
            for _ in 0..<3 { group.addTask { try await getWithAppToken(client, source, url) { ["Authorization": "Taknv1 \($0)"] }.status } }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        XCTAssertEqual(statuses, [200, 200, 200])
        var requested = await counter.count
        XCTAssertEqual(requested, 2)
        await source.drop("stale")
        let current = try await source.get()
        XCTAssertEqual(current, "fresh")
        requested = await counter.count
        XCTAssertEqual(requested, 2)
    }

    func testTheAppTokenIsAPostOfTheWebClientCredentialsWithABrowserAgent() async throws {
        let server = MockServer { call, _ in call.url.hasSuffix("/client_tokens") ? .json(["accessToken": "app"]) : .json([]) }
        let api = VelovAPI(transport: server.transport, pause: noPause)
        _ = try await api.stationBikes(2002)
        let calls = server.calls
        XCTAssertEqual(calls.map(\.method), ["POST", "GET"])
        XCTAssertEqual(calls[0].url, "https://api.cyclocity.fr/auth/environments/PRD/client_tokens")
        XCTAssertEqual(JSON.parse(calls[0].body)?["code"]?.string, "vls.web.lyon:PRD")
        XCTAssertEqual(calls[1].url, "https://api.cyclocity.fr/contracts/lyon/bikes?stationNumber=2002")
        XCTAssertEqual(calls[1].header("Authorization"), "Taknv1 app")
        XCTAssertEqual(calls[1].header("Accept"), "application/vnd.bikes.v4+json")
        for call in calls { XCTAssert(call.header("User-Agent")!.hasPrefix("Mozilla/"), call.url) }
    }

    func testStationBikesAreSortedByStandAndOneMalformedBikeDoesNotHideTheOthers() async throws {
        let server = MockServer { call, _ in
            call.url.hasSuffix("/client_tokens") ? .json(["accessToken": "app"])
                : .json([["number": 3, "standNumber": 9], ["number": "broken"], ["number": 2], ["number": 1, "standNumber": 4], ["number": 5, "standNumber": 4]])
        }
        let bikes = try await VelovAPI(transport: server.transport, pause: noPause).stationBikes(2002)
        XCTAssertEqual(bikes.map(\.number), [1, 5, 3, 2])
    }

    static let information: [String: Any] = ["data": ["stations": [
        ["station_id": "2002", "name": "2002 - BELLECOUR / SAINT-EXUPÉRY", "lat": 45.7578, "lon": 4.832, "address": "Place Bellecour"],
        ["station_id": "7001", "name": [["text": "GARE D’OULLINS", "language": "fr"]], "lat": 45.71, "lon": 4.81],
        ["station_id": "9001", "name": "", "lat": 45.7, "lon": 4.8]
    ]]]
    static let status: [String: Any] = ["last_updated": 1_772_444_000, "data": ["stations": [
        ["station_id": "2002", "num_vehicles_available": 5, "num_docks_available": 10, "is_renting": true, "vehicle_types_available": [["vehicle_type_id": "electrical", "count": 2]]],
        ["station_id": "7001", "num_bikes_available": 0, "num_docks_available": 20, "is_renting": 0],
        ["station_id": "9001", "num_docks_available": 1, "is_renting": 1]
    ]]]

    func testStationsAreOneSharedGBFSLoadNormalisedLikeTheWeb() async throws {
        let server = MockServer { call, _ in .json(call.url.hasSuffix("station_information.json") ? Self.information : Self.status) }
        let api = VelovAPI(transport: server.transport, pause: noPause)
        let loads = try await withThrowingTaskGroup(of: StationData.self) { group in
            for _ in 0..<3 { group.addTask { try await api.stations() } }
            return try await group.reduce(into: []) { $0.append($1) }
        }
        XCTAssertEqual(server.calls.count, 2)
        XCTAssertEqual(loads[1], loads[0])
        XCTAssertEqual(loads[0].updatedAt, Date(timeIntervalSince1970: 1_772_444_000))
        XCTAssertEqual(loads[0].stations.map { "\($0.name) \($0.mechanical) \($0.electrical) \($0.stands) \($0.open)" }, [
            "Bellecour / Saint-Exupéry 3 2 10 true", "Gare d’Oullins 0 0 20 false", "Station 9001 0 0 1 true"
        ])
        XCTAssertEqual(server.calls.map(\.url).sorted(), [
            "https://api.cyclocity.fr/contracts/lyon/gbfs/v3/station_information.json", "https://api.cyclocity.fr/contracts/lyon/gbfs/v3/station_status.json"
        ])
    }

    func testAFailedStationLoadIsAnUnavailableError() async {
        let server = MockServer { _, _ in .status(500) }
        do { _ = try await VelovAPI(transport: server.transport, pause: noPause).stations(); XCTFail("no error") }
        catch { XCTAssertEqual((error as? VelovError)?.code, .unavailable) }
    }

    func testAMemoSharesOneLoadKeepsItForItsTTLAndServesTheLastValueWhenStale() async throws {
        let clock = Clock()
        let memo = Memo<Int>(ttl: 45, stale: true, now: { clock.now })
        let loads = Counter()
        let first = try await memo.get("k") { await loads.next() }
        XCTAssertEqual(first, 0)
        clock.advance(44)
        let cached = try await memo.get("k") { await loads.next() }
        XCTAssertEqual(cached, 0)
        clock.advance(2)
        let stale = try await memo.get("k") { _ = await loads.next(); throw VelovError(.unavailable, "down") }
        XCTAssertEqual(stale, 0)
        let fresh = try await memo.get("k") { await loads.next() }
        XCTAssertEqual(fresh, 2)
        let strict = Memo<Int>(ttl: 45)
        do { _ = try await strict.get("k") { throw VelovError(.unavailable, "down") }; XCTFail("no error") } catch {}
        let after = try await strict.get("k") { 7 }
        XCTAssertEqual(after, 7)
    }
}

actor Counter {
    private(set) var count = 0
    func next() -> Int { defer { count += 1 }; return count }
}

actor Recorder<T: Sendable> {
    private(set) var values: [T] = []
    func add(_ value: T) { values.append(value) }
}

final class Clock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = date("2026-10-28T12:00:00Z")
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
}
