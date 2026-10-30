import SwiftUI
import VelovCore

struct ViaSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected: Int?
    @State private var position: GeoPoint?
    @State private var locating = false
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
    private var blocked: Bool { model.operations.sending }

    var body: some View {
        Group {
            if reviewing || held != nil, let target {
                review(target)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    SheetHeading(title: "15 minutes de plus", closeDisabled: blocked) { close() }
                    pick.padding(.top, Space.titleToContent)
                }
                .padding(Layout.dialog)
                .velovSheet(.fit, closeDisabled: blocked)
            }
        }
        .task {
            guard [.viaChosen, .viaReview, .viaUncertain].contains(model.snapshot) else { return }
            try? await Task.sleep(for: .seconds(1.5))
            guard let station = choices.first else { return }
            selected = station.number
            if model.snapshot == .viaChosen { return }
            reviewing = true
            if model.snapshot == .viaUncertain { confirm((station.number, station.name)) }
        }
    }

    private func review(_ station: (number: Int, name: String)) -> some View {
        ConfirmScaffold(title: "15 minutes de plus", closeDisabled: blocked, close: { close() }) {
            Text("La station ") + Text(verbatim: "\(station.name) (N°\u{a0}\(station.number))").fontWeight(.semibold)
                + Text(" est pleine. Demander 15 minutes de plus pour rejoindre une autre station\u{a0}?")
        } extra: {
            if let failure {
                FailureBlock(message: failure.message ?? "Les 15 minutes supplémentaires n’ont pas été accordées.",
                             uncertain: failure.isUncertain)
            }
            if let notice { FormError(notice) }
        } actions: {
            if failure?.isUncertain == true {
                PillButton("Fermer", variant: .ghost, fullWidth: true) { close() }.disabled(blocked)
            } else {
                PillButton("Retour", variant: .ghost, fullWidth: true) { refused = nil; notice = nil; reviewing = false }.disabled(pending)
                PillButton("Confirmer", pending: pending, fullWidth: true) { confirm(station) }.disabled(operationKey == nil)
            }
        }
    }

    private var pick: some View {
        VStack(alignment: .leading, spacing: Space.cards) {
            Text("Choisissez la station pleine où vous vouliez rendre votre vélo.")
                .typo(.body(.lead)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: Space.label) {
                Text("Rechercher une station pleine").typo(.caps(.label)).foregroundStyle(Palette.inkSoft)
                TextField("", text: $query, prompt: Text("Nom, adresse ou numéro").foregroundStyle(Palette.inkSoft))
                    .typo(.body(.input)).foregroundStyle(Palette.ink).autocorrectionDisabled()
                    .fieldPill()
            }
            PillButton(variant: .ghost, pending: locating, action: locate) { ButtonIcon(.navigationArrow); Text("Les plus proches") }
                .padding(.leading, -Space.row)
            switch model.stations {
            case .loading:
                VStack(alignment: .leading, spacing: Space.label) {
                    Text("Station pleine").typo(.caps(.label))
                    Capsule().frame(height: Layout.control)
                }
                .skeleton(Radius.capsule)
            case .failed(let failure):
                ErrorNotice(failure: failure, pending: model.stationsPending) { Task { await model.loadStations() } }
            case .ready:
                if choices.isEmpty {
                    Text("Aucune station pleine ne correspond à votre recherche.").typo(.body(.base)).foregroundStyle(Palette.inkSoft)
                } else {
                    SelectField(label: "Station pleine", value: $selected, options: choices.map { item in
                        .init(value: item.number, label: "\(item.name) · N°\u{a0}\(item.number)\(position.map { " · \(formatDistance(haversine($0, item.point)))" } ?? "")")
                    }, layout: .stacked, autoOpen: model.snapshot == .viaChoices, placeholder: "Choisir une station")
                }
            }
            PairedActions {
                PillButton("Annuler", variant: .ghost, fullWidth: true) { close() }
                PillButton("Continuer", fullWidth: true) { reviewing = true }.disabled(target == nil)
            }
            .padding(.top, Space.actions - Space.cards)
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
            } catch {
                model.showToast(error as? LocationFailure ?? .unavailable)
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
            let result = await model.runOnce(operationKey, meta: ["number": String(station.number), "name": station.name]) {
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
