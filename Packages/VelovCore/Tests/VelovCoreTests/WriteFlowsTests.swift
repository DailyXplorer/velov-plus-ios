import XCTest
@testable import VelovCore

/// The writes as the app calls them (web `lib/velov.ts`): the reads before, the local refusals that send nothing,
/// then exactly one state-changing request.
final class WriteFlowsTests: XCTestCase {
    let identity = Identity(accessToken: "user-access", email: "person@example.com")
    static let accountId = "0b6e1f6c-1d2e-4f3a-9b8c-7d6e5f4a3b2c"
    var account: String { "https://api.cyclocity.fr/contracts/lyon/accounts/\(Self.accountId)" }

    /// One account, station 2002 full with bike 20449 on borne 12. `route` answers first; any other write gets `write`.
    func cyclocity(write: Reply = .json([:]), route: @escaping @Sendable (Call) -> Reply? = { _ in nil }) -> MockServer {
        let account = "/accounts/\(Self.accountId)"
        return MockServer { call, _ in
            let url = call.url
            if url.hasSuffix("/client_tokens") { return .json(["accessToken": "app"]) }
            if let reply = route(call) { return reply }
            if call.method != "GET" { return write }
            if url.hasSuffix("/accounts/person%40example.com/id") { return .json(Self.accountId) }
            if url.contains("\(account)/subscriptions?periods=CURRENT") {
                return .json([["id": "sub-1", "type": "LT", "isLocked": false, "periods": [["id": "p-1", "renewalDetails": ["autoRenewalValue": false, "autoRenewalBtn": true]]]]])
            }
            if url.hasSuffix("\(account)/subscriptions/sub-1/rentbike") { return .json(true) }
            if url.hasSuffix("/stations/2002") { return .json(["id": "st-uuid", "number": 2002, "open": true, "availabilities": ["main": ["stands": 0]]]) }
            if url.hasSuffix("/bikes?stationNumber=2002") { return .json([["id": "bike-uuid", "number": 20449, "status": "AVAILABLE", "standNumber": 12, "isReserved": false]]) }
            if url.contains("/gbfs/v3/station_information") { return .json(UpstreamTests.information) }
            if url.contains("/gbfs/v3/station_status") { return .json(UpstreamTests.status) }
            if url.hasSuffix("\(account)/trips/ongoing") { return .json([["id": "t-9", "status": "STARTED", "startStation": 2002, "startDateTime": "2026-10-29T10:00:00"]]) }
            if url.hasSuffix("/rewards/configurations") { return .json([["name": "PROMOCODE", "enable": true, "reward": 50, "type": "VALUATION"]]) }
            if url.hasSuffix("\(account)/rewards") { return .json(["balance": 85]) }
            return .status(404)
        }
    }

    func api(_ server: MockServer) -> VelovAPI { VelovAPI(transport: server.transport, pause: noPause) }
    func writes(_ server: MockServer) -> [Call] { server.calls.filter { $0.method != "GET" && !$0.url.hasSuffix("/client_tokens") } }

    // MARK: Booking

