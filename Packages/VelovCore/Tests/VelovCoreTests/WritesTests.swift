import XCTest
@testable import VelovCore

/// The state-changing calls, against the mock only: one request per call, whatever the answer.
final class WritesTests: XCTestCase {
    let auth = WriteAuth(accountId: "acc-1", token: "client", identity: "user")

    func release(_ reply: Reply) async throws -> (Outcome, MockServer) {
        let server = MockServer { _, _ in reply }
        let outcome = try await Writes.release(auth, subscriptionId: "sub-1", stationNumber: 2002, standNumber: 1, bikeNumber: 20449, http: server.transport)
        return (outcome, server)
    }

    func testAReleasePostsTheAppsBodyOnceWithBothTokensAndABrowserAgent() async throws {
        let (outcome, server) = try await release(.json(["transactionState": "OK"]))
        XCTAssertEqual(server.calls.count, 1)
        let call = server.calls[0]
        XCTAssertEqual(call.url, "https://api.cyclocity.fr/contracts/lyon/accounts/acc-1/subscriptions/sub-1/trips")
        XCTAssertEqual(call.method, "POST")
        XCTAssertEqual(call.header("Authorization"), "Taknv1 client")
        XCTAssertEqual(call.header("Identity"), "user")
        XCTAssertEqual(call.header("Content-Type"), "application/vnd.trip.v6+json")
        XCTAssert(call.header("User-Agent")!.hasPrefix("Mozilla/"))
        XCTAssertEqual(call.bodyText, #"{"stationNumber":2002,"standNumber":1,"bikeNumber":20449,"typeFrom":"SMARTPHONE"}"#)
        XCTAssertEqual(outcome, Outcome(ok: true, httpStatus: 200, transactionState: "OK"))
    }

    func testAReleaseSucceedsOnTransactionStateOKOnlyNotOnHTTP200() async throws {
        for (state, message) in [("NOK", "Le vélo n’a pas pu être déverrouillé."), ("ABORT", "Le déverrouillage a été annulé."),
                                 ("TIME_OUT", "La borne n’a pas répondu à temps."), ("NOT_CONNECTED", "Aucun vélo n’est accroché à cette borne."),
                                 ("SOMETHING_NEW", Messages.releaseFailed), (nil, Messages.releaseFailed)] as [(String?, String)] {
            let (outcome, _) = try await release(.json(state.map { ["transactionState": $0] } ?? [:]))
            XCTAssertFalse(outcome.ok)
            XCTAssertEqual(outcome.transactionState, state)
            XCTAssertEqual(outcome.message, message)
        }
    }

    func testReleaseRefusalsMapToTheAppsFrenchMessagesAndKeepTheRawCodeAndMessage() async throws {
        let (reserved, _) = try await release(.json(["code": "trips.exception.bookings.already.reserved", "message": "Bike reserved by another user"], status: 404))
        XCTAssertEqual([reserved.ok ? "ok" : "no", String(reserved.httpStatus), reserved.code, reserved.detail], ["no", "404", "trips.exception.bookings.already.reserved", "Bike reserved by another user"])
        XCTAssert(reserved.message!.hasPrefix("Vélo réservé par un autre usager"))
        for (code, message) in [("kiwi.exception.customer.insuffisant.right", "Abonnement hors validité."),
                                ("trips.exception.invalid.customer.maxBikesRented", "Impossible de libérer le vélo, un autre trajet est en cours."),
                                ("kiwi.exception.customer.rent.time.limit", "Délai entre deux courses non écoulé."),
                                ("kiwi.exception.customer.paymentmode.not.valid", "Veuillez mettre à jour votre mode de paiement."),
                                ("kiwi.exception.no.release.bike", "Problème technique lors de la libération du vélo.")] {
            let (outcome, _) = try await release(.json(["code": code], status: 400))
            XCTAssertEqual(outcome.message, message)
        }
    }

    func testARefusalWithoutAJSONBodyFallsBackToTheBlootHeaderOrToTheSessionMessageOnA403() async throws {
        let (header, _) = try await release(.status(400, headers: ["Bloot-Error-Code": "kiwi.exception.customer.insuffisant.right"]))
        XCTAssertEqual(header.code, "kiwi.exception.customer.insuffisant.right")
        XCTAssertEqual(header.message, "Abonnement hors validité.")
        let (tomcat, _) = try await release(.status(403, body: "<html><body>HTTP Status 403</body></html>"))
        XCTAssertNil(tomcat.code)
        XCTAssert(tomcat.message!.contains("session"))
        XCTAssert(tomcat.detail!.contains("403"))
    }

    func testAReleaseIsNeverRetried() async throws {
        for status in [500, 502, 503, 504] {
            let (outcome, server) = try await release(.status(status, body: "<html>Bad Gateway</html>"))
            XCTAssertEqual(server.calls.count, 1, String(status))
            XCTAssertEqual(outcome.httpStatus, status)
            XCTAssertFalse(outcome.ok)
        }
        let (lost, server) = try await release(.failure(.timedOut))
        XCTAssertEqual(server.calls.count, 1)
        XCTAssertEqual([lost.ok ? "ok" : "no", String(lost.httpStatus), lost.code, lost.detail], ["no", "0", "network", "TimeoutError"])
        XCTAssert(lost.message!.contains("peut-être déverrouillé"))
        let expired = MockServer { _, _ in .status(401) }
        do { _ = try await Writes.release(auth, subscriptionId: "sub-1", stationNumber: 2002, standNumber: 1, bikeNumber: 20449, http: expired.transport); XCTFail("no error") }
        catch { XCTAssertEqual((error as? VelovError)?.code, .expired) }
        XCTAssertEqual(expired.calls.count, 1)
    }

    func book(_ reply: Reply) async throws -> (Outcome, RawBooking?, MockServer) {
        let server = MockServer { _, _ in reply }
        let (outcome, booking) = try await Writes.book(auth, stationId: "st-uuid", stationNumber: 2002, standNumber: 12, subscriptionId: "sub-1", bikeId: "bike-uuid", http: server.transport)
        return (outcome, booking, server)
    }

    func testABookingPostsCreateBookingInTheAppsFieldOrderAsPlainJSONWithoutAcceptOnce() async throws {
        let (outcome, booking, server) = try await book(.json(["id": "bk-1", "contractName": "lyon", "stationNumber": 2002, "standNumber": 12, "bikeId": "bike-uuid", "endTime": "2026-03-02T09:47:14"]))
        XCTAssertEqual(server.calls.count, 1)
        let call = server.calls[0]
        XCTAssertEqual(call.url, "https://api.cyclocity.fr/contracts/lyon/accounts/acc-1/bookings")
        XCTAssertEqual(call.header("Content-Type"), "application/json; charset=UTF-8")
        XCTAssertNil(call.header("Accept"))
        XCTAssertEqual(call.bodyText, #"{"stationId":"st-uuid","stationNumber":2002,"standNumber":12,"subscriptionId":"sub-1","bikeId":"bike-uuid"}"#)
        XCTAssertTrue(outcome.ok)
        XCTAssertEqual(booking?.id, "bk-1")
        XCTAssertEqual(booking?.endTime, "2026-03-02T09:47:14")
    }

    func testBookingRefusalsMapToFrenchMessagesAndAreNeverRetried() async throws {
        for (code, message) in [("booking.exception.bike.already.reserved", "Ce vélo est déjà réservé par un autre usager."),
                                ("bookings.exception.not.authorized", "Vous avez déjà une réservation en cours, ou moins de 10 points."),
                                ("rewards.exception.something", Messages.bookingFailed)] {
            let (outcome, booking, server) = try await book(.json(["code": code, "message": "raw"], status: 400))
            XCTAssertEqual(outcome.message, message)
            XCTAssertEqual(outcome.detail, "raw")
            XCTAssertNil(booking)
            XCTAssertEqual(server.calls.count, 1)
        }
        for reply in [Reply.status(502, body: "Bad Gateway"), .failure(.networkConnectionLost)] {
            let (outcome, _, server) = try await book(reply)
            XCTAssertFalse(outcome.ok)
            XCTAssertEqual(server.calls.count, 1)
        }
    }

    func testARatingPostsTheOfficialBodyOnceAndARefusalIsNotRetried() async throws {
        let server = MockServer { _, _ in .status(200, body: "{}") }
        try await Writes.rate(auth, tripId: "trip-1", bikeNumber: 20449, vote: .recommend, http: server.transport)
        XCTAssertEqual(server.calls[0].url, "https://api.cyclocity.fr/contracts/lyon/accounts/acc-1/trips/trip-1/rate")
        XCTAssertEqual(server.calls[0].bodyText, #"{"bikeId":20449,"recommended":true,"contract":"lyon","rating":null}"#)
        for (status, code) in [(401, VelovError.Code.expired), (404, .unavailable), (502, .unavailable)] {
            let failing = MockServer { _, _ in .status(status) }
            do { try await Writes.rate(auth, tripId: "trip-1", bikeNumber: 20449, vote: .warn(30), http: failing.transport); XCTFail("no error") }
            catch { XCTAssertEqual((error as? VelovError)?.code, code) }
            XCTAssertEqual(failing.calls.count, 1)
        }
    }

    func testAccountWritesUseTheAppsMethodsAndMapRefusals() async throws {
        let rewards = MockServer { _, _ in .json(["balance": 12, "autoSpend": true]) }
        let (outcome, value) = try await Writes.setAutoSpend(auth, true, http: rewards.transport)
        XCTAssertTrue(outcome.ok); XCTAssertEqual(value, true)
        XCTAssertEqual(rewards.calls[0].method, "PATCH")
        XCTAssertEqual(rewards.calls[0].bodyText, #"{"autoSpend":true}"#)
        let favorite = MockServer { _, _ in .status(204) }
        _ = try await Writes.setFavorite(auth, station: 2002, on: false, http: favorite.transport)
        XCTAssertEqual(favorite.calls[0].method, "DELETE")
        XCTAssertEqual(favorite.calls[0].url, "https://api.cyclocity.fr/contracts/lyon/accounts/acc-1/stationbookmarks/2002/")
        XCTAssertEqual(favorite.calls[0].header("Accept"), "application/vnd.account.v4+json")
        let pdf = Data("%PDF-1.4 receipt".utf8).base64EncodedString()
        let receipt = MockServer { _, _ in .json(["filename": "reçu 1.pdf", "translations": ["content": pdf]]) }
        let (ok, name, bytes) = try await Writes.receipt(auth, subscriptionId: "sub-1", periodId: "p-1", http: receipt.transport)
        XCTAssertTrue(ok.ok); XCTAssertEqual(name, "reu1.pdf"); XCTAssertEqual(bytes.map { String(decoding: $0, as: UTF8.self) }, "%PDF-1.4 receipt")
        let notPDF = MockServer { _, _ in .json(["translations": ["content": Data("<html>".utf8).base64EncodedString()]]) }
        let unreadable = try await Writes.receipt(auth, subscriptionId: "sub-1", periodId: "p-1", http: notPDF.transport)
        XCTAssertEqual(unreadable.outcome.code, "local.receipt.unreadable")
        let phone = MockServer { _, _ in .json(["code": "accounts.exception.notacceptable.account.phone.invalid", "message": "raw"], status: 400) }
        let refused = try await Writes.setFavorite(auth, station: 2002, on: true, http: phone.transport)
        XCTAssertEqual(refused.message, "Ce numéro de téléphone n’est pas valide.")
        for reply in [Reply.status(502), .failure(.timedOut), .status(401)] {
            let server = MockServer { _, _ in reply }
            _ = try? await Writes.setAutoSpend(auth, false, http: server.transport)
            XCTAssertEqual(server.calls.count, 1)
        }
    }

    func testTheRawLineShowsStatusCodeAndDetail() {
        XCTAssertEqual(rawLine(Outcome(ok: false, httpStatus: 0, code: "network", detail: "TimeoutError")), "TransactionState — · Code network · HTTP aucune réponse · TimeoutError")
        XCTAssertEqual(rawLine(Outcome(ok: false, httpStatus: 409, code: "x", detail: "conflict"), withState: false), "HTTP 409 · Code x · Conflict")
        XCTAssertEqual(rawLine(Outcome(ok: false, httpStatus: 400, code: nil), withState: false), "HTTP 400 · Code —")
    }
}
