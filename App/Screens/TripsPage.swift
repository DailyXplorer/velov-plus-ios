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
                StatsLink().padding(.bottom, 20)
                TripsFilterLine {
                    SelectField(label: "Type de vélo", hideLabel: true, value: $filter, options: tripFilters)
                } count: {
                    Text(verbatim: "\(formatNumber(trips.count)) trajet\(trips.count > 1 ? "s" : "")")
                }
                .zIndex(1)
                .onChange(of: filter) { limit = 10 }
                TripsList(trips: Array(trips.prefix(limit)), openFirst: model.snapshot == .tripSheet || model.snapshot == .rateCard)
                if trips.count > limit {
                    PillButton("Voir plus", variant: .secondary) { limit += 10 }.frame(maxWidth: .infinity).padding(.vertical, 24)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                StatsLink()
                EmptyState("\(Messages.missing).")
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
            Spacer(minLength: 8)
            count().typo(.caps(13)).foregroundStyle(Palette.inkSoft).lineLimit(1).fixedSize()
        }
        .padding(.bottom, 20)
    }
}

struct TripsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StatsLink().skeleton(21).padding(.bottom, 20)
            TripsFilterLine {
                SelectField(label: "Type de vélo", hideLabel: true, value: .constant(TripFilter.all), options: tripFilters).skeleton(21)
            } count: {
                Text(verbatim: "10 trajets").ghost()
            }
            GhostTrips(rows: 10)
            PillButton("Voir plus", variant: .secondary) {}.skeleton(21).frame(maxWidth: .infinity).padding(.vertical, 24)
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
    var openFirst = false
    @State private var selected: Trip?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                Button { selected = trip } label: { TripRow(trip: trip) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Détails du trajet du \(formatDate(trip.startedAt))")
                if index < trips.count - 1 { Hairline() }
            }
            if trips.isEmpty { EmptyState("Aucun trajet.") }
        }
        .sheet(item: $selected) { trip in TripSheet(trip: trip) }
        .task { if openFirst, selected == nil { selected = trips.first } }
    }
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
                      end: trip.endStation ?? (trip.bikeType == .electrical ? "Électrique" : trip.bikeType == .mechanical ? "Mécanique" : "Stations non renseignées"),
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
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    if ghost { Color.clear.frame(width: 32, height: 32).skeleton(16) } else { TripIcon(electrical: electrical) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(start).typo(.body(13, medium: true)).foregroundStyle(Palette.ink).lineLimit(1).ghost(ghost)
                        Text(end).typo(.body(11)).foregroundStyle(Palette.inkSoft).lineLimit(1).ghost(ghost)
                    }
                }
                HStack(spacing: 5) {
                    Text(date).typo(.body(11)).ghost(ghost)
                    Text(time).typo(.body(11)).ghost(ghost)
                }
                .foregroundStyle(Palette.inkSoft)
                .padding(.leading, 42)
            }
            Spacer(minLength: 0)
            Text(duration).typo(.body(11)).foregroundStyle(Palette.inkSoft).ghost(ghost).frame(width: 43, alignment: .leading)
            Text(price).typo(.body(12)).foregroundStyle(Palette.ink).ghost(ghost).frame(width: 59, alignment: .trailing)
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}
