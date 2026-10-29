import SwiftUI
import UIKit
import VelovCore

// account-actions.tsx, auto-renewal.tsx and contact-support.tsx: the account's writes, each confirmed and sent once.

let countries: [SelectOption<String>] = [
    .init(value: "FR", label: "France"), .init(value: "BE", label: "Belgique"), .init(value: "CH", label: "Suisse"), .init(value: "LU", label: "Luxembourg"),
    .init(value: "DE", label: "Allemagne"), .init(value: "ES", label: "Espagne"), .init(value: "IT", label: "Italie"), .init(value: "GB", label: "Royaume-Uni")
]

func countryName(_ code: String?) -> String? { countries.first { $0.value == code }?.label ?? code }

// MARK: Coordinates

struct ProfileDraft: Equatable {
    var address: String
    var complement: String
    var zipCode: String
    var city: String
    var country: String
    var phone: String

    init(_ profile: Profile) {
        address = profile.address ?? ""; complement = profile.addressComplement ?? ""; zipCode = profile.zipCode ?? ""
        city = profile.city ?? ""; country = profile.country ?? "FR"; phone = profile.phoneNumber ?? ""
    }
}

struct ProfileChange: Identifiable {
    let label: String
    let before: String
    let after: String
    var id: String { label }
}

struct ProfileReview: Identifiable {
    let body: ProfileBody
    let changes: [ProfileChange]
    let id = UUID()
}

/// `changesOf`: the PATCH body with only the fields that changed, or the first problem to fix; nil when nothing changed.
func reviewProfile(_ profile: Profile, _ draft: ProfileDraft) -> Result<ProfileReview, ProfileProblem>? {
    var body = ProfileBody()
    var changes: [ProfileChange] = []
    let trim = { (value: String) in value.trimmingCharacters(in: .whitespacesAndNewlines) }
    let address = trim(draft.address), complement = trim(draft.complement), zipCode = trim(draft.zipCode), city = trim(draft.city)
    let changed = { (value: String, before: String?) in value != (before ?? "") }
    if changed(address, profile.address) || changed(complement, profile.addressComplement) {
        if address.isEmpty { return .failure(ProfileProblem("Saisissez une adresse.")) }
        body.address = ProfileAddress(name: address, complement: complement)
        let before = [profile.address, profile.addressComplement].compactMap { $0 }.joined(separator: ", ")
        changes.append(ProfileChange(label: "Adresse", before: before.isEmpty ? "—" : before, after: [address, complement].filter { !$0.isEmpty }.joined(separator: ", ")))
    }
    if changed(zipCode, profile.zipCode) { body.zipCode = zipCode; changes.append(ProfileChange(label: "Code postal", before: profile.zipCode ?? "—", after: zipCode)) }
    if changed(city, profile.city) { body.city = city; changes.append(ProfileChange(label: "Ville", before: profile.city ?? "—", after: city)) }
    if changed(draft.country, profile.country) {
        body.country = draft.country
        changes.append(ProfileChange(label: "Pays", before: countryName(profile.country) ?? "—", after: countryName(draft.country) ?? draft.country))
    }
    let phone = normalizePhone(draft.phone, country: draft.country)
    if phone != (profile.phoneNumber ?? ""), trim(draft.phone) != (profile.phoneNumber ?? "") {
        body.phoneNumber = phone
        changes.append(ProfileChange(label: "Téléphone", before: profile.phoneNumber ?? "—", after: phone))
    }
    if changes.isEmpty { return nil }
    switch body.problem() {
    case nil: return .success(ProfileReview(body: body, changes: changes))
    case .phoneNumber?: return .failure(ProfileProblem("Numéro de téléphone invalide : 06 12 34 56 78 ou +33 6 12 34 56 78."))
    case .zipCode?: return .failure(ProfileProblem("Code postal invalide."))
    case .city?: return .failure(ProfileProblem("Saisissez une ville."))
    case .address?: return .failure(ProfileProblem("Adresse invalide (\(Rules.addressMax) caractères au plus)."))
    default: return .failure(ProfileProblem("Coordonnées invalides."))
    }
}

struct ProfileProblem: Error { let message: String; init(_ message: String) { self.message = message } }

/// `ProfileCoordinates`: address, postcode, city, country and phone only; names, email and secret code stay with Vélo’v.
struct ProfileCoordinates: View {
    let profile: Profile
    @Environment(AppModel.self) private var model
    @State private var draft: ProfileDraft?
    @State private var error: String?
    @State private var review: ProfileReview?

