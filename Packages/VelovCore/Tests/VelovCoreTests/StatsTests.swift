import XCTest
@testable import VelovCore

final class StatsTests: XCTestCase {
    let now = date("2026-10-29T11:00:00Z")
    let coords: [Int: GeoPoint] = [1: GeoPoint(lat: 45.75, lon: 4.83), 2: GeoPoint(lat: 45.76, lon: 4.85)]

    func trip(_ id: String, _ start: String, minutes: Double? = 10, from: Int? = 1, to: Int? = 2, bike: Int? = 100, type: BikeType = .mechanical,
              price: Double? = 0, status: String = "FINISHED", earned: Double = 0) -> Trip {
        Trip(id: id, status: status, startedAt: date(start), startStation: from.map { "Station \($0)" }, endStation: to.map { "Station \($0)" },
             startStationNumber: from, endStationNumber: to, bikeNumber: bike, bikeType: type, duration: minutes, price: price, pointsEarned: earned)
    }

    func input(_ trips: [Trip], movements: [StatsMovement]? = nil, balance: Double? = nil) -> StatsInput {
        StatsInput(trips: trips, coords: coords, movements: movements, balance: balance, now: now)
    }

    func testParisTimeFollowsLyonsCalendarAcrossMidnightAndSummerTime() {
        XCTAssertEqual(parisTime(date("2026-10-28T23:30:00Z")), ParisTime(day: "2026-10-29", month: "2026-10", hour: 0, weekday: 3))
        XCTAssertEqual(parisTime(date("2026-07-31T22:30:00Z")), ParisTime(day: "2026-08-01", month: "2026-08", hour: 0, weekday: 5))
        XCTAssertEqual(parisTime(date("2026-10-26T06:00:00Z")).weekday, 0)
        XCTAssertEqual(shiftDay("2026-03-01", -1), "2026-02-28")
        XCTAssertEqual(shiftDay("2026-12-31", 1), "2027-01-01")
        XCTAssertEqual(shiftMonth("2026-01", -11), "2025-02")
        XCTAssertEqual(shiftMonth("2026-12", 1), "2027-01")
    }

    func testTheDistanceIsTheStraightLineLengthenedZeroForALoopAndUnknownWithoutCoordinates() {
        let straight = haversine(coords[1]!, coords[2]!)
        XCTAssertEqual(estimateDistance(trip("a", "2026-10-28T10:00:00Z"), coords: coords)!, straight * 1.3, accuracy: 0.001)
        XCTAssertEqual(estimateDistance(trip("b", "2026-10-28T10:00:00Z", from: 1, to: 1), coords: coords), 0)
        XCTAssertNil(estimateDistance(trip("c", "2026-10-28T10:00:00Z", from: 1, to: 9), coords: coords))
        XCTAssertNil(estimateDistance(trip("d", "2026-10-28T10:00:00Z", from: nil, to: 2), coords: coords))

        let stats = periodStats(.all, input([trip("a", "2026-10-28T10:00:00Z"), trip("b", "2026-10-27T10:00:00Z", from: 1, to: 1), trip("c", "2026-10-26T10:00:00Z", from: 1, to: 9)]))
        XCTAssertEqual(stats.distance, DistanceEstimate(metres: (straight * 1.3).rounded(), known: 2))
        XCTAssertEqual(stats.co2Grams, (straight * 1.3 / 1000 * 200).rounded())
    }

