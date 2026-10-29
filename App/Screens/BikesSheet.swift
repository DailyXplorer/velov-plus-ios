import SwiftUI
import VelovCore

/// A bike sheet to push: from a station's live list (with its station) or alone from a trip.
struct BikeRoute: Hashable {
    let number: Int
    let station: Station?
}

private func typeLabel(_ type: Bike.Kind) -> (String, IconName) {
    switch type {
    case .mechanical: ("Mécanique", .personSimpleBike)
    case .electrical: ("Électrique", .lightning)
    case .other: ("Vélo’v", .personSimpleBike)
    }
}

/// station-bikes.tsx `StationBikes`: the live bikes of a station, assessed, the recommended ones first; a tap pushes the bike sheet.
struct BikesSheet: View {
    let station: Station
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var bikes: Resource<[Bike]> = .loading
    @State private var refreshing = false
    @State private var path: [BikeRoute] = []

    private var own: Set<Int> { Set(model.bookings.compactMap(\.bikeNumber)) }
    private var assessed: [AssessedBike]? { bikes.value.map { assessForAccount($0, own: own) } }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        Text(station.name).typo(.title(21)).foregroundStyle(Palette.ink).frame(maxWidth: .infinity, alignment: .leading)
                        Button { Task { await load() } } label: {
                            Group { if refreshing { Spinner(size: 19) } else { Icon(.arrowClockwise, .light, size: 19) } }
                                .foregroundStyle(Palette.inkSoft).frame(width: 40, height: 40)
                        }
                        .buttonStyle(.plain).disabled(refreshing).accessibilityLabel("Actualiser les vélos")
                        IconButton(icon: .x, label: "Fermer") { dismiss() }
                    }
                    .padding(.top, 14).padding(.bottom, 10)
                    Text(assessed.map { "\($0.count) vélo\($0.count > 1 ? "s" : "") à la station" } ?? "Chargement des vélos…")
                        .typo(.label(11)).foregroundStyle(Palette.inkMuted).padding(.bottom, 8)
                    switch bikes {
                    case .loading:
                        VStack(spacing: 10) { ForEach(0..<4, id: \.self) { _ in Skeleton(height: 64) } }.padding(.top, 6)
                    case .failed(let message):
                        ErrorNotice(message: message, pending: refreshing) { Task { await load() } }.padding(.top, 12)
                    case .ready:
                        if let assessed, !assessed.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(Array(assessed.enumerated()), id: \.element.id) { index, item in
                                    NavigationLink(value: BikeRoute(number: item.bike.number, station: station)) {
                                        BikeRow(item: item, mine: own.contains(item.bike.number))
                                    }
                                    .buttonStyle(.plain)
                                    if index < assessed.count - 1 { Hairline() }
                                }
                            }
                        } else {
                            EmptyState("Aucun vélo à cette station.")
                        }
                    }
                }
                .padding(.leading, 22).padding(.trailing, 12).padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: BikeRoute.self) { route in
                BikeDetail(route: route, preloaded: assessed?.first { $0.bike.number == route.number })
            }
        }
        .presentationDetents([.large])
        .presentationBackground(Palette.white)
        .sheetCorners()
        .task {
            await load()
            if model.snapshot == .bikeSheet || model.snapshot == .bookConfirm, let first = assessed?.first { path = [BikeRoute(number: first.bike.number, station: station)] }
        }
    }

    private func load() async {
        refreshing = true
        defer { refreshing = false }
        do { bikes = .ready(try await model.service.stationBikes(station.number)) }
        catch { bikes = .failed((error as? VelovError)?.message ?? Messages.stationBikesUnavailable) }
    }
}

/// Bikes this account has booked are not « Réservé » against it.
func assessForAccount(_ bikes: [Bike], own: Set<Int>) -> [AssessedBike] {
    assessBikes(bikes.map { bike in
        var copy = bike
        if own.contains(bike.number) { copy.isReserved = false }
        return copy
    })
}

/// `.bike-row`: type, number, borne, « Réservé », « Recommandé », the rating and the battery.
struct BikeRow: View {
    let item: AssessedBike
    let mine: Bool

