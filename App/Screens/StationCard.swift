import SwiftUI
import VelovCore

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
        let padding = max(radius - Self.pill / 2, 16)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(station.name).typo(.title(.small)).foregroundStyle(Palette.ink).lineLimit(1)
                IconButton(icon: .star, weight: favorite ? .fill : .light, size: 19, frame: 36, color: favorite ? Palette.red : Palette.inkSoft,
                           label: favorite ? "Retirer des favoris" : "Ajouter aux favoris") { wasFavorite = favorite; favoriteOpen = true }
                    .accessibilityAddTraits(favorite ? .isSelected : [])
                    .padding(.leading, -2)
                Spacer(minLength: 8)
                if !station.open { Text("Fermée").typo(.caps(.label)).foregroundStyle(Palette.inkSoft).fixedSize().padding(.trailing, 8) }
                IconButton(icon: .x, size: 18, frame: 36, label: "Fermer", action: close)
            }
            .padding(.trailing, -8)
            HStack(spacing: 18) {
                StationNumbers(station: station, compact: true)
                if let distance { Text(formatDistance(distance)).typo(.caps(.label)).foregroundStyle(Palette.inkSoft).lineLimit(1).fixedSize() }
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
            HStack(spacing: 8) {
                PillButton(variant: .secondary, height: Self.pill, fullWidth: true, action: { bikesOpen = true }) { Text("Voir les vélos") }
                PillButton(variant: .primary, height: Self.pill, fullWidth: true, action: directions) {
                    Text("Itinéraire")
                    CircleArrow(external: true, style: .onPrimary)
                }
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, padding).padding(.top, 14).padding(.bottom, padding)
        .floatingGlass(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .sheet(isPresented: $bikesOpen) { BikesSheet(station: station) }
        .sheet(isPresented: $favoriteOpen) {
            let key = OperationKey.favorite(station.number)
            let wanted = model.operations.get(key).flatMap { Intent.wanted($0.meta) } ?? !wasFavorite
            WriteDialog(title: !wanted ? "Retirer des favoris ?" : "Ajouter aux favoris ?", key: key, intent: Intent.wanted(wanted), run: {
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
            if model.snapshot == .bikeList || model.snapshot == .bikeSheet || model.snapshot == .bookConfirm {
                try? await Task.sleep(nanoseconds: 500_000_000)
                bikesOpen = true
            }
        }
    }

    private func directions() {
        if let url = URL(string: "maps://?daddr=\(station.lat),\(station.lon)&dirflg=w") { openURL(url) }
    }
}
