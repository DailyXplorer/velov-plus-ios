import SwiftUI
import UIKit
import VelovCore

extension View {
    func announced(_ text: String) -> some View {
        onAppear { AccessibilityNotification.Announcement(text).post() }
    }
}

struct FormError: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).typo(.body(.base)).foregroundStyle(Palette.formError).fixedSize(horizontal: false, vertical: true).announced(text)
    }
}

struct UncertainNote: View {
    var unlock = false
    var body: some View {
        Text(unlock ? Messages.uncertainUnlock : Messages.uncertain)
            .typo(.body(.base, medium: true)).foregroundStyle(Palette.redDeep).fixedSize(horizontal: false, vertical: true)
    }
}

struct FailureBlock: View {
    let message: String
    var uncertain = false
    var unlock = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FormError(message)
            if uncertain { UncertainNote(unlock: unlock).padding(.top, Space.label) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PairedActions<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        EqualCells(spacing: Space.cards) { content() }
    }
}

struct EqualCells: SwiftUI.Layout {
    let spacing: CGFloat

    private func arrangement(_ width: CGFloat?, _ subviews: Subviews) -> (cell: CGFloat, side: Bool) {
        let count = CGFloat(subviews.count)
        let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let gaps = spacing * (count - 1)
        let available = width ?? widest * count + gaps
        let side = widest * count + gaps <= available
        return (side ? (available - gaps) / count : available, side)
    }

    private func heights(_ cell: CGFloat, _ subviews: Subviews) -> [CGFloat] {
        subviews.map { $0.sizeThatFits(ProposedViewSize(width: cell, height: nil)).height }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let (cell, side) = arrangement(proposal.width, subviews)
        let heights = heights(cell, subviews)
        let width = side ? cell * CGFloat(subviews.count) + spacing * CGFloat(subviews.count - 1) : cell
        return CGSize(width: width, height: side ? heights.max() ?? 0 : heights.reduce(0, +) + spacing * CGFloat(subviews.count - 1))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let (cell, side) = arrangement(bounds.width, subviews)
        let heights = heights(cell, subviews)
        let row = heights.max() ?? 0
        var origin = bounds.origin
        for (subview, height) in zip(subviews, heights) {
            subview.place(at: origin, proposal: ProposedViewSize(width: cell, height: side ? row : height))
            if side { origin.x += cell + spacing } else { origin.y += height + spacing }
        }
    }
}

struct SheetHeading<Accessory: View>: View {
    let title: String
    var closeDisabled = false
    var back: (() -> Void)?
    let close: () -> Void
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            if let back {
                IconButton(icon: .arrowLeft, color: Palette.ink, label: "Retour", action: back).bleed(.leading).disabled(closeDisabled)
            }
            Text(frenchSpaced(title)).typo(.title(.section)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Space.label)
            accessory()
            IconButton(icon: .x, label: "Fermer", action: close).bleed(.trailing).disabled(closeDisabled)
        }
    }
}

extension SheetHeading where Accessory == EmptyView {
    init(title: String, closeDisabled: Bool = false, back: (() -> Void)? = nil, close: @escaping () -> Void) {
        self.init(title: title, closeDisabled: closeDisabled, back: back, close: close) { EmptyView() }
    }
}

enum SheetDetent { case fit, large }

private struct FitSheet: ViewModifier {
    @State private var height: CGFloat = 260

    func body(content: Content) -> some View {
        ScrollView {
            content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height = ceil($0) }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
        .ignoresSafeArea(.container, edges: .bottom)
        .presentationDetents([.height(height)])
    }
}

struct SheetPresence: ViewModifier {
    @Environment(AppModel.self) private var model
    func body(content: Content) -> some View {
        content.onAppear { model.sheetAppeared() }.onDisappear { model.sheetDisappeared() }
    }
}

private struct VelovSheet: ViewModifier {
    let detent: SheetDetent
    let closeDisabled: Bool

    func body(content: Content) -> some View {
        Group {
            switch detent {
            case .fit: content.modifier(FitSheet())
            case .large: content.presentationDetents([.large])
            }
        }
        .presentationBackground(Palette.white)
        .presentationDragIndicator(.hidden)
        .sheetCorners()
        .interactiveDismissDisabled(closeDisabled)
        .modifier(SheetPresence())
    }
}

