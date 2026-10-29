import Foundation

public enum Messages {
    public static let releaseCodes: [String: String] = [
        "trips.exception.bookings.already.reserved": "Vélo réservé par un autre usager. Choisissez-en un autre.",
        "trips.exception.invalid.customer.maxBikesRented": "Impossible de libérer le vélo, un autre trajet est en cours.",
        "kiwi.exception.customer.rent.time.limit": "Délai entre deux courses non écoulé.",
        "kiwi.exception.customer.insuffisant.right": "Abonnement hors validité.",
        "kiwi.exception.customer.paymentmode.not.valid": "Veuillez mettre à jour votre mode de paiement.",
        "kiwi.exception.no.release.bike": "Problème technique lors de la libération du vélo.",
        "trips.exception.invalid.customer.credit": "Crédit du compte insuffisant pour libérer un vélo."
    ]
    public static let releaseStates: [String: String] = [
        "ABORT": "Le déverrouillage a été annulé.",
        "NOK": "Le vélo n’a pas pu être déverrouillé.",
        "TIME_OUT": "La borne n’a pas répondu à temps.",
        "NOT_CONNECTED": "Aucun vélo n’est accroché à cette borne."
    ]
    public static let bookingCodes: [String: String] = [
        "booking.exception.bike.already.reserved": "Ce vélo est déjà réservé par un autre usager.",
        "bookings.exception.not.authorized": "Vous avez déjà une réservation en cours, ou moins de 10 points."
    ]
    public static let accountCodes: [String: String] = [
        "accounts.exception.validation.failed": "Vélo’v a refusé ces coordonnées : vérifiez le numéro de téléphone et l’adresse.",
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

    public static let uncertain = "Le résultat est incertain : vérifiez avant de réessayer."
    public static let uncertainUnlock = "Le résultat est incertain : vérifiez la borne avant de réessayer."
    public static let busy = "Une autre action est en cours. Attendez sa réponse avant de recommencer."
    public static let unsaved = "Ce téléphone ne peut pas suivre cette action. Rien n’a été envoyé."
    public static let lost = "L’app a été fermée avant la réponse. L’action a peut-être abouti."
    public static let notApplied = "Vélo’v n’a rien enregistré. Vous pouvez réessayer."
    public static let unverified = "Le résultat est incertain et n’a pas pu être vérifié. Vérifiez de nouveau avant de réessayer."
    public static let ratingUnconfirmed = "Vélo’v ne répond pas. La note a peut-être été enregistrée."
    public static let ratingUncertain = "Vélo’v n’a pas confirmé la note. Elle a peut-être été enregistrée."
    public static let ratingRefused = "Vélo’v a refusé cette note."
    public static let bookingsUnreadable = "Les réservations en cours n’ont pas pu être lues."
    public static let releaseFailed = "Le déverrouillage n’a pas abouti."
    public static let bookingFailed = "La réservation de votre vélo n’a pas fonctionné."
    public static let sessionRefused = "Votre session n’est plus valide. Reconnectez-vous."
    public static let sessionToRenew = "Votre session a expiré. Reconnectez-vous."
    public static let sessionExpired = "Votre session a expiré. Reconnectez-vous."
    public static let loginRefused = "Vélo’v a refusé la connexion."
    public static let otherDevice = "Votre compte est déjà connecté sur un autre appareil. Déconnectez-le avant de réessayer."
    public static let credentials = "Adresse e-mail ou code secret incorrect."
    public static let remoteLogoutUnconfirmed = "Déconnexion effectuée. Vélo’v ne l’a pas encore confirmée."
    public static let missing = "Indisponible pour le moment"
    public static let stationsUnavailable = "Les disponibilités des stations sont momentanément indisponibles."
    public static let stationBikesUnavailable = "Les vélos de cette station sont momentanément indisponibles."
    public static let bikeUnavailable = "Ce vélo est momentanément indisponible."
    public static let accountUnavailable = "Certaines informations Vélo’v ne sont pas disponibles pour le moment."
    public static let soon = "Bientôt disponible"
}

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

public func ratingLine(_ outcome: Outcome) -> String {
    let code = outcome.code.flatMap { $0.hasPrefix("local.") || $0 == "network" ? nil : "Code \($0)" }
    let detail = outcome.detail.flatMap { $0.isEmpty ? nil : capitalize($0) }
    return ["HTTP \(outcome.httpStatus == 0 ? "aucune réponse" : String(outcome.httpStatus))", code, detail].compactMap { $0 }.joined(separator: " · ")
}

public func ratingOutcome(_ outcome: Outcome) -> Outcome {
    guard !outcome.ok, outcome.code?.hasPrefix("local.") != true else { return outcome }
    var rated = outcome
    rated.message = outcome.httpStatus == 0 ? Messages.ratingUnconfirmed : outcome.isUncertain ? Messages.ratingUncertain : Messages.ratingRefused
    return rated
}

public func rawLine(_ outcome: Outcome, extra: String? = nil, withState: Bool = true) -> String {
    var parts: [String] = []
    if withState { parts.append("TransactionState \(outcome.transactionState ?? "—")") }
    let http = "HTTP \(outcome.httpStatus == 0 ? "aucune réponse" : String(outcome.httpStatus))"
    let code = "Code \(outcome.code ?? "—")"
    parts += withState ? [code, http] : [http, code]
    parts += [outcome.detail, extra].compactMap { $0?.isEmpty == false ? $0 : nil }.map(capitalize)
    return parts.joined(separator: " · ")
}
