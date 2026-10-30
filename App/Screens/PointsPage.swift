import SwiftUI
import VelovCore

private func rewardLabel(_ label: String) -> String { label == "Vélo évalué" ? "Évaluation" : label }

struct PointsPage: View {
    let data: Dashboard
    @State private var limit = 8

    var body: some View {
        let rewards = data.rewards
        let rules = Array(rewards.rules.filter { $0.kind == .earn }.prefix(3))
        let invite = rewards.rules.first { $0.name == "PROMOCODE" }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Space.cards) {
                PointsFigure(icon: .starFour, label: "Solde actuel", value: rewards.balance.map { formatNumber($0) } ?? "—")
                PointsFigure(icon: .trendUp, label: "Total gagné", value: rewards.total.map { formatNumber($0) } ?? "—")
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, Space.cards)
            AutoSpendSetting(value: rewards.autoSpend)
            InviteFriend(cost: invite.map { Int($0.points) }, balance: rewards.balance.map { Int($0) }, account: data.profile.email)
                .id(data.profile.email)
                .padding(.top, Space.cards)
            if !rules.isEmpty {
                SectionHeading("Gagner des points").padding(.top, Space.section)
                VStack(spacing: Space.group) {
                    ForEach(rules, id: \.name) { rule in
                        EarnRule(label: rule.label == "Vélo évalué" ? "Évaluation d’un vélo après un trajet" : rule.label, points: "+\(formatNumber(rule.points))")
                    }
                }
            }
            SectionHeading("Historique").padding(.top, Space.section)
            VStack(spacing: 0) {
                ForEach(rewards.movements.prefix(limit)) { movement in
                    MovementRow(label: rewardLabel(movement.label), date: formatDate(movement.date, .dayLongMonthYear),
                                amount: "\(movement.amount > 0 ? "+" : "")\(formatNumber(movement.amount))", credit: movement.amount > 0)
                    Hairline()
                }
                if rewards.movements.isEmpty { StateView("Aucun mouvement de points.") }
                if rewards.movements.count > limit {
                    PillButton("Voir plus", variant: .secondary) { limit += 12 }.frame(maxWidth: .infinity).padding(.vertical, 24)
                }
            }
        }
    }

}

struct PointsFigure: View {
    let icon: IconName
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow(icon: icon, text: label, surface: .mist)
            Text(value.glyphic).typo(.title(.figure)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .card(.mist, compact: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value == "—" ? "indisponible" : "\(value) points")")
    }
}

private let ghostRules = ["Départ d’une station pleine", "Arrivée dans une station vide", "Évaluation d’un vélo après un trajet"]
private let ghostMovements = ["Bonus de trajet", "Évaluation", "Arrivée dans une station vide", "Réduction sur un trajet"]

struct PointsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Space.cards) {
                PointsFigure(icon: .starFour, label: "Solde actuel", value: "0").skeleton()
                PointsFigure(icon: .trendUp, label: "Total gagné", value: "0").skeleton()
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, Space.cards)
            SettingRow(label: "Utilisation automatique", value: "Activée") { ConfirmToggle(label: "Utilisation automatique", on: true) {} }.skeleton()
            VStack(alignment: .leading, spacing: Space.label) {
                Text("Inviter un ami").typo(.caps(.label))
                Text("Échangez vos points contre un code à offrir à un ami.").typo(.body(.small))
                PillButton(variant: .secondary, action: {}) { ButtonIcon(.ticket); Text("Obtenir un code") }.padding(.top, Space.label)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(.mist)
            .skeleton()
            .padding(.top, Space.cards)
            SectionHeading("Gagner des points").padding(.top, Space.section)
            VStack(spacing: Space.group) {
                ForEach(ghostRules, id: \.self) { EarnRule(label: $0, points: "+5").skeleton() }
            }
            SectionHeading("Historique").padding(.top, Space.section)
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { index in
                    MovementRow(label: ghostMovements[index % ghostMovements.count], date: "12 octobre 2026", amount: "+5", credit: false, ghost: true)
                    Hairline()
                }
                PillButton("Voir plus", variant: .secondary) {}.skeleton(Layout.control / 2).frame(maxWidth: .infinity).padding(.vertical, 24)
            }
        }
        .accessibilityLabel("Chargement des points")
    }
}

struct SettingRow<Control: View>: View {
    let label: String
    let value: String
    var surface = true
    @ViewBuilder let control: () -> Control

    var body: some View {
        let row = HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: Space.label) {
                Text(label).typo(.caps(.label)).foregroundStyle(Palette.inkSoft)
                Text(value).typo(.title(.card)).foregroundStyle(Palette.ink)
            }
            Spacer(minLength: 0)
            control()
        }
        if surface { row.card(.mist) } else { row }
    }
}

struct EarnRule: View {
    let label: String
    let points: String
    var body: some View {
        HStack(spacing: 16) {
            Text(label).typo(.body(.small)).foregroundStyle(Palette.inkSoft)
            Spacer()
            Text(verbatim: points.glyphic).typo(.title(.section)).foregroundStyle(Palette.ink)
        }
        .frame(minHeight: 64 - 2 * Space.card)
        .card(.mist)
        .accessibilityElement(children: .combine)
    }
}

struct MovementRow: View {
    let label: String
    let date: String
    let amount: String
    let credit: Bool
    var ghost = false
    var body: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).typo(.body(.small, medium: true)).foregroundStyle(Palette.ink).ghost(ghost)
                Text(date).typo(.body(.micro)).foregroundStyle(Palette.inkSoft).ghost(ghost)
            }
            Spacer()
            Text(verbatim: amount).typo(.body(.lead, medium: true)).foregroundStyle(Palette.ink).ghost(ghost)
        }
        .padding(.vertical, Space.row).frame(minHeight: 76)
        .accessibilityElement(children: .combine)
    }
}

struct AutoSpendSetting: View {
    let value: Bool?
    @Environment(AppModel.self) private var model
    @State private var asking = false
    @State private var next = false

    var body: some View {
        SettingRow(label: "Utilisation automatique", value: value == nil ? Messages.missing : value! ? "Activée" : "Désactivée") {
            if let value {
                ConfirmToggle(label: "Utilisation automatique des points", on: value) { next = !value; asking = true }
            }
        }
        .task {
            guard model.snapshot == .toggleDialog, let value else { return }
            try? await Task.sleep(for: .seconds(1))
            next = !value
            asking = true
        }
        .sheet(isPresented: $asking) {
            let next = model.operations.get(OperationKey.autoSpend).flatMap { Intent.wanted($0.meta) } ?? self.next
            WriteDialog(title: next ? "Activer l’utilisation automatique ?" : "Désactiver l’utilisation automatique ?", key: OperationKey.autoSpend, intent: Intent.wanted(next), run: {
                var answered: Bool?
                let outcome = await attempt {
                    let result = try await model.service.setAutoSpend(next)
                    answered = result.autoSpend
                    return result.outcome
                }
                if outcome.ok { model.setAutoSpend(answered ?? next) }
                return outcome
            }, check: { intent in
                autoSpendCheck(try await model.service.dashboard(), Intent.wanted(intent) ?? next)
            }, verified: { intent in
                model.setAutoSpend(Intent.wanted(intent) ?? next)
            }) {
                Text(next ? "Vos points régleront automatiquement les minutes au-delà de la période gratuite."
                          : "Vos points ne régleront plus les minutes au-delà de la période gratuite.")
            }
        }
    }
}