    func testEachPeriodKeepsItsTripsByParisDayOrMonthAndDropsReversedOnes() {
        let trips = [
            trip("today", "2026-10-29T08:00:00Z", minutes: 12),
            trip("edge-in", "2026-09-29T22:30:00Z", minutes: 30),
            trip("edge-out", "2026-09-29T21:59:00Z", minutes: 7),
            trip("year", "2025-11-03T10:00:00Z", minutes: 20),
            trip("old", "2024-05-10T10:00:00Z", minutes: 5),
            trip("reversed", "2026-10-28T10:00:00Z", status: "REVERSED")
        ]
        let stats = buildStats(input(trips))
        XCTAssertEqual(stats.days30.trips, 2)
        XCTAssertEqual(stats.days30.minutes, 42)
        XCTAssertEqual(stats.days30.unit, .day)
        XCTAssertEqual(stats.days30.buckets.count, 30)
        XCTAssertEqual(stats.days30.buckets.first?.key, "2026-09-30")
        XCTAssertEqual(stats.days30.buckets.first?.minutes, 30)
        XCTAssertEqual(stats.days30.buckets.last, StatsBucket(key: "2026-10-29", minutes: 12, trips: 1))
        XCTAssertEqual(stats.months12.trips, 4)
        XCTAssertEqual(stats.months12.buckets.map(\.key).first, "2025-11")
        XCTAssertEqual(stats.months12.buckets.count, 12)
        XCTAssertEqual(stats.all.trips, 5)
        XCTAssertEqual(stats.all.buckets.first?.key, "2024-05")
        XCTAssertEqual(stats.all.buckets.count, 30)
        XCTAssertNil(stats.balance)
        XCTAssertEqual(stats.days30.heatmap[3][9], 1)
        XCTAssertEqual(stats.days30.heatmap.flatMap { $0 }.reduce(0, +), 2)
    }

    func testMoneyAndBikeTypes() {
        let trips = [
            trip("a", "2026-10-28T10:00:00Z", minutes: 4, type: .electrical, price: 150),
            trip("b", "2026-10-27T10:00:00Z", minutes: 5, price: -20),
            trip("c", "2026-10-26T10:00:00Z", minutes: 30, from: nil, to: nil, type: .unknown),
            trip("d", "2026-10-25T10:00:00Z", minutes: nil)
        ]
        var discounted = trips
        discounted[0].discount = 40
        let stats = periodStats(.days30, input(discounted))
        XCTAssertEqual(stats.spentCents, 150)
        XCTAssertEqual(stats.savedCents, 40)
        XCTAssertEqual(stats.bikeTypes, BikeTypeCounts(mechanical: 2, electrical: 1, unknown: 1))
        XCTAssertEqual(stats.minutes, 39)
    }

    func testTheStationsCountDeparturesAndArrivalsTogetherTopFiveThenByName() {
        var trips: [Trip] = []
        let counts = [10: 1, 11: 3, 12: 2, 13: 2, 14: 1, 15: 1]
        for (station, count) in counts.sorted(by: { $0.key < $1.key }) {
            for index in 0..<count { trips.append(trip("s\(station)-\(index)", "2026-10-28T10:00:00Z", from: station, to: 2)) }
        }
        trips.append(trip("loop", "2026-10-28T11:00:00Z", from: 14, to: 14))
        trips.append(trip("nameless", "2026-10-28T12:00:00Z", from: nil, to: nil))
        let stats = periodStats(.days30, input(trips))
        XCTAssertEqual(stats.stations, [StationCount(name: "Station 2", count: 10), StationCount(name: "Station 11", count: 3),
                                        StationCount(name: "Station 14", count: 3), StationCount(name: "Station 12", count: 2),
                                        StationCount(name: "Station 13", count: 2)])
    }

    func testRecordsLongestTripBusiestDayStreakAndFavouriteBike() {
        let trips = [
            trip("a", "2026-10-20T08:00:00Z", minutes: 15, bike: 7, type: .mechanical),
            trip("b", "2026-10-21T08:00:00Z", minutes: 45, bike: 7, type: .electrical),
            trip("c", "2026-10-22T08:00:00Z", minutes: 10, bike: 8),
            trip("d", "2026-10-22T17:00:00Z", minutes: 12, bike: 8),
            trip("e", "2026-10-25T08:00:00Z", minutes: 45, bike: 9)
        ]
        XCTAssertEqual(periodStats(.days30, input(trips)).records, StatsRecords(longestMinutes: 45, busiestDayTrips: 2, streakDays: 3, bike: 8))
        XCTAssertEqual(periodStats(.days30, input([])).records, StatsRecords(longestMinutes: nil, busiestDayTrips: nil, streakDays: nil, bike: nil))
    }

