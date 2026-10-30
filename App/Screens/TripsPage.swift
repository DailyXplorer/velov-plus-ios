import SwiftUI
import VelovCore

enum TripFilter: String, Hashable { case all, mechanical, electrical }

private let tripFilters: [SelectOption<TripFilter>] = [
    .init(value: .all, label: "Tous les vélos"), .init(value: .mechanical, label: "Vélos mécaniques"), .init(value: .electrical, label: "Vélos électriques")
]

struct TripsPage: View {
    let data: Dashboard
    @Environment(AppModel.self) private var model
    @State private var filter = TripFilter.all
    @State private var limit = 10

    var body: some View {
        if let all = data.trips {
            let trips = all.filter { filter == .all || $0.bikeType.rawValue == filter.rawValue }
            VStack(alignment: .leading, spacing: 0) {
                StatsLink().padding(.bottom, Space.cards)
                TripsFilterLine {
                    SelectField(label: "Type de vélo", hideLabel: true, value: $filter, options: tripFilters)
                } count: {
                    Text(verbatim: "\(formatNumber(trips.count)) trajet\(trips.count > 1 ? "s" : "")")
                }
                .zIndex(1)
                .onChange(of: filter) { limit = 10 }
                TripsList(trips: Array(trips.prefix(limit)),
                          emptyText: filter == .all ? "Aucun trajet." : "Aucun trajet pour ce type de vélo.")
                if trips.count > limit {
                    PillButton("Voir plus", variant: .secondary) { limit += 10 }.frame(maxWidth: .infinity).padding(.vertical, Space.actions)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                StatsLink()
                StateView("\(Messages.missing).", pending: model.refreshing) { Task { await model.manualRefresh() } }
            }
        }
    }
}

struct TripsFilterLine<Select: View, Count: View>: View {
    @ViewBuilder let select: () -> Select
    @ViewBuilder let count: () -> Count
    var body: some View {
        HStack {
            select()
            Spacer(minLength: Space.label)
            count().typo(.caps(.label)).foregroundStyle(Palette.inkSoft).lineLimit(1).fixedSize()
        }
        .padding(.bottom, Space.label)
    }
}

struct TripsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatsLink().skeleton(Radius.capsule).padding(.bottom, Space.cards)
            TripsFilterLine {
                SelectField(label: "Type de vélo", hideLabel: true, value: .constant(TripFilter.all), options: tripFilters).skeleton(Radius.capsule)
            } count: {
                Text(verbatim: "10 trajets").ghost()
            }
            GhostTrips(rows: 10)
            PillButton("Voir plus", variant: .secondary) {}.skeleton(Radius.capsule).frame(maxWidth: .infinity).padding(.vertical, Space.actions)
        }
        .accessibilityLabel("Chargement des trajets")
    }
}

private let ghostRoutes = [("Bellecour", "Part-Dieu Villette"), ("Hôtel de Ville", "Saxe-Gambetta"), ("Croix-Rousse", "Terreaux"), ("Perrache", "Jean Macé")]

struct GhostTrips: View {
    let rows: Int
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { index in
                let route = ghostRoutes[index % ghostRoutes.count]
                TripRowLayout(start: route.0, end: route.1, date: "12 oct.", time: "08:42", duration: "14 min", price: "0,00 €", electrical: false, ghost: true)
                if index < rows - 1 { Hairline() }
            }
        }
    }
}

struct TripsList: View {
    let trips: [Trip]
    var emptyText = "Aucun trajet."

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                NavigationLink(value: Route.trip(TripRoute(trip: trip))) { TripRow(trip: trip) }
                    .buttonStyle(.row)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(spokenTrip(trip))
                if index < trips.count - 1 { Hairline() }
            }
            if trips.isEmpty { StateView(emptyText) }
        }
    }
}

private func arrival(_ trip: Trip) -> String { trip.endStation ?? "Station non renseignée" }

func spokenTrip(_ trip: Trip) -> String {
    let start = trip.startedAt.map { "\(formatDate($0)) à \(formatDate($0, .time))" } ?? "date indisponible"
    let parts = ["Trajet de \(trip.startStation ?? "Trajet Vélo’v") à \(arrival(trip))", start, trip.duration.map(formatMinutes), trip.price.map(formatPrice)]
    return parts.compactMap { $0 }.joined(separator: ", ")
}

struct TripIcon: View {
    let electrical: Bool
    var size: CGFloat = 32
    var body: some View {
        Icon(electrical ? .lightning : .personSimpleBike, .light, size: electrical ? 18 : 20)
            .foregroundStyle(Palette.ink)
            .frame(width: size, height: size)
            .background(Circle().fill(Palette.mist))
    }
}

struct TripRow: View {
    let trip: Trip
    var body: some View {
        TripRowLayout(start: trip.startStation ?? "Trajet Vélo’v",
                      end: trip.startStation == nil && trip.endStation == nil ? "Stations non renseignées" : arrival(trip),
                      date: formatDate(trip.startedAt), time: formatDate(trip.startedAt, .time),
                      duration: trip.duration.map(formatMinutes) ?? "—", price: trip.price.map(formatPrice) ?? "—",
                      electrical: trip.bikeType == .electrical, ghost: false)
    }
}

struct TripRowLayout: View {
    let start: String
    let end: String
    let date: String
    let time: String
    let duration: String
    let price: String
    let electrical: Bool
    let ghost: Bool

    var body: some View {
        HStack(alignment: .top, spacing: Space.cards) {
            VStack(alignment: .leading, spacing: Space.pair) {
                HStack(spacing: Space.cards) {
                    if ghost { Color.clear.frame(width: 32, height: 32).skeleton(Radius.capsule) } else { TripIcon(electrical: electrical) }
                    VStack(alignment: .leading, spacing: Space.pair) {
                        Text(start).typo(.body(.small, medium: true)).foregroundStyle(Palette.ink).lineLimit(1).ghost(ghost)
                        Text(end).typo(.body(.micro)).foregroundStyle(Palette.inkSoft).lineLimit(1).ghost(ghost)
                    }
                }
                HStack(spacing: Space.pair) {
                    Text(date).typo(.body(.micro)).ghost(ghost)
                    Text(time).typo(.body(.micro)).ghost(ghost)
                }
                .foregroundStyle(Palette.inkSoft)
                .padding(.leading, 32 + Space.cards)
            }
            Spacer(minLength: 0)
            Text(duration).typo(.body(.micro)).foregroundStyle(Palette.inkSoft).ghost(ghost).frame(width: 43, alignment: .trailing)
            Text(price).typo(.body(.meta)).foregroundStyle(Palette.ink).ghost(ghost).frame(width: 59, alignment: .trailing)
        }
        .padding(.vertical, Space.row)
        .contentShape(Rectangle())
    }
}