    func testABookingReadsTheIdsThenPostsOnceAndNamesTheStation() async throws {
        let server = cyclocity(write: .json(["id": "bk-1", "stationNumber": 2002, "standNumber": 12, "bikeId": "bike-uuid", "endTime": "2026-10-29T10:15:00"]))
        let (outcome, booking) = try await api(server).book(identity, stationNumber: 2002, bikeNumber: 20449)
        XCTAssertTrue(outcome.ok)
        let posts = writes(server)
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(posts[0].url, "\(account)/bookings")
        XCTAssertEqual(posts[0].bodyText, #"{"stationId":"st-uuid","stationNumber":2002,"standNumber":12,"subscriptionId":"sub-1","bikeId":"bike-uuid"}"#)
        XCTAssertEqual(posts[0].header("Authorization"), "Taknv1 app")
        XCTAssertEqual(posts[0].header("Identity"), "user-access")
        XCTAssertEqual(booking?.bikeNumber, 20449)
        XCTAssertEqual(booking?.standNumber, 12)
        XCTAssertNotEqual(booking?.stationName, "Station 2002")
        XCTAssertEqual(booking?.endsAt, date("2026-10-29T10:15:00"))
    }

    func testABookingThatCannotGoThroughIsRefusedHereWithoutAnyPost() async throws {
        let cases: [(String, Reply, String)] = [
            ("/subscriptions?periods=CURRENT", .json([]), "local.no.subscription"),
            ("/bikes?stationNumber=2002", .json([["id": "bike-uuid", "number": 20449, "status": "AVAILABLE", "standNumber": 12, "isReserved": true]]), "local.bike.reserved"),
            ("/bikes?stationNumber=2002", .json([["id": "bike-uuid", "number": 20449, "status": "BROKEN", "standNumber": 12]]), "local.bike.gone"),
            ("/bikes?stationNumber=2002", .json([]), "local.bike.gone"),
            ("/bikes?stationNumber=2002", .json([["id": "bike-uuid", "number": 20449, "status": "AVAILABLE"]]), "local.bike.no.stand"),
            ("/bikes?stationNumber=2002", .json([["number": 20449, "status": "AVAILABLE", "standNumber": 12]]), "local.missing.id"),
            ("/stations/2002", .status(404), "local.missing.id")
        ]
        for (path, reply, code) in cases {
            let server = cyclocity { $0.method == "GET" && $0.url.contains(path) ? reply : nil }
            let (outcome, booking) = try await api(server).book(identity, stationNumber: 2002, bikeNumber: 20449)
            XCTAssertEqual(outcome.code, code, path)
            XCTAssertEqual(outcome.httpStatus, 0)
            XCTAssertNil(booking)
            XCTAssertEqual(writes(server).count, 0, code)
        }
    }

    func testARefusedBookingIsNotRetried() async throws {
        let server = cyclocity(write: .json(["code": "bookings.exception.not.authorized"], status: 403))
        let (outcome, booking) = try await api(server).book(identity, stationNumber: 2002, bikeNumber: 20449)
        XCTAssertEqual(outcome.message, "Vous avez déjà une réservation en cours, ou moins de 10 points.")
        XCTAssertNil(booking)
        XCTAssertEqual(writes(server).count, 1)
    }

    // MARK: Release

    func testAnUnlockPostsOnceThenLooksAtTheOngoingTrip() async throws {
        let server = cyclocity(write: .json(["transactionState": "OK"]))
        let (outcome, ongoing) = try await api(server).unlock(identity, stationNumber: 2002, standNumber: 12, bikeNumber: 20449)
        XCTAssertTrue(outcome.ok)
        let posts = writes(server)
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(posts[0].url, "\(account)/subscriptions/sub-1/trips")
        XCTAssertEqual(posts[0].bodyText, #"{"stationNumber":2002,"standNumber":12,"bikeNumber":20449,"typeFrom":"SMARTPHONE"}"#)
        XCTAssertEqual(ongoing?.map(\.id), ["t-9"])
        XCTAssertEqual(server.calls.filter { $0.url.hasSuffix("/trips/ongoing") }.count, 1)
    }

    func testAnUnlockWithoutAnswerOrSubscriptionSendsNothingMore() async throws {
        let lost = cyclocity(write: .failure(.timedOut))
        let (outcome, ongoing) = try await api(lost).unlock(identity, stationNumber: 2002, standNumber: 12, bikeNumber: 20449)
        XCTAssertEqual(outcome.code, "network")
        XCTAssertNil(ongoing)
        XCTAssertEqual(writes(lost).count, 1)
        XCTAssertEqual(lost.calls.filter { $0.url.hasSuffix("/trips/ongoing") }.count, 0)
        let none = cyclocity { $0.url.contains("/subscriptions?periods=CURRENT") ? .json([]) : nil }
        let refused = try await api(none).unlock(identity, stationNumber: 2002, standNumber: 12, bikeNumber: 20449)
        XCTAssertEqual(refused.outcome.code, "local.no.subscription")
        XCTAssertEqual(writes(none).count, 0)
    }

    // MARK: Account

    func testTheAccountWritesGoOutOnceToTheAccount() async throws {
        let server = cyclocity(write: .json(["autoSpend": false]))
        let api = api(server)
        try await api.rate(identity, tripId: "t-1", bikeNumber: 20449, vote: .warn(60))
        let spend = try await api.setAutoSpend(identity, false)
        XCTAssertEqual(spend.autoSpend, false)
        _ = try await api.setFavorite(identity, station: 2002, on: true)
        _ = try await api.updateProfile(identity, ProfileBody(city: "Lyon"))
        XCTAssertEqual(writes(server).map { "\($0.method) \($0.url.replacingOccurrences(of: account, with: ""))" },
                       ["POST /trips/t-1/rate", "PATCH /rewards", "POST /stationbookmarks/2002/", "PATCH "])
        let invalid = try await api.updateProfile(identity, ProfileBody(phoneNumber: "06"))
        XCTAssertEqual(invalid.code, "local.profile.invalid")
        XCTAssertEqual(writes(server).count, 4)
    }

    // MARK: Auto-renewal

    func testARenewalChangeIsCheckedWrittenOnceAndReadBack() async throws {
        let reads = CallCounter()
        let server = cyclocity(write: .status(204)) { call in
            guard call.method == "GET", call.url.contains("/subscriptions?periods=CURRENT") else { return nil }
            let value = reads.next() == 0 ? false : true
            return .json([["id": "sub-1", "isLocked": false, "periods": [["id": "p-1", "renewalDetails": ["autoRenewalValue": value, "autoRenewalBtn": true]]]]])
        }
        let result = try await api(server).setAutoRenewal(identity, subscriptionId: "sub-1", autoRenewal: true)
        XCTAssertEqual(result, AutoRenewalResult(outcome: Outcome(ok: true, httpStatus: 204), autoRenewal: true, autoRenewalAllowed: true, verified: true))
        let patches = writes(server)
        XCTAssertEqual(patches.count, 1)
        XCTAssertEqual(patches[0].url, "\(account)/subscriptions/sub-1")
        XCTAssertEqual(patches[0].bodyText, #"{"isAutoRenewal":true}"#)
        XCTAssertEqual(reads.count, 2)
    }

    func testARenewalTheAccountMayNotChangeSendsNoPatch() async throws {
        for details in [["autoRenewalValue": true], ["autoRenewalBtn": true], [:]] as [[String: Any]] {
            let server = cyclocity { call in
                call.method == "GET" && call.url.contains("/subscriptions?periods=CURRENT")
                    ? .json([["id": "sub-1", "periods": [["id": "p-1", "renewalDetails": details]]]]) : nil
            }
            let result = try await api(server).setAutoRenewal(identity, subscriptionId: "sub-1", autoRenewal: false)
            XCTAssertEqual(result.outcome.code, "local.renewal.not.allowed")
            XCTAssertTrue(result.verified)
            XCTAssertEqual(writes(server).count, 0)
        }
    }

    func testAFailedRereadIsNotAFailedPatchAndNeverRepeatsIt() async throws {
        let reads = CallCounter()
        let server = cyclocity(write: .status(204)) { call in
            guard call.method == "GET", call.url.contains("/subscriptions?periods=CURRENT") else { return nil }
            return reads.next() == 0 ? .json([["id": "sub-1", "periods": [["renewalDetails": ["autoRenewalValue": true, "autoRenewalBtn": true]]]]]) : .status(500)
        }
        let result = try await api(server).setAutoRenewal(identity, subscriptionId: "sub-1", autoRenewal: false)
        XCTAssertEqual([result.outcome.ok, result.verified, result.autoRenewalAllowed], [true, false, false])
        XCTAssertNil(result.autoRenewal)
        XCTAssertEqual(writes(server).count, 1)
        let refused = cyclocity(write: .json(["code": "x"], status: 401))
        let failed = try await api(refused).setAutoRenewal(identity, subscriptionId: "sub-1", autoRenewal: true)
        XCTAssertEqual([failed.outcome.ok, failed.verified], [false, false])
        XCTAssertEqual(failed.outcome.httpStatus, 401)
        XCTAssertEqual(writes(refused).count, 1)
        XCTAssertEqual(refused.calls.filter { $0.url.contains("/subscriptions?periods=CURRENT") }.count, 1)
    }

    // MARK: "15 minutes de plus"

    func testExtraTimeFindsTheRentingSubscriptionRechecksTheStationAndPostsOnce() async throws {
        let server = cyclocity(write: .json(["transactionState": "OK"]))
        let outcome = try await api(server).requestExtraTime(identity, stationNumber: 2002)
        XCTAssertTrue(outcome.ok)
        let posts = writes(server)
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(posts[0].url, "\(account)/subscriptions/sub-1/via")
        XCTAssertEqual(posts[0].bodyText, #"{"stationId":2002}"#)
        let station = server.calls.first { $0.url.hasSuffix("/stations/2002") }
        XCTAssertEqual(station?.header("Identity"), "user-access")
        XCTAssertEqual(station?.header("Accept"), "application/vnd.station.v4+json")
    }

    func testExtraTimeIsRefusedHereWithoutATripOrAFullStation() async throws {
        let twoSubscriptions: Reply = .json([["id": "sub-1", "periods": [["id": "p"]]], ["id": "sub-2", "periods": [["id": "q"]]]])
        let cases: [(String, @Sendable (Call) -> Reply?)] = [
            ("local.via.trip", { $0.url.hasSuffix("/rentbike") ? .json(false) : nil }),
            ("local.via.trip", { $0.url.contains("/subscriptions?periods=CURRENT") ? twoSubscriptions : $0.url.hasSuffix("/rentbike") ? .json(true) : nil }),
            ("local.via.not.full", { $0.url.hasSuffix("/stations/2002") ? .json(["id": "st-uuid", "number": 2002, "open": true, "availabilities": ["main": ["stands": 3]]]) : nil }),
            ("local.via.not.full", { $0.url.hasSuffix("/stations/2002") ? .json(["id": "st-uuid", "number": 2002, "open": false, "availabilities": ["main": ["stands": 0]]]) : nil })
        ]
        for (code, route) in cases {
            let server = cyclocity(route: route)
            let outcome = try await api(server).requestExtraTime(identity, stationNumber: 2002)
            XCTAssertEqual(outcome.code, code)
            XCTAssertEqual(writes(server).count, 0)
        }
    }

    // MARK: Customer service

    func testAMessageGoesOutOnceAndAnInvalidOneNever() async throws {
        let server = cyclocity(write: .status(204))
        let outcome = try await api(server).contactSupport(identity, ContactBody(complaintType: "PAYMENT", message: "Bonjour"))
        XCTAssertTrue(outcome.ok)
        XCTAssertEqual(writes(server).map(\.url), ["\(account)/mail"])
        let invalid = try await api(server).contactSupport(identity, ContactBody(complaintType: "OTHER", message: "Bonjour"))
        XCTAssertEqual(invalid.code, "local.contact.invalid")
        XCTAssertEqual(writes(server).count, 1)
    }

    // MARK: Invitation code

    func testAnInvitationCodeChecksThePriceAndTheBalanceBeforeTheOneDebit() async throws {
        let server = cyclocity(write: .json(["promoCode": "INVITE-1"]))
        let result = try await api(server).consumePromoCode(identity, expectedCost: 50)
        XCTAssertEqual(result.promoCode, "INVITE-1")
        XCTAssertEqual(writes(server).map(\.url), ["\(account)/rewards/consume/promocode"])
        XCTAssertEqual(server.calls.first { $0.url.hasSuffix("/rewards/configurations") }?.header("Accept"), "application/vnd.rewards.v5+json")

        let changed = cyclocity(write: .json(["promoCode": "NO"]))
        let disabled = cyclocity { $0.url.hasSuffix("/rewards/configurations") ? .json([["name": "PROMOCODE", "enable": false, "reward": 50, "type": "VALUATION"]]) : nil }
        let poor = cyclocity { $0.method == "GET" && $0.url.hasSuffix("/rewards") ? .json(["balance": 49]) : nil }
        for (server, cost, code) in [(changed, 40, "local.promo.price.changed"), (disabled, 50, "local.promo.price.changed"), (poor, 50, "local.promo.balance")] {
            let refused = try await api(server).consumePromoCode(identity, expectedCost: cost)
            XCTAssertEqual(refused.outcome.code, code)
            XCTAssertNil(refused.promoCode)
            XCTAssertEqual(writes(server).count, 0)
        }
    }

    // MARK: Dashboard

    func testTheDashboardSaysWhetherTheRenewalMayChange() async throws {
        let server = cyclocity { call in
            let url = call.url
            if url.hasSuffix("/accounts/\(Self.accountId)") { return .json(["email": "person@example.com"]) }
            if url.contains("periods=PAST") || url.contains("/trips?") || url.hasSuffix("/bookings") { return .json([]) }
            return nil
        }
        let data = try await api(server).dashboard(identity)
        XCTAssertEqual(data.subscription.subscription?.autoRenewal, false)
        XCTAssertEqual(data.subscription.subscription?.autoRenewalAllowed, true)
        XCTAssertEqual(Subscription(id: nil, title: "", type: "LT", validUntil: nil, active: true, autoRenewal: nil).autoRenewalAllowed, false)
    }
}

/// A thread-safe call counter for mock routes.
final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    /// The count before this call.
    func next() -> Int { lock.withLock { defer { value += 1 }; return value } }
}