    func testPointsEarnedComeFromTheMovementsAndTheBalanceFallsBackToTheirSum() {
        let movements = [StatsMovement(date: date("2026-10-28T10:00:00Z"), amount: 5), StatsMovement(date: date("2026-09-10T10:00:00Z"), amount: -10),
                         StatsMovement(date: date("2025-01-10T10:00:00Z"), amount: 50), StatsMovement(date: nil, amount: 1000)]
        XCTAssertEqual(periodStats(.months12, input([], movements: movements)).pointsEarned, 5)
        XCTAssertEqual(periodStats(.all, input([], movements: movements)).pointsEarned, 55)
        XCTAssertEqual(periodStats(.days30, input([trip("a", "2026-10-28T10:00:00Z", earned: 10)])).pointsEarned, 10)
        XCTAssertEqual(buildStats(input([], movements: movements, balance: 100)).balance, 100)
        XCTAssertEqual(buildStats(input([], movements: movements)).balance, 1045)
        XCTAssertNil(buildStats(input([])).balance)
        XCTAssertTrue(buildStats(input([])).complete)
        var partial = input([])
        partial.complete = false
        XCTAssertFalse(buildStats(partial).complete)
    }

    func testThousandsUseANarrowNoBreakSpace() {
        XCTAssertEqual(formatNumber(1240), "1\u{202F}240")
        XCTAssertEqual(formatNumber(123456.0), "123\u{202F}456")
        XCTAssertEqual(formatNumber(999), "999")
    }

    func testPartialStatsAreKeptOneMinuteAndCompleteOnesTenMinutes() async throws {
        let clock = StatsClock()
        let memo = Memo<Stats>(ttl: { $0.complete ? 10 * 60 : 60 }, now: { clock.now })
        var partial = buildStats(input([]))
        partial.complete = false
        let loads = StatsLoads()
        _ = try await memo.get("a") { await loads.add(); return partial }
        clock.now = clock.now.addingTimeInterval(59)
        _ = try await memo.get("a") { await loads.add(); return partial }
        var count = await loads.value
        XCTAssertEqual(count, 1)
        clock.now = clock.now.addingTimeInterval(2)
        let complete = buildStats(input([]))
        _ = try await memo.get("a") { await loads.add(); return complete }
        clock.now = clock.now.addingTimeInterval(9 * 60)
        _ = try await memo.get("a") { await loads.add(); return complete }
        count = await loads.value
        XCTAssertEqual(count, 2)
    }

    struct Boom: Error {}

    func testCollectPagesStopsOnAnEmptyOrRepeatedPageAndKeepsWhatWasReadOnALateFailure() async throws {
        let empty = try await collectPages(id: { $0 }) { page in page < 2 ? ["p\(page)a", "p\(page)b"] : [] }
        XCTAssertEqual(empty.items, ["p0a", "p0b", "p1a", "p1b"])
        XCTAssertTrue(empty.complete)

        var asked: [Int] = []
        let repeated = try await collectPages(id: { $0 }) { page in asked.append(page); return ["same", "other"] }
        XCTAssertEqual(repeated.items, ["same", "other"])
        XCTAssertTrue(repeated.complete)
        XCTAssertEqual(asked, [0, 1])

        let capped = try await collectPages(maxPages: 3, id: { $0 }) { page in ["p\(page)"] }
        XCTAssertEqual(capped.items, ["p0", "p1", "p2"])
        XCTAssertFalse(capped.complete)

        let late = try await collectPages(id: { $0 }) { page in if page == 1 { throw Boom() }; return ["p\(page)"] }
        XCTAssertEqual(late.items, ["p0"])
        XCTAssertFalse(late.complete)

        do {
            _ = try await collectPages(id: { (item: String) in item }) { _ in throw Boom() }
            XCTFail("the first page's failure must throw")
        } catch is Boom {}
    }

