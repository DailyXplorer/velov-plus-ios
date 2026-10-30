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
    @State private var refused: Outcome?
    @State private var notice: String?

    private var choices: [Station] { fullStations(model.stations.value?.stations ?? [], query: query, position: position) }
    private var operationKey: String? {
        guard let digest = model.operations.digest, let tripId = model.dashboard?.ongoing?.first?.id else { return nil }
        return OperationKey.via(digest, tripId: tripId)
    }
    private var operation: Operations.Entry? { operationKey.flatMap { model.operations.get($0) } }
    private var held: (number: Int, name: String)? {
        guard let operation, let number = Int(operation.meta["number"] ?? "") else { return nil }
        return (number, operation.meta["name"] ?? "")
    }
    private var target: (number: Int, name: String)? {
        if let held { return held }
        return choices.first { $0.number == selected }.map { ($0.number, $0.name) }
    }
    private var failure: Outcome? { operation?.outcome ?? refused }
    private var pending: Bool { operation?.status == .sending }
    private var blocked: Bool { pending && model.operations.sending }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeading(title: "15 minutes de plus", closeDisabled: blocked) { close() }
            Group {
                if reviewing || held != nil, let target { review(target) } else { pick }
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 20)
        .fitSheet()
        .interactiveDismissDisabled(blocked)
    }

    private func review(_ station: (number: Int, name: String)) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("La station ") + Text(verbatim: "\(station.name) (n° \(station.number))").fontWeight(.semibold)
             + Text(" est pleine. Demander 15 minutes de plus pour rejoindre une autre station\u{a0}?"))
                .typo(.body(.lead)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            if let failure {
                VStack(alignment: .leading, spacing: 6) {
                    FormError(failure.message ?? "Les 15 minutes supplémentaires n’ont pas été accordées.")
                    RawStatus(line: messageLine(failure))
                    if failure.isUncertain { UncertainNote().padding(.top, 4) }
                }
                .padding(.top, 14)
            }
            if let notice { FormError(notice).padding(.top, 12) }
            PairedActions {
                if failure?.isUncertain == true {
                    PillButton("Fermer", variant: .ghost, fullWidth: true) { close() }
                } else {
                    PillButton("Retour", variant: .ghost, fullWidth: true) { refused = nil; notice = nil; reviewing = false }.disabled(pending)
                    PillButton("Confirmer", pending: pending, fullWidth: true) { confirm(station) }.disabled(operationKey == nil)
                }
            }
            .padding(.top, 24)
        }
    }

    private var pick: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choisissez la station pleine où vous vouliez rendre votre vélo.")
                .typo(.body(.lead)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Rechercher une station pleine").typo(.caps(.label)).foregroundStyle(Palette.inkSoft)
                TextField("", text: $query, prompt: Text("Nom, adresse ou numéro").foregroundStyle(Palette.inkSoft))
                    .typo(.body(.input)).foregroundStyle(Palette.ink).autocorrectionDisabled()
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
                Text("Aucune station pleine ne correspond à votre recherche.").typo(.body(.base)).foregroundStyle(Palette.inkSoft)
            } else {
                SelectField(label: "Station pleine", hideLabel: true, value: $selected, options: [.init(value: nil, label: "Choisir une station")] + choices.map { item in
                    .init(value: item.number, label: "\(item.name) · N° \(item.number)\(position.map { " · \(formatDistance(haversine($0, item.point)))" } ?? "")")
                }, layout: .stacked)
                .zIndex(2)
            }
            PairedActions {
                PillButton("Annuler", variant: .ghost, fullWidth: true) { close() }
                PillButton("Continuer", fullWidth: true) { reviewing = true }.disabled(target == nil)
            }
            .padding(.top, 12)
        }
    }

    private func close() {
        guard !model.operations.sending else { return }
        dismiss()
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
                locationError = "Localisation indisponible. Recherchez une station par son nom."
            }
        }
    }

    private func confirm(_ station: (number: Int, name: String)) {
        guard let operationKey, !pending else { return }
        Haptics.confirm()
        refused = nil
        notice = nil
        let model = model
        Task {
            let result = await model.operations.runOnce(operationKey, meta: ["number": String(station.number), "name": station.name]) {
                await attempt { try await model.service.requestExtraTime(stationNumber: station.number) }
            }
            switch result {
            case .unsaved: notice = Messages.unsaved
            case .busy: if model.operations.get(operationKey) == nil { notice = Messages.busy }
            case .finished(let outcome):
                Haptics.result(outcome)
                if outcome.ok {
                    reviewing = false
                    selected = nil
                    query = ""
                    dismiss()
                } else if !outcome.isUncertain {
                    refused = outcome
                }
            }
        }
    }
}