    var body: some View {
        let bike = item.bike
        HStack(spacing: 14) {
            TripIcon(electrical: bike.type == .electrical, size: 36)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: "\(bike.number)").typo(.title(24)).foregroundStyle(Palette.ink)
                HStack(spacing: 8) {
                    Text(bike.standNumber.map { "Borne \($0)" } ?? "Borne inconnue").typo(.label(11)).foregroundStyle(Palette.inkSoft)
                    if bike.isReserved || mine { OutlinePill(text: "Réservé") }
                }
                .padding(.top, 5)
                if item.verdict == .recommended {
                    CardTag(icon: .thumbsUp, text: "Recommandé", compact: true).padding(.top, 8)
                }
            }
            .opacity(item.verdict == .avoid ? 0.6 : 1)
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                if let rating = bike.rating {
                    HStack(spacing: 5) { Icon(.star, .fill, size: 15).foregroundStyle(Palette.red); Text(outOfFive(rating.value)) }
                }
                if let battery = bike.batteryPercent { BatteryLevel(percent: battery) }
            }
            .typo(.body(13))
            .foregroundStyle(Palette.ink)
            .opacity(item.verdict == .avoid ? 0.6 : 1)
            Icon(.caretRight, .light, size: 16).foregroundStyle(Palette.inkSoft)
        }
        .padding(.vertical, 12)
        .frame(minHeight: 76)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.verdict == .avoid ? "À éviter" : "")
    }
}

struct BatteryLevel: View {
    let percent: Int
    var body: some View {
        let icon: IconName = percent >= 90 ? .batteryFull : percent >= 60 ? .batteryHigh : percent >= 30 ? .batteryMedium : percent >= 10 ? .batteryLow : .batteryEmpty
        HStack(spacing: 5) {
            Icon(icon, .light, size: 18).foregroundStyle(Palette.inkSoft)
            Text(verbatim: "\(percent) %")
        }
        .accessibilityLabel("Batterie \(percent) %")
    }
}

struct Stars: View {
    let value: Double
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                let point = Double(star)
                if value >= point - 0.25 { Icon(.star, .fill, size: 16) }
                else if value >= point - 0.75 { Icon(.starHalf, .fill, size: 16) }
                else { Icon(.star, .light, size: 16) }
            }
        }
        .foregroundStyle(Palette.red)
    }
}

/// `VerdictMark`: thumbs up in red, or a warning in mist, beside the bike number.
struct VerdictMark: View {
    let verdict: Verdict
    var body: some View {
        if verdict != .neutral {
            let recommended = verdict == .recommended
            Icon(recommended ? .thumbsUp : .warning, .bold, size: 18)
                .foregroundStyle(recommended ? Palette.white : Palette.inkSoft)
                .frame(width: 34, height: 34)
                .background(Circle().fill(recommended ? Palette.red : Palette.mist))
                .accessibilityLabel(recommended ? "Recommandé" : "À éviter")
        }
    }
}

/// `BikeSheet` / `BikeDrawer`: the live bike, its verdict mark beside the number, the actions (stage 2) and its facts.
struct BikeDetail: View {
    let route: BikeRoute
    var preloaded: AssessedBike?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var loaded: Resource<AssessedBike> = .loading
    @State private var pending: PendingAction?

