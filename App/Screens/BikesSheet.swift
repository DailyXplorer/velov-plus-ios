import SwiftUI
import VelovCore

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

struct BikesSheet: View {
    let station: Station
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var bikes: Resource<[Bike]> = .loading
    @State private var refreshing = false
    @State private var path: [BikeRoute] = []

    private var own: Set<Int> { Set(model.bookings.compactMap(\.bikeNumber)) }
    private var assessed: [AssessedBike]? { bikes.value.map { assessForAccount($0, own: own) } }
    private var subtitle: String? {
        switch bikes {
        case .loading: "Chargement des vélos…"
        case .ready: assessed.map { "\($0.count) vélo\($0.count > 1 ? "s" : "") à la station" }
        case .failed: nil
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            PushedPage(title: station.name, close: { dismiss() }, refresh: { await load() },
                       extra: BarAction(icon: .arrowClockwise, label: "Actualiser les vélos", pending: refreshing) { Task { await load() } }) {
                VStack(alignment: .leading, spacing: Space.pair) {
                    PageTitle(title: station.name)
                    if let subtitle {
                        Text(subtitle).typo(.caps(.label)).foregroundStyle(Palette.inkSoft).lineLimit(1)
                    }
                }
            } content: {
                switch bikes {
                case .loading:
                    BikesSkeleton(station: station)
                case .failed(let failure):
                    StateView(failure, pending: refreshing) { Task { await load() } }
                case .ready:
                    if let assessed, !assessed.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(assessed.enumerated()), id: \.element.id) { index, item in
                                NavigationLink(value: BikeRoute(number: item.bike.number, station: station)) {
                                    BikeRow(item: item, mine: own.contains(item.bike.number))
                                }
                                .buttonStyle(.row)
                                if index < assessed.count - 1 { Hairline() }
                            }
                        }
                    } else {
                        StateView("Aucun vélo à cette station.")
                    }
                }
            }
            .navigationDestination(for: BikeRoute.self) { route in
                BikeDetail(route: route, preloaded: assessed?.first { $0.bike.number == route.number }, close: { dismiss() })
            }
        }
        .environment(\.tabBarBand, 0)
        .velovSheet(.large, closeDisabled: model.operations.sending)
        .task {
            await load()
            if model.snapshot?.pushesBike == true, let first = assessed?.first { path = [BikeRoute(number: first.bike.number, station: station)] }
            if model.snapshot == .bikePush, let first = assessed?.first {
                try? await Task.sleep(for: .seconds(4))
                path = [BikeRoute(number: first.bike.number, station: station)]
            }
            if model.snapshot == .dockWhileBikes {
                try? await Task.sleep(for: .seconds(5))
                dismiss()
            }
        }
    }

    private func load() async {
        refreshing = true
        defer { refreshing = false }
        do { bikes = .ready(try await model.service.stationBikes(station.number)) }
        catch {
            let failure = LoadFailure(error, Messages.stationBikesUnavailable)
            if bikes.value == nil { bikes = .failed(failure) } else { model.showToast(failure.message) }
        }
    }
}

func assessForAccount(_ bikes: [Bike], own: Set<Int>) -> [AssessedBike] {
    assessBikes(bikes.map { bike in
        var copy = bike
        if own.contains(bike.number) { copy.isReserved = false }
        return copy
    })
}

struct BikeRow: View {
    let item: AssessedBike
    let mine: Bool

    var body: some View {
        let bike = item.bike
        BikeRowLayout(number: "\(bike.number)", stand: bike.standNumber.map { "Borne \($0)" } ?? "Borne non renseignée",
                      reserved: bike.isReserved || mine, recommended: item.verdict == .recommended, electrical: bike.type == .electrical, ghost: false) {
            VStack(alignment: .trailing, spacing: Space.pair) {
                if let rating = bike.rating {
                    HStack(spacing: Space.pair) { Icon(.star, .fill, size: 16).foregroundStyle(item.verdict == .avoid ? Palette.inkSoft : Palette.red); Text(outOfFive(rating.value)) }
                }
                if let battery = bike.batteryPercent { BatteryLevel(percent: battery) }
            }
            .typo(.body(.small))
            .foregroundStyle(Palette.ink)
        }
        .opacity(item.verdict == .avoid ? 0.6 : 1)
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.verdict == .avoid ? "À éviter" : "")
    }
}

struct BikeRowLayout<Facts: View>: View {
    let number: String
    let stand: String
    let reserved: Bool
    let recommended: Bool
    let electrical: Bool
    let ghost: Bool
    @ViewBuilder let facts: () -> Facts

