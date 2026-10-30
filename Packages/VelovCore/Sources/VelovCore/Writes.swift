import Foundation

public struct WriteAuth: Sendable {
    public let accountId: String
    public let token: String
    public let identity: String
    public init(accountId: String, token: String, identity: String) { self.accountId = accountId; self.token = token; self.identity = identity }
}

struct ErrorReply {
    let value: JSON?
    let code: String?
    let detail: String?
    let transactionState: String?

    init(_ response: HTTPResponse) {
        let text = response.text
        value = JSON.parse(response.body)
        code = value?["code"]?.string ?? response.header("Bloot-Error-Code")
        detail = value?["message"]?.string ?? (value == nil && !text.isEmpty ? String(text.prefix(160)) : nil)
        transactionState = value?["transactionState"]?.string
    }
}

public func attempt(_ run: () async throws -> Outcome) async -> Outcome {
    do {
        return try await run()
    } catch let error as VelovError {
        return Outcome(ok: false, httpStatus: error.code == .expired ? 401 : 0, code: "local.\(error.code.rawValue)", message: error.message)
    } catch {
        return Outcome(ok: false, httpStatus: 0, code: "network", message: Messages.noReply, detail: networkLine(error))
    }
}

public func beforeSending<T>(_ run: () async throws -> T) async throws -> T {
    do {
        return try await run()
    } catch let error as VelovError {
        throw error
    } catch {
        throw VelovError(.unavailable, Messages.notSent)
    }
}

func accountURL(_ accountId: String) -> String { "\(Cyclocity.base)/accounts/\(pathSegment(accountId))" }

func orderedJSON(_ pairs: [(String, Any?)]) -> Data {
    let parts = pairs.map { key, value -> String in
        let encoded: String
        switch value {
        case nil: encoded = "null"
        case let value as String: encoded = String(decoding: try! JSONSerialization.data(withJSONObject: value, options: .fragmentsAllowed), as: UTF8.self)
        case let value as Bool: encoded = value ? "true" : "false"
        case let value as Int: encoded = String(value)
        case let value as Data: encoded = String(decoding: value, as: UTF8.self)
        default: encoded = "null"
        }
        return "\"\(key)\":\(encoded)"
    }
    return Data("{\(parts.joined(separator: ","))}".utf8)
}

public enum Writes {
    public static func rate(_ auth: WriteAuth, tripId: String, bikeNumber: Int, vote: RateVote, http: HTTPTransport) async throws -> Outcome {
        let url = URL(string: "\(accountURL(auth.accountId))/trips/\(pathSegment(tripId))/rate")!
        let body = orderedJSON([("bikeId", bikeNumber), ("recommended", vote.recommended), ("contract", "lyon"), ("rating", vote.rating)])
        let response: HTTPResponse
        do {
            response = try await http.send(makeRequest(url, method: "POST", headers: [
                "Authorization": "Taknv1 \(auth.token)", "Identity": auth.identity, "Content-Type": "application/vnd.trip.v6+json"], body: body, timeout: 25))
        } catch {
            var outcome = Outcome.refusal("network", "")
            outcome.detail = networkLine(error)
            return ratingOutcome(outcome)
        }
        if response.ok, response.body.isEmpty || JSON.parse(response.body) != nil { return Outcome(ok: true, httpStatus: response.status) }
        let reply = ErrorReply(response)
        return ratingOutcome(Outcome(ok: false, httpStatus: response.status, code: reply.code, detail: reply.detail))
    }

    public static func release(_ auth: WriteAuth, subscriptionId: String, stationNumber: Int, standNumber: Int, bikeNumber: Int, http: HTTPTransport) async throws -> Outcome {
        let url = URL(string: "\(accountURL(auth.accountId))/subscriptions/\(pathSegment(subscriptionId))/trips")!
        let body = orderedJSON([("stationNumber", stationNumber), ("standNumber", standNumber), ("bikeNumber", bikeNumber), ("typeFrom", "SMARTPHONE")])
        let response: HTTPResponse
        do {
            response = try await http.send(makeRequest(url, method: "POST", headers: [
                "Authorization": "Taknv1 \(auth.token)", "Identity": auth.identity, "Content-Type": "application/vnd.trip.v6+json",
                "Accept": "application/vnd.trip.v6+json", "Accept-Language": "fr"], body: body, timeout: 30))
        } catch {
            var outcome = Outcome.refusal("network", Messages.unlockNoAnswer)
            outcome.detail = networkLine(error)
            return outcome
        }
        let reply = ErrorReply(response)
        return releaseOutcome(httpStatus: response.status, code: reply.code, detail: reply.detail, transactionState: reply.transactionState)
    }

