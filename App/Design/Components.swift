import SwiftUI

extension View {
    func ringed<S: InsettableShape>(_ shape: S) -> some View {
        background(shape.fill(Palette.white)).overlay(shape.strokeBorder(Palette.inkLine, lineWidth: 1))
    }

    func fieldPill() -> some View {
        padding(.leading, 18).padding(.trailing, 8).frame(minHeight: Layout.control).ringed(Capsule())
    }
}

extension EnvironmentValues {
    @Entry var onMist = false
}

enum CardStyle { case mist, ringed, red }

extension View {
    func card(_ style: CardStyle, compact: Bool = false) -> some View {
        modifier(CardSurface(style: style, padding: compact ? Space.cardCompact : Space.card))
    }
}

private struct CardSurface: ViewModifier {
    let style: CardStyle
    let padding: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        switch style {
        case .mist:
            content.padding(padding).environment(\.onMist, true).background(shape.fill(Palette.mist))
        case .ringed:
            content.padding(padding).ringed(shape)
        case .red:
            content.padding(padding).background(ZStack { Palette.red; DottedTexture() }).clipShape(shape)
        }
    }
}

enum ButtonVariant { case primary, secondary, ghost, destructive }

struct PillButton<Label: View>: View {
    var variant: ButtonVariant = .primary
    var pending = false
    var large = false
    var fullWidth = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @Environment(\.isEnabled) private var enabled
    @Environment(\.onMist) private var onMist

    var body: some View {
        Button(role: variant == .destructive ? .destructive : nil, action: action) {
            ZStack {
                HStack(spacing: 10) { label() }.opacity(pending ? 0 : 1)
                if pending { Spinner() }
            }
            .typo(.caps(.button))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 16)
            .frame(minHeight: large ? Layout.largeControl : Layout.control)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .foregroundStyle(foreground)
            .background(Capsule().fill(background))
            .overlay(Capsule().strokeBorder(ring, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.press)
        .disabled(pending)
    }

    private var muted: Bool { !enabled && !pending }
    private var filled: Bool { variant == .primary || variant == .destructive }

    private var foreground: Color {
        switch variant {
        case .primary, .destructive: muted ? Palette.inkSoft : Palette.white
        case .secondary: muted ? Palette.inkSoft : Palette.ink
        case .ghost: muted ? Palette.disabledInk : Palette.inkSoft
        }
    }

    private var background: Color {
        guard filled else { return .clear }
        return muted ? Palette.mist : Palette.red
    }

    private var ring: Color {
        switch variant {
        case .secondary: muted ? Palette.inkLine : Palette.secondaryRing
        case .primary, .destructive: muted && onMist ? Palette.inkLine : .clear
        case .ghost: .clear
        }
    }
}

extension PillButton where Label == Text {
    init(_ title: String, variant: ButtonVariant = .primary, pending: Bool = false, fullWidth: Bool = false, action: @escaping () -> Void) {
        self.init(variant: variant, pending: pending, fullWidth: fullWidth, action: action) { Text(title) }
    }
}

struct ButtonIcon: View {
    let name: IconName
    init(_ name: IconName) { self.name = name }
    var body: some View { Icon(name, .light, size: 18) }
}

struct Spinner: View {
    @State private var turning = false
    var size: CGFloat = 18
    var body: some View {
        Icon(.spinnerGap, .light, size: size)
            .rotationEffect(.degrees(turning ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: turning)
            .onAppear { turning = true }
    }
}

struct CircleArrow: View {
    enum Style { case filled, outline, onPrimary, onCard }
    var external = false
    var style: Style = .filled
    var size: CGFloat = 28

