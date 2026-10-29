import SwiftUI
import UIKit
import VelovCore

private let storageWarning = "Conservation locale indisponible. Copiez le code maintenant et gardez cette page ouverte."

/// invite-friend.tsx: points for a code to pass on. The storage is checked before the one debit, and a returned code is
/// written to this phone before anything else happens; no subscription process is ever sent.
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

    private var canObtain: Bool {
        guard let cost, let balance, key != nil else { return false }
        return cost >= 0 && balance >= cost
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "Inviter un ami\(cost.map { " · \($0) points" } ?? "")").typo(.label(12)).foregroundStyle(Palette.inkSoft)
                    Text("Échanger vos points contre un code à transmettre à votre ami.").typo(.body(13)).foregroundStyle(Palette.inkSoft)
                    if cost == nil {
                        SoonNote(text: "L’offre est momentanément indisponible. Vos codes conservés restent accessibles ci-dessous.")
                    } else if let cost, let balance, balance < cost {
                        SoonNote(text: "Il vous manque \(cost - balance) points.")
                    }
                }
                Spacer(minLength: 0)
                PillButton(codes.isEmpty ? "Obtenir" : "Obtenir un autre code", variant: .secondary) { outcome = nil; asking = true }
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
                Text("Code à transmettre à votre ami").typo(.label(11)).foregroundStyle(Palette.inkSoft)
                ForEach(codes, id: \.code) { entry in
                    HStack(spacing: 12) {
                        Text(entry.code).typo(.mono(15)).foregroundStyle(Palette.ink).textSelection(.enabled)
                        Spacer(minLength: 0)
                        PillButton(variant: .secondary, action: { copy(entry.code) }) { Icon(.copy, .light, size: 16); Text(copied == entry.code ? "Copié" : "Copier") }
                    }
                }
                SoonNote(text: "Conservé sur ce téléphone pour ce compte. Le ticket n’est pas activé automatiquement.")
            }
        }
    }

    private var sheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeading(title: "Échanger \(cost ?? 0) points ?", closeDisabled: pending) { asking = false }
            Text("Solde affiché : \(balance ?? 0) points. \(cost ?? 0) points seront débités dès la création du code, même si vous ne l’utilisez pas. Aucun ticket ne sera activé automatiquement.")
                .typo(.body(15)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
            if let outcome {
                VStack(alignment: .leading, spacing: 6) {
                    if outcome.outcome.ok {
                        DoneLine(text: "Code obtenu. Copiez-le avant de quitter cette page.")
                    } else {
                        FormError(outcome.outcome.message ?? "Le code n’a pas pu être obtenu.")
                        RawStatus(outcome: outcome.outcome)
                    }
                    codeList.padding(.top, 8)
                }
                .padding(.top, 14)
            }
            if let warning { FormError(warning).padding(.top, 12) }
            HStack(spacing: 10) {
                Spacer()
                PillButton(outcome == nil ? "Annuler" : "Fermer", variant: .ghost) { asking = false }.disabled(pending)
                if outcome == nil { PillButton("Confirmer", pending: pending) { confirm() }.disabled(!canObtain) }
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
            warning = "Impossible de lire les codes conservés sur ce téléphone. Aucun point ne sera échangé."
        }
    }

    private func confirm() {
        guard let cost, let key, !pending, outcome == nil else { return }
        // Fail before the debit if the storage is already unusable; never erase earlier codes.
        do { _ = try PromoStore.prepare(model.promoBacking, key: key) } catch {
            warning = "Le téléphone ne peut pas conserver le code. Aucun point n’a été échangé."
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
                result = PromoResult(outcome: Outcome(ok: false, httpStatus: error.code == .expired ? 401 : 0, code: error.code.rawValue, message: error.message), promoCode: nil)
            } catch {
                result = PromoResult(outcome: Outcome(ok: false, httpStatus: 0, code: "network", message: "Pas de réponse : les points ont peut-être été débités. Ne recommencez pas ; vérifiez votre compte ou contactez Vélo’v."), promoCode: nil)
            }
            if let code = result.promoCode {
                // Written to this phone before anything else; if that fails, at least on screen.
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

    /// The balance changed (or may have): read the account again once the answer has been seen.
    private func closed() {
        if outcome != nil { Task { await model.loadDashboard() } }
    }

    private func copy(_ code: String) {
        UIPasteboard.general.string = code
        copied = code
        Haptics.result(true)
    }
}
