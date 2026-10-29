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
            HStack(alignment: .top, spacing: 40) {
                figure(.starFour, "Solde", rewards.balance.map { formatNumber($0) } ?? "—", accent: true)
                figure(.trendUp, "Total gagné", rewards.total.map { formatNumber($0) } ?? "—", accent: false)
            }
            .padding(.bottom, 28)
            autoSpend(rewards.autoSpend)
            if let invite { inviteRow(cost: Int(invite.points), balance: rewards.balance) }
            if !rules.isEmpty {
                SectionHeading("Gagner des points").padding(.top, 40)
                VStack(spacing: 8) {
                    ForEach(rules, id: \.name) { rule in
                        HStack(spacing: 16) {
                            Text(rewardLabel(rule.label)).typo(.body(13)).foregroundStyle(Palette.inkSoft)
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
                if rewards.movements.isEmpty { EmptyState("Aucun mouvement.") }
                if rewards.movements.count > limit {
                    PillButton("Voir plus", variant: .secondary) { limit += 12 }.frame(maxWidth: .infinity).padding(.vertical, 24)
                }
            }
        }
    }

    private func figure(_ icon: Ph, _ label: String, _ value: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Eyebrow(icon: icon, text: label)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(value).typo(.title(52)).foregroundStyle(accent ? Palette.red : Palette.ink)
                Text("points").typo(.label(11)).foregroundStyle(Palette.inkSoft)
            }
        }
    }

    /// « Utilisation automatique »: the current state; the switch writes in stage 2.
    private func autoSpend(_ value: Bool?) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Utilisation automatique").typo(.label(12)).foregroundStyle(Palette.inkSoft)
                Text(value == nil ? Messages.missing : value! ? "Activée" : "Désactivée").typo(.title(20)).foregroundStyle(Palette.ink)
            }
            Spacer(minLength: 0)
            if let value { VelovSwitch(on: value).disabled(true).accessibilityLabel("Utilisation automatique des points") }
        }
        .padding(.leading, 20).padding(.trailing, 16).padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous).fill(Palette.mist))
    }

    private func inviteRow(cost: Int, balance: Double?) -> some View {
        let missing = balance.map { Int($0) < cost ? " · il vous manque \(cost - Int($0)) points" : "" } ?? ""
        return HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: "Inviter un ami · \(cost) points").typo(.label(12)).foregroundStyle(Palette.inkSoft)
                Text(verbatim: "Un ticket 1 trajet valable 24 h, pour libérer un second vélo\(missing).").typo(.body(13)).foregroundStyle(Palette.inkSoft)
                SoonNote()
            }
            Spacer(minLength: 0)
            PillButton("Obtenir", variant: .secondary) {}.disabled(true)
        }
        .padding(.leading, 20).padding(.trailing, 16).padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous).fill(Palette.mist))
        .padding(.top, 12)
    }
}
