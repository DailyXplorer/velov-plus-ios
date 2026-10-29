import SwiftUI
import VelovCore

/// `.station-sheet` as a card floating over the map, above the tab bar: name, star and X; the three counts and the distance;
/// « Voir les vélos » and « Itinéraire ». All four corners take the tab bar's radius, the buttons' pills concentric with it.
struct StationCard: View {
    let station: Station
    let favorite: Bool
    let distance: Double?
    let close: () -> Void
    @Environment(\.openURL) private var openURL
    @Environment(\.floatingRadius) private var radius
    @Environment(AppModel.self) private var model
    @State private var bikesOpen = false
    @State private var favoriteOpen = false
    @State private var wasFavorite = false

    private static let pill: CGFloat = 40

    var body: some View {
        // The bottom pills' curves run parallel to the card's.
        let padding = max(radius - Self.pill / 2, 16)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(station.name).typo(.title(18)).foregroundStyle(Palette.ink).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                if !station.open { Text("Fermée").typo(.label(13)).foregroundStyle(Palette.inkSoft) }
                IconButton(icon: .star, weight: favorite ? .fill : .light, size: 19, frame: 36, color: favorite ? Palette.red : Palette.inkSoft,
                           label: favorite ? "Retirer des favoris" : "Ajouter aux favoris") { wasFavorite = favorite; favoriteOpen = true }
                    .accessibilityAddTraits(favorite ? .isSelected : [])
                IconButton(icon: .x, size: 18, frame: 36, label: "Fermer", action: close)
            }
            .padding(.trailing, -8)
            HStack(spacing: 12) {
                StationNumbers(station: station, compact: true)
                if let distance { Text(formatDistance(distance)).typo(.label(13)).foregroundStyle(Palette.inkSoft).fixedSize() }
            }
            .padding(.top, 2)
            HStack(spacing: 8) {
                PillButton(variant: .secondary, height: Self.pill, fullWidth: true, action: { bikesOpen = true }) { Text("Voir les vélos").typo(.label(13)) }
                PillButton(variant: .primary, height: Self.pill, fullWidth: true, action: directions) {
                    Text("Itinéraire").typo(.label(13))
                    CircleArrow(external: true, style: .onPrimary)
                }
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, padding).padding(.top, 14).padding(.bottom, padding)
        .ringed(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .sheet(isPresented: $bikesOpen) { BikesSheet(station: station) }
        .sheet(isPresented: $favoriteOpen) {
            WriteDialog(title: wasFavorite ? "Retirer des favoris ?" : "Ajouter aux favoris ?") { [wasFavorite] in
                let outcome = await attempt { try await model.service.setFavorite(station: station.number, on: !wasFavorite) }
                if outcome.ok { model.setFavorite(station.number, !wasFavorite) }
                return outcome
            }
        }
        .task(id: station.id) {
            if model.snapshot == .bikeList || model.snapshot == .bikeSheet || model.snapshot == .bookConfirm {
                try? await Task.sleep(nanoseconds: 500_000_000)
                bikesOpen = true
            }
        }
    }

    /// Walking directions in Apple Plans.
    private func directions() {
        if let url = URL(string: "maps://?daddr=\(station.lat),\(station.lon)&dirflg=w") { openURL(url) }
    }
}
