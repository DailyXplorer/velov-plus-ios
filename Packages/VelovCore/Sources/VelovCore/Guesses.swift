import Foundation

/// Request shapes the public documentation leaves open. Every guessed field name, media type and enum value lives here,
/// with its source and confidence, so a first real answer can correct it in one place. None of them is sent in stage 1.
public enum Guesses {
    // MARK: Subscription auto-renewal — PATCH /accounts/{id}/subscriptions/{subscriptionId}
    /// Android method table (`ug/r.h`). Confidence: high.
    public static let autoRenewalContentType = "application/vnd.subscription.v6+json"
    /// Body of the Android model `SubscriptionAutoRenewal`; field name inferred from `renewalDetails.autoRenewalValue`. Confidence: medium.
    public static let autoRenewalField = "autoRenewal"
    /// Fallback if Vélo’v refuses the first name with a validation error. Confidence: low.
    public static let autoRenewalFallbackField = "autoRenewalValue"
    /// The GET field that says the app may show the switch. Confidence: high (seen in subscription answers).
    public static let autoRenewalAllowedField = "autoRenewalBtn"

    // MARK: "15 minutes de plus" — POST /accounts/{id}/subscriptions/{subscriptionId}/via
    /// Android method table (`ug/r.g`, model `CreateVia`). Confidence: high.
    public static let viaContentType = "application/vnd.subscription.v6+json"
    public static let viaField = "stationId"
    /// The `stationId` the app sends: the station UUID of GET /stations/{n} (v4), not its number. Confidence: medium.
    public static let viaUsesStationUUID = true

    // MARK: "Inviter un ami" — POST /accounts/{id}/rewards/consume/promocode, then a process
    /// Android method table (`qi/j.b`); answer `{ promoCode, offerId, badgeId, badgeType, rewardsSpent }`; points are debited here. Confidence: high.
    public static let promocodeAccept = "application/vnd.rewards.v5+json"
    /// Process that turns the code into a ticket (offer 579060 « Invitation ami »). Confidence: medium.
    public static let promocodeProcessType = "SHORT_TERM_SUBSCRIPTION_V2"
    public static let promocodeProcessPlatform = "MOBILE"

    // MARK: Contact customer service — POST /accounts/{id}/mail (multipart)
    /// Android method table (`qi/e.a`): `Accept: multipart/form-data`. Confidence: high.
    public static let mailAccept = "multipart/form-data"
    /// Multipart field names of the Android call. Confidence: high for the names, low for which ones are required.
    public static let mailFields = ["complaintType", "message", "subscriptionId", "tripId", "transactionId", "amount", "date", "status", "parkingId", "parkingNumber", "parkingName"]
    /// `complaintType` values are undocumented; this is the generic one the app's "Autre demande" most likely maps to. Confidence: low.
    public static let mailDefaultComplaintType = "OTHER"
    /// The fallback when the multipart call is refused.
    public static let supportAddress = "contact.velov@jcdecaux.com"
}
