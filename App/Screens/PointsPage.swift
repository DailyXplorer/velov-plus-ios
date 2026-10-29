import SwiftUI
import VelovCore

private func rewardLabel(_ label: String) -> String { label == "Vélo évalué" ? "Évaluation" : label }

/// dashboard.tsx `PointsPage`: balance, total, the auto-spend setting, the invite offer, how to earn and the history.
struct PointsPage: View {
    let data: Dashboard
    @State private var limit = 8

    var body: some View {
        let rewards = data.rewards
        let rules = Array(rewards.rules.filter { $0.kind == .earn }.prefix(3))
        let invite = rewards.rules.first { $0.name == "PROMOCODE" }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                figure(.starFour, "Solde actuel", rewards.balance.map { formatNumber($0) } ?? "—")
                figure(.trendUp, "Total gagné", rewards.total.map { formatNumber($0) } ?? "—")
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 16)
            AutoSpendSetting(value: rewards.autoSpend)
            InviteFriend(cost: invite.map { Int($0.points) }, balance: rewards.balance.map { Int($0) }, account: data.profile.email)
                .id(data.profile.email)
                .padding(.top, 12)
            if !rules.isEmpty {
                SectionHeading("Gagner des points").padding(.top, 40)
                VStack(spacing: 8) {
                    ForEach(rules, id: \.name) { rule in
                        HStack(spacing: 16) {
                            Text(rule.label == "Vélo évalué" ? "Évaluation d’un vélo après un trajet" : rule.label).typo(.body(13)).foregroundStyle(Palette.inkSoft)
                            Spacer()
                            Text(verbatim: "+\(formatNumber(rule.points))").typo(.title(23)).foregroundStyle(Palette.red)
                        }
                        .padding(.horizontal, 18).padding(.vertical, 16).frame(minHeight: 64)
                        .background(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous).fill(Palette.mist))
                    }
                }
            }
            SectionHeading("Historique").padding(.top, 40)
            VStack(spacing: 0) {
                ForEach(rewards.movements.prefix(limit)) { movement in
                    HStack(spacing: 20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rewardLabel(movement.label)).typo(.body(13, medium: true)).foregroundStyle(Palette.ink)
                            Text(formatDate(movement.date, .dayLongMonthYear)).typo(.body(11)).foregroundStyle(Palette.inkSoft)
                        }
                        Spacer()
                        Text(verbatim: "\(movement.amount > 0 ? "+" : "")\(formatNumber(movement.amount))").typo(.body(15, medium: true))
                            .foregroundStyle(movement.amount > 0 ? Palette.red : Palette.ink)
                    }
                    .padding(.vertical, 16).frame(minHeight: 76)
                    Hairline()
                }
                if rewards.movements.isEmpty { EmptyState("Aucun mouvement de points.") }
                if rewards.movements.count > limit {
                    PillButton("Voir plus", variant: .secondary) { limit += 12 }.frame(maxWidth: .infinity).padding(.vertical, 24)
                }
            }
        }
    }

    /// `.points-summary > div`: one of two equal mist cards sharing the row.
    private func figure(_ icon: IconName, _ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow(icon: icon, text: label)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).typo(.title(40)).foregroundStyle(Palette.ink)
                Text("points").typo(.label(11)).foregroundStyle(Palette.inkSoft)
            }
            .lineLimit(1).minimumScaleFactor(0.5)
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous).fill(Palette.mist))
    }

}

/// account-actions.tsx `AutoSpendSetting`: « Utilisation automatique » as a real switch (PATCH /rewards), confirmed first.
struct AutoSpendSetting: View {
    let value: Bool?
    @Environment(AppModel.self) private var model
    @State private var asking = false
    @State private var next = false

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Utilisation automatique").typo(.label(12)).foregroundStyle(Palette.inkSoft)
                Text(value == nil ? Messages.missing : value! ? "Activée" : "Désactivée").typo(.title(20)).foregroundStyle(Palette.ink)
            }
            Spacer(minLength: 0)
            if let value {
                VelovSwitch(on: value) { next = !value; asking = true }
                    .accessibilityLabel("Utilisation automatique des points").accessibilityValue(value ? "Activée" : "Désactivée")
            }
        }
        .padding(.leading, 20).padding(.trailing, 16).padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous).fill(Palette.mist))
        .sheet(isPresented: $asking) {
            WriteDialog(title: next ? "Activer l’utilisation automatique ?" : "Désactiver l’utilisation automatique ?") { [next] in
                var answered: Bool?
                let outcome = await attempt {
                    let result = try await model.service.setAutoSpend(next)
                    answered = result.autoSpend
                    return result.outcome
                }
                if outcome.ok { model.setAutoSpend(answered ?? next) }
                return outcome
            } question: {
                Text(next ? "Vos points régleront automatiquement les minutes au-delà de la période gratuite."
                          : "Vos points ne régleront plus les minutes au-delà de la période gratuite.")
            }
        }
    }
}
