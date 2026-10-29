import SwiftUI
import VelovCore

struct ViaAction: View {
    @State private var open = false

    var body: some View {
        PillButton(variant: .secondary, action: { open = true }) { Icon(.timer, .light, size: 17); Text("15 minutes de plus") }
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
    @State private var locationRaw = ""
    @State private var reviewing = false
    @State private var pending = false
    @State private var failure: Outcome?

    private var choices: [Station] { fullStations(model.stations.value?.stations ?? [], query: query, position: position) }
    private var station: Station? { choices.first { $0.number == selected } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeading(title: "15 minutes de plus", closeDisabled: pending) { dismiss() }
            Group {
                if reviewing, let station { review(station) } else { pick }
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 20)
        .fitSheet()
        .interactiveDismissDisabled(pending)
    }


    private func review(_ station: Station) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("La station ") + Text(verbatim: "\(station.name) (n° \(station.number))").fontWeight(.semibold)
             + Text(" est pleine. Demander 15 minutes de plus pour rejoindre une autre station ?"))
                .typo(.body(15)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            if let failure {
                VStack(alignment: .leading, spacing: 6) {
                    FormError(failure.message ?? "Les 15 minutes supplémentaires n’ont pas été accordées.")
                    RawStatus(outcome: failure)
                    if failure.isUncertain { UncertainNote().padding(.top, 4) }
                }
                .padding(.top, 14)
            }
            PairedActions {
                if failure?.isUncertain == true {
                    PillButton("Fermer", variant: .ghost, fullWidth: true) { dismiss() }
                } else {
                    PillButton("Retour", variant: .ghost, fullWidth: true) { failure = nil; reviewing = false }.disabled(pending)
                    PillButton("Confirmer", pending: pending, fullWidth: true) { confirm(station) }
                }
            }
            .padding(.top, 24)
        }
    }

    private var pick: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choisissez la station pleine où vous vouliez rendre votre vélo.")
                .typo(.body(15)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Rechercher une station pleine").typo(.label(13)).foregroundStyle(Palette.inkSoft)
                TextField("", text: $query, prompt: Text("Nom, adresse ou numéro").foregroundStyle(Palette.inkSoft))
                    .typo(.body(16)).foregroundStyle(Palette.ink).autocorrectionDisabled()
                    .fieldPill()
            }
            PillButton("Les plus proches", variant: .ghost, pending: locating) { locate() }
            if !locationError.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    SoonNote(text: locationError)
                    if !locationRaw.isEmpty { RawStatus(line: locationRaw) }
                }
            }
            if choices.isEmpty {
                Text("Aucune station pleine ne correspond à votre recherche.").typo(.body(14)).foregroundStyle(Palette.inkSoft)
            } else {
                VStack(spacing: 0) {
                    ForEach(choices.prefix(8)) { item in
                        Button { selected = item.number } label: {
                            Text(verbatim: "\(item.name) · N° \(item.number)\(position.map { " · \(formatDistance(haversine($0, item.point)))" } ?? "")")
                                .typo(.body(14)).foregroundStyle(selected == item.number ? Palette.red : Palette.ink).multilineTextAlignment(.leading)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 12).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected == item.number ? .isSelected : [])
                        Hairline(color: Palette.inkLine)
                    }
                }
            }
            PairedActions {
                PillButton("Annuler", variant: .ghost, fullWidth: true) { dismiss() }
                PillButton("Continuer", fullWidth: true) { reviewing = true }.disabled(station == nil)
            }
            .padding(.top, 12)
        }
    }

    private func locate() {
        locating = true
        Task {
            defer { locating = false }
            do {
                let here = try await Locator.shared.locate()
                position = GeoPoint(lat: here.coordinate.latitude, lon: here.coordinate.longitude)
                locationError = ""
                locationRaw = ""
            } catch let error as Locator.Failure {
                locationError = error.message
                locationRaw = error.raw
            } catch {
                locationError = "Position indisponible. Recherchez une station par son nom."
            }
        }
    }

    private func confirm(_ station: Station) {
        guard !pending else { return }
        Haptics.confirm()
        pending = true
        failure = nil
        Task {
            let outcome = await attempt { try await model.service.requestExtraTime(stationNumber: station.number) }
            Haptics.result(outcome.ok)
            pending = false
            if outcome.ok { dismiss() } else { failure = outcome }
        }
    }
}
