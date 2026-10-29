import SwiftUI
import VelovCore

struct AccountPage: View {
    let data: Dashboard
    let onLogout: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            profile
            subscription
            AccountSection(title: "Service client") {
                ContactSupport(trips: data.trips).padding(.top, 16)
            }
            LogoutButton(action: onLogout).padding(.top, 28)
        }
    }

    private var profile: some View {
        let person = data.profile
        let name = formatName("\(person.firstName) \(person.lastName)")
        return AccountSection(title: "Profil") {
            Text(name.isEmpty ? "Compte Vélo’v" : name).typo(.title(22)).foregroundStyle(Palette.ink).padding(.top, 18)
            Text(person.email).typo(.body(14)).foregroundStyle(Palette.inkSoft).padding(.top, 6)
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
        return AccountSection(title: "Abonnement") {
            Text(data.subscription == .unavailable ? Messages.missing : current?.title ?? "Aucun abonnement").typo(.title(22)).foregroundStyle(Palette.ink).padding(.top, 18)
            if let current {
                Text(current.validUntil.map { "Jusqu’au \(formatDate($0, .dayLongMonthYear))" } ?? (current.active ? "Actif" : "Inactif"))
                    .typo(.body(14)).foregroundStyle(Palette.inkSoft).padding(.top, 10)
                if current.type == "LT" { AutoRenewalSetting(subscription: current).id("\(current.id ?? ""):\(data.updatedAt.timeIntervalSince1970)") }
            }
            if let receipts = data.receipts, !receipts.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ReceiptsTitle()
                    ForEach(receipts) { ReceiptRow(receipt: $0) }
                }
                .padding(.top, 24)
            }
            ManageLink { if let url = URL(string: "https://velov.grandlyon.com/") { openURL(url) } }
        }
    }
}

struct AccountSection<Content: View>: View {
    let title: String
    var ghost = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).typo(.title(26)).foregroundStyle(Palette.ink)
            content()
        }
        .padding(.horizontal, 22).padding(.vertical, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous).fill(Palette.mist))
        .modifier(SectionGhost(on: ghost))
    }
}

private struct SectionGhost: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.skeleton() } else { content }
    }
}

private struct ReceiptsTitle: View {
    var body: some View { Text("Reçus").typo(.caps(13)).foregroundStyle(Palette.inkSoft).padding(.bottom, 8) }
}

private struct ManageLink: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) { Text("Gérer sur Vélo’v").typo(.caps(14)); CircleArrow(external: true, style: .outline) }
                .foregroundStyle(Palette.redDeep).frame(minHeight: 40)
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
    }
}

private struct LogoutButton: View {
    let action: () -> Void
    var body: some View {
        PillButton(height: 48, fullWidth: true, action: action) {
            Icon(.signOut, .light, size: 19)
            Text("Se déconnecter")
        }
    }
}

struct AccountSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AccountSection(title: "Profil", ghost: true) {
                Text(verbatim: "Prénom Nom").typo(.title(22)).padding(.top, 18)
                Text(verbatim: "prenom.nom@exemple.fr").typo(.body(14)).padding(.top, 6)
                VStack(alignment: .leading, spacing: 0) {
                    DetailRow(label: "Adresse") { StackedValue(value: "1 rue de la République", small: "69002 Lyon · France") }
                    DetailRow("Téléphone", "06 00 00 00 00", last: true)
                    PillButton("Modifier mes coordonnées", variant: .secondary) {}.padding(.top, 16)
                }
                .padding(.top, 14)
            }
            AccountSection(title: "Abonnement", ghost: true) {
                Text(verbatim: "Vélo’v Plus 1 an Jeunes – paiement comptant").typo(.title(22)).padding(.top, 18)
                Text(verbatim: "Jusqu’au 1 janvier 2027").typo(.body(14)).padding(.top, 10)
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Renouvellement automatique").typo(.caps(13))
                        Text("Désactivé").typo(.title(20))
                    }
                    Spacer(minLength: 0)
                    VelovSwitch(on: false)
                }
                .padding(.top, 20)
                VStack(alignment: .leading, spacing: 0) {
                    ReceiptsTitle()
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "Vélo’v Plus 1 an Jeunes").typo(.body(14, medium: true))
                            Text(verbatim: "Du 1 janv. 2026 au 1 janv. 2027").typo(.body(12))
                        }
                        Spacer()
                        PillButton(variant: .secondary, action: {}) { Icon(.downloadSimple, .light, size: 17); Text("Reçu") }
                    }
                    .padding(.vertical, 12)
                }
                .padding(.top, 24)
                ManageLink {}
            }
            AccountSection(title: "Service client", ghost: true) {
                PillButton(variant: .secondary, action: {}) { Icon(.envelopeSimple, .light, size: 18); Text("Écrire au service client") }.padding(.top, 16)
            }
            LogoutButton {}.skeleton(24).padding(.top, 28)
        }
        .accessibilityLabel("Chargement du compte")
    }
}
