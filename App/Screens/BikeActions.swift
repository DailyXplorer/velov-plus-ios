import CoreLocation
import SwiftUI
import VelovCore

/// bike-actions.tsx `Place`: the bike, its borne and its station, as the confirmation names them.
struct Place: Equatable {
    let stationNumber: Int
    let stationName: String
    let standNumber: Int
    let bikeNumber: Int
    let lat: Double?
    let lon: Double?

    init?(_ booking: Booking) {
        guard let bike = booking.bikeNumber, let stand = booking.standNumber else { return nil }
        self.init(stationNumber: booking.stationNumber, stationName: booking.stationName, standNumber: stand, bikeNumber: bike, lat: booking.lat, lon: booking.lon)
    }

    init(stationNumber: Int, stationName: String, standNumber: Int, bikeNumber: Int, lat: Double?, lon: Double?) {
        self.stationNumber = stationNumber; self.stationName = stationName; self.standNumber = standNumber
        self.bikeNumber = bikeNumber; self.lat = lat; self.lon = lon
    }
}

enum BikeAction { case book, unlock }

/// The distance to the station, only when the location is already allowed: this sheet never asks for it.
@MainActor
func knownDistance(to place: Place) async -> Double? {
    guard let lat = place.lat, let lon = place.lon else { return nil }
    let status = CLLocationManager().authorizationStatus
    guard status == .authorizedWhenInUse || status == .authorizedAlways, let here = try? await Locator().locate() else { return nil }
    return haversine(GeoPoint(lat: here.coordinate.latitude, lon: here.coordinate.longitude), GeoPoint(lat: lat, lon: lon))
}

/// bike-actions.tsx `BikeActions` as a sheet: the confirmation, exactly one request per « Confirmer », then the result.
/// A failure keeps Vélo’v's message and the raw line; nothing is sent again without a new confirmation.
struct BikeActionSheet: View {
    enum Step {
        case confirm(BikeAction)
        case sending(BikeAction)
        case booked(Booking?)
        case unlocked(ongoing: [Trip]?)
        case failed(BikeAction, Outcome)
    }

    let place: Place
    /// The account's booking of this bike, spent by an unlock.
    let bookingId: String?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step
    @State private var distance: Double?
    @State private var booking: String?

    init(place: Place, bookingId: String? = nil, action: BikeAction) {
        self.place = place
        self.bookingId = bookingId
        _step = State(initialValue: .confirm(action))
        _booking = State(initialValue: bookingId)
    }

