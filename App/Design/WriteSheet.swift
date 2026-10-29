import SwiftUI
import UIKit
import VelovCore

enum Haptics {
    static func confirm() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func result(_ ok: Bool) { UINotificationFeedbackGenerator().notificationOccurred(ok ? .success : .error) }
}

struct RawStatus: View {
    let line: String
    init(outcome: Outcome, withState: Bool = false) { line = rawLine(outcome, withState: withState) }
    init(line: String) { self.line = line }
    var body: some View {
        Text(line).typo(.label(12)).foregroundStyle(Palette.inkSoft)
            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
    }
}

func messageLine(_ outcome: Outcome) -> String {
    "HTTP \(outcome.httpStatus == 0 ? "aucune réponse" : String(outcome.httpStatus)) · Code \(outcome.code ?? "—") · \(capitalize(outcome.detail ?? outcome.message ?? "—"))"
}

struct FormError: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).typo(.body(14)).foregroundStyle(Palette.formError).fixedSize(horizontal: false, vertical: true) }
}

struct UncertainNote: View {
    var unlock = false
    var body: some View {
        Text(unlock ? Messages.uncertainUnlock : Messages.uncertain)
            .typo(.body(13, medium: true)).foregroundStyle(Palette.redDeep).fixedSize(horizontal: false, vertical: true)
    }
}

struct PairedActions<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(spacing: 10) { content() }.fixedSize(horizontal: false, vertical: true)
    }
}

struct SheetHeading: View {
    let title: String
    var closeDisabled = false
    let close: () -> Void
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).typo(.title(24)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            IconButton(icon: .x, label: "Fermer", action: close).padding(.trailing, -10).disabled(closeDisabled)
        }
    }
}

struct FitSheet: ViewModifier {
    @State private var height: CGFloat = 260

    func body(content: Content) -> some View {
        ScrollView {
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = ceil($0) }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .ignoresSafeArea(.container, edges: .bottom)
        .presentationDetents([.height(height)])
        .presentationBackground(Palette.white)
        .presentationDragIndicator(.hidden)
        .sheetCorners()
    }
}

extension View {
    func fitSheet() -> some View { modifier(FitSheet()) }
}

struct Restart {
    let title: String
    let action: () -> Void
}

typealias IntentCheck = ([String: String]) async throws -> Check

struct WriteDialog<Question: View>: View {
    let title: String
    let key: String?
    let ready: Bool
    let intent: [String: String]
    let run: () async -> Outcome
    let check: IntentCheck?
    let verified: ([String: String]) -> Void
    let restart: Restart?
    let question: () -> Question
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var refused: Outcome?
    @State private var notice: String?
    @State private var checking = false

    init(title: String, key: String?, ready: Bool = true, intent: [String: String] = [:], run: @escaping () async -> Outcome,
         check: IntentCheck? = nil, verified: @escaping ([String: String]) -> Void = { _ in }, restart: Restart? = nil,
         @ViewBuilder question: @escaping () -> Question) {
        self.title = title; self.key = key; self.ready = ready; self.intent = intent; self.run = run
        self.check = check; self.verified = verified; self.restart = restart; self.question = question
    }

    private var entry: Operations.Entry? { key.flatMap { model.operations.get($0) } }
    private var sending: Bool { entry?.status == .sending }
    private var busy: Bool { sending || checking }
    private var failure: Outcome? { entry?.status == .uncertain ? entry?.outcome : refused }
    private var uncertain: Bool { entry?.status == .uncertain }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeading(title: title, closeDisabled: busy) { dismiss() }
            if Question.self != EmptyView.self {
                question().typo(.body(15)).foregroundStyle(Palette.ink).padding(.top, 14)
            }
            if let failure {
                VStack(alignment: .leading, spacing: 6) {
                    FormError(failure.message ?? (failure.isUncertain ? Messages.unverified : "La modification n’a pas abouti."))
                    RawStatus(outcome: failure)
                    if uncertain { UncertainNote().padding(.top, 4) }
                }
                .padding(.top, 14)
            }
            if let notice { FormError(notice).padding(.top, 12) }
            PairedActions {
                if uncertain {
                    PillButton("Fermer", variant: .ghost, fullWidth: true) { dismiss() }.disabled(busy)
                    if check != nil {
                        PillButton("Vérifier", variant: .secondary, pending: checking, fullWidth: true) { verify() }
                    } else if let restart {
                        PillButton(restart.title, variant: .secondary, fullWidth: true) { restart.action() }
                    }
                } else {
                    PillButton("Annuler", variant: .ghost, fullWidth: true) { dismiss() }.disabled(busy)
                    PillButton("Confirmer", pending: sending, fullWidth: true) { confirm() }.disabled(!ready || key == nil)
                }
            }
            .padding(.top, 24)
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 20)
        .fitSheet()
        .interactiveDismissDisabled(busy)
    }

    private func confirm() {
        guard let key, ready, !busy else { return }
        Haptics.confirm()
        refused = nil
        notice = nil
        let operations = model.operations
        Task {
            switch await operations.runOnce(key, meta: intent, run) {
            case .unsaved:
                notice = Messages.unsaved
            case .busy:
                if operations.get(key) == nil { notice = Messages.busy }
            case .finished(let outcome):
                Haptics.result(outcome.ok)
                if outcome.ok {
                    dismiss()
                } else if !outcome.isUncertain {
                    refused = outcome
                } else if check != nil {
                    verify()
                }
            }
        }
    }

    private func verify() {
        guard let key, let check, !checking, let held = model.operations.get(key) else { return }
        checking = true
        let operations = model.operations
        Task {
            let settled = await operations.settleHeld(key, check: check)
            checking = false
            switch settled {
            case .done?:
                verified(held.meta)
                dismiss()
            case .refused(let answer)?:
                refused = answer
            case .uncertain?, nil:
                break
            }
        }
    }
}

extension WriteDialog where Question == EmptyView {
    init(title: String, key: String?, ready: Bool = true, intent: [String: String] = [:], run: @escaping () async -> Outcome,
         check: IntentCheck? = nil, verified: @escaping ([String: String]) -> Void = { _ in }, restart: Restart? = nil) {
        self.init(title: title, key: key, ready: ready, intent: intent, run: run, check: check, verified: verified, restart: restart) { EmptyView() }
    }
}

struct FormField: View {
    let label: String
    @Binding var text: String
    var maxLength = 60
    var keyboard: UIKeyboardType = .default
    var content: UITextContentType?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).typo(.caps(13)).foregroundStyle(Palette.inkSoft)
            TextField("", text: $text)
                .typo(.body(16)).foregroundStyle(Palette.ink)
                .keyboardType(keyboard).textContentType(content).autocorrectionDisabled()
                .fieldPill()
                .onChange(of: text) { _, value in if value.count > maxLength { text = String(value.prefix(maxLength)) } }
                .accessibilityLabel(label)
        }
    }
}
