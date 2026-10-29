import XCTest
@testable import VelovCore

final class DashboardTests: XCTestCase {
    let identity = Identity(accessToken: "user-access", email: "person@example.com")
    let accountId = "0b6e1f6c-1d2e-4f3a-9b8c-7d6e5f4a3b2c"

    func cyclocity(failing: [String] = [], profileStatus: Int = 200) -> MockServer {
        let accountId = accountId
        return MockServer { call, _ in
            let url = call.url
            if url.hasSuffix("/client_tokens") { return .json(["accessToken": "app"]) }
            if failing.contains(where: url.contains) { return .status(500) }
            if url.contains("/gbfs/v3/station_information") { return .json(UpstreamTests.information) }
            if url.contains("/gbfs/v3/station_status") { return .json(UpstreamTests.status) }
            if url.hasSuffix("/accounts/person%40example.com/id") { return .json(accountId) }
            let account = "/accounts/\(accountId)"
            if url.hasSuffix(account) {
                return .json(["firstName": "Camille", "email": "person@example.com", "completion": 1, "phoneNumber": "", "address": ["name": "1 rue X", "complement": ""],
                              "stations": [2002, "7001", ["number": 9001], ["stationNumber": "2002"], "x"]], status: profileStatus)
            }
            if url.hasSuffix("\(account)/rewards") { return .json(["balance": 42, "autoSpend": true]) }
            if url.contains("\(account)/subscriptions?periods=CURRENT") {
                return .json([["id": "sub-1", "type": "LT", "isLocked": false, "periods": [["id": "p-1", "offerId": 7, "validityStart": "2026-01-01", "validityEnd": "2026-12-31T23:59:59", "renewalDetails": ["autoRenewalValue": true]]]]])
            }
            if url.contains("\(account)/subscriptions?periods=PAST") {
                return .json([["id": "sub-1", "type": "LT", "periods": [["id": "p-0", "offerId": 7, "validityStart": "2025-01-01"], ["id": "p-1", "offerId": 7, "validityStart": "2026-01-01"]]]])
            }
            if url.contains("\(account)/trips?status=") { return .json([["id": "t-1", "status": "FINISHED", "startStation": 2002, "endStation": 7001, "bikeType": 1, "duration": 12]]) }
            if url.hasSuffix("\(account)/trips/ongoing") { return .json([]) }
            if url.hasSuffix("\(account)/payment") { return .json(["paymentValid": false]) }
            if url.contains("\(account)/rewards/history") { return .json(["content": [["id": "m-1", "createdAt": "2026-10-01T10:00:00", "direction": "DEBIT", "amount": 10, "reason": "BIKE_BOOKING"]]]) }
            if url.hasSuffix("/offers") { return .json([["id": 7, "title": "Vélo’v Plus 1 an – paiement comptant"]]) }
            if url.hasSuffix("/rewards/configurations") {
                return .json([["name": "RATE_BIKE", "enable": true, "reward": 5, "type": "RULE"], ["name": "PROMOCODE", "enable": true, "reward": 50, "type": "VALUATION"], ["name": "UNKNOWN", "enable": true, "reward": 1, "type": "RULE"]])
            }
            if url.hasSuffix("\(account)/bookings") { return .json([]) }
            return .status(404)
        }
    }

