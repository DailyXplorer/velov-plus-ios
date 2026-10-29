import CoreLocation
import MapKit
import SwiftUI
import VelovCore

enum StationFilter: String, Hashable { case all, favorites, available, electrical, stands }

func matches(_ station: Station, _ filter: StationFilter, favorites: Set<Int>) -> Bool {
    switch filter {
    case .all: true
    case .favorites: favorites.contains(station.number)
    case .available: station.bikes > 0
    case .electrical: station.electrical > 0
    case .stands: station.stands > 0
    }
}

/// dashboard.tsx `StationsPage` on a phone: search with the filter inside, Autour de moi, the map filling the screen, a card floating above the tab bar on selection.
struct StationsPage: View {
    let onLogout: () -> Void
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var filter = StationFilter.all
    @State private var selectedId: String?
    @State private var camera = StationMapView.lyon
    @State private var position: CLLocation?
    @State private var locating = false
    @State private var locationError = ""
    @State private var locationRaw = ""
    @FocusState private var searching: Bool
    /// The band the tab bar takes under the map, and the station card's height: MapKit's attribution stays above both.
    @State private var barBand: CGFloat = 0
    @State private var cardHeight: CGFloat = 0

    private var stations: [Station] { model.stations.value?.stations ?? [] }
    private var favorites: Set<Int> { Set(model.dashboard?.profile.favorites ?? []) }
    private var here: GeoPoint? { position.map { GeoPoint(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) } }

    /// Favourites first, then open stations, then the nearest (or by name).
    private var filtered: [Station] {
        let needle = fold(query)
        let favorites = favorites
        return stations.filter { (needle.isEmpty || fold("\($0.name) \($0.address) \($0.number)").contains(needle)) && matches($0, filter, favorites: favorites) }
            .sorted { left, right in
                let leftFavorite = favorites.contains(left.number), rightFavorite = favorites.contains(right.number)
                if leftFavorite != rightFavorite { return leftFavorite }
                if left.open != right.open { return left.open }
                if let here { return haversine(here, left.point) < haversine(here, right.point) }
                return left.name.compare(right.name, locale: Locale(identifier: "fr_FR")) == .orderedAscending
            }
    }

