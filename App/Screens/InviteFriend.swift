import SwiftUI
import UIKit
import VelovCore

private let storageWarning = "Ce téléphone ne peut pas garder le code. Copiez-le maintenant."

struct InviteFriend: View {
    let cost: Int?
    let balance: Int?
    let account: String
    @Environment(AppModel.self) private var model
    @State private var key: String?
    @State private var codes: [SavedPromo] = []
    @State private var warning: String?
    @State private var asking = false
    @State private var pending = false
    @State private var outcome: PromoResult?
    @State private var copied: String?

    private var settled: Bool { outcome.map { $0.outcome.ok || $0.outcome.isUncertain } ?? false }

    private var canObtain: Bool {
        guard let cost, let balance, key != nil else { return false }
        return cost >= 0 && balance >= cost
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Inviter un ami").typo(.label(13)).foregroundStyle(Palette.inkSoft)
                    Text("Échangez vos points contre un code à offrir à un ami.").typo(.body(13)).foregroundStyle(Palette.inkSoft)
                    if cost == nil {
                        SoonNote(text: "L’offre est momentanément indisponible.")
                    } else if let cost, let balance, balance < cost {
                        SoonNote(text: "Il vous manque \(cost - balance) points.")
                    }
                }
                Spacer(minLength: 0)
                PillButton(codes.isEmpty ? "Obtenir un code" : "Obtenir un autre code", variant: .secondary) { outcome = nil; asking = true }
                    .disabled(!canObtain || pending)
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
                Text("Code à transmettre à votre ami").typo(.label(13)).foregroundStyle(Palette.inkSoft)
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
            SheetHeading(title: "Échanger \(cost ?? 0) points ?", closeDisabled: pending) { asking = false }
            Text("Les \(cost ?? 0) points sont débités dès la création du code, même s’il n’est jamais utilisé.")
                .typo(.body(15)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
            if let outcome {
                VStack(alignment: .leading, spacing: 6) {
                    if outcome.outcome.ok {
                        DoneLine(text: "Code créé. Copiez-le pour l’envoyer à votre ami.")
                    } else {
                        FormError(outcome.outcome.message ?? "Le code n’a pas pu être obtenu.")
                        RawStatus(outcome: outcome.outcome)
                        if outcome.outcome.isUncertain { UncertainNote().padding(.top, 4) }
                    }
                    codeList.padding(.top, 8)
                }
                .padding(.top, 14)
            }
            if let warning { FormError(warning).padding(.top, 12) }
            PairedActions {
                PillButton(settled ? "Fermer" : "Annuler", variant: .ghost, fullWidth: true) { asking = false }.disabled(pending)
                if !settled { PillButton("Confirmer", pending: pending, fullWidth: true) { confirm() }.disabled(!canObtain) }
            }
            .padding(.top, 24)
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 20)
        .fitSheet()
        .interactiveDismissDisabled(pending)
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

    private func confirm() {
        guard let cost, let key, !pending, !settled else { return }
        do { _ = try PromoStore.prepare(model.promoBacking, key: key) } catch {
            warning = "Ce téléphone ne peut pas enregistrer le code. Vos points n’ont pas été utilisés."
            return
        }
        Haptics.confirm()
        pending = true
        warning = nil
        Task {
            let result: PromoResult
            do {
                result = try await model.service.consumePromoCode(expectedCost: cost)
            } catch let error as VelovError {
                result = PromoResult(outcome: Outcome(ok: false, httpStatus: error.code == .expired ? 401 : 0, code: "local.\(error.code.rawValue)", message: error.message), promoCode: nil)
            } catch {
                result = PromoResult(outcome: Outcome(ok: false, httpStatus: 0, code: "network", message: "Vélo’v ne répond pas. Vos points ont peut-être été débités."), promoCode: nil)
            }
            if let code = result.promoCode {
                do { codes = try PromoStore.save(model.promoBacking, key: key, code: code) } catch {
                    if !codes.contains(where: { $0.code == code }) { codes.append(SavedPromo(code: code, createdAt: ISO8601DateFormatter().string(from: Date()))) }
                    warning = storageWarning
                }
            }
            Haptics.result(result.outcome.ok)
            outcome = result
            pending = false
        }
    }

    private func closed() {
        if outcome != nil { Task { await model.loadDashboard() } }
    }

    private func copy(_ code: String) {
        UIPasteboard.general.string = code
        copied = code
        Haptics.result(true)
    }
}
