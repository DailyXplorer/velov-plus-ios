import SwiftUI
import UIKit
import VelovCore

let countries: [SelectOption<String>] = [
    .init(value: "FR", label: "France"), .init(value: "BE", label: "Belgique"), .init(value: "CH", label: "Suisse"), .init(value: "LU", label: "Luxembourg"),
    .init(value: "DE", label: "Allemagne"), .init(value: "ES", label: "Espagne"), .init(value: "IT", label: "Italie"), .init(value: "GB", label: "Royaume-Uni")
]

func countryName(_ code: String?) -> String? { countries.first { $0.value == code }?.label ?? code }

enum ProfileField: Hashable { case firstName, lastName, address, complement, zipCode, city, phone }

struct ProfileReview: Identifiable {
    let body: ProfileBody
    let id = UUID()
}

struct ProfileCoordinates: View {
    let profile: Profile
    @Environment(AppModel.self) private var model

    var body: some View {
        let address = [profile.address, profile.addressComplement].compactMap { $0 }.joined(separator: ", ")
        let place = [profile.zipCode, profile.city].compactMap { $0 }.joined(separator: " ")
        let country = profile.country.map { "\(place.isEmpty ? "" : " · ")\(countryName($0) ?? $0)" } ?? ""
        VStack(alignment: .leading, spacing: 0) {
            DetailRow(label: "Adresse") { StackedValue(value: address.isEmpty ? "Non renseignée" : address, small: place + country) }
            DetailRow("Téléphone", profile.phoneNumber.map(formatPhone) ?? "Non renseigné", last: true)
            PillButton(variant: .secondary, action: { model.push(.profile, on: .account) }) { ButtonIcon(.pencil); Text("Modifier mes coordonnées") }
                .padding(.top, Space.titleToContent)
        }
    }
}

struct LeaveGuard: ViewModifier {
    let dirty: Bool
    var page = Page.account
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content
            .askingBeforeBack(dirty ? { [model, page] in model.leave(.back(page)) } : nil)
            .onChange(of: dirty, initial: true) { _, dirty in
                if dirty { model.unsaved = page } else if model.unsaved == page { model.unsaved = nil }
            }
            .onDisappear { if model.unsaved == page { model.unsaved = nil } }
    }
}

struct ProfilePage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProfileDraft?
    @State private var error: String?
    @State private var review: ProfileReview?
    @State private var saved = false
    @FocusState private var focus: ProfileField?

    private var profile: Profile? { model.dashboard?.profile }
    private var dirty: Bool { profile.flatMap { profile in draft.map { reviewProfile(profile, $0) != nil } } ?? false }

    var body: some View {
        PushedPage("Modifier mes coordonnées") {
            if let profile, draft != nil { form(profile) }
        }
        .modifier(LeaveGuard(dirty: dirty))
        .onChange(of: profile?.email, initial: true) { if draft == nil, let profile { draft = ProfileDraft(profile) } }
        .sheet(item: $review, onDismiss: { if saved { dismiss() } }) { review in
            WriteDialog(title: "Enregistrer les modifications\u{a0}?", key: OperationKey.profile, intent: profileIntent(review.body), run: {
                let outcome = await attempt { try await model.service.updateProfile(review.body) }
                if outcome.ok { done() }
                return outcome
            }, check: { intent in
                profileCheck(intent, after: try await model.service.dashboard().profile)
            }, verified: { _ in done() })
        }
    }

    private func done() {
        saved = true
        if let profile { draft = ProfileDraft(profile) }
        Task { await model.loadDashboard() }
    }

    private func form(_ profile: Profile) -> some View {
        let binding = { (key: WritableKeyPath<ProfileDraft, String>) in
            Binding<String>(get: { draft?[keyPath: key] ?? "" }, set: { draft?[keyPath: key] = $0 })
        }
        let country = draft?.country ?? "FR"
        return VStack(alignment: .leading, spacing: Space.field) {
            FormField(label: "Prénom", text: binding(\.firstName), maxLength: Rules.nameMax, content: .givenName, focus: $focus, field: .firstName, next: .lastName)
            FormField(label: "Nom", text: binding(\.lastName), maxLength: Rules.nameMax, content: .familyName, focus: $focus, field: .lastName, next: .address)
            FormField(label: "Adresse", text: binding(\.address), maxLength: Rules.addressMax, content: .streetAddressLine1, focus: $focus, field: .address, next: .complement)
            FormField(label: "Complément", text: binding(\.complement), maxLength: Rules.addressMax, content: .streetAddressLine2, focus: $focus, field: .complement, next: .zipCode)
            HStack(alignment: .top, spacing: Space.cards) {
                FormField(label: "Code postal", text: binding(\.zipCode), maxLength: 10, keyboard: .numbersAndPunctuation, content: .postalCode, focus: $focus, field: .zipCode, next: .city).frame(width: 110)
                FormField(label: "Ville", text: binding(\.city), maxLength: 60, content: .addressCity, focus: $focus, field: .city, next: .phone)
            }
            SelectField(label: "Pays", value: binding(\.country),
                        options: countries.contains { $0.value == country } ? countries : countries + [.init(value: country, label: country)],
                        layout: .stacked, autoOpen: model.snapshot == .choiceSheet)
            FormField(label: "Téléphone", text: binding(\.phone), maxLength: 20, keyboard: .phonePad, content: .telephoneNumber, focus: $focus, field: .phone)
            if let error { FormError(error) }
            PairedActions {
                PillButton("Annuler", variant: .ghost, fullWidth: true) { model.leave(.back(.account)) }
                PillButton("Enregistrer", fullWidth: true) { submit(profile) }
            }
            .padding(.top, Space.actions - Space.field)
        }
    }

    private func submit(_ profile: Profile) {
        guard let draft else { return }
        switch reviewProfile(profile, draft) {
        case nil: error = "Vous n’avez rien modifié."
        case .failure(let problem)?: error = problem.message
        case .success(let body)?: error = nil; review = ProfileReview(body: body)
        }
    }
}

