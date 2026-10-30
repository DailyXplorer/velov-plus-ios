import SwiftUI
import VelovCore

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

    func ride(_ trip: Trip?, now: Date = Date()) -> Ride {
        trip.map { Ride($0, now: now) } ?? Ride(tripId: nil, startedAt: now, station: stationName, bikeNumber: bikeNumber)
    }
}

enum BikeAction { case book, unlock }

@MainActor
func knownDistance(to place: Place) async -> Double? {
    guard let lat = place.lat, let lon = place.lon else { return nil }
    guard Locator.shared.allowed, let here = try? await Locator.shared.locate() else { return nil }
    return haversine(GeoPoint(lat: here.coordinate.latitude, lon: here.coordinate.longitude), GeoPoint(lat: lat, lon: lon))
}

struct BikeActionSheet: View {
    let place: Place
    let chosen: BikeAction
    let bookingId: String?
    var done: (BikeAction) -> Void = { _ in }
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var refused: Outcome?
    @State private var notice: String?
    @State private var checking = false
    @State private var distance: Double?

    init(place: Place, bookingId: String? = nil, action: BikeAction, done: @escaping (BikeAction) -> Void = { _ in }) {
        self.place = place
        self.bookingId = bookingId
        self.done = done
        chosen = action
    }

    private func key(_ action: BikeAction) -> String {
        action == .book ? OperationKey.book(place.bikeNumber) : OperationKey.unlock(place.bikeNumber)
    }

    private var held: (action: BikeAction, entry: Operations.Entry)? {
        if let entry = model.operations.get(key(.unlock)) { return (.unlock, entry) }
        if chosen == .book, let entry = model.operations.get(key(.book)) { return (.book, entry) }
        return nil
    }

    private var action: BikeAction { held?.action ?? chosen }
    private var sending: Bool { held?.entry.status == .sending }
    private var busy: Bool { sending || checking }
    private var failure: Outcome? {
        if let held { return held.entry.outcome }
        return refused
    }
    private var uncertain: Bool { held?.entry.status == .uncertain }
    private var booked: Bool { model.bookings.contains { $0.bikeNumber == place.bikeNumber } }

    var body: some View {
        let far = action == .unlock && (distance ?? 0) > Rules.releaseDistance
        ConfirmScaffold(title: action == .book ? "Réserver le vélo \(place.bikeNumber)\u{a0}?" : "Déverrouiller le vélo \(place.bikeNumber)\u{a0}?",
                        closeDisabled: busy, close: { dismiss() }) {
            if action == .book {
                Text("\(Rules.bookingPoints) points pour garder ce vélo \(Rules.bookingMinutes) minutes.")
            } else {
                Text("Vous aurez ensuite 60 secondes pour appuyer sur le bouton de la borne \(place.standNumber) et retirer le vélo.")
            }
        } extra: {
            if far {
                HStack(alignment: .top, spacing: Space.label) {
                    Icon(.warning, .bold, size: 16).padding(.top, 1)
                    Text("Vous semblez être à plus de \(Int(Rules.releaseDistance)) m de la station. Si quelqu’un d’autre prend le vélo, le trajet vous sera facturé.")
                        .typo(.body(.small)).fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Palette.formError)
            }
            if let notice { FormError(notice) }
            if let failure {
                FailureBlock(message: failure.message ?? (action == .book ? "Réservation impossible." : "Déverrouillage impossible."),
                             uncertain: uncertain, unlock: action == .unlock)
            }
        } actions: {
            if uncertain {
                PillButton("Fermer", variant: .ghost, fullWidth: true) { dismiss() }.disabled(busy)
                PillButton("Vérifier", variant: .secondary, pending: checking, fullWidth: true) { verify(action) }
            } else {
                PillButton("Annuler", variant: .ghost, fullWidth: true) { dismiss() }.disabled(busy)
                PillButton("Confirmer", pending: sending, fullWidth: true) { send() }
            }
        }
        .onChange(of: booked, initial: true) { _, now in
            if now, held?.action == .book, held?.entry.status == .uncertain {
                model.operations.clear(key(.book))
                dismiss()
            }
        }
        .task {
            distance = model.snapshot == nil ? await knownDistance(to: place) : 640
            if model.snapshot == .unlockUncertain { send() }
        }
    }

    private func send() {
        guard !sending else { return }
        let action = action
        let key = key(action)
        let model = model
        let place = place
        let bookingId = bookingId
        Haptics.confirm()
        refused = nil
        notice = nil
        Task {
            var booking: Booking?
            var ongoing: [Trip]?
            let intent = ["station": String(place.stationNumber), "stand": String(place.standNumber), "bike": String(place.bikeNumber)]
            let result = await model.operations.runOnce(key, meta: intent) {
                await attempt {
                    switch action {
                    case .book:
                        let answer = try await model.service.book(stationNumber: place.stationNumber, bikeNumber: place.bikeNumber)
                        booking = answer.booking
                        return answer.outcome
                    case .unlock:
                        let answer = try await model.service.unlock(stationNumber: place.stationNumber, standNumber: place.standNumber, bikeNumber: place.bikeNumber)
                        ongoing = answer.ongoing
                        return answer.outcome
                    }
                }
            }
            let outcome: Outcome
            switch result {
            case .unsaved: notice = Messages.unsaved; return
            case .busy: if model.operations.get(key) == nil { notice = Messages.busy }; return
            case .finished(let answer): outcome = answer
            }
            Haptics.result(outcome)
            if outcome.ok {
                if action == .book { model.booked(booking) } else { model.unlocked(bookingId: bookingId, ride: place.ride(ongoing?.first)) }
                done(action)
                dismiss()
            } else if !outcome.isUncertain {
                refused = outcome
            } else if model.snapshot == nil {
                verify(action)
            }
        }
    }

    private func verify(_ action: BikeAction) {
        let key = key(action)
        guard !checking, let held = model.operations.get(key) else { return }
        checking = true
        let model = model
        let place = place
        let bookingId = bookingId
        Task {
            defer { checking = false }
            var trip: Trip?
            let settled = await model.operations.settleHeld(key) { _ in
                switch action {
                case .book:
                    return bookingCheck(try await model.service.bookings(), bike: place.bikeNumber)
                case .unlock:
                    let answer = try await model.service.tripCheck()
                    trip = answer.ongoing?.first { $0.bikeNumber == place.bikeNumber }
                    let bookings = bookingId == nil ? nil : try? await model.service.bookings()
                    return unlockCheck(answer, bike: place.bikeNumber, since: held.at, now: Date(), booking: bookingId, bookings: bookings)
                }
            }
            switch settled {
            case .done?:
                Haptics.success()
                if action == .unlock, let trip { model.unlocked(bookingId: bookingId, ride: place.ride(trip)) } else { await model.loadBookings(force: true) }
                done(action)
                dismiss()
            case .refused(let answer)?:
                Haptics.refused()
                refused = answer
                await model.loadBookings(force: true)
            case .uncertain?, nil:
                break
            }
        }
    }
}
