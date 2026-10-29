import SwiftUI
import VelovCore

private let countries = ["FR": "France", "BE": "Belgique", "CH": "Suisse", "LU": "Luxembourg", "DE": "Allemagne", "ES": "Espagne", "IT": "Italie", "GB": "Royaume-Uni"]

/// dashboard.tsx `AccountPage`: profile and coordinates, subscription with receipts, customer service, logout.
struct AccountPage: View {
    let data: Dashboard
    let onLogout: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            profile
            subscription
            section("Service client") {
                ContactSupport(trips: data.trips).padding(.top, 16)
            }
            PillButton(variant: .outlineRed, height: 48, fullWidth: true, action: onLogout) {
                Icon(.signOut, .regular, size: 19)
                Text("Se déconnecter").typo(.label(13))
            }
            .padding(.top, 28)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).typo(.title(26)).foregroundStyle(Palette.ink)
            content()
        }
        .padding(.horizontal, 22).padding(.vertical, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous).fill(Palette.mist))
    }

    private var profile: some View {
        let person = data.profile
        let name = [person.firstName, person.lastName].filter { !$0.isEmpty }.joined(separator: " ")
        let address = [person.address, person.addressComplement].compactMap { $0 }.joined(separator: ", ")
        let place = [person.zipCode, person.city].compactMap { $0 }.joined(separator: " ")
        let country = person.country.map { "\(place.isEmpty ? "" : " · ")\(countries[$0] ?? $0)" } ?? ""
        return section("Profil") {
            Text(name.isEmpty ? "Compte Vélo’v" : name).typo(.title(22)).foregroundStyle(Palette.ink).padding(.top, 18)
            Text(person.email).typo(.body(14)).foregroundStyle(Palette.inkSoft).padding(.top, 6)
            // Only what needs attention: an active account, a complete profile and a valid card go without saying.
            if person.locked || !person.complete || data.paymentValid == false {
                VStack(spacing: 0) {
                    if person.locked { DetailRow("Compte", "À vérifier") }
                    if !person.complete { DetailRow("Profil", "À compléter") }
                    if data.paymentValid == false { DetailRow("Paiement", "À vérifier") }
                }
                .padding(.top, 26)
            }
            VStack(spacing: 0) {
                DetailRow(label: "Adresse") { StackedValue(value: address.isEmpty ? "Non renseignée" : address, small: place + country) }
                DetailRow("Téléphone", person.phoneNumber ?? "Non renseigné")
            }
            .padding(.top, 14)
            PillButton("Modifier mes coordonnées", variant: .secondary) {}.disabled(true).padding(.top, 16)
            SoonNote().padding(.top, 6)
        }
    }

    private var subscription: some View {
        let current = data.subscription.subscription
        return section("Abonnement") {
            Text(data.subscription == .unavailable ? Messages.missing : current?.title ?? "Aucun abonnement").typo(.title(22)).foregroundStyle(Palette.ink).padding(.top, 18)
            if let current {
                Text(current.validUntil.map { "Jusqu’au \(formatDate($0, .dayLongMonthYear))" } ?? (current.active ? "Actif" : "Inactif"))
                    .typo(.body(14)).foregroundStyle(Palette.inkSoft).padding(.top, 10)
                if current.type == "LT" {
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Renouvellement automatique").typo(.label(12)).foregroundStyle(Palette.inkSoft)
                            Text(current.autoRenewal.map { "\($0 ? "Activé" : "Désactivé") · bientôt disponible" } ?? Messages.soon).typo(.body(12)).foregroundStyle(Palette.inkSoft)
                        }
                        Spacer()
                        VelovSwitch(on: current.autoRenewal == true).disabled(true).accessibilityLabel("Renouvellement automatique (bientôt disponible)")
                    }
                    .padding(.top, 20)
                }
            }
            if let receipts = data.receipts, !receipts.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Télécharger le reçu").typo(.label(12)).foregroundStyle(Palette.inkSoft).padding(.bottom, 8)
                    ForEach(receipts) { receipt in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(receipt.title).typo(.body(14, medium: true)).foregroundStyle(Palette.ink)
                                Text(periodLabel(receipt)).typo(.body(12)).foregroundStyle(Palette.inkSoft)
                            }
                            Spacer()
                            PillButton(variant: .secondary, action: {}) { Icon(.downloadSimple, .light, size: 17); Text("Reçu") }.disabled(true)
                        }
                        .padding(.vertical, 12)
                        .overlay(alignment: .bottom) { Hairline(color: Palette.inkLine) }
                    }
                }
                .padding(.top, 24)
            }
            Button { if let url = URL(string: "https://velov.grandlyon.com/") { openURL(url) } } label: {
                HStack(spacing: 12) { Text("Gérer sur Vélo’v").typo(.label(13)); CircleArrow(external: true, style: .outline) }
                    .foregroundStyle(Palette.redDeep).frame(minHeight: 40)
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
        }
    }

    /// "Du 1 mars au 2 mars 2026": the period a receipt covers.
    private func periodLabel(_ receipt: Receipt) -> String {
        switch (receipt.start, receipt.end) {
        case let (start?, end?): "Du \(formatDate(start, .dayMonthYear)) au \(formatDate(end, .dayMonthYear))"
        case let (start?, nil): "Depuis le \(formatDate(start, .dayMonthYear))"
        case let (nil, end?): "Jusqu’au \(formatDate(end, .dayMonthYear))"
        default: "Période sans dates"
        }
    }
}