    var body: some View {
        Icon(external ? .arrowUpRight : .arrowRight, .bold, size: 13)
            .foregroundStyle(style == .filled || style == .onCard ? Palette.white : Palette.red)
            .frame(width: size, height: size)
            .background(Circle().fill(style == .filled ? Palette.red : style == .onPrimary ? Palette.white : .clear))
            .overlay(Circle().strokeBorder(style == .outline ? Palette.red : style == .onCard ? Palette.white : .clear, lineWidth: 1))
    }
}

struct Eyebrow: View {
    enum Surface { case white, mist }
    let icon: IconName
    let text: String
    var surface = Surface.white
    var body: some View {
        HStack(spacing: 10) {
            Icon(icon, .bold, size: 13).foregroundStyle(Palette.white).frame(width: 26, height: 26).background(Circle().fill(Palette.red))
            Text(text).typo(.caps(.label)).foregroundStyle(Palette.inkSoft).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.leading, 4).padding(.trailing, 14).padding(.vertical, 4)
        .background(Capsule().fill(surface == .white ? Palette.mist : Palette.white))
    }
}

struct CardTag: View {
    enum Size { case regular, stat, pick }
    let icon: IconName
    let text: String
    var size = Size.regular

    private var metrics: (gap: CGFloat, icon: CGFloat, glyph: CGFloat, font: Typo.Caps, leading: CGFloat, trailing: CGFloat, vertical: CGFloat) {
        switch size {
        case .regular: (10, 28, 13, .label, 7, 16, 7)
        case .stat: (7, 22, 12, .tag, 4, 10, 4)
        case .pick: (6, 20, 11, .tag, 3, 10, 3)
        }
    }

    var body: some View {
        let metrics = metrics
        HStack(spacing: metrics.gap) {
            Icon(icon, .bold, size: metrics.glyph).foregroundStyle(Palette.white)
                .frame(width: metrics.icon, height: metrics.icon).background(Circle().fill(Palette.red))
            Text(text).typo(.caps(metrics.font)).foregroundStyle(Palette.ink).lineLimit(1)
        }
        .padding(.leading, metrics.leading).padding(.trailing, metrics.trailing).padding(.vertical, metrics.vertical)
        .background(Capsule().fill(Palette.white))
        .overlay(Capsule().strokeBorder(size == .pick ? Palette.inkLine : .clear, lineWidth: 1))
        .fixedSize()
    }
}

struct DottedTexture: View {
    var body: some View {
        Canvas { context, size in
            for x in stride(from: 5.0, to: size.width, by: 10) {
                for y in stride(from: 5.0, to: size.height, by: 10) {
                    context.fill(Path(ellipseIn: CGRect(x: x - 1.45, y: y - 1.45, width: 2.9, height: 2.9)), with: .color(.white.opacity(0.22)))
                }
            }
        }
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .clear, location: 0.75)], startPoint: .bottom, endPoint: .top))
        .allowsHitTesting(false)
    }
}

struct SummaryCard<Value: View>: View {
    let tag: (IconName, String)
    let detail: String
    var minHeight: CGFloat = 168
    let action: () -> Void
    @ViewBuilder let value: () -> Value

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                CardTag(icon: tag.0, text: tag.1)
                value().foregroundStyle(Palette.white).lineLimit(1).minimumScaleFactor(0.5).padding(.top, 20)
                Spacer(minLength: 18)
                HStack(spacing: 4) {
                    Text(detail).typo(.body(.micro)).lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    CircleArrow(style: .onCard, size: 24)
                }
                .foregroundStyle(Palette.white)
            }
            .frame(maxWidth: .infinity, minHeight: minHeight - 2 * Space.cardCompact, alignment: .topLeading)
            .card(.red, compact: true)
        }
        .buttonStyle(.press)
    }
}

struct SectionHeading<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title).typo(.title(.section)).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.bottom, Space.titleToContent)
    }
}

extension SectionHeading where Trailing == EmptyView {
    init(_ title: String) { self.init(title: title) { EmptyView() } }
}

struct TextLinkLabel: View {
    enum Trailing { case none, caret, external }
    let title: String
    var trailing = Trailing.none
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        HStack(spacing: trailing == .external ? 12 : 6) {
            Text(title).typo(.caps(.button)).multilineTextAlignment(.leading)
            switch trailing {
            case .none: EmptyView()
            case .caret: Icon(.caretRight, .bold, size: 16)
            case .external: CircleArrow(external: true, style: .outline)
            }
        }
        .foregroundStyle(enabled ? Palette.redDeep : Palette.disabledInk)
        .frame(minHeight: Layout.hit)
        .contentShape(Rectangle())
    }
}

