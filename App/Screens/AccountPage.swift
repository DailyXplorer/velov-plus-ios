import SwiftUI
import VelovCore

/// dashboard.tsx `AccountPage`: profile and coordinates, subscription with auto-renewal and receipts, customer service, logout.
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
            PillButton(height: 48, fullWidth: true, action: onLogout) {
                Icon(.signOut, .light, size: 19)
                Text("Se déconnecter").typo(.label(14))
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
        let name = formatName("\(person.firstName) \(person.lastName)")
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
            ProfileCoordinates(profile: person).padding(.top, 14)
        }
    }

    private var subscription: some View {
        let current = data.subscription.subscription
        return section("Abonnement") {
            Text(data.subscription == .unavailable ? Messages.missing : current?.title ?? "Aucun abonnement").typo(.title(22)).foregroundStyle(Palette.ink).padding(.top, 18)
            if let current {
                Text(current.validUntil.map { "Jusqu’au \(formatDate($0, .dayLongMonthYear))" } ?? (current.active ? "Actif" : "Inactif"))
                    .typo(.body(14)).foregroundStyle(Palette.inkSoft).padding(.top, 10)
                if current.type == "LT" { AutoRenewalSetting(subscription: current).id("\(current.id ?? ""):\(data.updatedAt.timeIntervalSince1970)") }
            }
            if let receipts = data.receipts, !receipts.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Reçus").typo(.label(13)).foregroundStyle(Palette.inkSoft).padding(.bottom, 8)
                    ForEach(receipts) { ReceiptRow(receipt: $0) }
                }
                .padding(.top, 24)
            }
            Button { if let url = URL(string: "https://velov.grandlyon.com/") { openURL(url) } } label: {
                HStack(spacing: 12) { Text("Gérer sur Vélo’v").typo(.label(14)); CircleArrow(external: true, style: .outline) }
                    .foregroundStyle(Palette.redDeep).frame(minHeight: 40)
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
        }
    }
}