    private var selected: Station? { filtered.first { $0.id == selectedId } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header(title: "Stations")
            VStack(alignment: .leading, spacing: 12) {
                BookingBanners(bottom: 0)
                toolbar.zIndex(2)
                if !locationError.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(locationError).typo(.body(13)).foregroundStyle(Palette.notice)
                        if !locationRaw.isEmpty { RawStatus(line: locationRaw) }
                    }
                }
                if case .failed(let message) = model.stations {
                    ErrorNotice(message: message, pending: model.stationsPending) { Task { await model.loadStations() } }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 12)
            .zIndex(2)
            map
        }
        .task {
            if model.snapshot == .stationSheet || model.snapshot == .bikeList || model.snapshot == .bikeSheet || model.snapshot == .bookConfirm {
                try? await Task.sleep(nanoseconds: 600_000_000)
                select("2002")
            }
        }
    }

    /// One pill: the search, then the filter after a divider (its list under the pill's right edge); Autour de moi beside it.
    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                HStack(spacing: 10) {
                    Icon(.magnifyingGlass, .light, size: 19).foregroundStyle(Palette.ink)
                    TextField("", text: $query, prompt: Text("Rechercher").foregroundStyle(Palette.inkSoft))
                        .typo(.body(16)).foregroundStyle(Palette.ink).focused($searching).submitLabel(.search)
                        .autocorrectionDisabled().accessibilityLabel("Rechercher une station")
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Icon(.x, .light, size: 16).foregroundStyle(Palette.ink).frame(width: 28, height: 28).background(Circle().fill(Palette.mist))
                        }
                        .buttonStyle(.plain).accessibilityLabel("Effacer la recherche")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 42)
                .layoutPriority(1)
                SelectField(label: "Afficher", hideLabel: true, value: $filter, options: [
                    .init(value: .all, label: "Toutes les stations", short: "Toutes"), .init(value: .favorites, label: "Favorites"),
                    .init(value: .available, label: "Vélos disponibles", short: "Vélos dispo"),
                    .init(value: .electrical, label: "Vélos électriques", short: "Électriques"), .init(value: .stands, label: "Places libres", short: "Places")
                ], layout: .inline)
                .fixedSize()
            }
            .padding(.leading, 14).padding(.trailing, 7)
            .ringed(Capsule())
            Button { locate() } label: {
                ZStack {
                    if locating { Spinner() } else { Icon(.navigationArrow, .light, size: 18) }
                }
                .foregroundStyle(Palette.ink)
                .frame(width: 42, height: 42)
                .ringed(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(locating)
            .accessibilityLabel("Stations autour de moi")
        }
    }

    private var map: some View {
        ZStack(alignment: .top) {
            StationMapView(stations: filtered, selected: selectedId, camera: $camera, showsUser: position != nil) { select($0) }
                // MapKit's logo and legal link sit above the tab bar and the station card, never under them.
                .safeAreaPadding(.bottom, barBand + (selected == nil ? 0 : cardHeight + Concentric.gap))
            if !query.isEmpty, model.stations.value != nil { results.padding(12) }
        }
        .ignoresSafeArea(.keyboard)
        // The map runs down behind the floating tab bar, to the screen's edge.
        .ignoresSafeArea(.container, edges: .bottom)
        .onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.bottom }) { barBand = $0 }
        // The card floats `gap` above the tab bar, with its side insets; the bar stays in view.
        .overlay(alignment: .bottom) {
            if let station = selected {
                StationCard(station: station, favorite: favorites.contains(station.number), distance: here.map { haversine($0, station.point) }) {
                    selectedId = nil
                }
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { cardHeight = $0 }
                .padding(.horizontal, Concentric.inset)
                .padding(.bottom, Concentric.gap)
                .ignoresSafeArea(.keyboard)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.3), value: selected?.id)
    }

    /// The search shows a short results list over the map.
    private var results: some View {
        let shown = Array(filtered.prefix(6))
        return VStack(spacing: 0) {
            ForEach(shown) { station in
                Button {
                    query = ""
                    searching = false
                    select(station.id)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(station.name).typo(.body(14, medium: true)).foregroundStyle(Palette.ink).lineLimit(1)
                            if favorites.contains(station.number) { Icon(.star, .fill, size: 14).foregroundStyle(Palette.red) }
                            Spacer(minLength: 0)
                            Icon(.caretRight, .light, size: 16).foregroundStyle(Palette.inkSoft)
                        }
                        Text(verbatim: "\(here.map { "\(formatDistance(haversine($0, station.point))) · " } ?? "")N° \(station.number)\(station.open ? "" : " · Fermée")")
                            .typo(.body(12)).foregroundStyle(Palette.inkSoft)
                    }
                    .padding(.horizontal, 15).padding(.vertical, 16)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if shown.isEmpty { EmptyState("Aucune station trouvée.") }
        }
        .padding(6)
        .frame(maxWidth: 340)
        .ringed(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Pans on a new selection only: a refreshed station list must not move the map. The map's safe area already ends above
    /// the card, so the station lands in the middle of what stays visible.
    private func select(_ id: String) {
        selectedId = id
        guard let station = stations.first(where: { $0.id == id }) else { return }
        withAnimation(.easeInOut(duration: 0.5)) {
            camera = .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: station.lat, longitude: station.lon), distance: 1800))
        }
    }

    private func locate() {
        locationError = ""
        locationRaw = ""
        locating = true
        Task {
            defer { locating = false }
            do {
                let location = try await Locator.shared.locate()
                located(location)
            } catch let error as Locator.Failure {
                locationError = error.message
                locationRaw = error.raw
            } catch {
                locationError = "Impossible de vous localiser pour le moment."
            }
        }
    }

    /// Selects the nearest open station and frames it with the user and up to three stations that have what the filter asks for.
    private func located(_ location: CLLocation) {
        position = location
        let here = GeoPoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
        let favorites = favorites
        let open = stations.filter { $0.open && matches($0, filter, favorites: favorites) }.sorted { haversine(here, $0.point) < haversine(here, $1.point) }
        let supplied = open.filter { filter == .stands ? $0.stands > 0 : $0.bikes > 0 }.prefix(3)
        guard let nearest = open.first else {
            locationError = "Aucune station ouverte ne correspond à ce filtre."
            return
        }
        selectedId = nearest.id
        let points = [here, nearest.point] + supplied.map(\.point)
        var rect = MKMapRect.null
        for point in points {
            let mapPoint = MKMapPoint(CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon))
            rect = rect.union(MKMapRect(x: mapPoint.x, y: mapPoint.y, width: 0, height: 0))
        }
        // The map's safe area keeps the station card clear: the same margin all round.
        let padX = max(rect.width * 0.25, 400), padY = max(rect.height * 0.2, 400)
        rect = MKMapRect(x: rect.minX - padX, y: rect.minY - padY, width: rect.width + 2 * padX, height: rect.height + 2 * padY)
        withAnimation(.easeInOut(duration: 0.6)) { camera = .rect(rect) }
    }
}

/// Accent- and case-insensitive search text.
func fold(_ value: String) -> String {
    value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_FR")).trimmingCharacters(in: .whitespaces)
}
