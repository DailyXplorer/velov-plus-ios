import Foundation

/// French copy for Cyclocity error codes and states, identical to the web app.
public enum Messages {
    /// Release refusals the official app translates, plus the booking clash it shows with its generic message.
    public static let releaseCodes: [String: String] = [
        "trips.exception.bookings.already.reserved": "Vélo réservé par un autre usager. Vélo’v renvoie parfois ce refus pour un vélo que vous avez vous-même réservé : essayez un autre vélo.",
        "trips.exception.invalid.customer.maxBikesRented": "Impossible de libérer le vélo, un autre trajet est en cours.",
        "kiwi.exception.customer.rent.time.limit": "Délai entre deux courses non écoulé.",
        "kiwi.exception.customer.insuffisant.right": "Abonnement hors validité.",
        "kiwi.exception.customer.paymentmode.not.valid": "Veuillez mettre à jour votre mode de paiement.",
        "kiwi.exception.no.release.bike": "Problème technique lors de la libération du vélo.",
        "trips.exception.invalid.customer.credit": "Crédit du compte insuffisant pour libérer un vélo."
    ]
    public static let releaseStates: [String: String] = [
        "ABORT": "La libération du vélo a été annulée.",
        "NOK": "La libération du vélo a échoué.",
        "TIME_OUT": "La borne n’a pas répondu à temps pour libérer le vélo.",
        "NOT_CONNECTED": "Aucun vélo n’est connecté à la borne : borne non connectée."
    ]
    public static let bookingCodes: [String: String] = [
        "booking.exception.bike.already.reserved": "Ce vélo est déjà réservé par un autre usager.",
        "bookings.exception.not.authorized": "Réservation refusée : un compte n’a qu’une réservation à la fois, et il faut 10 points."
    ]
    public static let accountCodes: [String: String] = [
        "accounts.exception.validation.failed": "Vélo’v a refusé ces coordonnées : vérifiez le numéro de téléphone et l’adresse.",
        "accounts.exception.notacceptable.account.phone.invalid": "Ce numéro de téléphone n’est pas valide."
    ]
    public static let rewardReasons: [String: String] = [
        "RATE_BIKE": "Vélo évalué", "START_STATION_FULL": "Départ d’une station pleine", "END_STATION_EMPTY": "Arrivée dans une station vide",
        "TRIP_BONUS": "Bonus de trajet", "START_TRIP_OVERFLOW": "Départ en station virtuelle", "REDUCTION": "Réduction sur un trajet",
        "BIKE_BOOKING": "Réservation d’un vélo", "PROMOCODE": "Invitation d’un proche"
    ]
    public static let tripStatuses: [String: String] = [
        "REQUESTED": "Demandé", "STARTED": "En cours", "PAUSED": "En pause", "FINISHED": "Terminé", "AUTO_FINISHED": "Terminé automatiquement",
        "REJECTED": "Refusé", "TIMEOUT": "Expiré", "ERROR": "En erreur", "WARNING": "Avertissement", "REVERSED": "Annulé"
    ]

    public static let releaseFailed = "La libération du vélo a échoué pour une raison inconnue."
    public static let bookingFailed = "La réservation de votre vélo n’a pas fonctionné."
    public static let sessionRefused = "Vélo’v n’a pas reconnu votre session. Reconnectez-vous puis réessayez."
    public static let sessionToRenew = "Votre session doit être renouvelée. Reconnectez-vous pour continuer."
    public static let sessionExpired = "Votre session a expiré. Reconnectez-vous pour continuer."
    /// A login refusal whose page carries no readable message. Otherwise the server's own words are shown.
    public static let loginRefused = "Vélo’v a refusé la connexion."
    public static let credentials = "L’email ou le code secret n’a pas été reconnu."
    public static let remoteLogoutUnconfirmed = "Déconnecté ici, mais Vélo’v n’a pas confirmé la fin de session."
    public static let missing = "Indisponible pour le moment"
    public static let stationsUnavailable = "Les disponibilités des stations sont momentanément indisponibles."
    public static let stationBikesUnavailable = "Les vélos de cette station sont momentanément indisponibles."
    public static let bikeUnavailable = "Ce vélo est momentanément indisponible."
    public static let accountUnavailable = "Certaines informations Vélo’v ne sont pas disponibles pour le moment."
    public static let soon = "Bientôt disponible"
}

/// Success is transactionState OK, never the HTTP status alone.
public func releaseOutcome(httpStatus: Int, code: String?, detail: String?, transactionState: String?) -> Outcome {
    let ok = httpStatus == 200 && transactionState == "OK"
    let message: String? = ok ? nil
        : code.flatMap { Messages.releaseCodes[$0] }
        ?? transactionState.flatMap { Messages.releaseStates[$0] }
        ?? (httpStatus == 403 ? Messages.sessionRefused : Messages.releaseFailed)
    return Outcome(ok: ok, httpStatus: httpStatus, transactionState: transactionState, code: code, message: message, detail: detail)
}

public func bookingOutcome(httpStatus: Int, code: String?, detail: String?) -> Outcome {
    let ok = (200..<300).contains(httpStatus)
    let message: String? = ok ? nil : code.flatMap { Messages.bookingCodes[$0] } ?? (httpStatus == 403 ? Messages.sessionRefused : Messages.bookingFailed)
    return Outcome(ok: ok, httpStatus: httpStatus, code: code, message: message, detail: detail)
}

public func accountOutcome(httpStatus: Int, code: String?, detail: String?, failed: String) -> Outcome {
    let ok = (200..<300).contains(httpStatus)
    let message: String? = ok ? nil : code.flatMap { Messages.accountCodes[$0] } ?? (httpStatus == 403 ? Messages.sessionRefused : failed)
    return Outcome(ok: ok, httpStatus: httpStatus, code: code, message: message, detail: detail)
}

/// "TransactionState OK · Code — · HTTP 200 · Detail": the raw line shown under a failed action.
public func rawLine(_ outcome: Outcome, extra: String? = nil, withState: Bool = true) -> String {
    var parts: [String] = []
    if withState { parts.append("TransactionState \(outcome.transactionState ?? "—")") }
    let http = "HTTP \(outcome.httpStatus == 0 ? "aucune réponse" : String(outcome.httpStatus))"
    let code = "Code \(outcome.code ?? "—")"
    parts += withState ? [code, http] : [http, code]
    parts += [outcome.detail, extra].compactMap { $0?.isEmpty == false ? $0 : nil }.map(capitalize)
    return parts.joined(separator: " · ")
}