/// « Écrire au service client »: a form that opens the user's mail app (no Cyclocity call).
struct ContactSupport: View {
    let trips: [Trip]?
    @Environment(\.openURL) private var openURL
    @State private var open = false
    @State private var subject = "Un trajet passé"
    @State private var message = ""
    @State private var tripId = "none"

    private let subjects = ["Un trajet passé", "Mon abonnement", "Mes paiements", "Mon compte", "Autre demande"]

    var body: some View {
        let recent = Array((trips ?? []).filter { $0.token != nil }.prefix(15))
        if !open {
            PillButton(variant: .secondary, action: { open = true }) { Icon(.envelopeSimple, .light, size: 18); Text("Écrire au service client") }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                SelectField(label: "Objet", value: $subject, options: subjects.map { .init(value: $0, label: $0) }, background: Palette.white).zIndex(3)
                if !recent.isEmpty {
                    SelectField(label: "Trajet", value: $tripId, options: [.init(value: "none", label: "Aucun")] + recent.map { .init(value: $0.id, label: "\(formatDate($0.startedAt)) · \($0.startStation ?? "Trajet")") }, background: Palette.white).zIndex(2)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Message").typo(.label(12)).foregroundStyle(Palette.inkSoft)
                    TextEditor(text: $message).typo(.body(16)).frame(minHeight: 110).scrollContentBackground(.hidden)
                        .padding(6).background(RoundedRectangle(cornerRadius: 5.625).fill(Palette.white))
                        .overlay(RoundedRectangle(cornerRadius: 5.625).strokeBorder(Palette.fieldLine, lineWidth: 1))
                        .onChange(of: message) { _, value in if value.count > 1500 { message = String(value.prefix(1500)) } }
                }
                Text("Le message s’ouvre dans votre messagerie : l’envoi direct depuis l’app n’est pas encore disponible.").typo(.body(12)).foregroundStyle(Palette.inkSoft)
                VStack(spacing: 8) {
                    PillButton("Ouvrir la messagerie", fullWidth: true) { send(recent) }
                    PillButton("Annuler", variant: .ghost, fullWidth: true) { open = false }
                }
            }
        }
    }

    private func send(_ recent: [Trip]) {
        let trip = recent.first { $0.id == tripId }
        var line = ""
        if let trip, let token = trip.token {
            let route = trip.startStation.map { ", \($0)\(trip.endStation.map { " → \($0)" } ?? "")" } ?? ""
            line = "Trajet du \(formatDate(trip.startedAt, .dayLongMonthYearTime))\(route) — code \(token)"
        }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = Guesses.supportAddress
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject + (trip?.token.map { " \($0)" } ?? "")),
            URLQueryItem(name: "body", value: [message.trimmingCharacters(in: .whitespacesAndNewlines), line].filter { !$0.isEmpty }.joined(separator: "\n\n"))
        ]
        if let url = components.url { openURL(url) }
    }
}
