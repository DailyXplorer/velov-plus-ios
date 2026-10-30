import Foundation

public enum StationFilter: String, Hashable, Sendable { case all, favorites, available, electrical, stands }

private let french = Locale(identifier: "fr_FR")

public func fold(_ value: String) -> String {
    value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: french).trimmingCharacters(in: .whitespaces)
}

extension Station {
    public func matches(_ filter: StationFilter, favorites: Set<Int>) -> Bool {
        switch filter {
        case .all: true
        case .favorites: favorites.contains(number)
        case .available: bikes > 0
        case .electrical: electrical > 0
        case .stands: stands > 0
        }
    }
}

public func locateMessage(failure: String?, supplied: Bool) -> String? {
    failure ?? (supplied ? nil : "Aucune station ouverte ne correspond à ce filtre.")
}

public struct StationRanking: Equatable, Sendable {
    public var stations: [Station]
    public var query: String
    public var filter: StationFilter
    public var favorites: Set<Int>
    public var here: GeoPoint?

    public init(stations: [Station], query: String, filter: StationFilter, favorites: Set<Int>, here: GeoPoint?) {
        self.stations = stations; self.query = query; self.filter = filter; self.favorites = favorites; self.here = here
    }

    public func ranked() -> [Station] {
        let needle = fold(query)
        return stations
            .filter { (needle.isEmpty || fold("\($0.name) \($0.address) \($0.number)").contains(needle)) && $0.matches(filter, favorites: favorites) }
            .map { station in (station: station, favorite: favorites.contains(station.number), distance: here.map { haversine($0, station.point) }) }
            .sorted { left, right in
                if left.favorite != right.favorite { return left.favorite }
                if left.station.open != right.station.open { return left.station.open }
                if let leftDistance = left.distance, let rightDistance = right.distance { return leftDistance < rightDistance }
                return left.station.name.compare(right.station.name, locale: french) == .orderedAscending
            }
            .map(\.station)
    }
}
