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

struct DoneLine: View {
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Icon(.check, .bold, size: 16).foregroundStyle(Palette.red).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
            Text(text).typo(.body(15)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
        }
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

struct WriteDialog<Question: View>: View {
    enum Step { case confirm, sending, failed(Outcome) }

    let title: String
    let run: () async -> Outcome
    @ViewBuilder let question: () -> Question
    @Environment(\.dismiss) private var dismiss
    @State private var step = Step.confirm

    private var sending: Bool { if case .sending = step { true } else { false } }
    private var failure: Outcome? { if case .failed(let outcome) = step { outcome } else { nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeading(title: title, closeDisabled: sending) { dismiss() }
            if Question.self != EmptyView.self {
                question().typo(.body(15)).foregroundStyle(Palette.ink).padding(.top, 14)
            }
            if let failure {
                VStack(alignment: .leading, spacing: 6) {
                    FormError(failure.message ?? "La modification n’a pas abouti.")
                    RawStatus(outcome: failure)
                    if failure.isUncertain { UncertainNote().padding(.top, 4) }
                }
                .padding(.top, 14)
            }
            PairedActions {
                if failure?.isUncertain == true {
                    PillButton("Fermer", variant: .ghost, fullWidth: true) { dismiss() }
                } else {
                    PillButton("Annuler", variant: .ghost, fullWidth: true) { dismiss() }.disabled(sending)
                    PillButton("Confirmer", pending: sending, fullWidth: true) { confirm() }
                }
            }
            .padding(.top, 24)
        }
        .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 20)
        .fitSheet()
        .interactiveDismissDisabled(sending)
    }

    private func confirm() {
        guard !sending else { return }
        Haptics.confirm()
        step = .sending
        Task {
            let outcome = await run()
            Haptics.result(outcome.ok)
            if outcome.ok { dismiss() } else { step = .failed(outcome) }
        }
    }
}

extension WriteDialog where Question == EmptyView {
    init(title: String, run: @escaping () async -> Outcome) {
        self.init(title: title, run: run) { EmptyView() }
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
            Text(label).typo(.label(13)).foregroundStyle(Palette.inkSoft)
            TextField("", text: $text)
                .typo(.body(16)).foregroundStyle(Palette.ink)
                .keyboardType(keyboard).textContentType(content).autocorrectionDisabled()
                .fieldPill()
                .onChange(of: text) { _, value in if value.count > maxLength { text = String(value.prefix(maxLength)) } }
                .accessibilityLabel(label)
        }
    }
}
