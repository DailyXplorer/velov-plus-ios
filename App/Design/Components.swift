import SwiftUI

extension View {
    func ringed<S: InsettableShape>(_ shape: S) -> some View {
        background(shape.fill(Palette.white)).overlay(shape.strokeBorder(Palette.inkLine, lineWidth: 1))
    }

    func fieldPill() -> some View {
        padding(.horizontal, 18).frame(minHeight: 42).ringed(Capsule())
    }
}

enum ButtonVariant { case primary, secondary, ghost, onRed }

struct PillButton<Label: View>: View {
    var variant: ButtonVariant = .primary
    var pending = false
    var height: CGFloat = 42
    var fullWidth = false
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @Environment(\.isEnabled) private var enabled

    var body: some View {
        Button(action: action) {
            ZStack {
                HStack(spacing: 10) { label() }.opacity(pending ? 0 : 1)
                if pending { Spinner() }
            }
            .typo(.caps(14))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 16)
            .frame(minHeight: height)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .foregroundStyle(foreground)
            .background(Capsule().fill(background))
            .overlay(Capsule().strokeBorder(ring, lineWidth: 1))
            .contentShape(Capsule())
            .opacity(enabled || pending ? 1 : 0.55)
        }
        .buttonStyle(.plain)
        .disabled(pending)
    }

    private var foreground: Color {
        switch variant {
        case .primary: Palette.white
        case .secondary: Palette.ink
        case .ghost: Palette.inkSoft
        case .onRed: Palette.red
        }
    }

    private var background: Color {
        switch variant {
        case .primary: Palette.red
        case .onRed: Palette.white
        default: .clear
        }
    }

    private var ring: Color {
        switch variant {
        case .secondary: Palette.secondaryRing
        default: .clear
        }
    }
}

extension PillButton where Label == Text {
    init(_ title: String, variant: ButtonVariant = .primary, pending: Bool = false, fullWidth: Bool = false, action: @escaping () -> Void) {
        self.init(variant: variant, pending: pending, fullWidth: fullWidth, action: action) { Text(title) }
    }
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

    var body: some View {
        Icon(external ? .arrowUpRight : .arrowRight, .bold, size: 13)
            .foregroundStyle(style == .filled || style == .onCard ? Palette.white : Palette.red)
            .frame(width: 28, height: 28)
            .background(Circle().fill(style == .filled ? Palette.red : style == .onPrimary ? Palette.white : .clear))
            .overlay(Circle().strokeBorder(style == .outline ? Palette.red : style == .onCard ? Palette.white : .clear, lineWidth: 1))
    }
}

struct Eyebrow: View {
    let icon: IconName
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Icon(icon, .bold, size: 13).foregroundStyle(Palette.white).frame(width: 26, height: 26).background(Circle().fill(Palette.red))
            Text(text).typo(.caps(13)).foregroundStyle(Palette.inkSoft).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.leading, 4).padding(.trailing, 14).padding(.vertical, 4)
        .background(Capsule().fill(Palette.mist))
    }
}

struct CardTag: View {
    enum Size { case regular, banner, stat, pick }
    let icon: IconName
    let text: String
    var size = Size.regular

    private var metrics: (gap: CGFloat, icon: CGFloat, glyph: CGFloat, font: CGFloat, leading: CGFloat, trailing: CGFloat, vertical: CGFloat) {
        switch size {
        case .regular: (10, 28, 13, 13, 7, 16, 7)
        case .banner: (8, 26, 13, 13, 5, 12, 5)
        case .stat: (7, 22, 12, 12, 4, 10, 4)
        case .pick: (6, 20, 11, 12, 3, 10, 3)
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
                value().foregroundStyle(Palette.white).padding(.top, 20)
                Spacer(minLength: 18)
                HStack(spacing: 12) {
                    Text(detail).typo(.body(11)).lineLimit(2).multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    CircleArrow(style: .onCard)
                }
                .foregroundStyle(Palette.white)
            }
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 16)
            .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
            .background(ZStack { Palette.red; DottedTexture() })
            .clipShape(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct SectionHeading<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title).typo(.title(23)).foregroundStyle(Palette.ink)
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.bottom, 18)
    }
}

extension SectionHeading where Trailing == EmptyView {
    init(_ title: String) { self.init(title: title) { EmptyView() } }
}

struct TextButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Text(title).typo(.caps(14)).foregroundStyle(Palette.redDeep).lineLimit(1).fixedSize().frame(minHeight: 40) }.buttonStyle(.plain)
    }
}

struct IconButton: View {
    let icon: IconName
    var weight: IconWeight = .light
    var size: CGFloat = 20
    var frame: CGFloat = 40
    var color: Color = Palette.inkSoft
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Icon(icon, weight, size: size).foregroundStyle(color).frame(width: frame, height: frame).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct EmptyState: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).typo(.body(14)).foregroundStyle(Palette.inkSoft).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.vertical, 44).padding(.horizontal, 20)
    }
}

struct ErrorNotice: View {
    let message: String
    var pending = false
    let retry: () -> Void
    var body: some View {
        HStack(spacing: 16) {
            Text(message).typo(.body(13)).foregroundStyle(Palette.notice)
            Spacer(minLength: 0)
            PillButton("Réessayer", variant: .secondary, pending: pending, action: retry)
        }
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
                Text(label).typo(.caps(13)).foregroundStyle(Palette.inkSoft).lineLimit(1).fixedSize()
                Spacer(minLength: 0)
                value().typo(.body(14)).foregroundStyle(Palette.ink).multilineTextAlignment(.trailing)
            }
            .padding(.vertical, 14)
            if !last { Rectangle().fill(Palette.inkLine).frame(height: 1) }
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
            if let small, !small.isEmpty { Text(small).typo(caps ? .caps(12) : .body(12)).foregroundStyle(Palette.inkSoft) }
        }
    }
}

struct VelovSwitch: View {
    let on: Bool
    var action: () -> Void = {}
    @Environment(\.isEnabled) private var enabled
    var body: some View {
        Button(action: action) {
            Capsule().fill(on ? Palette.red : Palette.ink.opacity(0.2)).frame(width: 52, height: 30)
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle().fill(Palette.white).frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(Palette.inkLine, lineWidth: 1)).padding(3)
                }
                .opacity(enabled ? 1 : 0.55)
        }
        .buttonStyle(.plain)
    }
}

struct OutlinePill: View {
    let text: String
    var body: some View {
        Text(text).typo(.caps(12)).foregroundStyle(Palette.redDeep).lineLimit(1).fixedSize()
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
            Button { withAnimation(.easeOut(duration: 0.2)) { open.toggle() } } label: {
                HStack(spacing: 8) {
                    if let icon {
                        Icon(icon, .light, size: 17)
                        Text(title).typo(.caps(13))
                    } else {
                        Text(title).typo(.caps(13))
                        Icon(.caretDown, .bold, size: 14).rotationEffect(.degrees(open ? 180 : 0))
                    }
                }
                .foregroundStyle(icon == nil ? Palette.inkSoft : Palette.dataNotice)
                .padding(.top, icon == nil ? 18 : 8).padding(.bottom, icon == nil ? 4 : 8)
            }
            .buttonStyle(.plain)
            if open { content() }
        }
    }
}

struct SoonNote: View {
    var text = "Bientôt disponible"
    var body: some View { Text(text).typo(.body(12)).foregroundStyle(Palette.inkSoft) }
}