struct TextLink: View {
    let title: String
    var trailing = TextLinkLabel.Trailing.none
    var hint: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) { TextLinkLabel(title: title, trailing: trailing) }
            .buttonStyle(.press)
            .accessibilityHint(hint ?? "")
    }
}

struct IconButton: View {
    let icon: IconName
    var weight: IconWeight = .light
    var size: CGFloat = Layout.glyph
    var color: Color = Palette.inkSoft
    let label: String
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            Icon(icon, weight, size: size).foregroundStyle(enabled ? color : Palette.disabledInk)
                .frame(width: Layout.hit, height: Layout.hit).contentShape(Rectangle())
        }
        .buttonStyle(.press)
        .accessibilityLabel(label)
    }
}

struct FloatingCircleButton<Content: View>: View {
    let label: String
    var value: String?
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            content()
                .foregroundStyle(Palette.ink)
                .frame(width: Layout.control, height: Layout.control)
                .floatingGlass(Circle(), interactive: true, fallback: Palette.mist)
                .contentShape(Circle())
        }
        .buttonStyle(.press)
        .accessibilityLabel(label)
        .accessibilityValue(value ?? "")
    }
}

struct StateView: View {
    let message: String
    var raw: String?
    var pending = false
    var retry: (() -> Void)?

    init(_ message: String, raw: String? = nil, pending: Bool = false, retry: (() -> Void)? = nil) {
        self.message = message; self.raw = raw; self.pending = pending; self.retry = retry
    }

    init(_ failure: LoadFailure, pending: Bool = false, retry: @escaping () -> Void) {
        self.init(failure.message, raw: failure.raw, pending: pending, retry: retry)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(message).typo(.body(.base)).foregroundStyle(Palette.inkSoft).multilineTextAlignment(.center).lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let raw, !raw.isEmpty { RawStatus(line: raw).multilineTextAlignment(.center).padding(.top, Space.pair) }
            if let retry {
                PillButton("Réessayer", variant: .secondary, pending: pending, action: retry).padding(.top, Space.titleToContent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.state)
        .announced(retry == nil ? "" : message)
    }
}

struct ErrorNotice: View {
    let failure: LoadFailure
    var pending = false
    let retry: () -> Void
    var body: some View {
        HStack(spacing: Space.row) {
            VStack(alignment: .leading, spacing: Space.pair) {
                Text(failure.message).typo(.body(.base)).foregroundStyle(Palette.formError).fixedSize(horizontal: false, vertical: true)
                if !failure.raw.isEmpty { RawStatus(line: failure.raw) }
            }
            Spacer(minLength: 0)
            PillButton("Réessayer", variant: .secondary, pending: pending, action: retry)
        }
        .announced(failure.message)
    }
}

struct Shimmer: View {
    var radius: CGFloat = Palette.radius
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var phase: CGFloat = -1
    var body: some View {
        GeometryReader { geometry in
            let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
            shape.fill(Palette.mist)
                .overlay(alignment: .leading) {
                    if !still {
                        LinearGradient(stops: [.init(color: .clear, location: 0.25), .init(color: .white.opacity(0.7), location: 0.5), .init(color: .clear, location: 0.75)],
                                       startPoint: .leading, endPoint: .trailing)
                            .frame(width: geometry.size.width * 2)
                            .offset(x: phase * geometry.size.width)
                    }
                }
                .clipShape(shape)
        }
        .onAppear { withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { phase = 1 } }
        .allowsHitTesting(false)
    }
}

struct Skeleton: View {
    var height: CGFloat
    var radius: CGFloat = Palette.radius
    var body: some View { Shimmer(radius: radius).frame(height: height).accessibilityHidden(true) }
}

extension View {
    func skeleton(_ radius: CGFloat = Palette.radius) -> some View {
        opacity(0).background(Shimmer(radius: radius)).accessibilityHidden(true).allowsHitTesting(false)
    }

    func ghost() -> some View { skeleton(6) }

    func ghost(_ on: Bool) -> some View { modifier(Ghosted(on: on)) }
}

private struct Ghosted: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.ghost() } else { content }
    }
}