extension View {
    func velovSheet(_ detent: SheetDetent, closeDisabled: Bool = false) -> some View {
        modifier(VelovSheet(detent: detent, closeDisabled: closeDisabled))
    }
}

struct ConfirmScaffold<Message: View, Extra: View, Actions: View>: View {
    let title: String
    var closeDisabled = false
    var stacked = false
    let close: () -> Void
    @ViewBuilder let message: () -> Message
    @ViewBuilder let extra: () -> Extra
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SheetHeading(title: title, closeDisabled: closeDisabled, close: close)
            if Message.self != EmptyView.self || Extra.self != EmptyView.self {
                VStack(alignment: .leading, spacing: Space.titleToContent) {
                    message().typo(.body(.lead)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                    extra()
                }
                .padding(.top, Space.titleToContent)
            }
            Group {
                if stacked { VStack(spacing: Space.cards, content: actions) } else { PairedActions(content: actions) }
            }
            .padding(.top, Space.actions)
        }
        .padding(Layout.dialog)
        .velovSheet(.fit, closeDisabled: closeDisabled)
    }
}

struct Restart {
    let title: String
    let note: String
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
        ConfirmScaffold(title: title, closeDisabled: busy, stacked: uncertain && check == nil && restart != nil, close: { dismiss() }) {
            if Question.self != EmptyView.self { question() }
        } extra: {
            if let failure {
                FailureBlock(message: failure.message ?? (failure.isUncertain ? Messages.noReply : "La modification n’a pas abouti."),
                             uncertain: uncertain)
            }
            if uncertain, check == nil, let restart {
                Text(restart.note).typo(.body(.base)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
            }
            if let notice { FormError(notice) }
        } actions: {
            if uncertain, check == nil, let restart {
                PillButton(restart.title, variant: .secondary, fullWidth: true) { restart.action() }
                PillButton("Fermer", variant: .ghost, fullWidth: true) { dismiss() }.disabled(busy)
            } else if uncertain {
                PillButton("Fermer", variant: .ghost, fullWidth: true) { dismiss() }.disabled(busy)
                if check != nil {
                    PillButton("Vérifier", variant: .secondary, pending: checking, fullWidth: true) { verify() }
                }
            } else {
                PillButton("Annuler", variant: .ghost, fullWidth: true) { dismiss() }.disabled(busy)
                PillButton("Confirmer", pending: sending, fullWidth: true) { confirm() }.disabled(!ready || key == nil)
            }
        }
        .task {
            guard model.snapshot == .contactUncertain, entry == nil else { return }
            try? await Task.sleep(for: .seconds(0.8))
            confirm()
        }
    }

    private func confirm() {
        guard let key, ready, !busy else { return }
        Haptics.confirm()
        refused = nil
        notice = nil
        let operations = model.operations
        Task {
            switch await model.runOnce(key, meta: intent, run) {
            case .unsaved:
                notice = Messages.unsaved
            case .busy:
                if operations.get(key) == nil { notice = Messages.busy }
            case .finished(let outcome):
                Haptics.result(outcome)
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
                Haptics.success()
                verified(held.meta)
                dismiss()
            case .refused(let answer)?:
                Haptics.refused()
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

struct FormField<Field: Hashable>: View {
    let label: String
    @Binding var text: String
    var maxLength = 60
    var keyboard: UIKeyboardType = .default
    var content: UITextContentType?
    let focus: FocusState<Field?>.Binding
    let field: Field
    var next: Field?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.label) {
            Text(label).typo(.caps(.label)).foregroundStyle(Palette.inkSoft)
            TextField("", text: $text)
                .typo(.body(.input)).foregroundStyle(Palette.ink)
                .keyboardType(keyboard).textContentType(content).autocorrectionDisabled()
                .focused(focus, equals: field)
                .submitLabel(next == nil ? .done : .next)
                .onSubmit { focus.wrappedValue = next }
                .fieldPill()
                .onChange(of: text) { _, value in if value.count > maxLength { text = String(value.prefix(maxLength)) } }
                .accessibilityLabel(label)
        }
    }
}