    private var sending: Bool { if case .sending = step { true } else { false } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeading(title: "Vélo \(place.bikeNumber)", closeDisabled: sending) { dismiss() }
            switch step {
            case .confirm(let action), .sending(let action): confirm(action)
            case .booked(let booking): booked(booking)
            case .unlocked(let ongoing): unlocked(ongoing)
            case .failed(let action, let outcome): failed(action, outcome)
            }
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 20)
        .fitSheet()
        .interactiveDismissDisabled(sending)
        .task {
            distance = model.snapshot == nil ? await knownDistance(to: place) : 640
            if model.snapshot == .unlockSuccess, case .confirm(let action) = step { send(action) }
        }
    }

    // MARK: Steps

    @ViewBuilder
    private func confirm(_ action: BikeAction) -> some View {
        let far = (distance ?? 0) > Rules.releaseDistance
        Text(action == .book ? "Réserver ce vélo ?" : "Déverrouiller ce vélo ?").typo(.title(20)).foregroundStyle(Palette.ink).padding(.top, 10)
        VStack(spacing: 0) {
            DetailRow("Station", place.stationName)
            DetailRow("Borne", "\(place.standNumber)")
            DetailRow("Vélo", "\(place.bikeNumber)", last: action == .unlock && distance == nil)
            if action == .book {
                DetailRow("Coût", "\(Rules.bookingPoints) points · \(Rules.bookingMinutes) min", last: true)
            } else if let distance {
                DetailRow("Distance", "≈ \(formatDistance(distance))", last: true)
            }
        }
        .padding(.top, 8)
        if action == .book {
            Text("Le vélo vous attend \(Rules.bookingMinutes) min, puis la réservation expire. Elle ne s’annule pas.")
                .typo(.body(13)).foregroundStyle(Palette.inkSoft).padding(.top, 12)
        } else {
            Text("Appuyez ensuite sur le bouton de la borne dans les 60 secondes, puis retirez le vélo. Passé ce délai, la borne le reverrouille.")
                .typo(.body(14, medium: true)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            if far {
                HStack(alignment: .top, spacing: 8) {
                    Icon(.warning, .bold, size: 16).padding(.top, 1)
                    Text("Vous semblez à plus de \(Int(Rules.releaseDistance)) m de la station : un vélo libéré à distance peut partir sur votre compte.")
                        .typo(.body(13)).fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Palette.formError)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.redTint))
                .padding(.top, 12)
            }
        }
        HStack(spacing: 10) {
            Spacer()
            PillButton("Annuler", variant: .ghost) { dismiss() }.disabled(sending)
            PillButton("Confirmer", pending: sending) { send(action) }
        }
        .padding(.top, 22)
    }

    private func booked(_ booking: Booking?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ResultLine(ok: true) {
                if let endsAt = booking?.endsAt {
                    (Text("Vélo réservé jusqu’à ") + Text(formatDate(endsAt, .time)).font(Typo.clock(15).font)).typo(.body(15, medium: true))
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let left = max(0, Int(endsAt.timeIntervalSince(context.date).rounded()))
                        HStack(spacing: 6) {
                            Icon(.clock, .bold, size: 14)
                            if left > 0 {
                                Text("reste").typo(.label(12))
                                Text(clock(left)).typo(.clock(13))
                            } else {
                                Text("réservation expirée").typo(.label(12))
                            }
                        }
                        .foregroundStyle(Palette.redDeep)
                    }
                } else {
                    Text("Vélo réservé pour \(Rules.bookingMinutes) min").typo(.body(15, medium: true))
                }
                Text("Vélo \(place.bikeNumber) · borne \(place.standNumber)").typo(.body(13)).foregroundStyle(Palette.inkSoft)
            }
            VStack(spacing: 10) {
                PillButton(fullWidth: true, action: { step = .confirm(.unlock) }) { Icon(.lockOpen, .light, size: 17); Text("Déverrouiller") }
                PillButton("Fermer", variant: .secondary, fullWidth: true) { dismiss() }
            }
            .padding(.top, 22)
        }
        .padding(.top, 14)
    }

    private func unlocked(_ ongoing: [Trip]?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ResultLine(ok: true) {
                Text("Vélo déverrouillé — borne \(place.standNumber)").typo(.body(15, medium: true))
                Text("Appuyez maintenant sur le bouton de la borne (60 s), puis retirez le vélo.").typo(.body(14)).foregroundStyle(Palette.ink)
                Text(ongoing?.isEmpty == false ? "Trajet en cours." : "Le trajet apparaît une dizaine de secondes après le retrait du vélo.")
                    .typo(.body(13)).foregroundStyle(Palette.inkSoft)
            }
            PillButton("Fermer", variant: .secondary, fullWidth: true) { dismiss() }.padding(.top, 22)
        }
        .padding(.top, 14)
    }

    private func failed(_ action: BikeAction, _ outcome: Outcome) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ResultLine(ok: false) {
                Text(action == .book ? "Réservation refusée" : "Déverrouillage refusé").typo(.body(15, medium: true))
                Text(outcome.message ?? Messages.releaseFailed).typo(.body(14)).foregroundStyle(Palette.ink)
            }
            RawStatus(outcome: outcome, withState: true).padding(.top, 12)
            PillButton("Retour", variant: .secondary, fullWidth: true) { dismiss() }.padding(.top, 22)
        }
        .padding(.top, 14)
    }

    // MARK: The one request

    private func send(_ action: BikeAction) {
        guard !sending else { return }
        Haptics.confirm()
        step = .sending(action)
        Task {
            switch action {
            case .book:
                var booking: Booking?
                let outcome = await attempt {
                    let answer = try await model.service.book(stationNumber: place.stationNumber, bikeNumber: place.bikeNumber)
                    booking = answer.booking
                    return answer.outcome
                }
                Haptics.result(outcome.ok)
                if outcome.ok {
                    self.booking = booking?.id
                    model.booked(booking)
                    step = .booked(booking)
                } else {
                    step = .failed(.book, outcome)
                }
            case .unlock:
                var ongoing: [Trip]?
                let outcome = await attempt {
                    let answer = try await model.service.unlock(stationNumber: place.stationNumber, standNumber: place.standNumber, bikeNumber: place.bikeNumber)
                    ongoing = answer.ongoing
                    return answer.outcome
                }
                Haptics.result(outcome.ok)
                if outcome.ok {
                    model.unlocked(bookingId: booking)
                    step = .unlocked(ongoing: ongoing)
                } else {
                    step = .failed(.unlock, outcome)
                }
            }
        }
    }
}

/// `.bike-action-result`: the red check (or X) circle and the lines beside it.
struct ResultLine<Content: View>: View {
    let ok: Bool
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Icon(ok ? .check : .x, .bold, size: 14).foregroundStyle(Palette.white)
                .frame(width: 28, height: 28).background(Circle().fill(Palette.red))
            VStack(alignment: .leading, spacing: 6) { content() }
                .foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous).fill(Palette.mist))
    }
}
