import XCTest
@testable import VelovCore

final class AccountWritesTests: XCTestCase {
    let auth = WriteAuth(accountId: "account/one", token: "app-token", identity: "user-token")
    let account = "https://api.cyclocity.fr/contracts/lyon/accounts/account%2Fone"
    let refusals = [400, 401, 403, 409, 429, 500, 502, 503, 504]

    func assertSigned(_ call: Call, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(call.header("Authorization"), "Taknv1 app-token", file: file, line: line)
        XCTAssertEqual(call.header("Identity"), "user-token", file: file, line: line)
        XCTAssert(call.header("User-Agent")?.hasPrefix("Mozilla/") == true, file: file, line: line)
    }

    func testAProfileChangeIsAPatchOfTheAccountWithOnlyTheChangedFieldsInTheAppsOrder() async throws {
        let server = MockServer { _, _ in .json([:]) }
        let body = ProfileBody(address: ProfileAddress(name: " 1 rue Exemple ", complement: ""), country: "FR", phoneNumber: "+33600000000")
        let outcome = try await Writes.setProfile(auth, body, http: server.transport)
        XCTAssertTrue(outcome.ok)
        XCTAssertEqual(server.calls.count, 1)
        let call = server.calls[0]
        XCTAssertEqual(call.url, account)
        XCTAssertEqual(call.method, "PATCH")
        XCTAssertEqual(call.header("Content-Type"), "application/vnd.account.v4+json")
        XCTAssertNil(call.header("Accept"))
        assertSigned(call)
        XCTAssertEqual(call.bodyText, #"{"country":"FR","phoneNumber":"+33600000000","address":{"name":"1 rue Exemple","complement":""}}"#)
    }

    func testARefusedProfileKeepsVelovsCodeAndRawMessage() async throws {
        let server = MockServer { _, _ in .json(["code": "accounts.exception.validation.failed", "message": "Account invalid phone number"], status: 400) }
        let outcome = try await Writes.setProfile(auth, ProfileBody(phoneNumber: "+33639980000"), http: server.transport)
        XCTAssertEqual([outcome.ok ? "ok" : "no", String(outcome.httpStatus), outcome.code, outcome.detail], ["no", "400", "accounts.exception.validation.failed", "Account invalid phone number"])
        XCTAssert(outcome.message!.contains("téléphone"))
    }

    func testNoProfileWriteIsEverRetried() async throws {
        for reply in [Reply.status(500, body: "<html>Bad Gateway</html>"), .status(502), .status(503), .status(504), .failure(.networkConnectionLost), .status(401), .json([:])] {
            let server = MockServer { _, _ in reply }
            do { _ = try await Writes.setProfile(auth, ProfileBody(city: "Lyon"), http: server.transport) }
            catch { XCTAssertEqual((error as? VelovError)?.code, .expired) }
            XCTAssertEqual(server.calls.count, 1)
        }
    }

    func testAHeldProfileChangeKeepsNoPersonalValueAndIsStillChecked() {
        let before = Profile(firstName: "Ada", lastName: "Lovelace", email: "person@example.com", locked: false, complete: true, phoneNumber: "+33612345678",
                             address: "1 rue de la République", addressComplement: nil, zipCode: "69002", city: "Lyon", country: "FR", favorites: [])
        let intent = profileIntent(ProfileBody(city: "Villeurbanne", phoneNumber: "+33698765432"))
        let stored = intent.map { "\($0.key)=\($0.value)" }.joined(separator: "&").lowercased()
        for value in ["villeurbanne", "698765432"] { XCTAssertFalse(stored.contains(value), value) }
        var after = before
        after.city = "Villeurbanne"
        after.phoneNumber = "+33698765432"
        XCTAssertEqual(profileCheck(intent, after: after), .applied)
        XCTAssertEqual(profileCheck(intent, after: before), .unchanged)
        after.city = "VILLEURBANNE"
        XCTAssertEqual(profileCheck(intent, after: after), .applied)
        after.phoneNumber = "+33600000000"
        XCTAssertEqual(profileCheck(intent, after: after), .unchanged)
    }

    func testTheProfileBodyAcceptsOnlyTheDocumentedFieldsTrimmedAndAtLeastOneOfThem() {
        XCTAssertNil(ProfileBody(zipCode: "69008", city: " Lyon ").problem())
        XCTAssertEqual(ProfileBody(zipCode: "69008", city: " Lyon ").trimmedForSending.city, "Lyon")
        let invalid: [(ProfileBody, ProfileField)] = [
            (ProfileBody(), .empty),
            (ProfileBody(address: ProfileAddress(name: String(repeating: "x", count: 39), complement: "")), .address),
            (ProfileBody(address: ProfileAddress(name: " ", complement: "")), .address),
            (ProfileBody(country: "France"), .country),
            (ProfileBody(phoneNumber: "0600000000"), .phoneNumber),
            (ProfileBody(city: "Ly\non"), .city),
            (ProfileBody(zipCode: "<script>"), .zipCode)
        ]
        for (body, field) in invalid { XCTAssertEqual(body.problem(), field, "\(body)") }
        XCTAssertNil(ProfileBody(address: ProfileAddress(name: String(repeating: "x", count: 38), complement: "")).problem())
    }

    func testFrenchPhoneNumbersAreWrittenInTheInternationalForm() {
        XCTAssertEqual(normalizePhone("06 12 34 56 78", country: "FR"), "+33612345678")
        XCTAssertEqual(normalizePhone("06.12.34.56.78", country: "FR"), "+33612345678")
        XCTAssertEqual(normalizePhone("0041 79 123 45 67", country: "CH"), "+41791234567")
        XCTAssertEqual(normalizePhone("+33 6 12 34 56 78", country: "BE"), "+33612345678")
        XCTAssertEqual(normalizePhone("0612345678", country: "BE"), "0612345678")
    }

    func testRenewalPatchSendsTheSourceSupportedIsAutoRenewalBodyExactlyOnce() async throws {
        XCTAssertEqual(Guesses.autoRenewalField, "isAutoRenewal")
        let server = MockServer { _, _ in .status(204) }
        let auth = WriteAuth(accountId: "account", token: "app-token", identity: "user-token")
        let outcome = try await Writes.setAutoRenewal(auth, subscriptionId: "subscription", autoRenewal: true, http: server.transport)
        XCTAssertTrue(outcome.ok)
        XCTAssertEqual(server.calls.count, 1)
        let call = server.calls[0]
        XCTAssertEqual(call.url, "https://api.cyclocity.fr/contracts/lyon/accounts/account/subscriptions/subscription")
        XCTAssertEqual(call.method, "PATCH")
        XCTAssertEqual(call.header("Content-Type"), "application/vnd.subscription.v6+json")
        assertSigned(call)
        XCTAssertEqual(call.bodyText, #"{"isAutoRenewal":true}"#)
    }

    func testRenewalPreservesRawNon2xxDetailsIncluding401AndNeverRetriesOrTriesAnotherField() async throws {
        for status in refusals {
            let server = MockServer { _, _ in .json(["code": "source.refused", "message": "Source message"], status: status) }
            let outcome = try await Writes.setAutoRenewal(auth, subscriptionId: "subscription", autoRenewal: false, http: server.transport)
            XCTAssertEqual(server.calls.count, 1)
            XCTAssertEqual([outcome.ok ? "ok" : "no", String(outcome.httpStatus), outcome.code, outcome.detail], ["no", String(status), "source.refused", "Source message"])
            XCTAssertEqual(server.calls[0].bodyText, #"{"isAutoRenewal":false}"#)
        }
        let lost = MockServer { _, _ in .failure(.networkConnectionLost) }
        let outcome = try await Writes.setAutoRenewal(auth, subscriptionId: "subscription", autoRenewal: true, http: lost.transport)
        XCTAssertEqual(outcome.code, "network")
        XCTAssertEqual(lost.calls.count, 1)
    }

    func testTheRenewalButtonIsStrictlyOptInAndTheStateStaysUnknownWhenAbsent() {
        XCTAssert(renewalState(of: nil) == (nil, false))
        XCTAssert(renewalState(of: .object(["periods": .array([.object(["renewalDetails": .object(["autoRenewalValue": .bool(false), "autoRenewalBtn": .bool(true)])])])])) == (false, true))
        XCTAssertFalse(renewalState(of: .object(["isLocked": .bool(true), "periods": .array([.object(["renewalDetails": .object(["autoRenewalBtn": .bool(true)])])])])).allowed)
    }

    func testViaUsesTheNumberAssumptionTheSubscriptionMediaTypeAndExactlyOnePost() async throws {
        XCTAssertEqual(Guesses.viaStationIdentifier, .number)
        let server = MockServer { _, _ in .json(["transactionState": "OK"]) }
        let outcome = try await Writes.via(auth, subscriptionId: "subscription/one", station: .number(1234), http: server.transport)
        XCTAssertEqual(server.calls.count, 1)
        let call = server.calls[0]
        XCTAssertEqual(call.url, "\(account)/subscriptions/subscription%2Fone/via")
        XCTAssertEqual(call.method, "POST")
        XCTAssertEqual(call.bodyText, #"{"stationId":1234}"#)
        assertSigned(call)
        XCTAssertEqual(call.header("Content-Type"), "application/vnd.subscription.v6+json")
        XCTAssertNil(call.header("Accept"))
        XCTAssertTrue(outcome.ok)
    }

    func testViaRetainsRawStatusCodeAndMessageAndNeverRetriesAnyFailure() async throws {
        for status in refusals {
            let server = MockServer { _, _ in .json(["code": "via.refused", "message": "Station not full"], status: status) }
            let outcome = try await Writes.via(auth, subscriptionId: "s", station: .number(1234), http: server.transport)
            XCTAssertEqual(server.calls.count, 1)
            XCTAssertEqual([outcome.ok ? "ok" : "no", String(outcome.httpStatus), outcome.code, outcome.detail], ["no", String(status), "via.refused", "Station not full"])
        }
        let lost = MockServer { _, _ in .failure(.networkConnectionLost) }
        let outcome = try await Writes.via(auth, subscriptionId: "s", station: .number(1234), http: lost.transport)
        XCTAssertEqual(lost.calls.count, 1)
        XCTAssertEqual([outcome.code, String(outcome.httpStatus)], ["network", "0"])
    }

    func testViaFallbackSupportsAUUIDWithoutASecondSubmission() async throws {
        let server = MockServer { _, _ in .json([:]) }
        _ = try await Writes.via(auth, subscriptionId: "s", station: .uuid("00000000-0000-0000-0000-000000000001"), http: server.transport)
        XCTAssertEqual(server.calls.count, 1)
        XCTAssertEqual(server.calls[0].bodyText, #"{"stationId":"00000000-0000-0000-0000-000000000001"}"#)
    }

    func testViaRequiresAnExplicitOKTransactionStateNotJustHTTPSuccess() async throws {
        for state in ["NOK", "ABORT", "TIME_OUT", "PENDING", "UNKNOWN"] {
            let server = MockServer { _, _ in .json(["transactionState": state]) }
            let outcome = try await Writes.via(auth, subscriptionId: "s", station: .number(1), http: server.transport)
            XCTAssertEqual(server.calls.count, 1)
            XCTAssertEqual([outcome.ok ? "ok" : "no", String(outcome.httpStatus), outcome.transactionState], ["no", "200", state])
        }
        for reply in [Reply.json([:]), .status(204)] {
            let server = MockServer { _, _ in reply }
            let outcome = try await Writes.via(auth, subscriptionId: "s", station: .number(1), http: server.transport)
            XCTAssertFalse(outcome.ok)
            XCTAssertNil(outcome.transactionState)
            XCTAssertEqual(server.calls.count, 1)
        }
    }

    func testViaAcceptsTheDirectTransactionStateStringUsedByVLSKit() async throws {
        for state in ["OK", "NOK", "ABORT", "TIME_OUT", "RUNNING", "UNSTARTED", "NOT_CONNECTED", "UNKNOW"] {
            let server = MockServer { _, _ in .json(state) }
            let outcome = try await Writes.via(auth, subscriptionId: "s", station: .number(1), http: server.transport)
            XCTAssertEqual(server.calls.count, 1)
            XCTAssertEqual(outcome.ok, state == "OK")
            XCTAssertEqual(outcome.transactionState, state)
        }
    }

    func testThePickerExcludesNonFullOrClosedStationsSearchesAccentsAndSortsNearestFirst() {
        let base = Station(id: "1", number: 1, name: "Étoile", address: "Rue exemple", lat: 0, lon: 1, mechanical: 4, electrical: 0, stands: 0, open: true)
        var b = base; b.number = 2; b.name = "B"; b.lon = 0
        var notFull = base; notFull.number = 3; notFull.stands = 1
        var closed = base; closed.number = 4; closed.open = false
        let stations = [base, b, notFull, closed]
        XCTAssertEqual(fullStations(stations, query: "", position: GeoPoint(lat: 0, lon: 0)).map(\.number), [2, 1])
        XCTAssertEqual(fullStations(stations, query: "etoile", position: nil).map(\.number), [1])
        XCTAssertEqual(fullStations(stations, query: "2", position: nil).map(\.number), [2])
    }

    func parts(_ call: Call) -> [(String, String)] {
        guard let type = call.header("Content-Type"), let range = type.range(of: "boundary=") else { return [] }
        let boundary = String(type[range.upperBound...])
        return call.bodyText.components(separatedBy: "--\(boundary)").dropFirst().compactMap { part -> (String, String)? in
            guard let header = part.range(of: "\r\n\r\n"), let name = part.firstMatch(of: /name="([^"]+)"/)?.output.1 else { return nil }
            var value = String(part[header.upperBound...])
            if value.hasSuffix("\r\n") { value.removeLast() }
            return (String(name), value)
        }
    }

    func testMailUsesOneMultipartPostWithDocumentedHeadersFieldsAndTheSelectedTripToken() async throws {
        let server = MockServer { _, _ in .status(204) }
        let auth = WriteAuth(accountId: "account/id", token: "app-token", identity: "user-token")
        let outcome = try await Writes.contactMail(auth, ContactBody(complaintType: "TRIP", message: "Bonjour, merci de vérifier.", tripToken: "ABC123"), http: server.transport)
        XCTAssertTrue(outcome.ok)
        XCTAssertEqual(server.calls.count, 1)
        let call = server.calls[0]
        XCTAssertEqual(call.url, "https://api.cyclocity.fr/contracts/lyon/accounts/account%2Fid/mail")
        XCTAssertEqual(call.method, "POST")
        assertSigned(call)
        XCTAssertEqual(call.header("Accept"), "multipart/form-data")
        XCTAssert(call.header("Content-Type")!.hasPrefix("multipart/form-data; boundary="))
        let fields = parts(call)
        XCTAssertEqual(fields.map(\.0), ["complaintType", "message"])
        XCTAssertEqual(fields.map(\.1), ["TRIP", "Bonjour, merci de vérifier.\r\n\r\nCode du trajet : ABC123"])
        XCTAssert(call.bodyText.hasSuffix("--\r\n"))
    }

    func testMailOmitsAllTripFieldsWhenNoneIsSelected() async throws {
        let server = MockServer { _, _ in .json([:]) }
        _ = try await Writes.contactMail(auth, ContactBody(complaintType: "SUBSCRIPTION", message: "Une question"), http: server.transport)
        XCTAssertEqual(parts(server.calls[0]).map(\.1), ["SUBSCRIPTION", "Une question"])
    }

    func testEveryMailRefusalRetainsItsRawStatusCodeAndMessageWithoutAnyRetry() async throws {
        let body = ContactBody(complaintType: "TRIP", message: "Bonjour", tripToken: "ABC123")
        for status in refusals {
            let server = MockServer { _, _ in .json(["code": "mail.invalid", "message": "Invalid complaintType"], status: status) }
            let outcome = try await Writes.contactMail(auth, body, http: server.transport)
            XCTAssertEqual([outcome.ok ? "ok" : "no", String(outcome.httpStatus), outcome.code, outcome.detail], ["no", String(status), "mail.invalid", "Invalid complaintType"])
            XCTAssertEqual(server.calls.count, 1)
        }
        for failure in [URLError.Code.networkConnectionLost, .timedOut] {
            let server = MockServer { _, _ in .failure(failure) }
            let outcome = try await Writes.contactMail(auth, body, http: server.transport)
            XCTAssertEqual([outcome.ok ? "ok" : "no", String(outcome.httpStatus), outcome.code], ["no", "0", "network"])
            XCTAssertEqual(server.calls.count, 1)
        }
    }

    func testContactValidationAcceptsOnlySupportedCategoriesAndBoundedFields() {
        let body = ContactBody(complaintType: "TRIP", message: "Bonjour, merci de vérifier.", tripToken: "ABC123")
        XCTAssertTrue(body.isValid)
        XCTAssertEqual(Guesses.mailComplaintTypes, ["TRIP", "SUBSCRIPTION", "PAYMENT", "PARKING"])
        for invalid in [ContactBody(complaintType: "OTHER", message: "Hi"), ContactBody(complaintType: "TRIP", message: " "),
                        ContactBody(complaintType: "TRIP", message: String(repeating: "x", count: 1501)), ContactBody(complaintType: "TRIP", message: "Hi", tripToken: "A\nB")] {
            XCTAssertFalse(invalid.isValid, String(invalid.message.prefix(10)))
        }
        XCTAssertTrue(ContactBody(complaintType: "TRIP", message: String(repeating: "é", count: 1500)).isValid)
        XCTAssertTrue(ContactBody(complaintType: "TRIP", message: String(repeating: "€", count: 1500)).isValid)
        XCTAssertEqual(contactMessage(ContactBody(complaintType: "PAYMENT", message: " Question ")), "Question")
    }

    func testPromocodeDebitsOnceWithNoBodyTheRewardsAcceptAndAuthenticatedBrowserHeaders() async throws {
        let server = MockServer { _, _ in .json(["promoCode": "INVITE-EXAMPLE", "offerId": 1, "badgeId": 2, "badgeType": "EXTERNAL", "rewardsSpent": 50]) }
        let auth = WriteAuth(accountId: "account/test", token: "app-token", identity: "user-token")
        let result = try await Writes.promoCode(auth, http: server.transport)
        XCTAssertEqual(server.calls.count, 1)
        let call = server.calls[0]
        XCTAssertEqual(call.url, "https://api.cyclocity.fr/contracts/lyon/accounts/account%2Ftest/rewards/consume/promocode")
        XCTAssertEqual(call.method, "POST")
        XCTAssertEqual(call.body, Data())
        XCTAssertEqual(call.header("Accept"), "application/vnd.rewards.v5+json")
        XCTAssertNil(call.header("Content-Type"))
        assertSigned(call)
        XCTAssertEqual(result, PromoResult(outcome: Outcome(ok: true, httpStatus: 200), promoCode: "INVITE-EXAMPLE"))
    }

    func testUnexpectedOrMissingMetadataNeverDiscardsAReturnedPromoCode() async throws {
        for body in [["promoCode": "KEEP-ME"], ["promoCode": "KEEP-ME", "offerId": NSNull(), "badgeId": [:] as [String: Any], "rewardsSpent": "unexpected"]] as [[String: Any]] {
            let server = MockServer { _, _ in .json(body) }
            let result = try await Writes.promoCode(auth, http: server.transport)
            XCTAssertEqual(result.promoCode, "KEEP-ME")
            XCTAssertTrue(result.outcome.ok)
        }
    }

    func testEveryPromoFailurePreservesRawHTTPCodeAndMessageAndIsNeverRetried() async throws {
        for status in refusals {
            let server = MockServer { _, _ in .json(["code": "rewards.exception.insufficient.rewards", "message": "Not enough rewards"], status: status) }
            let result = try await Writes.promoCode(auth, http: server.transport)
            XCTAssertEqual(server.calls.count, 1)
            XCTAssertEqual([result.outcome.ok ? "ok" : "no", String(result.outcome.httpStatus), result.outcome.code, result.outcome.detail],
                           ["no", String(status), "rewards.exception.insufficient.rewards", "Not enough rewards"])
            XCTAssertNil(result.promoCode)
        }
        let lost = MockServer { _, _ in .failure(.networkConnectionLost) }
        let result = try await Writes.promoCode(auth, http: lost.transport)
        XCTAssertEqual(lost.calls.count, 1)
        XCTAssertEqual(result.outcome.code, "network")
    }

    func testSuccessWithoutACodeWarnsAboutAPossibleDebitAndDoesNotRetry() async throws {
        for reply in [Reply.json(["offerId": 1]), .status(204)] {
            let server = MockServer { _, _ in reply }
            let result = try await Writes.promoCode(auth, http: server.transport)
            XCTAssertEqual(server.calls.count, 1)
            XCTAssertFalse(result.outcome.ok)
            XCTAssertEqual(result.outcome.code, "local.promo.unreadable")
            XCTAssert(result.outcome.message!.contains("avant de recommencer"))
        }
    }

    func testCodesPersistAppendRatherThanOverwriteAndDeduplicate() throws {
        let store = InMemoryPromoBacking()
        try PromoStore.prepare(store, key: "account-key")
        try PromoStore.save(store, key: "account-key", code: "CODE-A")
        try PromoStore.save(store, key: "account-key", code: "CODE-B")
        try PromoStore.save(store, key: "account-key", code: "CODE-A")
        XCTAssertEqual(try PromoStore.read(store, key: "account-key").map(\.code), ["CODE-A", "CODE-B"])
        XCTAssertEqual(try PromoStore.read(store, key: "another-account"), [])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("promo-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try PromoStore.save(FilePromoBacking(directory: directory), key: "velov:promocodes:v1:abc", code: "FILE-CODE")
        XCTAssertEqual(try PromoStore.read(FilePromoBacking(directory: directory), key: "velov:promocodes:v1:abc").map(\.code), ["FILE-CODE"])
    }

    func testStorageFailureIsDetectedBeforeTheDebitAndCorruptStorageIsNeverErased() {
        XCTAssertThrowsError(try PromoStore.prepare(InMemoryPromoBacking(failWrites: true), key: "key"))
        let store = InMemoryPromoBacking(["key": "corrupt-but-recoverable-code"])
        XCTAssertThrowsError(try PromoStore.prepare(store, key: "key"))
        XCTAssertThrowsError(try PromoStore.save(store, key: "key", code: "NEW-CODE"))
        XCTAssertEqual(store.value("key"), "corrupt-but-recoverable-code")
    }

    func testStorageKeysAreAccountScopedDigestsNotClearTextAddresses() {
        let first = PromoStore.key(account: "one@example.test")
        XCTAssertEqual(first, PromoStore.key(account: " ONE@example.test "))
        XCTAssertNotEqual(first, PromoStore.key(account: "two@example.test"))
        XCTAssertNotNil(first.wholeMatch(of: /velov:promocodes:v1:[0-9a-f]{64}/))
    }
}
