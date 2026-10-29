import SwiftUI
import VelovCore

/// `.station-sheet`: name, star and X; the three counts and the distance; « Voir les vélos » and « Itinéraire ».
struct StationSheet: View {
    let station: Station
    let favorite: Bool
    let distance: Double?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppModel.self) private var model
    @State private var bikesOpen = false
    @State private var favoriteOpen = false
    @State private var wasFavorite = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(station.name).typo(.title(18)).foregroundStyle(Palette.ink).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                if !station.open { Text("Fermée").typo(.label(11)).foregroundStyle(Palette.inkSoft) }
                IconButton(icon: .star, weight: favorite ? .fill : .light, size: 19, frame: 36, color: favorite ? Palette.red : Palette.inkSoft,
                           label: favorite ? "Retirer des favoris" : "Ajouter aux favoris") { wasFavorite = favorite; favoriteOpen = true }
                    .accessibilityAddTraits(favorite ? .isSelected : [])
                IconButton(icon: .x, size: 18, frame: 36, label: "Fermer") { dismiss() }
            }
            HStack(spacing: 12) {
                StationNumbers(station: station, compact: true)
                if let distance { Text(formatDistance(distance)).typo(.label(11)).foregroundStyle(Palette.inkSoft).fixedSize() }
            }
            .padding(.trailing, 6)
            .padding(.top, 2)
            HStack(spacing: 8) {
                PillButton(variant: .secondary, height: 40, fullWidth: true, action: { bikesOpen = true }) { Text("Voir les vélos").typo(.label(12)) }
                PillButton(variant: .primary, height: 40, fullWidth: true, action: directions) {
                    Text("Itinéraire").typo(.label(12))
                    CircleArrow(external: true, style: .onPrimary)
                }
            }
            .padding(.top, 10)
            .padding(.trailing, 6)
        }
        // No bottom padding: the floating sheet keeps its own clearance above the home indicator.
        .padding(.leading, 16).padding(.trailing, 10).padding(.top, 14)
        // As tall as its content: no empty band under the buttons.
        .fitSheet(interactiveBackground: true)
        .sheet(isPresented: $bikesOpen) { BikesSheet(station: station) }
        .sheet(isPresented: $favoriteOpen) {
            WriteDialog(title: wasFavorite ? "Retirer des favoris ?" : "Ajouter aux favoris ?",
                        success: wasFavorite ? "Station retirée des favoris." : "Station ajoutée aux favoris.") { [wasFavorite] in
                let outcome = await attempt { try await model.service.setFavorite(station: station.number, on: !wasFavorite) }
                if outcome.ok { model.setFavorite(station.number, !wasFavorite) }
                return outcome
            } question: {
                Text(station.name) + Text(verbatim: "  n° \(station.number)").foregroundColor(Palette.inkSoft)
            }
        }
        .task {
            if model.snapshot == .bikeList || model.snapshot == .bikeSheet {
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