    var body: some View {
        Group {
            if draft != nil { form } else { summary }
        }
        .task { if model.snapshot == .accountEdit, draft == nil { draft = ProfileDraft(profile) } }
        .sheet(item: $review) { review in
            WriteDialog(title: "Enregistrer ?", success: "Coordonnées enregistrées.") {
                let outcome = await attempt { try await model.service.updateProfile(review.body) }
                if outcome.ok {
                    draft = nil
                    Task { await model.loadDashboard() }
                }
                return outcome
            } question: {
                VStack(spacing: 0) {
                    ForEach(Array(review.changes.enumerated()), id: \.element.id) { index, change in
                        DetailRow(label: change.label, last: index == review.changes.count - 1) { StackedValue(value: change.after, small: "Avant : \(change.before)") }
                    }
                }
            }
        }
    }

    private var summary: some View {
        let address = [profile.address, profile.addressComplement].compactMap { $0 }.joined(separator: ", ")
        let place = [profile.zipCode, profile.city].compactMap { $0 }.joined(separator: " ")
        let country = profile.country.map { "\(place.isEmpty ? "" : " · ")\(countryName($0) ?? $0)" } ?? ""
        return VStack(alignment: .leading, spacing: 0) {
            DetailRow(label: "Adresse") { StackedValue(value: address.isEmpty ? "Non renseignée" : address, small: place + country) }
            DetailRow("Téléphone", profile.phoneNumber ?? "Non renseigné", last: true)
            PillButton("Modifier mes coordonnées", variant: .secondary) { error = nil; draft = ProfileDraft(profile) }.padding(.top, 16)
        }
    }

    private var form: some View {
        let binding = { (key: WritableKeyPath<ProfileDraft, String>) in
            Binding<String>(get: { draft?[keyPath: key] ?? "" }, set: { draft?[keyPath: key] = $0 })
        }
        let country = draft?.country ?? "FR"
        return VStack(alignment: .leading, spacing: 14) {
            FormField(label: "Adresse", text: binding(\.address), maxLength: Rules.addressMax, content: .streetAddressLine1)
            FormField(label: "Complément", text: binding(\.complement), maxLength: Rules.addressMax, content: .streetAddressLine2)
            HStack(alignment: .top, spacing: 10) {
                FormField(label: "Code postal", text: binding(\.zipCode), maxLength: 10, keyboard: .numbersAndPunctuation, content: .postalCode).frame(width: 110)
                FormField(label: "Ville", text: binding(\.city), maxLength: 60, content: .addressCity)
            }
            SelectField(label: "Pays", value: binding(\.country),
                        options: countries.contains { $0.value == country } ? countries : countries + [.init(value: country, label: country)],
                        background: Palette.white)
                .zIndex(2)
            FormField(label: "Téléphone", text: binding(\.phone), maxLength: 20, keyboard: .phonePad, content: .telephoneNumber)
            if let error { FormError(error) }
            HStack(spacing: 10) {
                Spacer()
                PillButton("Annuler", variant: .ghost) { draft = nil }
                PillButton("Enregistrer") { submit() }
            }
        }
        .padding(.top, 16)
    }

    private func submit() {
        guard let draft else { return }
        switch reviewProfile(profile, draft) {
        case nil: error = "Aucune modification."
        case .failure(let problem)?: error = problem.message
        case .success(let value)?: error = nil; review = value
        }
    }
}

// MARK: Auto-renewal

/// auto-renewal.tsx: experimental; the switch shows only when Vélo’v offers it, the state shown after a change is the one read back.
struct AutoRenewalSetting: View {
    let subscription: Subscription
    @Environment(AppModel.self) private var model
    @State private var asking = false
    @State private var pending = false
    @State private var result: AutoRenewalResult?

