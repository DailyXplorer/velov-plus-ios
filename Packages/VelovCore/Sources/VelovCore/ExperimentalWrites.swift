import Foundation

public enum ViaStation: Equatable, Sendable {
    case number(Int)
    case uuid(String)
}

extension Writes {
    public static func setAutoRenewal(_ auth: WriteAuth, subscriptionId: String, autoRenewal: Bool, http: HTTPTransport) async throws -> Outcome {
        try await accountCall(URL(string: "\(accountURL(auth.accountId))/subscriptions/\(pathSegment(subscriptionId))")!, method: "PATCH",
                              headers: ["Content-Type": Guesses.subscriptionMediaType], body: orderedJSON([(Guesses.autoRenewalField, autoRenewal)]), auth: auth,
                              failed: "Vélo’v n’a pas enregistré le renouvellement automatique.", http: http, preserveUnauthorized: true).outcome
    }

    public static func via(_ auth: WriteAuth, subscriptionId: String, station: ViaStation, http: HTTPTransport) async throws -> Outcome {
        let stationId: Any
        switch station {
        case .number(let number): stationId = number
        case .uuid(let uuid): stationId = uuid
        }
        let (answer, value) = try await accountCall(URL(string: "\(accountURL(auth.accountId))/subscriptions/\(pathSegment(subscriptionId))/via")!, method: "POST",
                                                    headers: ["Content-Type": Guesses.viaMediaType], body: orderedJSON([(Guesses.viaStationField, stationId)]), auth: auth,
                                                    failed: "Les 15 minutes supplémentaires n’ont pas été accordées.", http: http, preserveUnauthorized: true)
        guard answer.ok else { return answer }
        var outcome = answer
        let state = value?.string ?? value?[Guesses.viaStateField]?.string
        outcome.ok = state == Guesses.viaSuccessState
        outcome.transactionState = state
        outcome.message = outcome.ok ? nil : "Vélo’v n’a pas confirmé les minutes supplémentaires. Vérifiez votre trajet avant de réessayer."
        return outcome
    }

    public static func contactMail(_ auth: WriteAuth, _ body: ContactBody, http: HTTPTransport, boundary: String = "VelovBoundary-\(UUID().uuidString)") async throws -> Outcome {
        let form = multipart([(Guesses.mailFields.complaintType, body.complaintType), (Guesses.mailFields.message, contactMessage(body))], boundary: boundary)
        return try await accountCall(URL(string: "\(accountURL(auth.accountId))/mail")!, method: "POST",
                                     headers: ["Accept": Guesses.mailAccept, "Content-Type": "multipart/form-data; boundary=\(boundary)"], body: form, auth: auth,
                                     failed: "Vélo’v n’a pas confirmé l’envoi du message.", http: http, preserveUnauthorized: true).outcome
    }

    public static func promoCode(_ auth: WriteAuth, http: HTTPTransport) async throws -> PromoResult {
        let (answer, value) = try await accountCall(URL(string: "\(accountURL(auth.accountId))/rewards/consume/promocode")!, method: "POST",
                                                    headers: ["Accept": Guesses.promocodeAccept], body: nil, auth: auth,
                                                    failed: "Le code n’a pas pu être créé.", http: http, preserveUnauthorized: true)
        let code = value?[Guesses.promocodeCodeField]?.string.flatMap { $0.isEmpty ? nil : $0 }
        var outcome = answer
        if outcome.ok && code == nil {
            outcome.ok = false
            outcome.code = "local.promo.unreadable"
            outcome.message = "Aucun code n’a été reçu, mais vos points ont peut-être été débités. Contactez le service client avant de recommencer."
        }
        return PromoResult(outcome: outcome, promoCode: code)
    }
}

func multipart(_ fields: [(String, String)], boundary: String) -> Data {
    var text = ""
    for (name, value) in fields {
        let normalized = value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\n", with: "\r\n")
        text += "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(normalized)\r\n"
    }
    text += "--\(boundary)--\r\n"
    return Data(text.utf8)
}