    private var own: Set<Int> { Set(model.bookings.compactMap(\.bikeNumber)) }
    private var item: AssessedBike? { preloaded ?? loaded.value }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    IconButton(icon: .arrowLeft, label: route.station == nil ? "Retour au trajet" : "Retour à la liste des vélos") { dismiss() }.padding(.leading, -10)
                    HStack(spacing: 12) {
                        Text(verbatim: "\(route.number)").typo(.title(34)).foregroundStyle(Palette.ink)
                        if let item, !own.contains(route.number) { VerdictMark(verdict: item.verdict) }
                    }
                    Spacer()
                }
                .padding(.top, 14).padding(.bottom, 12)
                if let item {
                    sheet(item)
                } else if case .failed(let message) = loaded {
                    ErrorNotice(message: message) { Task { await load() } }.padding(.top, 12)
                } else {
                    VStack(spacing: 10) { ForEach(0..<3, id: \.self) { _ in Skeleton(height: 64) } }
                }
            }
            .padding(.horizontal, 22).padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
        .task { if preloaded == nil { await load() } }
        .sheet(item: $pending) { BikeActionSheet(place: $0.place, bookingId: $0.bookingId, action: $0.action) }
    }

    private func load() async {
        do {
            guard let bike = try await model.service.bike(route.number) else { loaded = .failed(Messages.bikeUnavailable); return }
            var assessed = assessForAccount([bike], own: own)[0]
            // Alone, a bike is no station's best pick: keep only the warnings.
            if assessed.verdict == .recommended { assessed.verdict = .neutral; assessed.reasons = [] }
            loaded = .ready(assessed)
        } catch {
            loaded = .failed((error as? VelovError)?.message ?? Messages.bikeUnavailable)
        }
    }

    @ViewBuilder
    private func sheet(_ item: AssessedBike) -> some View {
        let bike = item.bike
        let mine = own.contains(bike.number)
        let type = typeLabel(bike.type)
        HStack {
            Eyebrow(icon: type.1, text: type.0)
            Spacer()
            if bike.isReserved && !mine { OutlinePill(text: "Réservé") }
        }
        .padding(.top, 4)
        if bike.status != "AVAILABLE" {
            Text(bike.statusLabel ?? "Statut inconnu").typo(.body(14)).foregroundStyle(Palette.inkSoft).padding(.top, 14)
        }
        if let station = route.station, bike.status == "AVAILABLE", bike.standNumber != nil, !bike.isReserved || mine {
            actions(bike, station: station, mine: mine)
        }
        VStack(spacing: 0) {
            DetailRow(label: "Note") {
                if let rating = bike.rating {
                    VStack(alignment: .trailing, spacing: 3) {
                        HStack(spacing: 8) {
                            Stars(value: rating.value / 20)
                            Text(outOfFive(rating.value)) + Text("/5").foregroundStyle(Palette.inkSoft)
                        }
                        Text(verbatim: "\(rating.count) avis\(fromNow(rating.lastAt).map { " · Dernier avis \($0)" } ?? "")").typo(.body(12)).foregroundStyle(Palette.inkSoft)
                    }
                } else {
                    Text("Pas encore d’avis")
                }
            }
            if bike.type == .electrical {
                DetailRow(label: "Batterie") { if let battery = bike.batteryPercent { BatteryLevel(percent: battery) } else { Text("Non renseigné") } }
            }
            dateRow("Dernier trajet", bike.lastTripAt, withAgo: true)
            DetailRow(label: "Prochain contrôle") {
                HStack(spacing: 8) {
                    if isCheckOverdue(bike) { OutlinePill(text: "En retard") }
                    dateValue(bike.nextCheckAt, withAgo: true)
                }
            }
            DetailRow("Borne", bike.standNumber.map(String.init) ?? "Non renseigné", last: true)
        }
        .padding(.top, 12)
        Disclosure {
            VStack(spacing: 0) {
                dateRow("Dernier contrôle", bike.lastControlAt, withAgo: true)
                dateRow("Dernier signal", bike.lastSignalAt, withAgo: true)
                dateRow("Prochaine révision", bike.nextReviewAt, withAgo: false)
                DetailRow(label: "Cadre", last: true) { Text(bike.frameId ?? "Non renseigné").typo(.mono(13)) }
            }
        }
    }

    private func dateRow(_ label: String, _ date: Date?, withAgo: Bool) -> some View {
        DetailRow(label: label) { dateValue(date, withAgo: withAgo) }
    }

    @ViewBuilder
    private func dateValue(_ date: Date?, withAgo: Bool) -> some View {
        let exact = date.map { formatDate($0, withAgo ? .dayMonthYearTime : .dayMonthYear) }
        if let exact {
            if withAgo, let since = fromNow(date) { StackedValue(value: capitalize(since), small: exact) } else { Text(exact) }
        } else {
            Text("Non renseigné")
        }
    }

    /// Book and release, stacked full width like the web's phone layout; each opens its confirmation.
    private func actions(_ bike: Bike, station: Station, mine: Bool) -> some View {
        let booking = model.bookings.first { $0.bikeNumber == bike.number }
        let place = Place(stationNumber: station.number, stationName: station.name, standNumber: bike.standNumber ?? 0, bikeNumber: bike.number, lat: station.lat, lon: station.lon)
        return VStack(alignment: .leading, spacing: 10) {
            if mine, let endsAt = booking?.endsAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, Int(endsAt.timeIntervalSince(context.date).rounded()))
                    (Text("Vélo réservé jusqu’à ") + Text(formatDate(endsAt, .time)).font(Typo.clock(14).font) + Text(left > 0 ? " · Il reste " : " · Réservation expirée") + Text(left > 0 ? clock(left) : "").font(Typo.clock(14).font))
                        .typo(.body(14, medium: true)).foregroundStyle(Palette.ink)
                }
            }
            if !mine {
                // The cost and the duration show in the confirmation only.
                PillButton(variant: .secondary, fullWidth: true, action: { pending = PendingAction(place: place, bookingId: nil, action: .book) }) {
                    Icon(.timer, .light, size: 17); Text("Réserver")
                }
            }
            PillButton(variant: .primary, fullWidth: true, action: { pending = PendingAction(place: place, bookingId: booking?.id, action: .unlock) }) { Icon(.lockOpen, .light, size: 17); Text("Déverrouiller") }
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
        .background(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous).fill(Palette.mist))
        .padding(.top, 18)
        .task {
            guard model.snapshot == .bookConfirm, !mine else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            pending = PendingAction(place: place, bookingId: nil, action: .book)
        }
    }
}

/// The sheet a bike action opens: what to confirm and with which booking.
struct PendingAction: Identifiable {
    let place: Place
    let bookingId: String?
    let action: BikeAction
    var id: String { "\(place.bikeNumber)-\(action)" }
}
