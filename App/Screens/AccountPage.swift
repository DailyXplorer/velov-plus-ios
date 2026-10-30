import SwiftUI
import VelovCore

struct AccountPage: View {
    let data: Dashboard
    let onLogout: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: Space.cards) {
            profile
            subscription
            AccountSection(title: "Service client") {
                ContactSupport().padding(.top, Space.titleToContent)
            }
            AccountSection(title: "Journal technique") {
                JournalLink().padding(.top, Space.titleToContent)
            }
            LogoutButton(action: onLogout).padding(.top, Space.section - Space.cards)
        }
    }

    private var profile: some View {
        let person = data.profile
        let name = formatName("\(person.firstName) \(person.lastName)")
        return AccountSection(title: "Profil") {
            Text(name.isEmpty ? "Compte Vélo’v" : name).typo(.title(.card)).foregroundStyle(Palette.ink).padding(.top, 18)
            Text(person.email).typo(.body(.base)).foregroundStyle(Palette.inkSoft).padding(.top, 6)
            if person.locked || !person.complete || data.paymentValid == false {
                VStack(spacing: 0) {
                    if person.locked { DetailRow("Compte", "À vérifier") }
                    if !person.complete { DetailRow("Profil", "À compléter") }
                    if data.paymentValid == false { DetailRow("Paiement", "À vérifier") }
                }
                .padding(.top, 26)
            }
            ProfileCoordinates(profile: person).padding(.top, Space.label)
        }
    }

    private var subscription: some View {
        let current = data.subscription.subscription
        return AccountSection(title: "Abonnement") {
            Text(data.subscription == .unavailable ? Messages.missing : current?.title ?? "Aucun abonnement").typo(.title(.card)).foregroundStyle(Palette.ink).padding(.top, 18)
            if let current {
                if let line = current.validUntil.map({ "Jusqu’au \(formatDate($0, .dayLongMonthYear))" }) ?? (current.active ? nil : "Inactif") {
                    Text(line).typo(.body(.base)).foregroundStyle(Palette.inkSoft).padding(.top, Space.label)
                }
                if current.type == "LT" { AutoRenewalSetting(subscription: current).id(current.id ?? "") }
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
            Text(title).typo(.title(.section)).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            content()
        }
        .padding(.vertical, Space.actions - Space.card)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(.mist)
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
    var body: some View { Text("Reçus").typo(.caps(.label)).foregroundStyle(Palette.inkSoft).padding(.bottom, 8) }
}

private struct ManageLink: View {
    let action: () -> Void
    var body: some View {
        TextLink(title: "Gérer sur Vélo’v", trailing: .external, hint: "Ouvre le site Vélo’v", action: action).padding(.top, 16)
    }
}

private struct LogoutButton: View {
    let action: () -> Void
    var body: some View {
        PillButton(variant: .destructive, large: true, fullWidth: true, action: action) {
            ButtonIcon(.signOut)
            Text("Se déconnecter")
        }
    }
}

struct AccountSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.cards) {
            AccountSection(title: "Profil", ghost: true) {
                Text(verbatim: "Prénom Nom").typo(.title(.card)).padding(.top, 18)
                Text(verbatim: "prenom.nom@exemple.fr").typo(.body(.base)).padding(.top, 6)
                VStack(alignment: .leading, spacing: 0) {
                    DetailRow(label: "Adresse") { StackedValue(value: "1 rue de la République", small: "69002 Lyon · France") }
                    DetailRow("Téléphone", "06 00 00 00 00", last: true)
                    PillButton(variant: .secondary, action: {}) { ButtonIcon(.pencil); Text("Modifier mes coordonnées") }.padding(.top, Space.titleToContent)
                }
                .padding(.top, Space.label)
            }
            AccountSection(title: "Abonnement", ghost: true) {
                Text(verbatim: "Vélo’v Plus 1 an Jeunes – paiement comptant").typo(.title(.card)).padding(.top, 18)
                Text(verbatim: "Jusqu’au 1 janvier 2027").typo(.body(.base)).padding(.top, 10)
                SettingRow(label: "Renouvellement automatique", value: "Désactivé", surface: false) {
                    ConfirmToggle(label: "Renouvellement automatique", on: false) {}
                }
                .padding(.top, 20)
                VStack(alignment: .leading, spacing: 0) {
                    ReceiptsTitle()
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: "Vélo’v Plus 1 an Jeunes").typo(.body(.base, medium: true))
                            Text(verbatim: "Du 1 janv. 2026 au 1 janv. 2027").typo(.body(.meta))
                        }
                        Spacer()
                        PillButton(variant: .secondary, action: {}) { ButtonIcon(.downloadSimple); Text("Reçu") }
                    }
                    .padding(.vertical, 12)
                }
                .padding(.top, 24)
                ManageLink {}
            }
            AccountSection(title: "Service client", ghost: true) {
                PillButton(variant: .secondary, action: {}) { ButtonIcon(.envelopeSimple); Text("Écrire au service client") }.padding(.top, Space.titleToContent)
            }
            AccountSection(title: "Journal technique", ghost: true) {
                VStack(alignment: .leading, spacing: Space.titleToContent) {
                    Text("Les \(TechnicalJournal.capacity) dernières requêtes envoyées à Vélo’v, sans jeton ni donnée personnelle.").typo(.body(.base))
                    PillButton(variant: .secondary, action: {}) { ButtonIcon(.file); Text("Ouvrir le journal") }
                }
                .padding(.top, Space.titleToContent)
            }
            LogoutButton {}.skeleton(Layout.largeControl / 2).padding(.top, Space.section - Space.cards)
        }
        .accessibilityLabel("Chargement du compte")
    }
}
