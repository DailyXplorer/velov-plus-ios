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
    @State private var awaiting: CLLocation?
    @State private var rankedFilter: StationFilter?
    @Environment(\.accessibilityReduceMotion) private var still
    @Environment(\.tabBarClearance) private var clearance
    @Environment(\.floatingFloor) private var floor
    @Environment(\.floatingRadius) private var floatingRadius
    @FocusState private var searching: Bool
    @State private var cardHeight: CGFloat = 0
    @State private var toolbarBand: CGFloat = 0
    @State private var filtered: [Station] = []

    private var stations: [Station] { model.stations.value?.stations ?? [] }
    private var favorites: Set<Int> { Set(model.favorites) }
    private var here: GeoPoint? { position.map { GeoPoint(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) } }
    private var ranking: StationRanking { StationRanking(stations: stations, query: query, filter: filter, favorites: favorites, here: here) }

    private var selected: Station? { filtered.first { $0.id == selectedId } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Header(title: "Stations")
            BookingBanners(bottom: Space.cards)
                .padding(.horizontal, Layout.margin)
            map
        }
        .task(id: ranking) {
            let ranking = ranking
            let ranked = await Task.detached(priority: .userInitiated) { ranking.ranked() }.value
            if !Task.isCancelled {
                filtered = ranked
                rankedFilter = ranking.filter
                if let id = selectedId, !ranked.contains(where: { $0.id == id }) { selectedId = nil }
            }
        }
        .onLeaving(.stations) { searching = false }
        .onChange(of: model.stationsPending) { resume() }
        .task {
            if model.snapshot == .stationSheet || model.snapshot == .guestStationSheet || model.snapshot?.opensBikes == true {
                try? await Task.sleep(nanoseconds: 600_000_000)
                select("2002")
            }
            switch model.snapshot {
            case .stationsSearch?: query = "Part"
            case .stationsEmptyFilter?: filter = .favorites
            case .locationError?: model.showToast(.denied)
            case .locationTimeout?: model.showToast(.timedOut)
            default: break
            }
            if model.snapshot == .stationSheetLong {
                try? await Task.sleep(nanoseconds: 600_000_000)
                select("3003")
            }
        }
    }

    private var toolbar: some View {
        HStack(spacing: Space.label) {
            HStack(spacing: 0) {
                HStack(spacing: Layout.iconGap) {
                    Icon(.magnifyingGlass, .light, size: 18).foregroundStyle(Palette.ink)
                    TextField("", text: $query, prompt: Text("Rechercher").foregroundStyle(Palette.inkSoft))
                        .typo(.body(.input)).foregroundStyle(Palette.ink).focused($searching).submitLabel(.search)
                        .onSubmit { searching = false }
                        .autocorrectionDisabled().accessibilityLabel("Rechercher une station")
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Icon(.x, .light, size: 16).foregroundStyle(Palette.ink).frame(width: 28, height: 28).background(Circle().fill(Palette.mist))
                                .frame(width: Layout.hit, height: Layout.hit).contentShape(Rectangle())
                        }
                        .buttonStyle(.press).accessibilityLabel("Effacer la recherche")
                        .bleed(.horizontal, visible: 28)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: Layout.control)
                .layoutPriority(1)
                SelectField(label: "Afficher", hideLabel: true, value: $filter, options: [
                    .init(value: .all, label: "Toutes les stations", short: "Toutes"), .init(value: .favorites, label: "Favorites"),
                    .init(value: .available, label: "Vélos disponibles", short: "Vélos dispo"),
                    .init(value: .electrical, label: "Vélos électriques", short: "Électriques"), .init(value: .stands, label: "Places libres", short: "Places")
                ], layout: .inline)
                .fixedSize()
            }
            .padding(.leading, Layout.fieldLeading).padding(.trailing, Space.label)
            .floatingGlass(Capsule())
            FloatingCircleButton(label: "Stations autour de moi", value: locating ? "Localisation en cours" : nil) { locate() } content: {
                if locating { Spinner() } else { Icon(.navigationArrow, .light, size: Layout.glyph) }
            }
            .disabled(locating)
        }
    }

    private var map: some View {
        ZStack(alignment: .top) {
            StationMapView(stations: filtered, selected: selectedId, camera: $camera, showsUser: position != nil, onSelect: { select($0) }) {
                searching = false
                selectedId = nil
            }
                .safeAreaPadding(.top, toolbarBand)
                .safeAreaPadding(.bottom, selected == nil ? clearance : floor + cardHeight)
                .ignoresSafeArea(.container, edges: .bottom)
            VStack(alignment: .leading, spacing: Space.cards) {
                toolbar
                    .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { toolbarBand = $0 + Space.cards }
                    .zIndex(1)
                if case .failed(let failure) = model.stations {
                    ErrorNotice(failure: failure, pending: model.stationsPending) { Task { await model.loadStations() } }
                        .padding(Space.cardCompact)
                        .ringed(RoundedRectangle(cornerRadius: floatingRadius, style: .continuous))
                }
                if !query.isEmpty, model.stations.value != nil { results }
                if query.isEmpty, filter != .all, rankedFilter == filter, filtered.isEmpty, model.stations.value != nil { emptyFilter }
            }
            .padding(.horizontal, Layout.margin)
            .padding(.top, Space.cards)
        }
        .ignoresSafeArea(.keyboard)
        .ignoresSafeArea(.container, edges: .bottom)
        .overlay(alignment: .bottom) {
            if let station = selected {
                StationCard(station: station, favorite: favorites.contains(station.number), distance: here.map { haversine($0, station.point) }) {
                    selectedId = nil
                }
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { cardHeight = $0 }
                .padding(.horizontal, Concentric.inset)
                .padding(.bottom, floor)
                .ignoresSafeArea(edges: .bottom)
                .transition(Motion.panelTransition(still: still))
            }
        }
        .animation(Motion.panel, value: selected?.id)
    }

    private var emptyFilter: some View {
        let message = Text("Aucune station pour ce filtre.").typo(.body(.small)).foregroundStyle(Palette.ink)
        let link = TextLink(title: "Toutes les stations") { filter = .all }.fixedSize()
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.cards) {
                message.fixedSize()
                Spacer(minLength: 0)
                link
            }
            VStack(alignment: .leading, spacing: 0) {
                message.fixedSize(horizontal: false, vertical: true).padding(.top, Space.cards)
                link
            }
        }
        .padding(.horizontal, Space.row)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floatingGlass(RoundedRectangle(cornerRadius: floatingRadius, style: .continuous))
    }

    private var results: some View {
        let shown = Array(filtered.prefix(6))
        let shape = RoundedRectangle(cornerRadius: floatingRadius, style: .continuous)
        return VStack(spacing: 0) {
            ForEach(shown) { station in
                Button {
                    query = ""
                    searching = false
                    select(station.id)
                } label: {
                    VStack(alignment: .leading, spacing: Space.pair) {
                        HStack(spacing: Space.label) {
                            Text(station.name).typo(.body(.base, medium: true)).foregroundStyle(Palette.ink).lineLimit(1)
                            if favorites.contains(station.number) { Icon(.star, .fill, size: 16).foregroundStyle(Palette.red) }
                            Spacer(minLength: 0)
                            Icon(.caretRight, .light, size: 16).foregroundStyle(Palette.inkSoft)
                        }
                        HStack(spacing: Space.label) {
                            Text(verbatim: "\(here.map { "\(formatDistance(haversine($0, station.point))) · " } ?? "")N°\u{a0}\(station.number)")
                                .typo(.body(.meta)).foregroundStyle(Palette.inkSoft)
                            if !station.open { Text("Fermée").typo(.caps(.label)).foregroundStyle(Palette.inkSoft) }
                        }
                    }
                    .padding(.horizontal, Space.row).padding(.vertical, Space.row)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.row(bleed: 0))
            }
            if shown.isEmpty { Text("Aucune station trouvée.").typo(.body(.small)).foregroundStyle(Palette.inkSoft).frame(maxWidth: .infinity, alignment: .leading).padding(Space.row) }
        }
        .padding(Space.label)
        .clipShape(shape)
        .ringed(shape)
    }

    private func select(_ id: String) {
        Haptics.selection()
        selectedId = id
        guard let station = stations.first(where: { $0.id == id }) else { return }
        withAnimation(still ? nil : Motion.camera) {
            camera = .camera(MapCamera(centerCoordinate: CLLocationCoordinate2D(latitude: station.lat, longitude: station.lon), distance: 1800))
        }
    }

    private func locate() {
        locating = true
        Task {
            defer { locating = false }
            do {
                let location = try await Locator.shared.locate()
                guard case .loading = model.stations else { return located(location) }
                awaiting = location
                await model.loadStations()
                resume()
            } catch {
                model.showToast(error as? LocationFailure ?? .unavailable)
            }
        }
    }

    private func resume() {
        guard !model.stationsPending, let location = awaiting else { return }
        awaiting = nil
        located(location)
    }

    private func located(_ location: CLLocation) {
        position = location
        let here = GeoPoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude)
        let favorites = favorites
        let open = stations.filter { $0.open && $0.matches(filter, favorites: favorites) }.sorted { haversine(here, $0.point) < haversine(here, $1.point) }
        let supplied = open.filter { filter == .stands ? $0.stands > 0 : $0.bikes > 0 }.prefix(3)
        var failure: String?
        if case .failed(let reason) = model.stations { failure = reason.message }
        if let message = locateMessage(failure: failure, supplied: !supplied.isEmpty) { return model.showToast(message) }
        guard let nearest = supplied.first else { return }
        selectedId = nearest.id
        let points = [here, nearest.point] + supplied.map(\.point)
        var rect = MKMapRect.null
        for point in points {
            let mapPoint = MKMapPoint(CLLocationCoordinate2D(latitude: point.lat, longitude: point.lon))
            rect = rect.union(MKMapRect(x: mapPoint.x, y: mapPoint.y, width: 0, height: 0))
        }
        let padX = max(rect.width * 0.25, 400), padY = max(rect.height * 0.2, 400)
        rect = MKMapRect(x: rect.minX - padX, y: rect.minY - padY, width: rect.width + 2 * padX, height: rect.height + 2 * padY)
        withAnimation(still ? nil : Motion.camera) { camera = .rect(rect) }
    }
}
