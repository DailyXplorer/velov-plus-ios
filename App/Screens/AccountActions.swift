import SwiftUI
import UIKit
import VelovCore

let countries: [SelectOption<String>] = [
    .init(value: "FR", label: "France"), .init(value: "BE", label: "Belgique"), .init(value: "CH", label: "Suisse"), .init(value: "LU", label: "Luxembourg"),
    .init(value: "DE", label: "Allemagne"), .init(value: "ES", label: "Espagne"), .init(value: "IT", label: "Italie"), .init(value: "GB", label: "Royaume-Uni")
]

func countryName(_ code: String?) -> String? { countries.first { $0.value == code }?.label ?? code }

struct ProfileReview: Identifiable {
    let body: ProfileBody
    let id = UUID()
}

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
            WriteDialog(title: "Enregistrer les modifications ?", key: OperationKey.profile, intent: profileIntent(review.body), run: {
                let outcome = await attempt { try await model.service.updateProfile(review.body) }
                if outcome.ok { saved() }
                return outcome
            }, check: { intent in
                profileCheck(intent, after: try await model.service.dashboard().profile)
            }, verified: { _ in saved() })
        }
    }

    private func saved() {
        draft = nil
        Task { await model.loadDashboard() }
    }

    private var summary: some View {
        let address = [profile.address, profile.addressComplement].compactMap { $0 }.joined(separator: ", ")
        let place = [profile.zipCode, profile.city].compactMap { $0 }.joined(separator: " ")
        let country = profile.country.map { "\(place.isEmpty ? "" : " · ")\(countryName($0) ?? $0)" } ?? ""
        return VStack(alignment: .leading, spacing: 0) {
            DetailRow(label: "Adresse") { StackedValue(value: address.isEmpty ? "Non renseignée" : address, small: place + country) }
            DetailRow("Téléphone", profile.phoneNumber.map(formatPhone) ?? "Non renseigné", last: true)
            PillButton("Modifier mes coordonnées", variant: .secondary) { error = nil; draft = ProfileDraft(profile) }.padding(.top, 16)
        }
    }

    private var form: some View {
        let binding = { (key: WritableKeyPath<ProfileDraft, String>) in
            Binding<String>(get: { draft?[keyPath: key] ?? "" }, set: { draft?[keyPath: key] = $0 })
        }
        let country = draft?.country ?? "FR"
        return VStack(alignment: .leading, spacing: 14) {
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

struct FormActions<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View { VStack(spacing: 8) { content() } }
}

struct AutoRenewalSetting: View {
    let subscription: Subscription
    @Environment(AppModel.self) private var model
    @State private var asking = false
    @State private var saved: AutoRenewalResult?

    private var actual: Bool? { saved.map(\.autoRenewal) ?? subscription.autoRenewal }
    private var canChange: Bool { saved?.autoRenewalAllowed ?? subscription.autoRenewalAllowed }
    private var next: Bool { !(actual ?? false) }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Renouvellement automatique").typo(.caps(.label)).foregroundStyle(Palette.inkSoft)
                Text(actual == nil ? "Indisponible pour le moment" : actual! ? "Activé" : "Désactivé").typo(.title(.card)).foregroundStyle(Palette.ink)
            }
            Spacer(minLength: 0)
            if canChange, subscription.id != nil, let actual {
                VelovSwitch(on: actual) { asking = true }
                    .accessibilityLabel("Renouvellement automatique").accessibilityValue(actual ? "Activé" : "Désactivé")
            }
        }
        .padding(.top, 20)
        .onChange(of: subscription) { saved = nil }
        .sheet(isPresented: $asking) { dialog }
    }

    @ViewBuilder
    private var dialog: some View {
        if let id = subscription.id {
            let next = model.operations.get(OperationKey.autoRenewal(id)).flatMap { Intent.wanted($0.meta) } ?? self.next
            WriteDialog(title: next ? "Activer le renouvellement automatique ?" : "Désactiver le renouvellement automatique ?", key: OperationKey.autoRenewal(id), intent: Intent.wanted(next), run: {
                let value: AutoRenewalResult
                do {
                    value = try await model.service.setAutoRenewal(subscriptionId: id, autoRenewal: next)
                } catch {
                    let outcome = await attempt { throw error }
                    value = AutoRenewalResult(outcome: outcome, autoRenewal: nil, autoRenewalAllowed: false, verified: false)
                }
                if value.outcome.ok {
                    if value.verified, value.autoRenewal != nil { saved = value }
                    Task { await model.loadDashboard() }
                }
                return value.outcome
            }, check: { intent in
                renewalCheck(try await model.service.dashboard(), subscriptionId: id, wanted: Intent.wanted(intent) ?? next)
            }, verified: { _ in
                Task { await model.loadDashboard() }
            }) {
                if next { Text("Votre abonnement sera renouvelé et facturé à son échéance.").fixedSize(horizontal: false, vertical: true) }
            }
        }
    }
}

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
                    Text(receipt.title).typo(.body(.base, medium: true)).foregroundStyle(Palette.ink)
                    Text(periodLabel(receipt)).typo(.body(.meta)).foregroundStyle(Palette.inkSoft)
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
        .overlay(alignment: .bottom) { Hairline() }
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
    let items: [Any]
    init(url: URL) { items = [url] }
    init(items: [Any]) { self.items = items }
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private let subjects: [SelectOption<String>] = zip(Guesses.mailComplaintTypes, ["Un trajet", "Mon abonnement", "Mes paiements", "Un parking"]).map { .init(value: $0, label: $1) }

