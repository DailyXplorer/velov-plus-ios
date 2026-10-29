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
    private var blocked: Bool { pending && model.operations.sending }
    private var uncertain: Outcome? { operation?.status == .uncertain ? operation?.outcome : nil }
    private var shown: Outcome? { uncertain ?? outcome }
    private var settled: Bool { shown.map { $0.ok || $0.isUncertain } == true || verification == .debited }

    private var canObtain: Bool {
        guard let cost, let balance, key != nil, operationKey != nil else { return false }
        return cost >= 0 && balance >= cost
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Inviter un ami").typo(.caps(13)).foregroundStyle(Palette.inkSoft)
                    Text("Échangez vos points contre un code à offrir à un ami.").typo(.body(13)).foregroundStyle(Palette.inkSoft)
                    if cost == nil {
                        SoonNote(text: "L’offre est momentanément indisponible.")
                    } else if let cost, let balance, balance < cost {
                        SoonNote(text: "Il vous manque \(formatNumber(cost - balance)) points.")
                    }
                }
                Spacer(minLength: 0)
                PillButton(codes.isEmpty ? "Obtenir un code" : "Obtenir un autre code", variant: .secondary) { open() }
                    .disabled(operation == nil && !canObtain)
            }
            .padding(.leading, 20).padding(.trailing, 16).padding(.vertical, 18)
            .background(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous).fill(Palette.mist))
            codeList.padding(.top, 16)
            if !asking, let warning { FormError(warning).padding(.top, 10) }
        }
        .task(id: account) { load() }
        .sheet(isPresented: $asking, onDismiss: closed) { sheet }
    }

    @ViewBuilder
    private var codeList: some View {
        if !codes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Code à transmettre à votre ami").typo(.caps(13)).foregroundStyle(Palette.inkSoft)
                ForEach(codes, id: \.code) { entry in
                    HStack(spacing: 12) {
                        Text(entry.code).typo(.label(15)).foregroundStyle(Palette.ink).textSelection(.enabled)
                        Spacer(minLength: 0)
                        PillButton(variant: .secondary, action: { copy(entry.code) }) { Icon(.copy, .light, size: 16); Text(copied == entry.code ? "Copié" : "Copier") }
                    }
                }
                SoonNote(text: "Enregistré sur ce téléphone.")
            }
        }
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeading(title: "Échanger \(formatNumber(cost ?? 0)) points ?", closeDisabled: blocked) { close() }
            Text("Les \(formatNumber(cost ?? 0)) points sont débités dès la création du code, même s’il n’est jamais utilisé.")
                .typo(.body(15)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
            if verification == .debited {
                FormError("Vos points ont été débités, mais aucun code n’a été reçu. Contactez le service client pour le récupérer.").padding(.top, 14)
            } else if let shown {
                VStack(alignment: .leading, spacing: 6) {
                    if shown.ok {
                        Text("Code créé. Copiez-le pour l’envoyer à votre ami.").typo(.body(15)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    } else {
                        FormError(shown.message ?? "Le code n’a pas pu être créé.")
                        RawStatus(line: messageLine(shown))
                    }
                    if shown.isUncertain { UncertainNote().padding(.top, 4) }
                    codeList.padding(.top, 8)
                }
                .padding(.top, 14)
            }
            Group {
                switch verification {
                case .notDebited?: SoonNote(text: "Votre historique complet ne montre aucun débit de \(formatNumber(operationCost)) points depuis la demande.")
                case .unknown?: SoonNote(text: "Votre historique de points ne permet pas encore d’exclure un débit. Vérifiez de nouveau dans quelques minutes ou écrivez au service client.")
                case .failed?: FormError("Votre historique de points n’a pas pu être lu. Réessayez dans un instant.")
                default: EmptyView()
                }
            }
            .padding(.top, 12)
            if uncertain != nil || verification == .debited { TextButton(title: "Écrire au service client", action: contact).padding(.top, 8) }
            if let warning { FormError(warning).padding(.top, 12) }
            PairedActions {
                PillButton(settled ? "Fermer" : "Annuler", variant: .ghost, fullWidth: true) { close() }.disabled(blocked)
                if uncertain != nil, verification == .notDebited {
                    PillButton("Je n’ai pas été débité, réessayer", fullWidth: true) { retry() }
                } else if uncertain != nil {
                    PillButton("Vérifier mes points", variant: .secondary, pending: verification == .checking, fullWidth: true) { verify() }
                } else if !settled {
                    PillButton("Confirmer", pending: pending, fullWidth: true) { confirm() }.disabled(!canObtain)
                }
            }
            .padding(.top, 24)
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 20)
        .fitSheet()
        .interactiveDismissDisabled(blocked)
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
            let result = await model.operations.runOnce(operationKey, keep: true, meta: meta) {
                let answer: PromoResult
                do {
                    answer = try await model.service.consumePromoCode(expectedCost: cost)
                } catch let error as VelovError {
                    answer = PromoResult(outcome: Outcome(ok: false, httpStatus: error.code == .expired ? 401 : 0, code: "local.\(error.code.rawValue)", message: error.message), promoCode: nil)
                } catch {
                    answer = PromoResult(outcome: noAnswer("Vélo’v ne répond pas. Vos points ont peut-être été débités."), promoCode: nil)
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
            case .unsaved: warning = Messages.unsaved
            case .busy: if model.operations.get(operationKey) == nil { warning = Messages.busy }
            case .finished(let answer):
                Haptics.result(answer.ok)
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
        copied = code
        Haptics.result(true)
    }
}