    func testTheAPIReadsEveryPageInTurnWithGETsOnlyAndKeepsTheResultTenMinutes() async throws {
        let accountId = "0b6e1f6c-1d2e-4f3a-9b8c-7d6e5f4a3b2c"
        let account = "/accounts/\(accountId)"
        let raw = { (id: String, start: String) -> [String: Any] in
            ["id": id, "status": "FINISHED", "startDateTime": start, "startStation": 2002, "endStation": 7001, "bikeNumber": 4, "bikeType": 1, "duration": 12, "price": 0]
        }
        let server = MockServer { call, _ in
            let url = call.url
            if url.hasSuffix("/client_tokens") { return .json(["accessToken": "app"]) }
            if url.contains("/gbfs/v3/station_information") { return .json(UpstreamTests.information) }
            if url.contains("/gbfs/v3/station_status") { return .json(UpstreamTests.status) }
            if url.hasSuffix("/accounts/person%40example.com/id") { return .json(accountId) }
            if url.contains("\(account)/trips?status=FINISHED&status=ERROR&status=REVERSED&page=0&size=100") {
                return .json([raw("t-1", "2026-10-28T09:00:00"), raw("t-2", "2026-10-27T09:00:00")])
            }
            if url.contains("\(account)/trips?status=FINISHED&status=ERROR&status=REVERSED&page=1&size=100") { return .json([raw("t-3", "2026-01-10T09:00:00")]) }
            if url.contains("\(account)/trips?") { return .json([]) }
            if url.contains("\(account)/rewards/history?page=0") {
                return .json(["content": [["id": "m-1", "createdAt": "2026-10-28T10:00:00", "direction": "CREDIT", "amount": 5]]])
            }
            if url.contains("\(account)/rewards/history?page=1") { return .status(500) }
            if url.hasSuffix("\(account)/rewards") { return .json(["balance": 42]) }
            return .status(404)
        }
        let clock = date("2026-10-29T11:00:00Z")
        let api = VelovAPI(transport: server.transport, pause: noPause)
        let identity = Identity(accessToken: "user-access", email: "person@example.com")
        let stats = try await api.stats(identity, now: { clock })
        XCTAssertEqual(stats.all.trips, 3)
        XCTAssertEqual(stats.days30.trips, 2)
        XCTAssertGreaterThan(stats.all.distance.metres, 0)
        XCTAssertTrue(stats.all.stations.map(\.name).contains("Bellecour / Saint-Exupéry"))
        XCTAssertEqual(stats.balance, 42)

        let paths = server.calls.map(\.url).filter { $0.contains("/trips?") || $0.contains("/rewards") }.map { $0.components(separatedBy: accountId).last! }
        XCTAssertEqual(paths, [
            "/trips?status=FINISHED&status=ERROR&status=REVERSED&page=0&size=100",
            "/trips?status=FINISHED&status=ERROR&status=REVERSED&page=1&size=100",
            "/trips?status=FINISHED&status=ERROR&status=REVERSED&page=2&size=100",
            "/rewards/history?page=0", "/rewards/history?page=1", "/rewards"
        ])
        XCTAssertEqual(Set(server.calls.filter { !$0.url.hasSuffix("/client_tokens") }.map(\.method)), ["GET"])
        XCTAssertEqual(server.calls.first { $0.url.contains("/trips?") }?.header("Accept"), "application/vnd.trip.v6+json")

        let count = server.calls.count
        _ = try await api.stats(identity, now: { clock })
        XCTAssertEqual(server.calls.count, count)
    }

    func testTheFirstHistoryPageFailingFailsTheStats() async {
        let server = MockServer { call, _ in
            if call.url.hasSuffix("/client_tokens") { return .json(["accessToken": "app"]) }
            if call.url.hasSuffix("/id") { return .json("0b6e1f6c-1d2e-4f3a-9b8c-7d6e5f4a3b2c") }
            return .status(500)
        }
        let api = VelovAPI(transport: server.transport, pause: noPause)
        do {
            _ = try await api.stats(Identity(accessToken: "a", email: "person@example.com"))
            XCTFail("expected a failure")
        } catch let error as VelovError {
            XCTAssertEqual(error.code, .unavailable)
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}

private final class StatsClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
}

private actor StatsLoads {
    var value = 0
    func add() { value += 1 }
}
