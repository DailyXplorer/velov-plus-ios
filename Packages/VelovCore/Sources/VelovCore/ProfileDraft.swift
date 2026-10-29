import Foundation

// profile-draft.ts: the « Modifier mes coordonnées » form without SwiftUI: what the user typed, and the PATCH body it becomes.

public struct ProfileDraft: Equatable, Sendable {
    public var firstName: String
    public var lastName: String
    public var address: String
    public var complement: String
    public var zipCode: String
    public var city: String
    public var country: String
    public var phone: String

    /// The current values; names are shown capitalised (Vélo’v stores them in lower case) and only sent if the user edits them.
    public init(_ profile: Profile) {
        firstName = formatName(profile.firstName); lastName = formatName(profile.lastName)
        address = profile.address ?? ""; complement = profile.addressComplement ?? ""; zipCode = profile.zipCode ?? ""
        city = profile.city ?? ""; country = profile.country ?? "FR"; phone = profile.phoneNumber ?? ""
    }
}

public struct ProfileProblem: Error, Equatable, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

private func nameError(_ field: ProfileField) -> String {
    "\(field == .firstName ? "Prénom" : "Nom") invalide : lettres, espaces, apostrophes et traits d’union uniquement, \(Rules.nameMax) caractères au plus."
}

/// `changesOf`: the PATCH body with only the fields that changed, or the first problem to fix; nil when nothing changed.
public func reviewProfile(_ profile: Profile, _ draft: ProfileDraft) -> Result<ProfileBody, ProfileProblem>? {
    var body = ProfileBody()
    let trim = { (value: String) in value.trimmingCharacters(in: .whitespacesAndNewlines) }
    let changed = { (value: String, before: String?) in value != (before ?? "") }
    for (key, value, before, empty) in [(\ProfileBody.firstName, draft.firstName, profile.firstName, "Saisissez votre prénom."),
                                        (\ProfileBody.lastName, draft.lastName, profile.lastName, "Saisissez votre nom.")] {
        let name = cleanName(value)
        if !changed(name, before) || name == formatName(before) { continue }
        if name.isEmpty { return .failure(ProfileProblem(empty)) }
        body[keyPath: key] = name
    }
    let address = trim(draft.address), complement = trim(draft.complement), zipCode = trim(draft.zipCode), city = trim(draft.city)
    if changed(address, profile.address) || changed(complement, profile.addressComplement) {
        if address.isEmpty { return .failure(ProfileProblem("Saisissez une adresse.")) }
        body.address = ProfileAddress(name: address, complement: complement)
    }
    if changed(zipCode, profile.zipCode) { body.zipCode = zipCode }
    if changed(city, profile.city) { body.city = city }
    if changed(draft.country, profile.country) { body.country = draft.country }
    let phone = normalizePhone(draft.phone, country: draft.country)
    if phone != (profile.phoneNumber ?? ""), trim(draft.phone) != (profile.phoneNumber ?? "") { body.phoneNumber = phone }
    switch body.problem() {
    case .empty?: return nil
    case nil: return .success(body)
    case .firstName?: return .failure(ProfileProblem(nameError(.firstName)))
    case .lastName?: return .failure(ProfileProblem(nameError(.lastName)))
    case .phoneNumber?: return .failure(ProfileProblem("Numéro de téléphone invalide. Exemple : 06 12 34 56 78."))
    case .zipCode?: return .failure(ProfileProblem("Code postal invalide."))
    case .city?: return .failure(ProfileProblem("Saisissez une ville."))
    case .address?: return .failure(ProfileProblem("L’adresse ne doit pas dépasser \(Rules.addressMax) caractères."))
    case .country?: return .failure(ProfileProblem("Coordonnées invalides."))
    }
}
