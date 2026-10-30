import MapKit
import SwiftUI
import VelovCore

struct StationMapView: View {
    let stations: [Station]
    var selected: String?
    @Binding var camera: MapCameraPosition
    var interactive = true
    var showsUser = false
    var attributionInset = Concentric.inset
    var onSelect: (String) -> Void = { _ in }
    var onBackground: () -> Void = {}

    static let lyon = MapCameraPosition.region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 45.7576, longitude: 4.832),
                                                                  span: MKCoordinateSpan(latitudeDelta: 0.022, longitudeDelta: 0.022)))

    @State private var zone: CGRect = .zero
    @State private var covered: Set<String> = []

    var body: some View {
        MapReader { proxy in
            Map(position: $camera, interactionModes: interactive ? [.pan, .zoom] : []) {
                ForEach(stations.filter { $0.id == selected || ($0.open && !covered.contains($0.id)) }) { station in
                    Annotation(station.name, coordinate: CLLocationCoordinate2D(latitude: station.lat, longitude: station.lon), anchor: .center) {
                        Button { onSelect(station.id) } label: { StationPin(total: station.bikes, selected: selected == station.id) }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(station.name), \(station.bikes) vélo\(station.bikes > 1 ? "s" : "")")
                            .accessibilityAddTraits(selected == station.id ? .isSelected : [])
                    }
                    .annotationTitles(.hidden)
                }
                if showsUser {
                    UserAnnotation { UserDot() }
                }
            }
            .onGeometryChange(for: CGRect.self, of: { MapAttribution.zone($0) }) { zone = $0 }
            .onMapCameraChange(frequency: .onEnd) { covered = covering(proxy) }
            .onChange(of: zone) { covered = covering(proxy) }
            .onChange(of: stations.map(\.id)) { covered = covering(proxy) }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
            .mapControls {}
            .safeAreaPadding(.horizontal, attributionInset - Layout.mapKitMargin)
            .onTapGesture { onBackground() }
            .background(Palette.mist)
        }
    }

    private func covering(_ proxy: MapProxy) -> Set<String> {
        Set(stations.filter { station in
            proxy.convert(CLLocationCoordinate2D(latitude: station.lat, longitude: station.lon), to: .local).map(zone.contains) ?? false
        }.map(\.id))
    }
}

private enum MapAttribution {
    static let size = CGSize(width: 145, height: 24)

    static func zone(_ proxy: GeometryProxy) -> CGRect {
        let width = Layout.mapKitMargin + size.width, height = Layout.mapKitMargin + size.height
        return CGRect(x: 0, y: proxy.size.height - height, width: width, height: height)
            .insetBy(dx: -StationPin.size / 2, dy: -StationPin.size / 2)
    }
}

struct StationPin: View {
    static let size: CGFloat = 28
    let total: Int
    let selected: Bool
    var body: some View {
        let size: CGFloat = selected ? 38 : Self.size
        Text(verbatim: "\(total)")
            .typo(.label(selected ? .small : .micro))
            .foregroundStyle(total == 0 && !selected ? Palette.inkSoft : Palette.white)
            .frame(width: size, height: size)
            .background(Circle().fill(total == 0 && !selected ? Palette.white : Palette.red))
            .overlay(Circle().strokeBorder(Palette.white, lineWidth: 2))
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .animation(Motion.standard, value: selected)
    }
}

struct UserDot: View {
    var body: some View {
        Circle().fill(Palette.white).frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(Palette.red, lineWidth: 3))
            .background(Circle().fill(Palette.inkLine).frame(width: 32, height: 32))
            .accessibilityElement()
            .accessibilityLabel("Votre position")
    }
}

struct StationNumbers: View {
    let station: Station
    var compact = false
    var body: some View {
        HStack(alignment: .top, spacing: compact ? Space.titleToContent : Space.actions) {
            count(.personSimpleBike, station.mechanical, "Mécaniques", size: 18)
            count(.lightning, station.electrical, "Électriques", size: 18)
            count(.letterCircleP, station.stands, "Places", size: 18)
        }
        .fixedSize()
    }

    private func count(_ icon: IconName, _ value: Int, _ label: String, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Space.pair) {
            HStack(spacing: Space.pair) {
                Icon(icon, .light, size: compact ? 16 : size).foregroundStyle(Palette.inkSoft)
                Text(verbatim: "\(value)").typo(.body(compact ? .small : .lead, medium: !compact)).foregroundStyle(Palette.ink)
            }
            if !compact { Text(label).typo(.caps(.label)).foregroundStyle(Palette.inkSoft).lineLimit(1) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label == "Places" ? "places libres" : label.lowercased())")
    }
}