struct AutoRenewalSetting: View {
    let subscription: Subscription
    @Environment(AppModel.self) private var model
    @State private var asking = false
    @State private var saved: AutoRenewalResult?

    private var actual: Bool? { renewalShown(subscription, after: saved).value }
    private var canChange: Bool { renewalShown(subscription, after: saved).canChange }
    private var next: Bool { !(actual ?? false) }

    var body: some View {
        SettingRow(label: "Renouvellement automatique", value: actual == nil ? "Indisponible pour le moment" : actual! ? "Activé" : "Désactivé", surface: false) {
            if canChange, subscription.id != nil, let actual {
                ConfirmToggle(label: "Renouvellement automatique", on: actual) { asking = true }
            }
        }
        .padding(.top, Space.card)
        .onChange(of: subscription) { saved = nil }
        .sheet(isPresented: $asking) { dialog }
        .task {
            guard model.snapshot == .renewalDialog else { return }
            try? await Task.sleep(for: .seconds(1.5))
            asking = true
        }
    }

    @ViewBuilder
    private var dialog: some View {
        if let id = subscription.id {
            let next = model.operations.get(OperationKey.autoRenewal(id)).flatMap { Intent.wanted($0.meta) } ?? self.next
            WriteDialog(title: next ? "Activer le renouvellement automatique\u{a0}?" : "Désactiver le renouvellement automatique\u{a0}?", key: OperationKey.autoRenewal(id), intent: Intent.wanted(next), run: {
                let value: AutoRenewalResult
                do {
                    value = try await model.service.setAutoRenewal(subscriptionId: id, autoRenewal: next)
                } catch {
                    let outcome = await attempt { throw error }
                    value = AutoRenewalResult(outcome: outcome, autoRenewal: nil, autoRenewalAllowed: false, verified: false)
                }
                if value.outcome.ok {
                    saved = value
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
    @State private var file: URL?

    var body: some View {
        HStack(spacing: Space.cards) {
            VStack(alignment: .leading, spacing: Space.pair) {
                Text(receipt.title).typo(.body(.base, medium: true)).foregroundStyle(Palette.ink)
                Text(periodLabel(receipt)).typo(.body(.meta)).foregroundStyle(Palette.inkSoft)
            }
            Spacer()
            if let file {
                ShareLink(item: file) { PillLabel(variant: .secondary) { ButtonIcon(.share); Text("Partager") } }
                    .buttonStyle(.press)
                    .accessibilityLabel("Partager le reçu, \(periodLabel(receipt))")
            } else {
                PillButton(variant: .secondary, pending: pending, action: download) { ButtonIcon(.downloadSimple); Text("Reçu") }
                    .accessibilityLabel("Télécharger le reçu, \(periodLabel(receipt))")
            }
        }
        .padding(.vertical, Space.cards)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func download() {
        guard !pending else { return }
        pending = true
        Task {
            defer { pending = false }
            var pdf: Data?, name: String?
            let outcome = await attempt {
                let answer = try await model.service.receipt(subscriptionId: receipt.subscriptionId, periodId: receipt.periodId)
                (pdf, name) = (answer.pdf, answer.filename)
                return answer.outcome
            }
            guard outcome.ok, let pdf else { return model.showToast(outcome.message ?? "Le reçu n’a pas pu être téléchargé.") }
            let url = FileManager.default.temporaryDirectory.appending(path: name ?? "recu-velov.pdf")
            do {
                try pdf.write(to: url, options: .atomic)
                file = url
            } catch {
                model.showToast("Le reçu n’a pas pu être enregistré sur ce téléphone.")
            }
        }
    }
}

func periodLabel(_ receipt: Receipt) -> String {
    func day(_ date: Date) -> String { formatDate(date, .dayMonthYear).replacingOccurrences(of: " ", with: "\u{a0}") }
    return switch (receipt.start, receipt.end) {
    case let (start?, end?): "Du \(day(start)) au \(day(end))"
    case let (start?, nil): "Depuis le \(day(start))"
    case let (nil, end?): "Jusqu’au \(day(end))"
    default: "Dates inconnues"
    }
}

private let subjects: [SelectOption<String>] = zip(Guesses.mailComplaintTypes, ["Un trajet", "Mon abonnement", "Mes paiements", "Un parking"]).map { .init(value: $0, label: $1) }

private struct ContactDialog: View {
    let draft: ContactBody?
    let sent: () -> Void
    let writeAgain: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        WriteDialog(title: "Envoyer au service client\u{a0}?", key: model.operations.digest.map(OperationKey.contact), ready: draft != nil, run: { [draft] in
            guard let draft else { return Outcome.refusal("local.empty", "Votre message est vide ou trop long.") }
            let outcome = await attempt { try await model.service.contactSupport(draft) }
            if outcome.ok { sent() }
            return outcome
        }, restart: Restart(title: "Écrire un nouveau message", note: "Votre premier message est peut-être déjà arrivé.", action: writeAgain))
    }
}

struct ContactSupport: View {
    @Environment(AppModel.self) private var model
    @State private var asking = false
    @State private var trip: TripRoute?

    private var operationKey: String? { model.operations.digest.map(OperationKey.contact) }

    var body: some View {
        PillButton(variant: .secondary, action: { start(nil) }) { ButtonIcon(.envelopeSimple); Text("Écrire au service client") }
            .onChange(of: model.contactRequest, initial: true) { _, request in
                guard let request else { return }
                model.contactRequest = nil
                start(request.trip)
            }
            .sheet(isPresented: $asking) {
                ContactDialog(draft: nil, sent: {}, writeAgain: writeAgain)
            }
    }

    private func start(_ trip: TripRoute?) {
        self.trip = trip
        if operationKey.flatMap({ model.operations.get($0) }) != nil { asking = true } else { model.push(.contact(trip), on: .account) }
    }

    private func writeAgain() {
        if let operationKey { model.operations.clear(operationKey) }
        asking = false
        model.push(.contact(trip), on: .account)
    }
}

struct ContactPage: View {
    let preset: Trip?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var subject = Guesses.mailComplaintTypes[0]
    @State private var message = ""
    @State private var tripId: String
    @State private var error: String?
    @State private var draft: ContactBody?
    @State private var asking = false
    @State private var sent = false

    init(preset: Trip?) {
        self.preset = preset?.token == nil ? nil : preset
        _tripId = State(initialValue: self.preset?.id ?? "none")
    }

    private var recent: [Trip] {
        let latest = Array((model.dashboard?.trips ?? []).filter { $0.token != nil }.prefix(15))
        guard let preset, !latest.contains(where: { $0.id == preset.id }) else { return latest }
        return [preset] + latest
    }
    private var contact: ContactBody { ContactBody(complaintType: subject, message: message, tripToken: recent.first { $0.id == tripId }?.token) }
    private var operationKey: String? { model.operations.digest.map(OperationKey.contact) }
    private var dirty: Bool { !message.isEmpty || (tripId != "none" && tripId != preset?.id) || subject != Guesses.mailComplaintTypes[0] }

    var body: some View {
        PushedPage("Écrire au service client") { form }
            .modifier(LeaveGuard(dirty: dirty))
            .task {
                guard model.snapshot == .contactUncertain else { return }
                try? await Task.sleep(for: .seconds(1.5))
                message = "Bonjour, mon dernier trajet n’apparaît pas dans mon historique."
                review()
            }
            .sheet(isPresented: $asking, onDismiss: {
                draft = nil
                if sent { dismiss() }
            }) {
                ContactDialog(draft: draft, sent: {
                    message = ""; tripId = "none"; subject = Guesses.mailComplaintTypes[0]; draft = nil; sent = true
                }, writeAgain: writeAgain)
            }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: Space.field) {
            SelectField(label: "Objet", value: $subject, options: subjects, layout: .stacked)
            if !recent.isEmpty {
                SelectField(label: "Trajet (facultatif)", value: $tripId,
                            options: [.init(value: "none", label: "Aucun")] + recent.map { .init(value: $0.id, label: "\(formatDate($0.startedAt)) · \($0.startStation ?? "Trajet")") },
                            layout: .stacked)
            }
            VStack(alignment: .leading, spacing: Space.label) {
                Text("Message").typo(.caps(.label)).foregroundStyle(Palette.inkSoft)
                TextEditor(text: $message).typo(.body(.input)).frame(minHeight: 110).scrollContentBackground(.hidden)
                    .padding(.horizontal, 13).padding(.vertical, 4)
                    .ringed(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .accessibilityLabel("Message")
                    .onChange(of: message) { _, value in
                        guard value.utf16.count > 1500 else { return }
                        var cut = value
                        while cut.utf16.count > 1500 { cut.removeLast() }
                        message = cut
                    }
            }
            if let error { FormError(error) }
            PairedActions {
                PillButton("Annuler", variant: .ghost, fullWidth: true) { model.leave(.back(.account)) }
                PillButton(variant: .primary, fullWidth: true, action: review) { ButtonIcon(.send); Text("Envoyer") }
            }
            .padding(.top, Space.actions - Space.field)
        }
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
    }
}
