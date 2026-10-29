import CoreLocation
import MapKit
import SwiftUI
import VelovCore

struct StationsPage: View {
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
    @State private var barBand: CGFloat = 0
    @State private var cardHeight: CGFloat = 0
    @State private var toolbarBand: CGFloat = 0
    @State private var filtered: [Station] = []

    private var stations: [Station] { model.stations.value?.stations ?? [] }
    private var favorites: Set<Int> { Set(model.dashboard?.profile.favorites ?? []) }
    private var here: GeoPoint? { position.map { GeoPoint(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) } }
    private var ranking: StationRanking { StationRanking(stations: stations, query: query, filter: filter, favorites: favorites, here: here) }

    private var selected: Station? { filtered.first { $0.id == selectedId } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header(title: "Stations")
            Group {
                BookingBanners(bottom: 12)
                if !locationError.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(locationError).typo(.body(13)).foregroundStyle(Palette.notice)
                        if !locationRaw.isEmpty { RawStatus(line: locationRaw) }
                    }
                    .padding(.bottom, 12)
                }
                if case .failed(let message) = model.stations {
                    ErrorNotice(message: message, pending: model.stationsPending) { Task { await model.loadStations() } }
                        .padding(.bottom, 12)
                }
            }
            .padding(.horizontal, 22)
            map
        }
        .task(id: ranking) {
            let ranking = ranking
            let ranked = await Task.detached(priority: .userInitiated) { ranking.ranked() }.value
            if !Task.isCancelled { filtered = ranked }
        }
        .onLeaving(.stations) { searching = false }
        .task {
            if model.snapshot == .stationSheet || model.snapshot == .bikeList || model.snapshot == .bikeSheet || model.snapshot == .bookConfirm {
                try? await Task.sleep(nanoseconds: 600_000_000)
                select("2002")
            }
            if model.snapshot == .stationSheetLong {
                try? await Task.sleep(nanoseconds: 600_000_000)
                select("3003")
            }
        }
    }

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
            .floatingGlass(Capsule())
            Button { locate() } label: {
                ZStack {
                    if locating { Spinner() } else { Icon(.navigationArrow, .light, size: 18) }
                }
                .foregroundStyle(Palette.ink)
                .frame(width: 42, height: 42)
                .floatingGlass(Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .disabled(locating)
            .accessibilityLabel("Stations autour de moi")
        }
    }

    private var map: some View {
        ZStack(alignment: .top) {
            StationMapView(stations: filtered, selected: selectedId, camera: $camera, showsUser: position != nil) { select($0) }
                .safeAreaPadding(.top, toolbarBand)
                .safeAreaPadding(.bottom, barBand + (selected == nil ? 0 : cardHeight + Concentric.gap))
            VStack(alignment: .leading, spacing: 12) {
                toolbar
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { toolbarBand = $0 + 12 }
                    .zIndex(1)
                if !query.isEmpty, model.stations.value != nil { results }
            }
            .padding(.horizontal, 22)
            .padding(.top, 12)
        }
        .ignoresSafeArea(.keyboard)
        .ignoresSafeArea(.container, edges: .bottom)
        .onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.bottom }) { barBand = $0 }
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

    private func located(_ location: CLLocation) {
        position = location
        let here = GeoPoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
        let favorites = favorites
        let open = stations.filter { $0.open && $0.matches(filter, favorites: favorites) }.sorted { haversine(here, $0.point) < haversine(here, $1.point) }
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
        let padX = max(rect.width * 0.25, 400), padY = max(rect.height * 0.2, 400)
        rect = MKMapRect(x: rect.minX - padX, y: rect.minY - padY, width: rect.width + 2 * padX, height: rect.height + 2 * padY)
        withAnimation(.easeInOut(duration: 0.6)) { camera = .rect(rect) }
    }
}