    var body: some View {
        HStack(spacing: Space.cards) {
            if ghost { Color.clear.frame(width: 36, height: 36).skeleton(Radius.capsule) } else { TripIcon(electrical: electrical, size: 36) }
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: number).typo(.title(.section)).foregroundStyle(Palette.ink).ghost(ghost)
                HStack(spacing: Space.label) {
                    Text(stand).typo(.caps(.label)).foregroundStyle(Palette.inkSoft).lineLimit(1).ghost(ghost)
                    if reserved { OutlinePill(text: "Réservé") }
                }
                .padding(.top, Space.pair)
                if recommended {
                    Group {
                        if ghost { CardTag(icon: .thumbsUp, text: "Recommandé", size: .pick).skeleton(Radius.capsule) } else { CardTag(icon: .thumbsUp, text: "Recommandé", size: .pick) }
                    }
                    .padding(.top, Space.label)
                }
            }
            Spacer(minLength: 0)
            facts()
            if ghost { Color.clear.frame(width: 16) } else { Icon(.caretRight, .light, size: 16).foregroundStyle(Palette.inkSoft) }
        }
        .padding(.vertical, Space.row)
        .frame(minHeight: 76)
        .contentShape(Rectangle())
    }
}

struct BikesSkeleton: View {
    let station: Station
    var body: some View {
        let count = station.mechanical + station.electrical
        let picks = (station.mechanical > 0 ? 1 : 0) + (station.electrical > 0 ? 1 : 0)
        if count == 0 {
            StateView("Aucun vélo à cette station.").ghost()
        } else {
            VStack(spacing: 0) {
                ForEach(0..<count, id: \.self) { index in
                    BikeRowLayout(number: "\(12000 + index * 731)", stand: "Borne \(index + 1)", reserved: false, recommended: index < picks, electrical: false, ghost: true) {
                        Text(verbatim: "4,5").typo(.body(.small)).ghost()
                    }
                    if index < count - 1 { Hairline() }
                }
            }
            .accessibilityLabel("Chargement des vélos")
        }
    }
}

struct BatteryLevel: View {
    let percent: Int
    var body: some View {
        let icon: IconName = percent >= 90 ? .batteryFull : percent >= 60 ? .batteryHigh : percent >= 30 ? .batteryMedium : percent >= 10 ? .batteryLow : .batteryEmpty
        HStack(spacing: Space.pair) {
            Icon(icon, .light, size: 18).foregroundStyle(Palette.inkSoft)
            Text(verbatim: "\(percent)\u{a0}%")
        }
        .accessibilityLabel("Batterie \(percent)\u{a0}%")
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(String(format: "%.1f", value).replacingOccurrences(of: ".", with: ",")) sur 5")
    }
}

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

struct BikeDetail: View {
    let route: BikeRoute
    var preloaded: AssessedBike?
    var close: (() -> Void)?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var loaded: Resource<AssessedBike> = .loading
    @State private var retrying = false
    @State private var pending: PendingAction?
    @State private var unlockedHere = false

    private var own: Set<Int> { Set(model.bookings.compactMap(\.bikeNumber)) }
    private var item: AssessedBike? { preloaded ?? loaded.value }

    var body: some View {
        PushedPage(title: "Vélo \(route.number)", close: close) {
            HStack(spacing: Space.cards) {
                Text(verbatim: "\(route.number)").typo(.title(.figureS)).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
                    .accessibilityLabel("Vélo \(route.number)")
                if let item, !own.contains(route.number) { VerdictMark(verdict: item.verdict) }
            }
        } content: {
            if let item {
                sheet(item)
            } else if case .failed(let failure) = loaded {
                StateView(failure, pending: retrying) { Task { await load() } }
            } else {
                BikeSheetSkeleton()
            }
        }
        .task { if preloaded == nil { await load() } }
        .sheet(item: $pending, onDismiss: { if unlockedHere { (close ?? { dismiss() })() } }) {
            BikeActionSheet(place: $0.place, bookingId: $0.bookingId, action: $0.action) { action in
                if action == .unlock { unlockedHere = true }
            }
        }
    }

