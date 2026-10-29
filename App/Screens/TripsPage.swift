import SwiftUI
import VelovCore

enum TripSort: String, Hashable { case recent, oldest, longest, priciest }
enum TripFilter: String, Hashable { case all, mechanical, electrical }

/// dashboard.tsx `TripsPage`: Type de vélo, Trier par, the count, ten trips at a time.
struct TripsPage: View {
    let data: Dashboard
    @Environment(AppModel.self) private var model
    @State private var filter = TripFilter.all
    @State private var sort = TripSort.recent
    @State private var limit = 10

    var body: some View {
        if let all = data.trips {
            let trips = sorted(all.filter { filter == .all || $0.bikeType.rawValue == filter.rawValue })
            VStack(alignment: .leading, spacing: 0) {
                StatsLink().padding(.bottom, 20)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SelectField(label: "Type de vélo", hideLabel: true, value: $filter, options: [
                            .init(value: .all, label: "Tous les vélos"), .init(value: .mechanical, label: "Vélos mécaniques"), .init(value: .electrical, label: "Vélos électriques")
                        ])
                        Spacer(minLength: 8)
                        Text(verbatim: "\(trips.count) trajet\(trips.count > 1 ? "s" : "")").typo(.label(13)).foregroundStyle(Palette.inkMuted)
                    }
                    .zIndex(2)
                    SelectField(label: "Trier par", value: $sort, options: [
                        .init(value: .recent, label: "Plus récents"), .init(value: .oldest, label: "Plus anciens"),
                        .init(value: .longest, label: "Plus longs"), .init(value: .priciest, label: "Plus chers")
                    ])
                    .zIndex(1)
                }
                .zIndex(1)
                .padding(.bottom, 20)
                .onChange(of: filter) { limit = 10 }
                .onChange(of: sort) { limit = 10 }
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

    private func sorted(_ trips: [Trip]) -> [Trip] {
        switch sort {
        case .recent: trips
        case .oldest: trips.reversed()
        case .longest: trips.sorted { ($0.duration ?? -1) > ($1.duration ?? -1) }
        case .priciest: trips.sorted { ($0.price ?? -1) > ($1.price ?? -1) }
        }
    }
}

/// `TripsTable` in its phone layout; a tap opens the trip sheet.
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
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    TripIcon(electrical: trip.bikeType == .electrical)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(trip.startStation ?? "Trajet Vélo’v").typo(.body(13, medium: true)).foregroundStyle(Palette.ink).lineLimit(1)
                        Text(trip.endStation ?? (trip.bikeType == .electrical ? "Électrique" : trip.bikeType == .mechanical ? "Mécanique" : "Stations non renseignées"))
                            .typo(.body(11)).foregroundStyle(Palette.inkSoft).lineLimit(1)
                    }
                }
                HStack(spacing: 5) {
                    Text(formatDate(trip.startedAt)).typo(.body(11))
                    Text(formatDate(trip.startedAt, .time)).typo(.body(11))
                }
                .foregroundStyle(Palette.inkSoft)
                .padding(.leading, 42)
            }
            Spacer(minLength: 0)
            Text(trip.duration.map { "\(Int($0)) min" } ?? "—").typo(.body(11)).foregroundStyle(Palette.inkSoft).frame(width: 43, alignment: .leading)
            Text(trip.price.map(formatPrice) ?? "—").typo(.body(12)).foregroundStyle(Palette.ink).frame(width: 59, alignment: .trailing)
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }
}
