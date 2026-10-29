import Foundation

public enum Guesses {
    public static let autoRenewalField = "isAutoRenewal"
    public static let autoRenewalFallbackFields = ["autoRenewal", "autoRenewalValue"]
    public static let subscriptionMediaType = "application/vnd.subscription.v6+json"

    public static let viaMediaType = "application/vnd.subscription.v6+json"
    public static let viaStationField = "stationId"
    public enum ViaStationIdentifier: Sendable { case number, uuid }
    public static let viaStationIdentifier: ViaStationIdentifier = .number

    public static let mailAccept = "multipart/form-data"
    public static let mailFields = (complaintType: "complaintType", message: "message")
    public static let mailComplaintTypes = ["TRIP", "SUBSCRIPTION", "PAYMENT", "PARKING"]
    public static let viaSuccessState = "OK"
    public static let viaStateField = "transactionState"

    public static let promocodeAccept = "application/vnd.rewards.v5+json"
    public static let promocodeCodeField = "promoCode"
    public static let promocodeReward = "PROMOCODE"
}

public enum Support {
    public static let address = "contact.velov@jcdecaux.com"
}
