import SwiftUI
import VelovCore

/// via-action.tsx: « 15 minutes de plus » during a trip, to bring the bike back to another station when this one is full.
/// The station is chosen, reviewed, rechecked by the core before the one request; a result cannot be sent again.
struct ViaAction: View {
    @State private var open = false

    var body: some View {
        HStack(spacing: 10) {
            PillButton(variant: .secondary, action: { open = true }) { Icon(.timer, .light, size: 17); Text("15 minutes de plus") }
            ExperimentalTag()
        }
        .sheet(isPresented: $open) { ViaSheet() }
    }
}

private struct ViaSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected: Int?
    @State private var position: GeoPoint?
    @State private var locating = false
    @State private var locationError = ""
    @State private var reviewing = false
    @State private var pending = false
    @State private var result: Outcome?

    private var choices: [Station] { fullStations(model.stations.value?.stations ?? [], query: query, position: position) }
    private var station: Station? { choices.first { $0.number == selected } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeading(title: "15 minutes de plus", closeDisabled: pending) { dismiss() }
            ExperimentalTag().padding(.top, 2)
            Group {
                if let result { done(result) } else if reviewing, let station { review(station) } else { pick }
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 20)
        .fitSheet()
        .interactiveDismissDisabled(pending)
    }

    private func done(_ result: Outcome) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if result.ok {
                DoneLine(text: "Vélo’v a accepté la demande de minutes supplémentaires.")
            } else {
                FormError(result.message ?? "Vélo’v n’a pas accordé les 15 minutes supplémentaires.")
                RawStatus(outcome: result)
            }
            PillButton("Fermer", variant: .secondary) { dismiss() }.frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 18)
        }
    }

    private func review(_ station: Station) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("Demander 15 minutes supplémentaires pour rendre votre vélo à une autre station ? La station ")
             + Text(verbatim: "\(station.name) (n° \(station.number))").fontWeight(.semibold) + Text(" est pleine."))
                .typo(.body(15)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Spacer()
                PillButton("Retour", variant: .ghost) { reviewing = false }.disabled(pending)
                PillButton("Confirmer", pending: pending) { confirm(station) }
            }
            .padding(.top, 24)
        }
    }

    private var pick: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choisissez la station pleine où vous souhaitez rendre votre vélo. Sa disponibilité sera revérifiée avant l’envoi.")
                .typo(.body(15)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Rechercher une station pleine").typo(.label(11)).foregroundStyle(Palette.inkSoft)
                TextField("", text: $query, prompt: Text("Nom, adresse ou numéro").foregroundStyle(Palette.inkFaint))
                    .typo(.body(16)).foregroundStyle(Palette.ink).autocorrectionDisabled()
                    .padding(.horizontal, 11.25).frame(minHeight: 42)
                    .background(RoundedRectangle(cornerRadius: 5.625).fill(Palette.fieldFill))
                    .overlay(RoundedRectangle(cornerRadius: 5.625).strokeBorder(Palette.fieldLine, lineWidth: 1))
            }
            PillButton("Les plus proches", variant: .ghost, pending: locating) { locate() }
            if !locationError.isEmpty { SoonNote(text: locationError) }
            if choices.isEmpty {
                Text("Aucune station pleine ne correspond à votre recherche.").typo(.body(14)).foregroundStyle(Palette.inkSoft)
            } else {
                VStack(spacing: 0) {
                    ForEach(choices.prefix(8)) { item in
                        Button { selected = item.number } label: {
                            HStack(spacing: 10) {
                                Text(verbatim: "\(item.name) · n° \(item.number)\(position.map { " · \(formatDistance(haversine($0, item.point)))" } ?? "")")
                                    .typo(.body(14)).foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                if selected == item.number { Icon(.check, .bold, size: 15).foregroundStyle(Palette.red) }
                            }
                            .padding(.vertical, 12).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected == item.number ? .isSelected : [])
                        Hairline(color: Palette.inkLine)
                    }
                }
            }
            HStack(spacing: 10) {
                Spacer()
                PillButton("Annuler", variant: .ghost) { dismiss() }
                PillButton("Continuer") { reviewing = true }.disabled(station == nil)
            }
            .padding(.top, 12)
        }
    }

    private func locate() {
        locating = true
        Task {
            defer { locating = false }
            do {
                let here = try await Locator().locate()
                position = GeoPoint(lat: here.coordinate.latitude, lon: here.coordinate.longitude)
                locationError = ""
            } catch {
                locationError = "Position indisponible. Recherchez une station par son nom."
            }
        }
    }

    private func confirm(_ station: Station) {
        guard !pending, result == nil else { return }
        Haptics.confirm()
        pending = true
        Task {
            let outcome = await attempt { try await model.service.requestExtraTime(stationNumber: station.number) }
            Haptics.result(outcome.ok)
            result = outcome
            pending = false
        }
    }
}