    private var actual: Bool? { result?.outcome.ok == true ? result?.autoRenewal : subscription.autoRenewal }
    private var canChange: Bool { result?.outcome.ok == true ? result!.autoRenewalAllowed : subscription.autoRenewalAllowed }
    private var next: Bool { !(actual ?? false) }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Renouvellement automatique").typo(.label(12)).foregroundStyle(Palette.inkSoft)
                ExperimentalTag()
                Text(actual == nil ? "État à actualiser" : actual! ? "Activé" : "Désactivé").typo(.body(15, medium: true)).foregroundStyle(Palette.ink)
            }
            Spacer(minLength: 0)
            if canChange, subscription.id != nil, let actual {
                VelovSwitch(on: actual) { result = nil; asking = true }
                    .disabled(result != nil)
                    .accessibilityLabel("Renouvellement automatique").accessibilityValue(actual ? "Activé" : "Désactivé")
            }
        }
        .padding(.top, 20)
        .sheet(isPresented: $asking, onDismiss: { if result != nil { Task { await model.loadDashboard() } } }) { sheet }
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeading(title: "Renouvellement automatique", closeDisabled: pending) { asking = false }
            ExperimentalTag().padding(.top, 2)
            Group {
                if let result {
                    if result.outcome.ok {
                        DoneLine(text: !result.verified || result.autoRenewal == nil
                                 ? "Demande acceptée, mais l’état n’a pas pu être relu. Actualisez sans renvoyer la demande."
                                 : "État confirmé par Vélo’v : renouvellement \(result.autoRenewal! ? "activé" : "désactivé").")
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            FormError(result.outcome.message ?? "Vélo’v n’a pas enregistré le renouvellement automatique.")
                            RawStatus(outcome: result.outcome)
                        }
                    }
                } else {
                    Text(next ? "Activer le renouvellement automatique de votre abonnement ? Il pourra être renouvelé et facturé à son échéance."
                              : "Désactiver le renouvellement automatique de votre abonnement ?")
                        .typo(.body(15)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 14)
            HStack(spacing: 10) {
                Spacer()
                PillButton(result == nil ? "Annuler" : "Fermer", variant: .secondary) { asking = false }.disabled(pending)
                if result == nil { PillButton("Confirmer", pending: pending) { confirm() } }
            }
            .padding(.top, 24)
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 20)
        .fitSheet()
        .interactiveDismissDisabled(pending)
    }

    private func confirm() {
        guard !pending, result == nil, let id = subscription.id else { return }
        let next = next
        Haptics.confirm()
        pending = true
        Task {
            let value: AutoRenewalResult
            do {
                value = try await model.service.setAutoRenewal(subscriptionId: id, autoRenewal: next)
            } catch {
                let outcome = await attempt { throw error }
                value = AutoRenewalResult(outcome: outcome, autoRenewal: nil, autoRenewalAllowed: false, verified: false)
            }
            Haptics.result(value.outcome.ok)
            result = value
            pending = false
        }
    }
}

// MARK: Receipts

/// The receipt POST only reads: no confirmation, one request per tap, the PDF handed to the share sheet.
struct ReceiptRow: View {
    let receipt: Receipt
    @Environment(AppModel.self) private var model
    @State private var pending = false
    @State private var failed: Outcome?
    @State private var file: SharedFile?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(receipt.title).typo(.body(14, medium: true)).foregroundStyle(Palette.ink)
                    Text(periodLabel(receipt)).typo(.body(12)).foregroundStyle(Palette.inkSoft)
                }
                Spacer()
                PillButton(variant: .secondary, pending: pending, action: download) { Icon(.downloadSimple, .light, size: 17); Text("Reçu") }
                    .accessibilityLabel("Télécharger le reçu, \(periodLabel(receipt))")
            }
            if let failed {
                FormError(failed.message ?? "Le reçu n’a pas pu être téléchargé.")
                RawStatus(outcome: failed)
            }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) { Hairline(color: Palette.inkLine) }
        .sheet(item: $file) { ShareSheet(url: $0.url).presentationDetents([.medium, .large]) }
    }

    private func download() {
        guard !pending else { return }
        pending = true
        failed = nil
        Task {
            defer { pending = false }
            var pdf: Data?, name: String?
            let outcome = await attempt {
                let answer = try await model.service.receipt(subscriptionId: receipt.subscriptionId, periodId: receipt.periodId)
                (pdf, name) = (answer.pdf, answer.filename)
                return answer.outcome
            }
            guard outcome.ok, let pdf else { failed = outcome; return }
            let url = FileManager.default.temporaryDirectory.appending(path: name ?? "recu-velov.pdf")
            do {
                try pdf.write(to: url, options: .atomic)
                file = SharedFile(url: url)
            } catch {
                failed = Outcome(ok: false, httpStatus: outcome.httpStatus, code: "local.receipt.file", message: "Le reçu n’a pas pu être enregistré sur ce téléphone.")
            }
        }
    }
}

