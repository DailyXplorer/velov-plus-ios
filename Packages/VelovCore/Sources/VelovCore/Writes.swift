import Foundation

// State-changing Cyclocity calls. Each one goes out EXACTLY ONCE per user confirmation: never through `ReadClient`,
// never retried, whatever the answer (a lost answer may hide a booking or a release that went through).
// The experimental ones (renewal, extra time, mail, invitation code) are in `ExperimentalWrites.swift`.

/// The tokens a write needs: the account, the app token and the user's access token.
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

func accountURL(_ accountId: String) -> String { "\(Cyclocity.base)/accounts/\(pathSegment(accountId))" }

private func networkFailure(_ error: Error) -> String {
    (error as? URLError)?.code == .timedOut ? "TimeoutError" : String(describing: type(of: error))
}

/// JSON with the keys in the given order, as the official app writes its bodies.
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
    /// Rates the bike of a trip, once.
    public static func rate(_ auth: WriteAuth, tripId: String, bikeNumber: Int, vote: RateVote, http: HTTPTransport) async throws {
        let url = URL(string: "\(accountURL(auth.accountId))/trips/\(pathSegment(tripId))/rate")!
        let body = orderedJSON([("bikeId", bikeNumber), ("recommended", vote.recommended), ("contract", "lyon"), ("rating", vote.rating)])
        let response = try await http.send(makeRequest(url, method: "POST", headers: [
            "Authorization": "Taknv1 \(auth.token)", "Identity": auth.identity, "Content-Type": "application/vnd.trip.v6+json"], body: body, timeout: 15))
        if response.status == 401 { throw VelovError(.expired, Messages.sessionToRenew) }
        guard response.ok else { throw VelovError(.unavailable, "Vélo’v n’a pas enregistré la note. Réessayez dans un instant.") }
    }

    /// Releases a bike, exactly once: the borne may already have opened, so a lost answer must never be retried.
    public static func release(_ auth: WriteAuth, subscriptionId: String, stationNumber: Int, standNumber: Int, bikeNumber: Int, http: HTTPTransport) async throws -> Outcome {
        let url = URL(string: "\(accountURL(auth.accountId))/subscriptions/\(pathSegment(subscriptionId))/trips")!
        let body = orderedJSON([("stationNumber", stationNumber), ("standNumber", standNumber), ("bikeNumber", bikeNumber), ("typeFrom", "SMARTPHONE")])
        let response: HTTPResponse
        do {
            response = try await http.send(makeRequest(url, method: "POST", headers: [
                "Authorization": "Taknv1 \(auth.token)", "Identity": auth.identity, "Content-Type": "application/vnd.trip.v6+json",
                "Accept": "application/vnd.trip.v6+json", "Accept-Language": "fr"], body: body, timeout: 30))
        } catch {
            var outcome = Outcome.refusal("network", "Vélo’v ne répond pas. Le vélo est peut-être déverrouillé : regardez la borne avant de réessayer.")
            outcome.detail = networkFailure(error)
            return outcome
        }
        if response.status == 401 { throw VelovError(.expired, Messages.sessionToRenew) }
        let reply = ErrorReply(response)
        return releaseOutcome(httpStatus: response.status, code: reply.code, detail: reply.detail, transactionState: reply.transactionState)
    }

    /// Books a bike, exactly once: it costs points, and a lost answer may hide a booking that went through.
    public static func book(_ auth: WriteAuth, stationId: String, stationNumber: Int, standNumber: Int, subscriptionId: String, bikeId: String, http: HTTPTransport) async throws -> (outcome: Outcome, booking: RawBooking?) {
        let url = URL(string: "\(accountURL(auth.accountId))/bookings")!
        // Field order of the app's CreateBooking constructor.
        let body = orderedJSON([("stationId", stationId), ("stationNumber", stationNumber), ("standNumber", standNumber), ("subscriptionId", subscriptionId), ("bikeId", bikeId)])
        let response: HTTPResponse
        do {
            response = try await http.send(makeRequest(url, method: "POST", headers: [
                "Authorization": "Taknv1 \(auth.token)", "Identity": auth.identity, "Content-Type": "application/json; charset=UTF-8"], body: body, timeout: 30))
        } catch {
            var outcome = Outcome.refusal("network", "Vélo’v ne répond pas. Le vélo est peut-être réservé : actualisez avant de réessayer.")
            outcome.detail = networkFailure(error)
            return (outcome, nil)
        }
        if response.status == 401 { throw VelovError(.expired, Messages.sessionToRenew) }
        let reply = ErrorReply(response)
        let outcome = bookingOutcome(httpStatus: response.status, code: reply.code, detail: reply.detail)
        return (outcome, outcome.ok ? reply.value.flatMap(RawBooking.init) : nil)
    }

    /// One call that changes the account, exactly once: whatever happens, it is never sent again without a new confirmation.
    /// With `preserveUnauthorized` a 401 comes back as an outcome (experimental writes keep their raw answer) instead of ending the session.
    static func accountCall(_ url: URL, method: String, headers: [String: String], body: Data?, auth: WriteAuth, failed: String, http: HTTPTransport,
                            preserveUnauthorized: Bool = false) async throws -> (outcome: Outcome, value: JSON?) {
        let response: HTTPResponse
        do {
            var all = headers
            all["Authorization"] = "Taknv1 \(auth.token)"
            all["Identity"] = auth.identity
            response = try await http.send(makeRequest(url, method: method, headers: all, body: body, timeout: 15))
        } catch {
            var outcome = Outcome.refusal("network", "Vélo’v ne répond pas. La modification a peut-être été prise en compte : actualisez avant de réessayer.")
            outcome.detail = networkFailure(error)
            return (outcome, nil)
        }
        if response.status == 401 && !preserveUnauthorized { throw VelovError(.expired, Messages.sessionToRenew) }
        let reply = ErrorReply(response)
        return (accountOutcome(httpStatus: response.status, code: reply.code, detail: reply.detail, failed: failed), response.ok ? reply.value : nil)
    }

    /// PATCH /rewards with the app's UpdateReward body; Vélo’v answers the whole rewards object.
    public static func setAutoSpend(_ auth: WriteAuth, _ autoSpend: Bool, http: HTTPTransport) async throws -> (outcome: Outcome, autoSpend: Bool?) {
        let (outcome, value) = try await accountCall(URL(string: "\(accountURL(auth.accountId))/rewards")!, method: "PATCH",
                                                     headers: ["Content-Type": "application/vnd.rewards.v5+json"], body: orderedJSON([("autoSpend", autoSpend)]),
                                                     auth: auth, failed: "Vélo’v n’a pas enregistré ce réglage.", http: http)
        return (outcome, value?["autoSpend"]?.bool ?? (outcome.ok ? autoSpend : nil))
    }

    /// Adds (POST) or removes (DELETE) a favourite station, with the app's trailing slash and Accept.
    public static func setFavorite(_ auth: WriteAuth, station: Int, on: Bool, http: HTTPTransport) async throws -> Outcome {
        try await accountCall(URL(string: "\(accountURL(auth.accountId))/stationbookmarks/\(station)/")!, method: on ? "POST" : "DELETE",
                              headers: ["Accept": "application/vnd.account.v4+json"], body: nil, auth: auth,
                              failed: on ? "Vélo’v n’a pas ajouté cette station aux favoris." : "Vélo’v n’a pas retiré cette station des favoris.", http: http).outcome
    }

    /// The receipt of one subscription period: a POST without body that only reads, answered as base64 under Accept: application/json.
    public static func receipt(_ auth: WriteAuth, subscriptionId: String, periodId: String, http: HTTPTransport) async throws -> (outcome: Outcome, filename: String?, pdf: Data?) {
        let url = URL(string: "\(accountURL(auth.accountId))/subscriptions/\(pathSegment(subscriptionId))/periods/\(pathSegment(periodId))/reports")!
        var (outcome, value) = try await accountCall(url, method: "POST", headers: ["Accept": "application/json"], body: nil, auth: auth, failed: "Ce reçu n’est pas disponible.", http: http)
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

    /// PATCH /accounts/{id} with only the changed fields, in the order of the body the app sends.
    public static func setProfile(_ auth: WriteAuth, _ body: ProfileBody, http: HTTPTransport) async throws -> Outcome {
        let body = body.trimmedForSending
        let address = body.address.map { orderedJSON([("name", $0.name), ("complement", $0.complement)]) }
        let pairs: [(String, Any?)] = [("country", body.country), ("zipCode", body.zipCode), ("city", body.city), ("phoneNumber", body.phoneNumber), ("address", address)]
        return try await accountCall(URL(string: accountURL(auth.accountId))!, method: "PATCH", headers: ["Content-Type": "application/vnd.account.v4+json"],
                                     body: orderedJSON(pairs.filter { $0.1 != nil }), auth: auth, failed: "Vélo’v n’a pas enregistré ces coordonnées.", http: http).outcome
    }
}
