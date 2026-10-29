import Foundation

// The experimental account writes, built on the shapes in `Guesses.swift`. Each one goes out once per confirmation;
// a refusal keeps its raw status, code and message (a 401 included) and is never followed by another body.

/// The station a "15 minutes de plus" request names, in the form `Guesses.viaStationIdentifier` selects.
public enum ViaStation: Equatable, Sendable {
    case number(Int)
    case uuid(String)
}

extension Writes {
    /// Experimental subscription setting. Never try an alternative body after a refusal.
    public static func setAutoRenewal(_ auth: WriteAuth, subscriptionId: String, autoRenewal: Bool, http: HTTPTransport) async throws -> Outcome {
        try await accountCall(URL(string: "\(accountURL(auth.accountId))/subscriptions/\(pathSegment(subscriptionId))")!, method: "PATCH",
                              headers: ["Content-Type": Guesses.subscriptionMediaType], body: orderedJSON([(Guesses.autoRenewalField, autoRenewal)]), auth: auth,
                              failed: "Vélo’v n’a pas enregistré le renouvellement automatique.", http: http, preserveUnauthorized: true).outcome
    }

    /// Request a full-station extension once. A missing answer can hide a granted extension: no retry or alternate body.
    public static func via(_ auth: WriteAuth, subscriptionId: String, station: ViaStation, http: HTTPTransport) async throws -> Outcome {
        let stationId: Any
        switch station {
        case .number(let number): stationId = number
        case .uuid(let uuid): stationId = uuid
        }
        let (answer, value) = try await accountCall(URL(string: "\(accountURL(auth.accountId))/subscriptions/\(pathSegment(subscriptionId))/via")!, method: "POST",
                                                    headers: ["Content-Type": Guesses.viaMediaType], body: orderedJSON([(Guesses.viaStationField, stationId)]), auth: auth,
                                                    failed: "Vélo’v n’a pas accordé les 15 minutes supplémentaires.", http: http, preserveUnauthorized: true)
        guard answer.ok else { return answer }
        // VLSKit SubscriptionService.requestExtraTime returns TransactionState, not an HTTP-only acknowledgement.
        var outcome = answer
        let state = value?.string ?? value?[Guesses.viaStateField]?.string
        outcome.ok = state == Guesses.viaSuccessState
        outcome.transactionState = state
        outcome.message = outcome.ok ? nil : "Vélo’v n’a pas confirmé les minutes supplémentaires. Vérifiez votre trajet avant de réessayer."
        return outcome
    }

    /// One multipart customer-service message. One request, including on a lost response or expired session.
    public static func contactMail(_ auth: WriteAuth, _ body: ContactBody, http: HTTPTransport, boundary: String = "VelovBoundary-\(UUID().uuidString)") async throws -> Outcome {
        let form = multipart([(Guesses.mailFields.complaintType, body.complaintType), (Guesses.mailFields.message, contactMessage(body))], boundary: boundary)
        return try await accountCall(URL(string: "\(accountURL(auth.accountId))/mail")!, method: "POST",
                                     headers: ["Accept": Guesses.mailAccept, "Content-Type": "multipart/form-data; boundary=\(boundary)"], body: form, auth: auth,
                                     failed: "Vélo’v n’a pas confirmé l’envoi du message.", http: http, preserveUnauthorized: true).outcome
    }

    /// The single debit, without a body. Optional response metadata must never hide a returned code.
    public static func promoCode(_ auth: WriteAuth, http: HTTPTransport) async throws -> PromoResult {
        let (answer, value) = try await accountCall(URL(string: "\(accountURL(auth.accountId))/rewards/consume/promocode")!, method: "POST",
                                                    headers: ["Accept": Guesses.promocodeAccept], body: nil, auth: auth,
                                                    failed: "Vélo’v n’a pas fourni de code d’invitation.", http: http, preserveUnauthorized: true)
        let code = value?[Guesses.promocodeCodeField]?.string.flatMap { $0.isEmpty ? nil : $0 }
        var outcome = answer
        if outcome.ok && code == nil {
            outcome.ok = false
            outcome.code = "local.promo.unreadable"
            outcome.message = "Les points ont peut-être été débités, mais aucun code lisible n’a été reçu. Ne recommencez pas : contactez Vélo’v."
        }
        return PromoResult(outcome: outcome, promoCode: code)
    }
}

/// `multipart/form-data` text fields, as `FormData` writes them: line breaks in values become CRLF.
func multipart(_ fields: [(String, String)], boundary: String) -> Data {
    var text = ""
    for (name, value) in fields {
        let normalized = value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
        text += "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(normalized)\r\n"
    }
    text += "--\(boundary)--\r\n"
    return Data(text.utf8)
}
