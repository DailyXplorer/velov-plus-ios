import SwiftUI
import UIKit
import VelovCore

/// trip-sheet.tsx `RateBike`: five stars, then one tap on « Envoyer » sends one note; the stars are the choice, the button is the confirmation.
/// Offered for 3 hours after the trip ends (`canRate`); a failure keeps its raw line and the stars may be sent again.
struct RateBike: View {
    let trip: Trip
    let bikeNumber: Int
    /// « Plus tard »: the sheet closes and « Trajet terminé » is not offered again for this trip.
    let onLater: () -> Void
    @Environment(AppModel.self) private var model
    @State private var stars: Int?
    @State private var sending = false
    @State private var failure: Outcome?

    var body: some View {
        if model.ratedHere.contains(trip.id) {
            // `.trip-rate-done`.
            HStack(spacing: 8) {
                Icon(.check, .bold, size: 16)
                Text("Merci ! +5 points").typo(.body(14))
            }
            .foregroundStyle(Palette.redDeep)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous).fill(Palette.redTint))
            .padding(.top, 14)
        } else {
            card
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            Text("Noter ce vélo").typo(.label(12)).foregroundStyle(Palette.ink).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { value in
                    let on = stars.map { value <= $0 } ?? false
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        stars = value
                        failure = nil
                    } label: {
                        Icon(.star, on ? .fill : .light, size: 34)
                            .foregroundStyle(on ? Palette.red : Palette.inkSoft)
                            .frame(width: 54, height: 54).contentShape(Circle())
                    }
                    .buttonStyle(StarPress())
                    .disabled(sending)
                    .accessibilityLabel("\(value) étoile\(value > 1 ? "s" : "") sur 5 · \(StarRating.labels[value]!)")
                    .accessibilityAddTraits(stars == value ? .isSelected : [])
                }
            }
            .padding(.top, 8)
            Text(stars.flatMap { StarRating.labels[$0] } ?? "Touchez une étoile")
                .typo(.body(15)).foregroundStyle(stars == nil ? Palette.inkSoft : Palette.ink)
                .frame(minHeight: 22).padding(.top, 2)
            if let failure {
                VStack(alignment: .leading, spacing: 4) {
                    FormError(failure.message ?? "La note n’a pas pu être envoyée.")
                    RawStatus(line: rawLine(failure, withState: false))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            }
            VStack(spacing: 2) {
                PillButton("Envoyer · +5 points", pending: sending, fullWidth: true) { send() }.disabled(stars == nil)
                if !sending { TextButton(title: "Plus tard", action: onLater) }
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)
        .background(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous).fill(Palette.mist))
        .padding(.top, 14)
        .task { if model.snapshot == .tripEndedStars { stars = 4 } }
    }

    private func send() {
        guard let stars, !sending else { return }
        Haptics.confirm()
        sending = true
        failure = nil
        Task {
            let outcome = await attempt { try await model.service.rate(tripId: trip.id, bikeNumber: bikeNumber, vote: StarRating.vote(stars)) }
            Haptics.result(outcome.ok)
            sending = false
            if outcome.ok { model.ratedHere.insert(trip.id) } else { failure = outcome }
        }
    }
}

/// `.trip-rate-star:active`: the star shrinks under the finger.
private struct StarPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.9 : 1).animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// trip-sheet.tsx `TripEndedSheet`: opened when the bike is docked, or on launch for a recent unrated trip.
/// Where, how long, how much, and the stars; any way out counts as « Plus tard ».
struct TripEndedSheet: View {
    let trip: Trip
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Decided once: the card stays for its « Merci » after a note, whatever reloads behind the sheet.
    @State private var rateable: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeading(title: "Trajet terminé") { dismiss() }
            tripTimes(trip).padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text("Station d’arrivée").typo(.label(11)).foregroundStyle(Palette.inkSoft)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(trip.endStation ?? "Non renseignée").typo(.body(15)).foregroundStyle(Palette.ink)
                    if let stand = trip.endStand { Text(verbatim: "Borne \(stand)").typo(.label(11)).foregroundStyle(Palette.inkSoft).fixedSize() }
                }
            }
            .padding(.top, 20)
            VStack(spacing: 0) {
                Hairline()
                HStack(alignment: .top, spacing: 10) {
                    fact("Durée", trip.duration.map { "\(Int($0)) min" } ?? "—")
                    fact("Prix", trip.price.map(formatPrice) ?? "—")
                }
                .padding(.vertical, 16)
                Hairline()
            }
            .padding(.top, 18)
            if rateable ?? isRateable, let bike = trip.bikeNumber {
                RateBike(trip: trip, bikeNumber: bike) { dismiss() }
            } else {
                PillButton("Fermer", variant: .secondary, fullWidth: true) { dismiss() }.padding(.top, 22)
            }
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 16)
        .fitSheet()
        .onAppear { if rateable == nil { rateable = isRateable } }
        .onDisappear { model.closeEnded(trip) }
    }

    private var isRateable: Bool { trip.isRated != true && !model.ratedHere.contains(trip.id) && canRate(trip) }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).typo(.label(11)).foregroundStyle(Palette.inkSoft)
            Text(value).typo(.title(20)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `tripTimes`: « jeudi 29 octobre 2026 · 10:02 → 10:16 ».
func tripTimes(_ trip: Trip) -> some View {
    HStack(spacing: 0) {
        if let start = trip.startedAt {
            Text(verbatim: "\(formatDate(start, .dayLongMonthYear)) · ").typo(.body(14))
            Text(formatDate(start, .time) + (trip.endedAt.map { " → \(formatDate($0, .time))" } ?? "")).typo(.clock(14))
        } else {
            Text("Date indisponible").typo(.body(14))
        }
    }
    .foregroundStyle(Palette.inkSoft)
}