/// "Du 1 mars au 2 mars 2026": the period a receipt covers.
func periodLabel(_ receipt: Receipt) -> String {
    switch (receipt.start, receipt.end) {
    case let (start?, end?): "Du \(formatDate(start, .dayMonthYear)) au \(formatDate(end, .dayMonthYear))"
    case let (start?, nil): "Depuis le \(formatDate(start, .dayMonthYear))"
    case let (nil, end?): "Jusqu’au \(formatDate(end, .dayMonthYear))"
    default: "Période sans dates"
    }
}

struct SharedFile: Identifiable {
    let url: URL
    var id: URL { url }
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: Customer service

private let subjects: [SelectOption<String>] = zip(Guesses.mailComplaintTypes, ["Un trajet", "Mon abonnement", "Mes paiements", "Un parking"]).map { .init(value: $0, label: $1) }

/// contact-support.tsx: experimental; one multipart message after the review, the mail app as the alternative.
struct ContactSupport: View {
    let trips: [Trip]?
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var open = false
    @State private var subject = Guesses.mailComplaintTypes[0]
    @State private var message = ""
    @State private var tripId = "none"
    @State private var error: String?
    @State private var draft: ContactDraft?

    struct ContactDraft: Identifiable {
        let body: ContactBody
        let id = UUID()
    }

    private var recent: [Trip] { Array((trips ?? []).filter { $0.token != nil }.prefix(15)) }
    private var contact: ContactBody { ContactBody(complaintType: subject, message: message, tripToken: recent.first { $0.id == tripId }?.token) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !open {
                PillButton(variant: .secondary, action: { open = true }) { Icon(.envelopeSimple, .light, size: 18); Text("Écrire au service client") }
            } else {
                form
            }
            ExperimentalTag()
            Button { openMail() } label: { Text("Ouvrir ma messagerie à la place").typo(.body(13)).underline().foregroundStyle(Palette.redDeep) }
                .buttonStyle(.plain)
        }
        .sheet(item: $draft, onDismiss: nil) { draft in
            WriteDialog(title: "Envoyer au service client ?", success: "Message envoyé au service client.", experimental: true) {
                let outcome = await attempt { try await model.service.contactSupport(draft.body) }
                if outcome.ok { message = ""; tripId = "none" }
                return outcome
            } question: {
                VStack(alignment: .leading, spacing: 10) {
                    Text(subjects.first { $0.value == draft.body.complaintType }?.label ?? "Demande").typo(.label(12)).foregroundStyle(Palette.inkSoft)
                    Text(contactMessage(draft.body)).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            SelectField(label: "Objet", value: $subject, options: subjects, background: Palette.white).zIndex(3)
            if !recent.isEmpty {
                SelectField(label: "Trajet (facultatif)", value: $tripId,
                            options: [.init(value: "none", label: "Aucun")] + recent.map { .init(value: $0.id, label: "\(formatDate($0.startedAt)) · \($0.startStation ?? "Trajet")") },
                            background: Palette.white).zIndex(2)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Message").typo(.label(12)).foregroundStyle(Palette.inkSoft)
                TextEditor(text: $message).typo(.body(16)).frame(minHeight: 110).scrollContentBackground(.hidden)
                    .padding(6).background(RoundedRectangle(cornerRadius: 5.625).fill(Palette.white))
                    .overlay(RoundedRectangle(cornerRadius: 5.625).strokeBorder(Palette.fieldLine, lineWidth: 1))
                    .onChange(of: message) { _, value in if value.count > 1500 { message = String(value.prefix(1500)) } }
            }
            if let error { FormError(error) }
            HStack(spacing: 10) {
                Spacer()
                PillButton("Annuler", variant: .ghost) { open = false }
                PillButton("Vérifier et envoyer") { review() }
            }
        }
    }

    private func review() {
        let body = contact
        guard body.isValid else {
            error = "Saisissez un message et une catégorie valides (4 Ko au maximum)."
            return
        }
        error = nil
        draft = ContactDraft(body: body)
    }

    private func openMail() {
        let body = contact
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Support.address
        components.queryItems = [URLQueryItem(name: "subject", value: subjects.first { $0.value == subject }?.label ?? "Demande"),
                                 URLQueryItem(name: "body", value: contactMessage(body))]
        if let url = components.url { openURL(url) }
    }
}
