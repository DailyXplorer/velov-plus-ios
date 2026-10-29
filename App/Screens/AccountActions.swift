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

struct ProfileReview: Identifiable {
    let body: ProfileBody
    let id = UUID()
}

/// `ProfileCoordinates`: first and last name, address, postcode, city, country and phone (PATCH /accounts/{id}); email and secret code stay with Vélo’v.
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
            WriteDialog(title: "Enregistrer les modifications ?") {
                let outcome = await attempt { try await model.service.updateProfile(review.body) }
                // Back to the coordinates, read again from Vélo’v.
                if outcome.ok {
                    draft = nil
                    Task { await model.loadDashboard() }
                }
                return outcome
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
            // `.name-pair` on a phone: one field per row.
            FormField(label: "Prénom", text: binding(\.firstName), maxLength: Rules.nameMax, content: .givenName)
            FormField(label: "Nom", text: binding(\.lastName), maxLength: Rules.nameMax, content: .familyName)
            FormField(label: "Adresse", text: binding(\.address), maxLength: Rules.addressMax, content: .streetAddressLine1)
            FormField(label: "Complément", text: binding(\.complement), maxLength: Rules.addressMax, content: .streetAddressLine2)
            HStack(alignment: .top, spacing: 10) {
                FormField(label: "Code postal", text: binding(\.zipCode), maxLength: 10, keyboard: .numbersAndPunctuation, content: .postalCode).frame(width: 110)
                FormField(label: "Ville", text: binding(\.city), maxLength: 60, content: .addressCity)
            }
            SelectField(label: "Pays", value: binding(\.country),
                        options: countries.contains { $0.value == country } ? countries : countries + [.init(value: country, label: country)],
                        layout: .stacked)
                .zIndex(2)
            FormField(label: "Téléphone", text: binding(\.phone), maxLength: 20, keyboard: .phonePad, content: .telephoneNumber)
            if let error { FormError(error) }
            FormActions {
                PillButton("Annuler", variant: .ghost, fullWidth: true) { draft = nil }
                PillButton("Enregistrer", fullWidth: true) { submit() }
            }
        }
        .padding(.top, 16)
    }

    private func submit() {
        guard let draft else { return }
        switch reviewProfile(profile, draft) {
        case nil: error = "Vous n’avez rien modifié."
        case .failure(let problem)?: error = problem.message
        case .success(let body)?: error = nil; review = ProfileReview(body: body)
        }
    }
}

/// `.profile-form-actions` on a phone: one full-width button per row, all the same size.
struct FormActions<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View { VStack(spacing: 8) { content() } }
}

// MARK: Auto-renewal

/// auto-renewal.tsx: the switch shows only when Vélo’v offers it; success closes the sheet and the state shown is the one read back.
struct AutoRenewalSetting: View {
    let subscription: Subscription
    @Environment(AppModel.self) private var model
    @State private var asking = false
    @State private var pending = false
    @State private var failure: Outcome?
    /// Vélo’v's answer to the last change, shown until the account is read again.
    @State private var saved: AutoRenewalResult?

    private var actual: Bool? { saved.map(\.autoRenewal) ?? subscription.autoRenewal }
    private var canChange: Bool { saved?.autoRenewalAllowed ?? subscription.autoRenewalAllowed }
    private var next: Bool { !(actual ?? false) }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Renouvellement automatique").typo(.label(12)).foregroundStyle(Palette.inkSoft)
                Text(actual == nil ? "Indisponible pour le moment" : actual! ? "Activé" : "Désactivé").typo(.body(15, medium: true)).foregroundStyle(Palette.ink)
            }
            Spacer(minLength: 0)
            if canChange, subscription.id != nil, let actual {
                VelovSwitch(on: actual) { failure = nil; asking = true }
                    .accessibilityLabel("Renouvellement automatique").accessibilityValue(actual ? "Activé" : "Désactivé")
            }
        }
        .padding(.top, 20)
        .onChange(of: subscription) { saved = nil }
        .sheet(isPresented: $asking) { sheet }
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeading(title: next ? "Activer le renouvellement automatique ?" : "Désactiver le renouvellement automatique ?", closeDisabled: pending) { asking = false }
            if next {
                Text("Votre abonnement sera renouvelé et facturé à son échéance.")
                    .typo(.body(15)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
            }
            if let failure {
                VStack(alignment: .leading, spacing: 6) {
                    FormError(failure.message ?? "Vélo’v n’a pas enregistré le renouvellement automatique.")
                    RawStatus(outcome: failure)
                }
                .padding(.top, 14)
            }
            PairedActions {
                PillButton("Annuler", variant: .secondary, fullWidth: true) { asking = false }.disabled(pending)
                PillButton("Confirmer", pending: pending, fullWidth: true) { confirm() }
            }
            .padding(.top, 24)
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 20)
        .fitSheet()
        .interactiveDismissDisabled(pending)
    }

    private func confirm() {
        guard !pending, let id = subscription.id else { return }
        let next = next
        Haptics.confirm()
        pending = true
        failure = nil
        Task {
            let value: AutoRenewalResult
            do {
                value = try await model.service.setAutoRenewal(subscriptionId: id, autoRenewal: next)
            } catch {
                let outcome = await attempt { throw error }
                value = AutoRenewalResult(outcome: outcome, autoRenewal: nil, autoRenewalAllowed: false, verified: false)
            }
            Haptics.result(value.outcome.ok)
            pending = false
            guard value.outcome.ok else { failure = value.outcome; return }
            if value.verified, value.autoRenewal != nil { saved = value }
            asking = false
            Task { await model.loadDashboard() }
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
        .sheet(item: $file) { ShareSheet(url: $0.url).presentationDetents([.medium, .large]).sheetCorners() }
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
    default: "Dates inconnues"
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

/// contact-support.tsx: one multipart message after « Confirmer »; success clears and closes the form.
struct ContactSupport: View {
    let trips: [Trip]?
    @Environment(AppModel.self) private var model
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
        }
        .sheet(item: $draft) { draft in
            WriteDialog(title: "Envoyer au service client ?") {
                let outcome = await attempt { try await model.service.contactSupport(draft.body) }
                if outcome.ok { message = ""; tripId = "none"; open = false }
                return outcome
            }
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            SelectField(label: "Objet", value: $subject, options: subjects, layout: .stacked).zIndex(3)
            if !recent.isEmpty {
                SelectField(label: "Trajet (facultatif)", value: $tripId,
                            options: [.init(value: "none", label: "Aucun")] + recent.map { .init(value: $0.id, label: "\(formatDate($0.startedAt)) · \($0.startStation ?? "Trajet")") },
                            layout: .stacked).zIndex(2)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Message").typo(.label(12)).foregroundStyle(Palette.inkSoft)
                // `.field textarea`: the ring on the card radius; TextEditor's own inset brings the text to 18 × 12.
                TextEditor(text: $message).typo(.body(16)).frame(minHeight: 110).scrollContentBackground(.hidden)
                    .padding(.horizontal, 13).padding(.vertical, 4)
                    .ringed(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous))
                    .onChange(of: message) { _, value in if value.count > 1500 { message = String(value.prefix(1500)) } }
            }
            if let error { FormError(error) }
            FormActions {
                PillButton("Annuler", variant: .ghost, fullWidth: true) { open = false }
                PillButton("Envoyer", fullWidth: true) { review() }
            }
        }
    }

    private func review() {
        let body = contact
        guard body.isValid else {
            error = "Votre message est vide ou trop long."
            return
        }
        error = nil
        draft = ContactDraft(body: body)
    }
}