struct ContactSupport: View {
    let trips: [Trip]?
    @Environment(AppModel.self) private var model
    @State private var open = false
    @State private var subject = Guesses.mailComplaintTypes[0]
    @State private var message = ""
    @State private var tripId = "none"
    @State private var error: String?
    @State private var draft: ContactBody?
    @State private var asking = false

    private var recent: [Trip] { Array((trips ?? []).filter { $0.token != nil }.prefix(15)) }
    private var contact: ContactBody { ContactBody(complaintType: subject, message: message, tripToken: recent.first { $0.id == tripId }?.token) }
    private var operationKey: String? { model.operations.digest.map(OperationKey.contact) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !open {
                PillButton(variant: .secondary, action: start) { Icon(.envelopeSimple, .light, size: 18); Text("Écrire au service client") }
            } else {
                form
            }
        }
        .onChange(of: model.contactRequested, initial: true) { _, requested in
            guard requested else { return }
            model.contactRequested = false
            start()
        }
        .sheet(isPresented: $asking, onDismiss: { draft = nil }) {
            WriteDialog(title: "Envoyer au service client ?", key: operationKey, ready: draft != nil, run: { [draft] in
                guard let draft else { return Outcome.refusal("local.empty", "Votre message est vide ou trop long.") }
                let outcome = await attempt { try await model.service.contactSupport(draft) }
                if outcome.ok { message = ""; tripId = "none"; open = false; self.draft = nil }
                return outcome
            }, restart: Restart(title: "Écrire un nouveau message", action: writeAgain))
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
                Text("Message").typo(.caps(.label)).foregroundStyle(Palette.inkSoft)
                TextEditor(text: $message).typo(.body(.input)).frame(minHeight: 110).scrollContentBackground(.hidden)
                    .padding(.horizontal, 13).padding(.vertical, 4)
                    .ringed(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous))
                    .accessibilityLabel("Message")
                    .onChange(of: message) { _, value in
                        guard value.utf16.count > 1500 else { return }
                        var cut = value
                        while cut.utf16.count > 1500 { cut.removeLast() }
                        message = cut
                    }
            }
            if let error { FormError(error) }
            FormActions {
                PillButton("Annuler", variant: .ghost, fullWidth: true) { open = false }
                PillButton("Envoyer", fullWidth: true) { review() }
            }
        }
    }

    private func start() {
        if operationKey.flatMap({ model.operations.get($0) }) != nil { asking = true } else { open = true }
    }

    private func review() {
        let body = contact
        guard body.isValid else {
            error = "Votre message est vide ou trop long."
            return
        }
        error = nil
        draft = body
        asking = true
    }

    private func writeAgain() {
        if let operationKey { model.operations.clear(operationKey) }
        message = ""
        tripId = "none"
        draft = nil
        asking = false
        open = true
    }
}
