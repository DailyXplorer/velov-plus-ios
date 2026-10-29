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
    guard Locator.shared.allowed, let here = try? await Locator.shared.locate() else { return nil }
    return haversine(GeoPoint(lat: here.coordinate.latitude, lon: here.coordinate.longitude), GeoPoint(lat: lat, lon: lon))
}

/// bike-actions.tsx `BikeActions` as a sheet: the confirmation and exactly one request per « Confirmer »; success closes the sheet
/// and hands over to the page (the booking banner, the dock watch). A failure stays with Vélo’v's message and the raw line:
/// a sure refusal may be confirmed again, an uncertain one only closes.
struct BikeActionSheet: View {
    let place: Place
    let action: BikeAction
    /// The account's booking of this bike, spent by an unlock.
    let bookingId: String?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var sending = false
    @State private var failure: Outcome?
    @State private var distance: Double?

    init(place: Place, bookingId: String? = nil, action: BikeAction) {
        self.place = place
        self.bookingId = bookingId
        self.action = action
    }

    private var uncertain: Bool { failure?.isUncertain == true }

    var body: some View {
        let far = action == .unlock && (distance ?? 0) > Rules.releaseDistance
        VStack(alignment: .leading, spacing: 0) {
            SheetHeading(title: "Vélo \(place.bikeNumber)", closeDisabled: sending) { dismiss() }
            Text(action == .book ? "Réserver ce vélo ?" : "Déverrouiller ce vélo ?").typo(.title(20)).foregroundStyle(Palette.ink).padding(.top, 10)
            Group {
                if action == .book {
                    Text("\(Rules.bookingPoints) points pour garder ce vélo \(Rules.bookingMinutes) minutes.").foregroundStyle(Palette.inkSoft)
                } else {
                    Text("Vous aurez ensuite 60 secondes pour appuyer sur le bouton de la borne \(place.standNumber) et retirer le vélo.").foregroundStyle(Palette.ink)
                }
            }
            .typo(.body(14)).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            if far {
                HStack(alignment: .top, spacing: 8) {
                    Icon(.warning, .bold, size: 16).padding(.top, 1)
                    Text("Vous semblez être à plus de \(Int(Rules.releaseDistance)) m de la station. Si quelqu’un d’autre prend le vélo, le trajet vous sera facturé.")
                        .typo(.body(13)).fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Palette.formError)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12).fill(Palette.redTint))
                .padding(.top, 12)
            }
            if let failure {
                VStack(alignment: .leading, spacing: 6) {
                    FormError(failure.message ?? (action == .book ? "Réservation impossible." : "Déverrouillage impossible."))
                    RawStatus(outcome: failure, withState: true)
                    if failure.isUncertain { UncertainNote(unlock: action == .unlock).padding(.top, 4) }
                }
                .padding(.top, 14)
            }
            PairedActions {
                if uncertain {
                    PillButton("Fermer", variant: .ghost, fullWidth: true) { dismiss() }
                } else {
                    PillButton("Annuler", variant: .ghost, fullWidth: true) { dismiss() }.disabled(sending)
                    PillButton("Confirmer", pending: sending, fullWidth: true) { send() }
                }
            }
            .padding(.top, 22)
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 20)
        .fitSheet()
        .interactiveDismissDisabled(sending)
        .task {
            distance = model.snapshot == nil ? await knownDistance(to: place) : 640
            if model.snapshot == .unlockUncertain { send() }
        }
    }

    // MARK: The one request

    private func send() {
        guard !sending else { return }
        Haptics.confirm()
        sending = true
        failure = nil
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
                sending = false
                if outcome.ok {
                    model.booked(booking)
                    dismiss()
                } else {
                    failure = outcome
                    // Only the booking's own state can be read back; the borne is checked by the user.
                    if outcome.isUncertain { Task { await model.loadBookings() } }
                }
            case .unlock:
                var ongoing: [Trip]?
                let outcome = await attempt {
                    let answer = try await model.service.unlock(stationNumber: place.stationNumber, standNumber: place.standNumber, bikeNumber: place.bikeNumber)
                    ongoing = answer.ongoing
                    return answer.outcome
                }
                Haptics.result(outcome.ok)
                sending = false
                if outcome.ok {
                    model.unlocked(bookingId: bookingId, tripId: ongoing?.first?.id)
                    dismiss()
                } else {
                    failure = outcome
                }
            }
        }
    }
}