    func testTheDashboardAssemblesEveryReadWithTheAccountAndAppTokens() async throws {
        let server = cyclocity()
        let data = try await VelovAPI(transport: server.transport, pause: noPause).dashboard(identity)
        XCTAssertEqual(data.warnings, [])
        XCTAssertEqual(data.profile.firstName, "Camille")
        XCTAssertNil(data.profile.phoneNumber)
        XCTAssertEqual(data.profile.address, "1 rue X")
        XCTAssertNil(data.profile.addressComplement)
        XCTAssertEqual(data.profile.favorites, [2002, 7001, 9001])
        XCTAssertEqual(data.rewards.balance, 42)
        XCTAssertEqual(data.rewards.total, 42)
        XCTAssertEqual(data.rewards.autoSpend, true)
        XCTAssertEqual(data.rewards.movements, [RewardMovement(id: "m-1", date: date("2026-10-01T10:00:00Z"), label: "Réservation d’un vélo", amount: -10)])
        XCTAssertEqual(data.rewards.rules.map(\.name), ["RATE_BIKE", "PROMOCODE"])
        XCTAssertEqual(data.rewards.rules.map(\.kind), [.earn, .spend])
        XCTAssertEqual(data.subscription.subscription?.title, "Vélo’v Plus 1 an – paiement comptant")
        XCTAssertEqual(data.subscription.subscription?.autoRenewal, true)
        XCTAssertEqual(data.subscription.subscription?.validUntil, date("2026-12-31T23:59:59Z"))
        XCTAssertEqual(data.receipts?.map(\.periodId), ["p-1", "p-0"])
        XCTAssertEqual(data.paymentValid, false)
        XCTAssertEqual(data.trips?.first?.startStation, "Bellecour / Saint-Exupéry")
        XCTAssertEqual(data.trips?.first?.bikeType, .electrical)
        XCTAssertEqual(data.ongoing, [])
        XCTAssertEqual(data.bookings, 0)
        for call in server.calls where call.url.contains("/accounts/") {
            XCTAssertEqual(call.header("Authorization"), "Taknv1 app", call.url)
            XCTAssertEqual(call.header("Identity"), "user-access", call.url)
            XCTAssertEqual(call.method, "GET")
        }
    }

    func testOptionalReadsDegradeToWarningsAndMissingPieces() async throws {
        let server = cyclocity(failing: ["/rewards", "/trips?status", "subscriptions?periods=CURRENT", "/gbfs/"])
        let data = try await VelovAPI(transport: server.transport, pause: noPause).dashboard(identity)
        XCTAssertNil(data.rewards.balance)
        XCTAssertNil(data.rewards.autoSpend)
        XCTAssertNil(data.trips)
        XCTAssertEqual(data.subscription, .unavailable)
        XCTAssertEqual(Set(data.warnings), [
            "Le solde de points est momentanément indisponible.", "L’historique des trajets est momentanément indisponible.",
            "L’abonnement n’a pas pu être actualisé.", "Les noms des stations sont momentanément indisponibles.",
            "L’historique des points est momentanément indisponible.", "Les règles de fidélité n’ont pas pu être actualisées."
        ])
    }

    func testTheProfileIsFatalAndAnExpiredSessionIsNotAWarning() async {
        do { _ = try await VelovAPI(transport: cyclocity(profileStatus: 500).transport, pause: noPause).dashboard(identity); XCTFail("no error") }
        catch { XCTAssertEqual((error as? VelovError)?.code, .unavailable) }
        let expired = MockServer { call, _ in call.url.hasSuffix("/client_tokens") ? .json(["accessToken": "app"]) : .status(401) }
        do { _ = try await VelovAPI(transport: expired.transport, pause: noPause).dashboard(identity); XCTFail("no error") }
        catch { XCTAssertEqual((error as? VelovError)?.code, .expired) }
    }

    func testBookingsFindTheirBikeNumbersBack() async throws {
        let accountId = accountId
        let server = MockServer { call, _ in
            let url = call.url
            if url.hasSuffix("/client_tokens") { return .json(["accessToken": "app"]) }
            if url.hasSuffix("/id") { return .json(accountId) }
            if url.hasSuffix("/bookings") { return .json([["id": "bk-1", "stationNumber": 2002, "standNumber": 4, "bikeId": "bike-uuid", "endTime": "2026-03-02T09:47:14"]]) }
            if url.contains("/bikes?stationNumber=2002") { return .json([["id": "bike-uuid", "number": 20449]]) }
            if url.contains("station_information") { return .json(UpstreamTests.information) }
            if url.contains("station_status") { return .json(UpstreamTests.status) }
            return .status(404)
        }
        let bookings = try await VelovAPI(transport: server.transport, pause: noPause).bookings(identity)
        XCTAssertEqual(bookings, [Booking(id: "bk-1", stationNumber: 2002, stationName: "Bellecour / Saint-Exupéry", standNumber: 4, bikeNumber: 20449,
                                          endsAt: date("2026-03-02T09:47:14Z"), lat: 45.7578, lon: 4.832)])
    }
}
