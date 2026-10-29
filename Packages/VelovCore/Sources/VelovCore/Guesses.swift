import Foundation

/// Request shapes the public documentation leaves open, identical to the web client's `lib/guesses.ts`.
/// Guesses are switches for a future reviewed change, never runtime retries or fallback submissions.
public enum Guesses {
    // MARK: Subscription auto-renewal — PATCH /accounts/{id}/subscriptions/{subscriptionId}
    /// Medium confidence: VLSKit 5fea3c62 Models/Subscription.swift L203–211 encodes isAutoRenewal directly.
    /// https://github.com/Fyroeo/VLSKit/blob/5fea3c62a541de8b0061755c17b76e612dcfa155/Sources/VLSKit/Models/Subscription.swift#L203-L211
    public static let autoRenewalField = "isAutoRenewal"
    /// Low confidence alternatives suggested by GET renewalDetails; not sent automatically.
    public static let autoRenewalFallbackFields = ["autoRenewal", "autoRenewalValue"]
    /// High confidence: community-README.md Android table L2418; VLSKit SubscriptionService.swift L129–136.
    public static let subscriptionMediaType = "application/vnd.subscription.v6+json"

    // MARK: "15 minutes de plus" — POST /accounts/{id}/subscriptions/{subscriptionId}/via
    /// Via: community-README §5.5 / Android ug/r.g; VLSKit SubscriptionService.swift (5fea3c6), lines 93–116. Confidence: high for media type and field.
    public static let viaMediaType = "application/vnd.subscription.v6+json"
    public static let viaStationField = "stationId"
    public enum ViaStationIdentifier: Sendable { case number, uuid }
    /// VLSKit Models/Subscription.swift lines 131–158 uses Int64 and explicitly assumes a station number (unverified). Confidence: medium.
    /// Change only this line to `.uuid` after confirmation, never retry with another format.
    public static let viaStationIdentifier: ViaStationIdentifier = .number

    // MARK: Contact customer service — POST /accounts/{id}/mail (multipart)
    /// Mail: high confidence field names/media type, Android qi/e.a in docs/api/community-README.md §10 table.
    /// Enum values: medium confidence, reconstructed client Fyroeo/VLSKit EmailService.swift L6–14.
    /// Source: https://github.com/Fyroeo/VLSKit/blob/5fea3c62a541de8b0061755c17b76e612dcfa155/Sources/VLSKit/Services/EmailService.swift
    /// No live request has confirmed this format. Change these constants, never retry with a fallback body.
    public static let mailAccept = "multipart/form-data"
    /// tripId is deliberately omitted: VLSKit calls it tripNumber; the dashboard only has a UUID.
    /// The selected trip token is appended to message instead of guessing its identifier kind.
    public static let mailFields = (complaintType: "complaintType", message: "message")
    public static let mailComplaintTypes = ["TRIP", "SUBSCRIPTION", "PAYMENT", "PARKING"]
    /// VLSKit SubscriptionService.requestExtraTime returns the string TransactionState enum (Models/Trip.swift), confidence: medium;
    /// object envelope is a defensive compatibility assumption.
    public static let viaSuccessState = "OK"
    public static let viaStateField = "transactionState"

    // MARK: "Inviter un ami" — POST /accounts/{id}/rewards/consume/promocode
    /// High confidence: Android qi/j.b in community-README.md §5.8/§7 table; confirmed by Fyroeo/VLSKit@5fea3c62 RewardService.swift L38–44.
    public static let promocodeAccept = "application/vnd.rewards.v5+json"
    /// High confidence: Android ConsumePromocode response, community-README.md §5.8.
    public static let promocodeCodeField = "promoCode"
    /// High confidence: rewards configuration name, community-README.md §5.8.
    public static let promocodeReward = "PROMOCODE"
    // No SHORT_TERM_SUBSCRIPTION_V2 is sent: invitation-specific browser parameters
    // and process/payment completion have not been exercised. Keep the redeemable code.
}

/// The customer-service address the web app's mailto links use.
public enum Support {
    public static let address = "contact.velov@jcdecaux.com"
}
