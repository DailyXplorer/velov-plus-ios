import Foundation

private func trimmed(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }
private func hasControlCharacter(_ value: String) -> Bool { value.unicodeScalars.contains { $0.properties.generalCategory == .control } }

private func validLine(_ value: String, max: Int, min: Int = 0) -> Bool {
    let value = trimmed(value)
    return value.utf16.count >= min && value.utf16.count <= max && !hasControlCharacter(value)
}

public struct ProfileAddress: Equatable, Sendable {
    public var name: String
    public var complement: String
    public init(name: String, complement: String) { self.name = name; self.complement = complement }
}

public func cleanName(_ value: String) -> String { trimmed(value).replacing(/\ {2,}/, with: " ") }

private func validName(_ value: String) -> Bool {
    let name = cleanName(value)
    return !name.isEmpty && name.utf16.count <= Rules.nameMax && name.wholeMatch(of: /\p{L}[\p{L}\p{M} ’'\-]*/) != nil
}

public enum ProfileField: Equatable, Sendable { case firstName, lastName, address, zipCode, city, country, phoneNumber, empty }

public struct ProfileBody: Equatable, Sendable {
    public var firstName: String?
    public var lastName: String?
    public var address: ProfileAddress?
    public var zipCode: String?
    public var city: String?
    public var country: String?
    public var phoneNumber: String?

    public init(firstName: String? = nil, lastName: String? = nil, address: ProfileAddress? = nil, zipCode: String? = nil, city: String? = nil, country: String? = nil, phoneNumber: String? = nil) {
        self.firstName = firstName; self.lastName = lastName
        self.address = address; self.zipCode = zipCode; self.city = city; self.country = country; self.phoneNumber = phoneNumber
    }

    public func problem() -> ProfileField? {
        if firstName == nil, lastName == nil, address == nil, zipCode == nil, city == nil, country == nil, phoneNumber == nil { return .empty }
        if let firstName, !validName(firstName) { return .firstName }
        if let lastName, !validName(lastName) { return .lastName }
        if let address, !validLine(address.name, max: Rules.addressMax, min: 1) || !validLine(address.complement, max: Rules.addressMax) { return .address }
        if let zipCode, !validLine(zipCode, max: 10) || trimmed(zipCode).wholeMatch(of: /[A-Za-z0-9][A-Za-z0-9 -]{1,9}/) == nil { return .zipCode }
        if let city, !validLine(city, max: 60, min: 1) { return .city }
        if let country, country.wholeMatch(of: /[A-Z]{2}/) == nil { return .country }
        if let phoneNumber, phoneNumber.wholeMatch(of: /\+[1-9]\d{7,14}/) == nil { return .phoneNumber }
        return nil
    }

    var trimmedForSending: ProfileBody {
        ProfileBody(firstName: firstName.map(cleanName), lastName: lastName.map(cleanName),
                    address: address.map { ProfileAddress(name: trimmed($0.name), complement: trimmed($0.complement)) },
                    zipCode: zipCode.map(trimmed), city: city.map(trimmed), country: country, phoneNumber: phoneNumber)
    }
}

public struct ContactBody: Equatable, Sendable {
    public static let byteLimit = 10_240

    public var complaintType: String
    public var message: String
    public var tripToken: String?

    public init(complaintType: String, message: String, tripToken: String? = nil) {
        self.complaintType = complaintType; self.message = message; self.tripToken = tripToken
    }

    public var isValid: Bool {
        let length = trimmed(message).utf16.count
        guard Guesses.mailComplaintTypes.contains(complaintType), length >= 1, length <= 1500 else { return false }
        if let tripToken, !validLine(tripToken, max: 128, min: 1) { return false }
        var pairs: [(String, Any?)] = [("complaintType", complaintType), ("message", message)]
        if let tripToken { pairs.append(("tripToken", tripToken)) }
        return orderedJSON(pairs).count <= Self.byteLimit
    }
}

public func contactMessage(_ body: ContactBody) -> String {
    let token = body.tripToken.map(trimmed).flatMap { $0.isEmpty ? nil : $0 }
    return [trimmed(body.message), token.map { "Code du trajet : \($0)" }].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: "\n\n")
}

public struct AutoRenewalResult: Equatable, Sendable {
    public var outcome: Outcome
    public var autoRenewal: Bool?
    public var autoRenewalAllowed: Bool
    public var verified: Bool
    public init(outcome: Outcome, autoRenewal: Bool?, autoRenewalAllowed: Bool, verified: Bool) {
        self.outcome = outcome; self.autoRenewal = autoRenewal; self.autoRenewalAllowed = autoRenewalAllowed; self.verified = verified
    }
}

public struct PromoResult: Equatable, Sendable {
    public var outcome: Outcome
    public var promoCode: String?
    public init(outcome: Outcome, promoCode: String?) { self.outcome = outcome; self.promoCode = promoCode }
}

func renewalState(of subscription: JSON?) -> (autoRenewal: Bool?, allowed: Bool) {
    let details = subscription?["periods"]?.array?.last?["renewalDetails"]
    return (details?["autoRenewalValue"]?.bool, subscription?["isLocked"]?.bool != true && details?["autoRenewalBtn"]?.bool == true)
}

public func fullStations(_ stations: [Station], query: String, position: GeoPoint?) -> [Station] {
    let french = Locale(identifier: "fr_FR")
    let normalize = { (text: String) in text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: french) }
    let needle = normalize(query)
    let matching = stations.filter { $0.open && $0.stands == 0 && (needle.isEmpty || normalize("\($0.name) \($0.address) \($0.number)").contains(needle)) }
    return matching.enumerated().sorted { left, right in
        if let position {
            let delta = haversine(position, left.element.point) - haversine(position, right.element.point)
            if delta != 0 { return delta < 0 }
        }
        let order = left.element.name.compare(right.element.name, locale: french)
        return order == .orderedSame ? left.offset < right.offset : order == .orderedAscending
    }.map(\.element)
}
