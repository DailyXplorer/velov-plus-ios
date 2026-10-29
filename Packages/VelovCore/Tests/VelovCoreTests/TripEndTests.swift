import XCTest
@testable import VelovCore

@MainActor
final class TripEndTests: XCTestCase {
    final class Store: TripEndStore {
        var values: [String: Any] = [:]
        func string(forKey key: String) -> String? { values[key] as? String }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
    }

    let now = date("2026-10-29T12:00:00")

    func finished(_ id: String, endedMinutesAgo: Double, rated: Bool = false, status: String = "FINISHED") -> Trip {
        let end = now.addingTimeInterval(-endedMinutesAgo * 60)
        return Trip(id: id, status: status, startedAt: end.addingTimeInterval(-600), endedAt: end, bikeNumber: 20449, isRated: rated)
    }

    func testFiveAndFourStarsRecommendThreeAndTwoReportAMinorProblemOneASeriousOne() {
        XCTAssertEqual((1...5).map(StarRating.vote), [.warn(30), .warn(60), .warn(60), .recommend, .recommend])
        XCTAssertEqual((1...5).map { StarRating.labels[$0]! }, ["À réparer", "Décevant", "Moyen", "Bien", "Parfait"])
    }

    func testARatingPostsTheStarsVoteOnceAndKeepsTheRawStatusOfARefusal() async throws {
        let auth = WriteAuth(accountId: "acc-1", token: "app", identity: "user")
        let server = MockServer { _, _ in .status(200, body: "{}") }
        let ok = try await Writes.rate(auth, tripId: "trip-1", bikeNumber: 20449, vote: StarRating.vote(2), http: server.transport)
        XCTAssertTrue(ok.ok)
        XCTAssertEqual(server.calls.map(\.bodyText), [#"{"bikeId":20449,"recommended":false,"contract":"lyon","rating":60}"#])
        let refused = MockServer { _, _ in .json(["code": "trips.exception.rating", "message": "Already rated"], status: 409) }
        let outcome = try await Writes.rate(auth, tripId: "trip-1", bikeNumber: 20449, vote: .recommend, http: refused.transport)
        XCTAssertEqual([String(outcome.httpStatus), outcome.code, outcome.detail], ["409", "trips.exception.rating", "Already rated"])
        XCTAssertEqual(outcome.message, "Vélo’v n’a pas enregistré la note.")
        let lost = MockServer { _, _ in .failure(.networkConnectionLost) }
        let silent = try await Writes.rate(auth, tripId: "trip-1", bikeNumber: 20449, vote: .recommend, http: lost.transport)
        XCTAssertEqual([String(silent.httpStatus), silent.code, silent.message], ["0", "network", Messages.ratingUnconfirmed])
        XCTAssertEqual(lost.calls.count, 1)
    }

    func testTheGreetingOffersOnlyTheLatestFinishedRateableTripNeverDismissedHere() {
        let store = Store()
        let latest = finished("late", endedMinutesAgo: 30)
        let trips = [finished("early", endedMinutesAgo: 90), latest, finished("error", endedMinutesAgo: 5, status: "ERROR")]
        XCTAssertEqual(latestFinished(trips)?.id, "late")
        XCTAssertEqual(tripToGreet(trips, store: store, now: now)?.id, "late")
        dismissTrip(store, "late")
        XCTAssertTrue(wasDismissed(store, "late"))
        XCTAssertNil(tripToGreet(trips, store: store, now: now))
        XCTAssertNil(tripToGreet([finished("rated", endedMinutesAgo: 10, rated: true)], store: Store(), now: now))
        XCTAssertNil(tripToGreet([finished("old", endedMinutesAgo: 181)], store: Store(), now: now))
    }

    final class Harness {
        var clock: Date
        var answers: [Result<TripCheck, Error>] = []
        var checks = 0
        var docked: [(String, Trip?)] = []
        var visible = true
        var timers: [(delay: TimeInterval, fire: @MainActor () async -> Void, cancelled: Bool)] = []
        init(clock: Date) { self.clock = clock }
        var pending: Int { timers.filter { !$0.cancelled }.count }
    }

    func watch(_ harness: Harness) -> DockWatch {
        DockWatch(check: {
            harness.checks += 1
            guard !harness.answers.isEmpty else { throw URLError(.notConnectedToInternet) }
            return try harness.answers.removeFirst().get()
        }, docked: { harness.docked.append(($0, $1)) }, visible: { harness.visible }, now: { harness.clock }, schedule: { delay, fire in
            harness.timers.append((delay, fire, false))
            let index = harness.timers.count - 1
            return { harness.timers[index].cancelled = true }
        })
    }

    func fire(_ harness: Harness) async {
        guard let index = harness.timers.lastIndex(where: { !$0.cancelled }) else { return XCTFail("no timer") }
        harness.timers[index].cancelled = true
        harness.clock += harness.timers[index].delay
        await harness.timers[index].fire()
    }

    func riding(_ id: String) -> TripCheck { TripCheck(ongoing: [Trip(id: id, status: "STARTED")], latest: nil) }

    func testAnOngoingTripIsPolledEvery20SecondsAndTheDockFiresOnceWithTheLatestTrip() async {
        let harness = Harness(clock: now)
        let watch = watch(harness)
        watch.follow("t-1")
        XCTAssertEqual(harness.timers.map(\.delay), [20])
        harness.answers = [.success(riding("t-1")), .success(TripCheck(ongoing: [], latest: finished("t-1", endedMinutesAgo: 0)))]
        await fire(harness)
        XCTAssertEqual(harness.checks, 1)
        XCTAssertEqual(harness.pending, 1)
        await fire(harness)
        XCTAssertEqual(harness.docked.map(\.0), ["t-1"])
        XCTAssertEqual(harness.docked.first?.1?.id, "t-1")
        XCTAssertFalse(watch.active)
        XCTAssertEqual(harness.pending, 0)
    }

    func testAFailedOrUnansweredCheckIsTriedAgainNextRoundAndNeverDocks() async {
        let harness = Harness(clock: now)
        let watch = watch(harness)
        watch.follow("t-1")
        harness.answers = [.failure(URLError(.timedOut)), .success(TripCheck(ongoing: nil, latest: nil))]
        await fire(harness)
        await fire(harness)
        XCTAssertEqual(harness.checks, 2)
        XCTAssertEqual(harness.timers.map(\.delay), [20, 40, 80])
        XCTAssertTrue(harness.docked.isEmpty)
        XCTAssertTrue(watch.active)
        XCTAssertEqual(harness.pending, 1)
    }

    func testAfterAnUnlockTheWatchWaitsForTheTripThenGivesUpAfterTwoMinutes() async {
        let harness = Harness(clock: now)
        let watch = watch(harness)
        watch.follow(nil)
        harness.answers = Array(repeating: .success(TripCheck(ongoing: [], latest: nil)), count: 6)
        for _ in 0..<5 { await fire(harness) }
        XCTAssertTrue(watch.active, "100 s after the unlock")
        await fire(harness)
        XCTAssertFalse(watch.active)
        XCTAssertTrue(harness.docked.isEmpty)

        let second = Harness(clock: now)
        let next = self.watch(second)
        next.follow(nil)
        second.answers = [.success(riding("t-2")), .success(TripCheck(ongoing: [], latest: nil))]
        await fire(second)
        await fire(second)
        XCTAssertEqual(second.docked.map(\.0), ["t-2"])
    }

    func testInTheBackgroundNothingIsSentAndTheForegroundChecksAtOnce() async {
        let harness = Harness(clock: now)
        let watch = watch(harness)
        watch.follow("t-1")
        harness.visible = false
        await fire(harness)
        XCTAssertEqual(harness.checks, 0)
        XCTAssertEqual(harness.pending, 0, "paused until the app comes back")
        harness.visible = true
        harness.answers = [.success(TripCheck(ongoing: [], latest: nil))]
        await watch.visibilityChanged()
        XCTAssertEqual(harness.checks, 1)
        XCTAssertEqual(harness.docked.map(\.0), ["t-1"])
    }

    func testTheWatchStopsAfterThreeHours() async {
        let harness = Harness(clock: now)
        let watch = watch(harness)
        watch.follow("t-1")
        harness.answers = Array(repeating: .success(riding("t-1")), count: 600)
        var rounds = 0
        while watch.active && rounds < 600 { await fire(harness); rounds += 1 }
        XCTAssertFalse(watch.active)
        XCTAssertEqual(harness.checks, 539, "3 h of 20 s rounds, the last one only stops")
        XCTAssertTrue(harness.docked.isEmpty)
    }

    func testOneCheckAtATimeAndAStopIgnoresTheAnswerInFlight() async {
        let harness = Harness(clock: now)
        var release: CheckedContinuation<Void, Never>?
        let watch = DockWatch(check: {
            harness.checks += 1
            await withCheckedContinuation { release = $0 }
            return TripCheck(ongoing: [], latest: nil)
        }, docked: { harness.docked.append(($0, $1)) }, visible: { true }, now: { harness.clock }, schedule: { delay, fire in
            harness.timers.append((delay, fire, false))
            return {}
        })
        watch.follow("t-1")
        harness.clock += 20
        let first = Task { await watch.visibilityChanged() }
        while release == nil { await Task.yield() }
        await watch.visibilityChanged()
        XCTAssertEqual(harness.checks, 1, "a second check waits for the first")
        watch.stop()
        release?.resume()
        await first.value
        XCTAssertTrue(harness.docked.isEmpty)
    }

    func testComingBackWaitsOnlyForWhatIsLeftOfTheDelay() async {
        let harness = Harness(clock: now)
        let watch = watch(harness)
        watch.follow("t-1")
        harness.clock += 5
        harness.visible = false
        await watch.visibilityChanged()
        XCTAssertEqual(harness.pending, 0)
        harness.clock += 5
        harness.visible = true
        await watch.visibilityChanged()
        XCTAssertEqual(harness.checks, 0, "no check sooner than 20 s after the last plan")
        XCTAssertEqual(harness.timers.last?.delay, 10)
        harness.answers = [.success(riding("t-1"))]
        await fire(harness)
        XCTAssertEqual(harness.checks, 1)
        XCTAssertEqual(harness.timers.last?.delay, 20)
    }

    func testErrorsAndRateLimitsBackOffToTwoMinutesAndAnAnswerResetsTheRhythm() async {
        let harness = Harness(clock: now)
        let watch = watch(harness)
        watch.follow("t-1")
        harness.answers = Array(repeating: .failure(VelovError(.unavailable, "429")), count: 4) + [.success(TripCheck(ongoing: nil, latest: nil)), .success(riding("t-1"))]
        for _ in 0..<6 { await fire(harness) }
        XCTAssertEqual(harness.timers.map(\.delay), [20, 40, 80, 120, 120, 120, 20])
        XCTAssertTrue(harness.docked.isEmpty)
        watch.stop()
        watch.follow("t-1")
        XCTAssertEqual(harness.timers.last?.delay, 20)
    }

    func testARateLimitedPollAnswersNoOngoingListSoTheWatchBacksOff() async throws {
        let identity = Identity(accessToken: "user-access", email: "person@example.com")
        let accountId = WriteFlowsTests.accountId
        let server = MockServer { call, _ in
            if call.url.hasSuffix("/client_tokens") { return .json(["accessToken": "app"]) }
            if call.url.hasSuffix("/id") { return .json(accountId) }
            return call.url.hasSuffix("/trips/ongoing") ? .status(429, headers: ["Retry-After": "60"]) : .status(404)
        }
        let check = try await VelovAPI(transport: server.transport, pause: noPause).tripCheck(identity)
        XCTAssertNil(check.ongoing)
        XCTAssertFalse(server.calls.contains { $0.url.contains("status=FINISHED") })
    }

    func testOnlyASureRefusalMayBeConfirmedAgain() {
        let sure = [
            Outcome.refusal("local.no.subscription", "x"),
            Outcome(ok: false, httpStatus: 400, code: "booking.exception.bike.already.reserved"),
            Outcome(ok: false, httpStatus: 200, transactionState: "NOK"),
            Outcome(ok: false, httpStatus: 409, transactionState: "NOT_CONNECTED"),
            Outcome(ok: false, httpStatus: 401, code: "local.expired")
        ]
        let uncertain = [
            Outcome.refusal("network", "x"),
            Outcome(ok: false, httpStatus: 0, code: nil),
            Outcome(ok: false, httpStatus: 200, transactionState: "TIME_OUT"),
            Outcome(ok: false, httpStatus: 502, code: "gateway"),
            Outcome(ok: false, httpStatus: 500, transactionState: "NOK"),
            Outcome(ok: false, httpStatus: 400),
            Outcome(ok: false, httpStatus: 200, code: "local.promo.unreadable")
        ]
        XCTAssertEqual(sure.filter(\.isUncertain), [])
        XCTAssertEqual(uncertain.filter { !$0.isUncertain }, [])
        XCTAssertFalse(Outcome(ok: true, httpStatus: 0).isUncertain)
    }

    func testNamesAreShownCapitalisedWithTheFrenchParticlesKeptLow() {
        let cases = [
            ("jean-pierre de la tour", "Jean-Pierre de la Tour"), ("D'ARTAGNAN", "D'Artagnan"), ("marie d’aubigné", "Marie d’Aubigné"),
            ("o'neil", "O'Neil"), ("  camille   martin ", "Camille Martin"), ("le goff", "Le Goff"), ("ÉLODIE", "Élodie"), ("", "")
        ]
        for (raw, shown) in cases { XCTAssertEqual(formatName(raw), shown, raw) }
    }

    func testNamesAreValidatedLikeTheWebAndSentFirstWithTheirOwnRefusalMessage() async throws {
        XCTAssertNil(ProfileBody(firstName: " Jean  Pierre ", lastName: "D’Artagnan-Lévêque").problem())
        XCTAssertEqual(ProfileBody(firstName: "Jean  Pierre").trimmedForSending.firstName, "Jean Pierre")
        let invalid: [(ProfileBody, ProfileField)] = [
            (ProfileBody(firstName: " "), .firstName), (ProfileBody(firstName: "-Jean"), .firstName), (ProfileBody(lastName: "R2D2"), .lastName),
            (ProfileBody(lastName: String(repeating: "a", count: 51)), .lastName), (ProfileBody(firstName: "Jean", lastName: "<b>"), .lastName)
        ]
        for (body, field) in invalid { XCTAssertEqual(body.problem(), field, "\(body)") }
        XCTAssertNil(ProfileBody(lastName: String(repeating: "a", count: 50)).problem())

        let auth = WriteAuth(accountId: "acc-1", token: "app", identity: "user")
        let server = MockServer { _, _ in .json([:]) }
        _ = try await Writes.setProfile(auth, ProfileBody(firstName: " Jean ", lastName: "Martin", city: "Lyon"), http: server.transport)
        XCTAssertEqual(server.calls.map(\.bodyText), [#"{"firstName":"Jean","lastName":"Martin","city":"Lyon"}"#])
        let refused = MockServer { _, _ in .json(["code": "accounts.exception.validation.failed"], status: 400) }
        let renamed = try await Writes.setProfile(auth, ProfileBody(lastName: "Martin"), http: refused.transport)
        XCTAssertEqual(renamed.message, "Vélo’v n’a pas accepté ce changement de nom.")
        let address = try await Writes.setProfile(auth, ProfileBody(city: "Lyon"), http: refused.transport)
        XCTAssertNotEqual(address.message, renamed.message)
    }

    func testThePollReadsTheOngoingTripsThenTheLatestFinishedOneOnlyOnceNoneIsLeft() async throws {
        let identity = Identity(accessToken: "user-access", email: "person@example.com")
        let accountId = WriteFlowsTests.accountId
        let ongoingTrips = MockLock<[Any]>([["id": "t-9", "status": "STARTED", "startStation": 2002, "startDateTime": "2026-10-29T10:00:00"]])
        let server = MockServer { call, _ in
            let url = call.url
            if url.hasSuffix("/client_tokens") { return .json(["accessToken": "app"]) }
            if url.hasSuffix("/accounts/person%40example.com/id") { return .json(accountId) }
            if url.hasSuffix("/trips/ongoing") { return .json(ongoingTrips.value) }
            if url.hasSuffix("/trips?status=FINISHED") {
                return .json([["id": "t-8", "status": "FINISHED", "startDateTime": "2026-10-29T09:00:00", "endDateTime": "2026-10-29T09:20:00"],
                              ["id": "t-9", "status": "FINISHED", "startDateTime": "2026-10-29T10:00:00", "endDateTime": "2026-10-29T10:12:00"]])
            }
            if url.contains("/gbfs/v3/station_information") { return .json(UpstreamTests.information) }
            if url.contains("/gbfs/v3/station_status") { return .json(UpstreamTests.status) }
            return .status(404)
        }
        let api = VelovAPI(transport: server.transport, pause: noPause)
        let riding = try await api.tripCheck(identity)
        XCTAssertEqual(riding.ongoing?.map(\.id), ["t-9"])
        XCTAssertNil(riding.latest)
        XCTAssertFalse(riding.historyRead)
        XCTAssertFalse(server.calls.contains { $0.url.contains("status=FINISHED") })
        ongoingTrips.value = []
        let docked = try await api.tripCheck(identity)
        XCTAssertEqual(docked.ongoing, [])
        XCTAssertEqual(docked.latest?.id, "t-9")
        XCTAssertEqual(server.calls.filter { $0.method != "GET" }.map(\.url), ["https://api.cyclocity.fr/auth/environments/PRD/client_tokens"])

        let down = MockServer { call, _ in
            if call.url.hasSuffix("/client_tokens") { return .json(["accessToken": "app"]) }
            if call.url.hasSuffix("/id") { return .json(accountId) }
            return call.url.hasSuffix("/trips/ongoing") ? .status(401) : .status(404)
        }
        do { _ = try await VelovAPI(transport: down.transport, pause: noPause).tripCheck(identity); XCTFail("no error") }
        catch { XCTAssertEqual((error as? VelovError)?.code, .expired) }

        let noHistory = MockServer { call, _ in
            if call.url.hasSuffix("/client_tokens") { return .json(["accessToken": "app"]) }
            if call.url.hasSuffix("/id") { return .json(accountId) }
            if call.url.hasSuffix("/trips/ongoing") { return .json([]) }
            return call.url.contains("status=FINISHED") ? .status(500) : .status(404)
        }
        let unread = try await VelovAPI(transport: noHistory.transport, pause: noPause).tripCheck(identity)
        XCTAssertEqual(unread.ongoing, [])
        XCTAssertFalse(unread.historyRead)
        let since = Date()
        XCTAssertEqual(unlockCheck(unread, bike: 7, since: since, now: since.addingTimeInterval(180)), .unknown)
        XCTAssertTrue(docked.historyRead)
    }
}

final class MockLock<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
