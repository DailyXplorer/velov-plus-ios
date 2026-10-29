import MapKit
import SwiftUI
import VelovCore

/// station-map.tsx on Apple Plans: muted standard style, red pins with the bike count, the user as a red-ringed dot.
struct StationMapView: View {
    let stations: [Station]
    var selected: String?
    @Binding var camera: MapCameraPosition
    var interactive = true
    var showsUser = false
    var onSelect: (String) -> Void = { _ in }

    static let lyon = MapCameraPosition.region(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 45.7576, longitude: 4.832),
                                                                  span: MKCoordinateSpan(latitudeDelta: 0.022, longitudeDelta: 0.022)))

    var body: some View {
        Map(position: $camera, interactionModes: interactive ? [.pan, .zoom] : []) {
            ForEach(stations.filter(\.open)) { station in
                Annotation(station.name, coordinate: CLLocationCoordinate2D(latitude: station.lat, longitude: station.lon), anchor: .center) {
                    StationPin(total: station.bikes, selected: selected == station.id)
                        .onTapGesture { onSelect(station.id) }
                        .accessibilityLabel("\(station.name), \(station.bikes) vélos")
                        .accessibilityAddTraits(.isButton)
                }
                .annotationTitles(.hidden)
            }
            if showsUser {
                UserAnnotation { UserDot() }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
        .mapControls {}
        .background(Palette.mist)
    }
}

/// `.station-pin`: 28 pt, white ring, red with the count; white when empty; larger once selected.
struct StationPin: View {
    let total: Int
    let selected: Bool
    var body: some View {
        let size: CGFloat = selected ? 38 : 28
        Text(verbatim: "\(total)")
            .typo(.label(selected ? 13 : 10))
            .foregroundStyle(total == 0 && !selected ? Palette.inkSoft : Palette.white)
            .frame(width: size, height: size)
            .background(Circle().fill(total == 0 && !selected ? Palette.white : Palette.red))
            .overlay(Circle().strokeBorder(Palette.white, lineWidth: 2))
            .shadow(color: Palette.ink.opacity(selected ? 0.28 : 0.16), radius: selected ? 6 : 2.5, y: 1)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.15), value: selected)
    }
}

/// `.user-position`: a white dot ringed in red with a soft halo.
struct UserDot: View {
    var body: some View {
        Circle().fill(Palette.white).frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(Palette.red, lineWidth: 3))
            .background(Circle().fill(Palette.red.opacity(0.16)).frame(width: 32, height: 32))
            .shadow(color: Palette.ink.opacity(0.2), radius: 2, y: 1)
    }
}

/// The three counts of a station: mechanical, electric, free stands.
struct StationNumbers: View {
    let station: Station
    var compact = false
    var body: some View {
        HStack(spacing: compact ? 10 : 8) {
            count(.personSimpleBike, station.mechanical, "Mécaniques", size: 18)
            count(.lightning, station.electrical, "Électriques", size: 17)
            count(.letterCircleP, station.stands, "Places libres", size: 18)
        }
    }

    private func count(_ icon: Ph, _ value: Int, _ label: String, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Icon(icon, .light, size: compact ? 16 : size).foregroundStyle(Palette.inkSoft)
                Text(verbatim: "\(value)").typo(.body(compact ? 13 : 15, medium: !compact)).foregroundStyle(Palette.ink)
            }
            if !compact { Text(label).typo(.label(10)).foregroundStyle(Palette.inkSoft) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label.lowercased())")
    }
}