struct DetailRow<Value: View>: View {
    let label: String
    var last = false
    @ViewBuilder let value: () -> Value
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(label).typo(.caps(.label)).foregroundStyle(Palette.inkSoft).lineLimit(1).fixedSize()
                Spacer(minLength: 0)
                value().typo(.body(.base)).foregroundStyle(Palette.ink).multilineTextAlignment(.trailing)
            }
            .padding(.vertical, Space.row)
            if !last { Hairline() }
        }
    }
}

extension DetailRow where Value == Text {
    init(_ label: String, _ value: String, last: Bool = false) {
        self.init(label: label, last: last) { Text(value) }
    }
}

struct StackedValue: View {
    let value: String
    let small: String?
    var caps = false
    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(value)
            if let small, !small.isEmpty { Text(small).typo(caps ? .caps(.tag) : .body(.meta)).foregroundStyle(Palette.inkSoft) }
        }
    }
}

struct ConfirmToggle: View {
    let label: String
    let on: Bool
    let ask: () -> Void

    var body: some View {
        Toggle(label, isOn: Binding(get: { on }, set: { _ in ask() }))
            .labelsHidden()
            .tint(Palette.red)
            .frame(minHeight: Layout.hit)
            .contentShape(Rectangle())
    }
}

struct OnRedPill: View {
    let icon: IconName
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Icon(icon, .light, size: 15).foregroundStyle(Palette.white)
                    .frame(width: 32, height: 32).background(Circle().fill(Palette.red))
                Text(title).typo(.caps(.button)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.85)
            }
            .padding(.leading, 6).padding(.trailing, 18)
            .frame(minHeight: Layout.control)
            .background(Capsule().fill(Palette.white))
            .contentShape(Capsule())
        }
        .buttonStyle(.press)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
    }
}

struct OutlinePill: View {
    let text: String
    var body: some View {
        Text(text).typo(.caps(.tag)).foregroundStyle(Palette.redDeep).lineLimit(1).fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(Palette.red, lineWidth: 1))
    }
}

struct Hairline: View {
    var color = Palette.line
    var body: some View { Rectangle().fill(color).frame(height: 1) }
}

struct Disclosure<Content: View>: View {
    var title = "Détails"
    var icon: IconName?
    @State private var open = false
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(Motion.standard) { open.toggle() } } label: {
                HStack(spacing: Space.label) {
                    if let icon { Icon(icon, .light, size: 18) }
                    Text(title).typo(.caps(.label))
                    Icon(.caretDown, .bold, size: 16).rotationEffect(.degrees(open ? 180 : 0))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Palette.inkSoft)
                .frame(minHeight: Layout.hit)
                .contentShape(Rectangle())
            }
            .buttonStyle(.press)
            .accessibilityValue(open ? "Déplié" : "Replié")
            if open { content() }
        }
    }
}

struct Note: View {
    let text: String
    var body: some View { Text(text).typo(.body(.small)).foregroundStyle(Palette.inkSoft).fixedSize(horizontal: false, vertical: true) }
}

extension View {
    func heldWhile(_ held: Bool) -> some View {
        navigationBarBackButtonHidden(held)
            .interactiveDismissDisabled(held)
            .background(PopGestureLock(locked: held).frame(width: 0, height: 0))
    }
}

private struct PopGestureLock: UIViewControllerRepresentable {
    let locked: Bool

    func makeUIViewController(context: Context) -> Probe { Probe() }

    func updateUIViewController(_ probe: Probe, context: Context) {
        probe.locked = locked
    }

    static func dismantleUIViewController(_ probe: Probe, coordinator: ()) {
        probe.locked = false
    }

    final class Probe: UIViewController {
        var locked = false { didSet { apply() } }
        private weak var held: UINavigationController?

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply()
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            release()
        }

        private func apply() {
            guard locked else { return release() }
            guard let navigation = navigationController ?? held else { return }
            held = navigation
            gestures(of: navigation).forEach { $0.isEnabled = false }
        }

        private func release() {
            guard let navigation = held else { return }
            held = nil
            gestures(of: navigation).forEach { $0.isEnabled = true }
        }

        private func gestures(of navigation: UINavigationController) -> [UIGestureRecognizer] {
            var gestures = [navigation.interactivePopGestureRecognizer]
            if #available(iOS 26, *) { gestures.append(navigation.interactiveContentPopGestureRecognizer) }
            return gestures.compactMap { $0 }
        }
    }
}
