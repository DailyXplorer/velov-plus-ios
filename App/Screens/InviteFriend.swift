import SwiftUI
import UIKit
import VelovCore

private let storageWarning = "Ce téléphone ne peut pas garder le code. Copiez-le maintenant."

struct InviteFriend: View {
    enum Verification { case checking, debited, notDebited, unknown, failed }

    let cost: Int?
    let balance: Int?
    let account: String
    @Environment(AppModel.self) private var model
    @State private var key: String?
    @State private var codes: [SavedPromo] = []
    @State private var warning: String?
    @State private var asking = false
    @State private var outcome: Outcome?
    @State private var verification: Verification?
    @State private var copied: String?

    private var operationKey: String? { model.operations.digest.map(OperationKey.invite) }
    private var operation: Operations.Entry? { operationKey.flatMap { model.operations.get($0) } }
    private var pending: Bool { operation?.status == .sending }
    private var blocked: Bool { model.operations.sending }
    private var uncertain: Outcome? { operation?.status == .uncertain ? operation?.outcome : nil }
    private var shown: Outcome? { uncertain ?? outcome }
    private var settled: Bool { shown.map { $0.ok || $0.isUncertain } == true || verification == .debited }

    private var canObtain: Bool {
        guard let cost, let balance, key != nil, operationKey != nil else { return false }
        return cost >= 0 && balance >= cost
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Space.label) {
                Text("Inviter un ami").typo(.caps(.label)).foregroundStyle(Palette.inkSoft)
                Text("Échangez vos points contre un code à offrir à un ami.").typo(.body(.small)).foregroundStyle(Palette.inkSoft)
                if cost == nil {
                    Note(text: "L’offre est momentanément indisponible.")
                } else if let cost, let balance, balance < cost {
                    Note(text: "Il vous manque \(formatNumber(cost - balance)) points.")
                }
                PillButton(variant: .secondary, action: open) { ButtonIcon(.ticket); Text(codes.isEmpty ? "Obtenir un code" : "Obtenir un autre code") }
                    .disabled(operation == nil && !canObtain)
                    .padding(.top, Space.label)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(.mist)
            codeList.padding(.top, Space.titleToContent)
            if !asking, let warning { FormError(warning).padding(.top, Space.cards) }
        }
        .task(id: account) {
            load()
            guard model.snapshot == .inviteDialog || model.snapshot == .inviteCode else { return }
            try? await Task.sleep(for: .seconds(1))
            open()
            guard model.snapshot == .inviteCode else { return }
            try? await Task.sleep(for: .seconds(0.8))
            confirm()
        }
        .task(id: copied) {
            guard copied != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            withAnimation(Motion.standard) { copied = nil }
        }
        .sheet(isPresented: $asking, onDismiss: closed) { sheet }
    }

    @ViewBuilder
    private var codeList: some View {
        if !codes.isEmpty {
            VStack(alignment: .leading, spacing: Space.label) {
                Text("Code à transmettre à votre ami").typo(.caps(.label)).foregroundStyle(Palette.inkSoft)
                ForEach(codes, id: \.code) { entry in
                    HStack(spacing: Space.cards) {
                        Text(entry.code).typo(.label(.lead)).foregroundStyle(Palette.ink).textSelection(.enabled)
                        Spacer(minLength: 0)
                        PillButton(variant: .secondary, action: { copy(entry.code) }) { ButtonIcon(.copy); Text(copied == entry.code ? "Copié" : "Copier") }
                    }
                }
                Note(text: "Enregistré sur ce téléphone.")
            }
        }
    }

    private var sheet: some View {
        let created = shown?.ok == true
        return ConfirmScaffold(title: created ? "Votre code" : "Obtenir un code\u{a0}?", closeDisabled: blocked, close: { close() }) {
            if !created { Text("\(formatNumber(cost ?? 0)) points sont débités dès la création du code, même s’il n’est jamais utilisé.") }
        } extra: {
            if verification == .debited {
                FormError("Vos points ont été débités, mais aucun code n’a été reçu. Contactez le service client pour le récupérer.")
            } else if let shown {
                VStack(alignment: .leading, spacing: 0) {
                    if shown.ok {
                        Text("Code créé. Copiez-le pour l’envoyer à votre ami.").typo(.body(.lead)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    } else {
                        FailureBlock(message: shown.message ?? "Le code n’a pas pu être créé.", uncertain: shown.isUncertain)
                    }
                    codeList.padding(.top, Space.label)
                }
            }
            switch verification {
            case .notDebited?: Note(text: "Votre historique complet ne montre aucun débit de \(formatNumber(operationCost)) points depuis la demande.")
            case .unknown?: Note(text: "Votre historique de points ne permet pas encore d’exclure un débit. Vérifiez de nouveau dans quelques minutes ou écrivez au service client.")
            case .failed?: FailureBlock(message: "Votre historique de points n’a pas pu être lu. Réessayez dans un instant.")
            default: EmptyView()
            }
            if uncertain != nil || verification == .debited { TextLink(title: "Écrire au service client", action: contact) }
            if let warning { FormError(warning) }
        } actions: {
            PillButton(settled ? "Fermer" : "Annuler", variant: .ghost, fullWidth: true) { close() }.disabled(blocked)
            if uncertain != nil, verification == .notDebited {
                PillButton("Je n’ai pas été débité, réessayer", fullWidth: true) { retry() }
            } else if uncertain != nil {
                PillButton("Vérifier mes points", variant: .secondary, pending: verification == .checking, fullWidth: true) { verify() }
            } else if !settled {
                PillButton("Confirmer", pending: pending, fullWidth: true) { confirm() }.disabled(!canObtain)
            }
        }
    }

    private func load() {
        let key = PromoStore.key(account: account)
        do {
            codes = try PromoStore.read(model.promoBacking, key: key)
            self.key = key
        } catch {
            warning = "Impossible de lire les codes enregistrés sur ce téléphone."
        }
    }

    private func open() {
        if operation == nil { outcome = nil }
        verification = nil
        asking = true
    }

    private func close() {
        guard !model.operations.sending else { return }
        asking = false
    }

    private func confirm() {
        guard let cost, let key, let operationKey, canObtain else { return }
        do { _ = try PromoStore.prepare(model.promoBacking, key: key) } catch {
            warning = "Ce téléphone ne peut pas enregistrer le code. Vos points n’ont pas été utilisés."
            return
        }
        Haptics.confirm()
        outcome = nil
        warning = nil
        verification = nil
        let model = model
        let meta = ["cost": String(cost)]
        Task {
            let result = await model.runOnce(operationKey, meta: meta) {
                let answer: PromoResult
                do {
                    answer = try await model.service.consumePromoCode(expectedCost: cost)
                } catch {
                    answer = PromoResult(outcome: await attempt { throw error }, promoCode: nil)
                }
                if let code = answer.promoCode {
                    do { codes = try PromoStore.save(model.promoBacking, key: key, code: code) } catch {
                        if !codes.contains(where: { $0.code == code }) { codes.append(SavedPromo(code: code, createdAt: ISO8601DateFormatter().string(from: Date()))) }
                        warning = storageWarning
                    }
                }
                return answer.outcome
            }
            switch result {
            case .superseded: break
            case .unsaved: warning = Messages.unsaved
            case .busy: if model.operations.get(operationKey) == nil { warning = Messages.busy }
            case .finished(let answer):
                Haptics.result(answer)
                outcome = answer
                if answer.ok || answer.isUncertain { model.statsChanged() }
            }
        }
    }

    private var operationCost: Int { operation.flatMap { Int($0.meta["cost"] ?? "") } ?? cost ?? 0 }

    private func verify() {
        guard let operation, operation.status == .uncertain, let operationKey, verification != .checking else { return }
        let before = DebitBefore(at: operation.at, cost: operationCost)
        verification = .checking
        let model = model
        Task {
            do {
                let ledger = try await model.service.rewardLedger()
                let check = inviteDebit(before, ledger: ledger, now: Date())
                if check == .debited { model.operations.clear(operationKey, held: operation) }
                verification = switch check {
                case .debited: .debited
                case .notDebited: .notDebited
                case .unknown: .unknown
                }
            } catch {
                verification = .failed
            }
        }
    }

    private func retry() {
        guard let operation, let operationKey, verification == .notDebited else { return }
        model.operations.clear(operationKey, held: operation)
        confirm()
    }

    private func contact() {
        asking = false
        model.contactRequested = true
        model.page = .account
    }

    private func closed() {
        if outcome != nil || verification != nil { Task { await model.loadDashboard() } }
        verification = nil
    }

    private func copy(_ code: String) {
        UIPasteboard.general.string = code
        withAnimation(Motion.standard) { copied = code }
        Haptics.success()
    }
}
