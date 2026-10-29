import SwiftUI
import VelovCore

/// trip-sheet.tsx `RateBike`: « Noter ce vélo · +5 points », offered for 3 hours after the trip ends (`canRate`).
/// The vote is confirmed in its own sheet and sent once.
struct RateBike: View {
    /// The defect list (GET /defect-type-groups) refuses the web client token, so its two rating levels stand in for it.
    static let defects: [(rating: Int, label: String)] = [(30, "Problème grave (freins, crevaison, ne démarre pas)"), (60, "Autre problème")]

    let trip: Trip
    let bikeNumber: Int
    @Environment(AppModel.self) private var model
    @State private var reasons = false
    @State private var vote: Vote?

    struct Vote: Identifiable {
        let value: RateVote
        var id: String { "\(value.recommended)-\(value.rating ?? 0)" }
        var summary: String {
            value.recommended ? "Je recommande ce vélo"
                : "Je déconseille ce vélo · \(RateBike.defects.first { $0.rating == value.rating }?.label ?? "")"
        }
    }

    var body: some View {
        Group {
            if model.ratedHere.contains(trip.id) {
                HStack(spacing: 8) {
                    Icon(.check, .bold, size: 16).foregroundStyle(Palette.red)
                    Text("Merci ! +5 points").typo(.label(12)).foregroundStyle(Palette.ink)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    (Text("Noter ce vélo · ") + Text("+5 points").foregroundColor(Palette.redDeep)).typo(.label(12)).foregroundStyle(Palette.ink)
                    if reasons {
                        Text("Quel problème ?").typo(.body(14, medium: true)).foregroundStyle(Palette.ink).padding(.top, 12)
                        VStack(spacing: 0) {
                            ForEach(Self.defects, id: \.rating) { defect in
                                Button { vote = Vote(value: .warn(defect.rating)) } label: {
                                    HStack(spacing: 10) {
                                        Text(defect.label).typo(.body(14)).foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                                        Spacer(minLength: 0)
                                        Icon(.caretRight, .light, size: 15).foregroundStyle(Palette.inkSoft)
                                    }
                                    .padding(.vertical, 12).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Hairline(color: Palette.inkLine)
                            }
                        }
                        .padding(.top, 4)
                        PillButton("Annuler", variant: .ghost) { reasons = false }.padding(.top, 8)
                    } else {
                        VStack(spacing: 8) {
                            PillButton(variant: .secondary, fullWidth: true, action: { vote = Vote(value: .recommend) }) { Icon(.thumbsUp, .light, size: 17); Text("Je recommande") }
                            PillButton(variant: .secondary, fullWidth: true, action: { reasons = true }) { Icon(.thumbsDown, .light, size: 17); Text("Je déconseille") }
                        }
                        .padding(.top, 12)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
        .background(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous).fill(Palette.mist))
        .padding(.top, 14)
        .sheet(item: $vote) { vote in
            WriteDialog(title: "Envoyer la note ?", success: "Merci ! +5 points", showsRawLine: false) {
                let outcome = await attempt {
                    try await model.service.rate(tripId: trip.id, bikeNumber: bikeNumber, vote: vote.value)
                    return Outcome(ok: true, httpStatus: 200)
                }
                if outcome.ok { model.ratedHere.insert(trip.id) }
                return outcome
            } question: {
                Text(vote.summary)
            }
        }
    }
}
