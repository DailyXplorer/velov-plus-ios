import SwiftUI
import UIKit
import VelovCore

struct RateBike: View {
    let trip: Trip
    let bikeNumber: Int
    let onRated: () -> Void
    let onLater: () -> Void
    @Environment(AppModel.self) private var model
    @State private var stars: Int?
    @State private var refused: Outcome?
    @State private var checking = false
    @State private var notice: String?

    init(trip: Trip, bikeNumber: Int, onRated: @escaping () -> Void = {}, onLater: @escaping () -> Void) {
        self.trip = trip; self.bikeNumber = bikeNumber; self.onRated = onRated; self.onLater = onLater
    }

    private var key: String { OperationKey.rate(trip.id) }
    private var entry: Operations.Entry? { model.operations.get(key) }
    private var uncertain: Outcome? { entry?.status == .uncertain ? entry?.outcome : nil }
    private var sending: Bool { entry != nil || checking }
    private var failure: Outcome? { uncertain ?? refused }

    var body: some View {
        if !model.ratedHere.contains(trip.id) { card }
    }

    private var card: some View {
        VStack(spacing: 0) {
            Text("Noter ce vélo").typo(.caps(.label)).foregroundStyle(Palette.ink).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 2) {
                ForEach(1...5, id: \.self) { value in
                    let on = stars.map { value <= $0 } ?? false
                    Button {
                        Haptics.selection()
                        stars = value
                        refused = nil
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
                .typo(.body(.lead)).foregroundStyle(stars == nil ? Palette.inkSoft : Palette.ink)
                .frame(minHeight: 22).padding(.top, 2)
            if let failure {
                FailureBlock(message: failure.message ?? Messages.ratingUnconfirmed, raw: ratingLine(failure), uncertain: uncertain != nil)
                    .padding(.top, Space.label)
            }
            if let notice { FormError(notice).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8) }
            VStack(spacing: 2) {
                if uncertain != nil {
                    PillButton("Vérifier", variant: .secondary, pending: checking, fullWidth: true) { verify() }
                    TextLink(title: "Plus tard", action: onLater)
                } else {
                    PillButton("Envoyer", pending: sending, fullWidth: true) { send() }.disabled(stars == nil)
                    if !sending { TextLink(title: "Plus tard", action: onLater) }
                }
            }
            .padding(.top, 14)
        }
        .card(.mist, compact: true)
        .padding(.top, 14)
        .task { if model.snapshot == .tripEndedStars { stars = 4 } }
    }

    private func send() {
        guard let stars, !sending else { return }
        Haptics.confirm()
        refused = nil
        notice = nil
        let model = model
        let trip = trip
        let bikeNumber = bikeNumber
        let key = key
        Task {
            let result = await model.operations.runOnce(key) {
                ratingOutcome(await attempt { try await model.service.rate(tripId: trip.id, bikeNumber: bikeNumber, vote: StarRating.vote(stars)) })
            }
            let outcome: Outcome
            switch result {
            case .unsaved: notice = Messages.unsaved; return
            case .busy: if model.operations.get(key) == nil { notice = Messages.busy }; return
            case .finished(let answer): outcome = answer
            }
            Haptics.result(outcome)
            if outcome.ok { rated() } else if outcome.isUncertain { verify() } else { refused = outcome }
        }
    }

    private func verify() {
        guard !checking else { return }
        checking = true
        let model = model
        let trip = trip
        let key = key
        Task {
            let settled = await model.operations.settleHeld(key) { _ in ratingCheck(try await model.service.dashboard(), tripId: trip.id) }
            checking = false
            switch settled {
            case .done?:
                Haptics.success()
                rated()
            case .refused(let answer)?:
                Haptics.refused()
                refused = answer
            case .uncertain?, nil:
                break
            }
        }
    }

    private func rated() {
        model.ratedHere.insert(trip.id)
        model.statsChanged()
        onRated()
    }
}

private struct StarPress: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.9 : 1).animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct TripEndedSheet: View {
    let trip: Trip
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var rateable: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeading(title: "Trajet terminé", closeDisabled: rating) { dismiss() }
            tripTimes(trip).padding(.top, 4)
            VStack(alignment: .leading, spacing: 4) {
                Text("Station d’arrivée").typo(.caps(.label)).foregroundStyle(Palette.inkSoft)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(trip.endStation ?? "Non renseignée").typo(.body(.lead)).foregroundStyle(Palette.ink)
                    if let stand = trip.endStand { Text(verbatim: "Borne \(stand)").typo(.caps(.label)).foregroundStyle(Palette.inkSoft).fixedSize() }
                }
            }
            .padding(.top, 20)
            VStack(spacing: 0) {
                Hairline()
                HStack(alignment: .top, spacing: 10) {
                    fact("Durée", trip.duration.map(formatMinutes) ?? "—")
                    fact("Prix", trip.price.map(formatPrice) ?? "—")
                }
                .padding(.vertical, 16)
                Hairline()
            }
            .padding(.top, 18)
            if rateable ?? isRateable, let bike = trip.bikeNumber {
                RateBike(trip: trip, bikeNumber: bike, onRated: { dismiss() }, onLater: { dismiss() })
            } else {
                PillButton("Fermer", variant: .secondary, fullWidth: true) { dismiss() }.padding(.top, 22)
            }
        }
        .padding(Layout.dialog)
        .velovSheet(.fit, closeDisabled: rating)
        .onAppear { if rateable == nil { rateable = isRateable } }
        .onDisappear { model.closeEnded(trip) }
    }

    private var rating: Bool { model.operations.get(OperationKey.rate(trip.id))?.status == .sending }

    private var isRateable: Bool { trip.isRated != true && !model.ratedHere.contains(trip.id) && canRate(trip) }

    private func fact(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).typo(.caps(.label)).foregroundStyle(Palette.inkSoft)
            Text(value.glyphic).typo(.title(.card)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

func tripTimes(_ trip: Trip) -> some View {
    HStack(spacing: 0) {
        if let start = trip.startedAt {
            Text(verbatim: "\(formatDate(start, .dayLongMonthYear)) · ").typo(.body(.base))
            Text(formatDate(start, .time) + (trip.endedAt.map { " → \(formatDate($0, .time))" } ?? "")).typo(.body(.base))
        } else {
            Text("Date indisponible").typo(.body(.base))
        }
    }
    .foregroundStyle(Palette.inkSoft)
}