    public static func book(_ auth: WriteAuth, stationId: String, stationNumber: Int, standNumber: Int, subscriptionId: String, bikeId: String, http: HTTPTransport) async throws -> (outcome: Outcome, booking: RawBooking?) {
        let url = URL(string: "\(accountURL(auth.accountId))/bookings")!
        let body = orderedJSON([("stationId", stationId), ("stationNumber", stationNumber), ("standNumber", standNumber), ("subscriptionId", subscriptionId), ("bikeId", bikeId)])
        let response: HTTPResponse
        do {
            response = try await http.send(makeRequest(url, method: "POST", headers: [
                "Authorization": "Taknv1 \(auth.token)", "Identity": auth.identity, "Content-Type": "application/json; charset=UTF-8"], body: body, timeout: 30))
        } catch {
            var outcome = Outcome.refusal("network", Messages.bookingNoAnswer)
            outcome.detail = networkLine(error)
            return (outcome, nil)
        }
        let reply = ErrorReply(response)
        var outcome = bookingOutcome(httpStatus: response.status, code: reply.code, detail: reply.detail)
        guard outcome.ok else { return (outcome, nil) }
        if let booking = reply.value.flatMap(RawBooking.init), booking.stationNumber == stationNumber, booking.bikeId == bikeId {
            return (outcome, booking)
        }
        outcome.ok = false
        outcome.message = Messages.bookingNoAnswer
        outcome.detail = reply.detail ?? (response.body.isEmpty ? "Réponse vide" : String(response.text.prefix(160)))
        return (outcome, nil)
    }

    static func accountCall(_ url: URL, method: String, headers: [String: String], body: Data?, auth: WriteAuth, failed: String,
                            unsure: String = Messages.changeNoAnswer, http: HTTPTransport) async throws -> (outcome: Outcome, value: JSON?) {
        let response: HTTPResponse
        do {
            var all = headers
            all["Authorization"] = "Taknv1 \(auth.token)"
            all["Identity"] = auth.identity
            response = try await http.send(makeRequest(url, method: method, headers: all, body: body, timeout: 15))
        } catch {
            var outcome = Outcome.refusal("network", unsure)
            outcome.detail = networkLine(error)
            return (outcome, nil)
        }
        let reply = ErrorReply(response)
        return (accountOutcome(httpStatus: response.status, code: reply.code, detail: reply.detail, failed: failed, unsure: unsure), response.ok ? reply.value : nil)
    }

    public static func setAutoSpend(_ auth: WriteAuth, _ autoSpend: Bool, http: HTTPTransport) async throws -> (outcome: Outcome, autoSpend: Bool?) {
        let (outcome, value) = try await accountCall(URL(string: "\(accountURL(auth.accountId))/rewards")!, method: "PATCH",
                                                     headers: ["Content-Type": "application/vnd.rewards.v5+json"], body: orderedJSON([("autoSpend", autoSpend)]),
                                                     auth: auth, failed: "Vélo’v n’a pas enregistré ce réglage.", http: http)
        return (outcome, value?["autoSpend"]?.bool ?? (outcome.ok ? autoSpend : nil))
    }

    public static func setFavorite(_ auth: WriteAuth, station: Int, on: Bool, http: HTTPTransport) async throws -> Outcome {
        try await accountCall(URL(string: "\(accountURL(auth.accountId))/stationbookmarks/\(station)/")!, method: on ? "POST" : "DELETE",
                              headers: ["Accept": "application/vnd.account.v4+json"], body: nil, auth: auth,
                              failed: on ? "Vélo’v n’a pas ajouté cette station aux favoris." : "Vélo’v n’a pas retiré cette station des favoris.", http: http).outcome
    }

    public static func receipt(_ auth: WriteAuth, subscriptionId: String, periodId: String, http: HTTPTransport) async throws -> (outcome: Outcome, filename: String?, pdf: Data?) {
        let url = URL(string: "\(accountURL(auth.accountId))/subscriptions/\(pathSegment(subscriptionId))/periods/\(pathSegment(periodId))/reports")!
        var (outcome, value) = try await accountCall(url, method: "POST", headers: ["Accept": "application/json"], body: nil, auth: auth, failed: "Ce reçu n’est pas disponible.",
                                                     unsure: Messages.noReply, http: http)
        guard outcome.ok else { return (outcome, nil, nil) }
        guard let content = value?["translations"]?["content"]?.string, let bytes = Data(base64Encoded: content), bytes.starts(with: Data("%PDF-".utf8)) else {
            outcome.ok = false
            outcome.code = "local.receipt.unreadable"
            outcome.message = "Ce reçu ne peut pas être ouvert."
            return (outcome, nil, nil)
        }
        let name = (value?["filename"]?.string ?? "").filter { $0.isASCII && ($0.isLetter || $0.isNumber || "_.-".contains($0)) }
        return (outcome, name.isEmpty ? "recu-\(periodId).pdf" : name, bytes)
    }

    public static func setProfile(_ auth: WriteAuth, _ body: ProfileBody, http: HTTPTransport) async throws -> Outcome {
        let body = body.trimmedForSending
        let address = body.address.map { orderedJSON([("name", $0.name), ("complement", $0.complement)]) }
        let pairs: [(String, Any?)] = [("firstName", body.firstName), ("lastName", body.lastName), ("country", body.country), ("zipCode", body.zipCode),
                                       ("city", body.city), ("phoneNumber", body.phoneNumber), ("address", address)]
        var outcome = try await accountCall(URL(string: accountURL(auth.accountId))!, method: "PATCH", headers: ["Content-Type": "application/vnd.account.v4+json"],
                                            body: orderedJSON(pairs.filter { $0.1 != nil }), auth: auth, failed: "Vélo’v n’a pas enregistré ces coordonnées.", http: http).outcome
        if body.firstName != nil || body.lastName != nil, (400..<500).contains(outcome.httpStatus), !outcome.isUncertain {
            outcome.message = "Vélo’v n’a pas accepté ce changement de nom."
        }
        return outcome
    }
}
