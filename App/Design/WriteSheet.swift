import SwiftUI
import UIKit
import VelovCore

// The pieces every state-changing action shares: a confirmation sheet sized to its content, a haptic on « Confirmer »,
// one request per confirmation, a success state, and the raw status line on failure only.

enum Haptics {
    static func confirm() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func result(_ ok: Bool) { UINotificationFeedbackGenerator().notificationOccurred(ok ? .success : .error) }
}

/// `.bike-action-raw`: « HTTP 400 · Code … · Detail », mono, under a failure only.
struct RawStatus: View {
    let outcome: Outcome
    var withState = false
    var extra: String?
    var body: some View {
        Text(rawLine(outcome, extra: extra, withState: withState)).typo(.mono(11)).foregroundStyle(Palette.inkSoft)
            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
    }
}

/// `.form-error`.
struct FormError: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).typo(.body(14)).foregroundStyle(Palette.formError).fixedSize(horizontal: false, vertical: true) }
}

/// `.write-done`: a check and the success sentence.
struct DoneLine: View {
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Icon(.check, .bold, size: 16).foregroundStyle(Palette.red).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }
            Text(text).typo(.body(15)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// `.modal-heading`: the title and X.
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

/// A sheet exactly as tall as what it shows (up to the full screen, then it scrolls).
struct FitSheet: ViewModifier {
    var interactiveBackground = false
    @State private var height: CGFloat = 260

    func body(content: Content) -> some View {
        ScrollView {
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = ceil($0) }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        // The floating sheet already keeps clear of the home indicator: no second inset under the content.
        .ignoresSafeArea(.container, edges: .bottom)
        .presentationDetents([.height(height)])
        .presentationBackgroundInteraction(interactiveBackground ? .enabled(upThrough: .height(height)) : .automatic)
        .presentationBackground(Palette.white)
        .presentationCornerRadius(Palette.radius)
        .presentationDragIndicator(.hidden)
    }
}

extension View {
    func fitSheet(interactiveBackground: Bool = false) -> some View { modifier(FitSheet(interactiveBackground: interactiveBackground)) }
}

/// account-actions.tsx `ConfirmDialog`: a question, one request per « Confirmer », then the result.
struct WriteDialog<Question: View>: View {
    enum Step { case confirm, sending, done, failed(Outcome) }

    let title: String
    let success: String
    /// Off where the core reports a failure as a message only (the rating, as on the web).
    var showsRawLine = true
    /// Sends the one request; applies its effect itself when it succeeds.
    let run: () async -> Outcome
    @ViewBuilder let question: () -> Question
    @Environment(\.dismiss) private var dismiss
    @State private var step = Step.confirm

    private var sending: Bool { if case .sending = step { true } else { false } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeading(title: title, closeDisabled: sending) { dismiss() }
            if case .done = step {
                DoneLine(text: success).padding(.top, 18)
                PillButton("Fermer", variant: .secondary) { dismiss() }.frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 24)
            } else {
                question().typo(.body(15)).foregroundStyle(Palette.ink).padding(.top, 14)
                if case .failed(let outcome) = step {
                    VStack(alignment: .leading, spacing: 6) {
                        FormError(outcome.message ?? "La modification n’a pas abouti.")
                        if showsRawLine { RawStatus(outcome: outcome) }
                    }
                    .padding(.top, 14)
                }
                HStack(spacing: 10) {
                    Spacer()
                    PillButton("Annuler", variant: .ghost) { dismiss() }.disabled(sending)
                    PillButton("Confirmer", pending: sending) { confirm() }
                }
                .padding(.top, 24)
            }
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
            step = outcome.ok ? .done : .failed(outcome)
        }
    }
}

/// A form field like `.field`: the mono label above a grey input.
struct FormField: View {
    let label: String
    @Binding var text: String
    var maxLength = 60
    var keyboard: UIKeyboardType = .default
    var content: UITextContentType?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).typo(.label(11)).foregroundStyle(Palette.inkSoft)
            TextField("", text: $text)
                .typo(.body(16)).foregroundStyle(Palette.ink)
                .keyboardType(keyboard).textContentType(content).autocorrectionDisabled()
                .padding(.horizontal, 11.25).frame(minHeight: 42)
                .background(RoundedRectangle(cornerRadius: 5.625).fill(Palette.white))
                .overlay(RoundedRectangle(cornerRadius: 5.625).strokeBorder(Palette.fieldLine, lineWidth: 1))
                .onChange(of: text) { _, value in if value.count > maxLength { text = String(value.prefix(maxLength)) } }
                .accessibilityLabel(label)
        }
    }
}
