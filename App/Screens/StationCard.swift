import MapKit
import SwiftUI
import VelovCore

struct StationCard: View {
    let station: Station
    let favorite: Bool
    let distance: Double?
    let close: () -> Void
    @Environment(\.floatingRadius) private var radius
    @Environment(AppModel.self) private var model
    @State private var bikesOpen = false
    @State private var favoriteOpen = false
    @State private var wasFavorite = false

    private static let pill = Layout.control

    var body: some View {
        let padding = max(radius - Self.pill / 2, Space.cardCompact)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(station.name).typo(.title(.small)).foregroundStyle(Palette.ink).lineLimit(1)
                IconButton(icon: .star, weight: favorite ? .fill : .light, color: favorite ? Palette.red : Palette.inkSoft,
                           label: favorite ? "Retirer des favoris" : "Ajouter aux favoris") {
                    if model.isGuest {
                        Haptics.selection()
                        model.setGuestFavorite(station.number, !favorite)
                    } else {
                        wasFavorite = favorite
                        favoriteOpen = true
                    }
                }
                    .accessibilityAddTraits(favorite ? .isSelected : [])
                    .padding(.leading, Layout.bleed + Space.pair)
                Spacer(minLength: Space.label)
                if !station.open { Text("Fermée").typo(.caps(.label)).foregroundStyle(Palette.inkSoft).fixedSize() }
                IconButton(icon: .x, label: "Fermer", action: close).bleed(.trailing)
            }
            HStack(spacing: Space.titleToContent) {
                StationNumbers(station: station, compact: true)
                if let distance { Text(formatDistance(distance)).typo(.body(.small)).foregroundStyle(Palette.inkSoft).lineLimit(1).fixedSize() }
                Spacer(minLength: 0)
            }
            HStack(spacing: Space.cards) {
                PillButton(variant: .primary, fullWidth: true, action: { bikesOpen = true }) { Text("Voir les vélos") }
                PillButton(variant: .secondary, fullWidth: true, action: directions) {
                    Text("Itinéraire")
                    CircleArrow(external: true, style: .outline)
                }
                .accessibilityHint("Ouvre Plans")
            }
            .padding(.top, Space.cards)
        }
        .padding(.horizontal, padding).padding(.top, max(padding + Layout.bleed, Space.pair)).padding(.bottom, padding)
        .floatingGlass(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .sheet(isPresented: $bikesOpen) { BikesSheet(station: station) }
        .sheet(isPresented: $favoriteOpen) {
            let key = OperationKey.favorite(station.number)
            let wanted = model.operations.get(key).flatMap { Intent.wanted($0.meta) } ?? !wasFavorite
            WriteDialog(title: !wanted ? "Retirer des favoris\u{a0}?" : "Ajouter aux favoris\u{a0}?", key: key, intent: Intent.wanted(wanted), run: {
                let outcome = await attempt { try await model.service.setFavorite(station: station.number, on: wanted) }
                if outcome.ok { model.setFavorite(station.number, wanted) }
                return outcome
            }, check: { intent in
                favoriteCheck(try await model.service.dashboard(), station: station.number, wanted: Intent.wanted(intent) ?? wanted)
            }, verified: { intent in
                model.setFavorite(station.number, Intent.wanted(intent) ?? wanted)
            })
        }
        .task(id: station.id) {
            if model.snapshot?.opensBikes == true {
                try? await Task.sleep(nanoseconds: 500_000_000)
                bikesOpen = true
            }
        }
    }

    private func directions() {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: station.lat, longitude: station.lon)))
        item.name = station.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
    }
}