    private func load() async {
        retrying = true
        defer { retrying = false }
        do {
            guard let bike = try await model.service.bike(route.number) else { loaded = .failed(LoadFailure(message: Messages.bikeUnavailable)); return }
            var assessed = assessForAccount([bike], own: own)[0]
            if assessed.verdict == .recommended { assessed.verdict = .neutral; assessed.reasons = [] }
            loaded = .ready(assessed)
        } catch {
            loaded = .failed(LoadFailure(error, Messages.bikeUnavailable))
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
        if bike.status != "AVAILABLE" {
            Text(bike.statusLabel ?? "Statut inconnu").typo(.body(.base)).foregroundStyle(Palette.inkSoft).padding(.top, Space.titleToContent)
        }
        if model.isGuest {
            if route.station != nil { signIn }
        } else if let station = route.station, bike.status == "AVAILABLE", bike.standNumber != nil, !bike.isReserved || mine {
            actions(bike, station: station, mine: mine)
        }
        VStack(spacing: 0) {
            DetailRow(label: "Note") {
                if let rating = bike.rating {
                    VStack(alignment: .trailing, spacing: Space.pair) {
                        HStack(spacing: Space.label) {
                            Stars(value: rating.value / 20)
                            Text(outOfFive(rating.value)) + Text("/5").foregroundStyle(Palette.inkSoft)
                        }
                        Text(verbatim: "\(formatNumber(rating.count)) avis\(fromNow(rating.lastAt).map { " · Dernier avis \($0)" } ?? "")").typo(.caps(.tag)).foregroundStyle(Palette.inkSoft)
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
                if let next = nextCheckText(bike.nextCheckAt) { StackedValue(value: next.value, small: next.detail, caps: true) } else { Text("Non renseigné") }
            }
            DetailRow("Borne", bike.standNumber.map(String.init) ?? "Non renseigné", last: true)
        }
        .padding(.top, Space.cards)
        Disclosure {
            VStack(spacing: 0) {
                dateRow("Dernier contrôle", bike.lastControlAt, withAgo: true)
                dateRow("Dernier signal", bike.lastSignalAt, withAgo: true)
                dateRow("Prochaine révision", bike.nextReviewAt, withAgo: false)
                DetailRow("Cadre", bike.frameId ?? "Non renseigné", last: true)
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
            if withAgo, let since = fromNow(date) { StackedValue(value: capitalize(since), small: exact, caps: true) } else { Text(exact) }
        } else {
            Text("Non renseigné")
        }
    }

    private var signIn: some View {
        Button { model.leaveGuest() } label: {
            HStack(spacing: Space.label) {
                Icon(.signIn, .light, size: 18)
                Text("Se connecter pour réserver ou déverrouiller").typo(.caps(.tag)).multilineTextAlignment(.leading)
            }
            .foregroundStyle(Palette.redDeep)
            .frame(minHeight: Layout.hit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .accessibilityLabel("Se connecter pour réserver ou déverrouiller")
        .padding(.top, Space.label)
    }

    private func actions(_ bike: Bike, station: Station, mine: Bool) -> some View {
        let booking = model.bookings.first { $0.bikeNumber == bike.number }
        let place = Place(stationNumber: station.number, stationName: station.name, standNumber: bike.standNumber ?? 0, bikeNumber: bike.number, lat: station.lat, lon: station.lon)
        return TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = booking?.endsAt.map { max(0, Int($0.timeIntervalSince(context.date).rounded())) }
            let expired = mine && left == 0
            VStack(alignment: .leading, spacing: Space.cards) {
                if mine {
                    if let endsAt = booking?.endsAt, let left {
                        VStack(alignment: .leading, spacing: Space.pair) {
                            Text(verbatim: "Vélo réservé jusqu’à \(formatDate(endsAt, .time))").typo(.title(.card)).foregroundStyle(Palette.ink)
                            HStack(spacing: Space.label) {
                                Icon(.clock, .bold, size: 16)
                                Text(left > 0 ? "Il reste \(clock(left))" : "Réservation expirée").typo(.caps(.label)).monospacedDigit()
                            }
                            .foregroundStyle(Palette.redDeep)
                        }
                    } else {
                        Text(verbatim: "Vélo réservé pour \(Rules.bookingMinutes) minutes").typo(.title(.card)).foregroundStyle(Palette.ink)
                    }
                }
                if !expired {
                    PairedActions {
                        if !mine {
                            PillButton(variant: .secondary, fullWidth: true, action: { pending = PendingAction(place: place, bookingId: nil, action: .book) }) {
                                ButtonIcon(.timer); Text("Réserver")
                            }
                        }
                        PillButton(variant: .primary, fullWidth: true, action: { pending = PendingAction(place: place, bookingId: booking?.id, action: .unlock) }) { ButtonIcon(.lockOpen); Text("Déverrouiller") }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(.mist)
            .onChange(of: expired) { _, now in if now { Task { await model.loadBookings(force: true) } } }
        }
        .padding(.top, Space.titleToContent)
        .task {
            guard model.snapshot == .bookConfirm, !mine else { return }
            try? await Task.sleep(nanoseconds: 500_000_000)
            pending = PendingAction(place: place, bookingId: nil, action: .book)
        }
    }
}

struct BikeSheetSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(icon: .personSimpleBike, text: "Mécanique").skeleton(Radius.capsule)
            VStack(spacing: 0) {
                DetailRow(label: "Note") {
                    VStack(alignment: .trailing, spacing: Space.pair) {
                        HStack(spacing: Space.label) { Stars(value: 4.5); Text(verbatim: "4,5/5") }.ghost()
                        Text(verbatim: "12 avis · Dernier avis il y a 3 j").typo(.caps(.tag)).ghost()
                    }
                }
                DetailRow(label: "Dernier trajet") { ghostDate }
                DetailRow(label: "Prochain contrôle") { ghostDate }
                DetailRow(label: "Borne", last: true) { Text(verbatim: "12").ghost() }
            }
            .padding(.top, Space.cards)
            Disclosure { EmptyView() }.disabled(true)
        }
        .accessibilityLabel("Chargement du vélo")
    }

    private var ghostDate: some View {
        VStack(alignment: .trailing, spacing: Space.pair) {
            Text(verbatim: "Il y a 2 h").ghost()
            Text(verbatim: "12 oct. 2026, 08:42").typo(.caps(.tag)).ghost()
        }
    }
}

struct PendingAction: Identifiable {
    let place: Place
    let bookingId: String?
    let action: BikeAction
    var id: String { "\(place.bikeNumber)-\(action)" }
}
