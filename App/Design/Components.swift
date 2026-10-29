import SwiftUI

// The shared pieces of components/ui.tsx and globals.css.

extension View {
    /// `--shadow-ring`: a white surface on a 1 pt ink-line ring. Nothing in the app casts a drop shadow.
    func ringed<S: InsettableShape>(_ shape: S) -> some View {
        background(shape.fill(Palette.white)).overlay(shape.strokeBorder(Palette.inkLine, lineWidth: 1))
    }

    /// `.search-field`, `.field input`, `.login-form input`: a white pill on the ring, as tall as the buttons.
    func fieldPill() -> some View {
        padding(.horizontal, 18).frame(minHeight: 42).ringed(Capsule())
    }
}

enum ButtonVariant { case primary, secondary, ghost, onRed }

/// `.button`: a 42 pt pill in DM Sans 500, primary red, secondary outline, ghost.
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
            .typo(.label(14))
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

/// `.circle-arrow`: a 28 pt circle with an arrow, filled red, outlined red, white on a primary button, outlined white on a red card.
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

/// `.eyebrow`: mist pill with a red icon circle.
struct Eyebrow: View {
    let icon: IconName
    let text: String
    var body: some View {
        HStack(spacing: 10) {
            Icon(icon, .bold, size: 13).foregroundStyle(Palette.white).frame(width: 26, height: 26).background(Circle().fill(Palette.red))
            Text(text).typo(.label(13)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.leading, 4).padding(.trailing, 14).padding(.vertical, 4)
        .background(Capsule().fill(Palette.mist))
    }
}

/// `.card-tag`: white pill with a red icon circle.
struct CardTag: View {
    let icon: IconName
    let text: String
    var compact = false
    var body: some View {
        HStack(spacing: compact ? 6 : 10) {
            Icon(icon, .bold, size: compact ? 11 : 13).foregroundStyle(Palette.white)
                .frame(width: compact ? 20 : 28, height: compact ? 20 : 28).background(Circle().fill(Palette.red))
            Text(text).typo(.label(compact ? 12 : 13)).foregroundStyle(Palette.ink)
        }
        .padding(.leading, compact ? 3 : 7).padding(.trailing, compact ? 10 : 16).padding(.vertical, compact ? 3 : 7)
        .background(Capsule().fill(Palette.white))
        .overlay(Capsule().strokeBorder(compact ? Palette.inkLine : .clear, lineWidth: 1))
    }
}

/// White dots on a 10 pt grid, fading out toward the top: the summary cards' texture.
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

/// `.summary-card`: red, dotted, a tag, a big number and a detail line with an arrow.
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

/// `.section-heading`: a 23 pt title and an optional action.
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

/// `.text-button`: red-deep mono text.
struct TextButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) { Text(title).typo(.label(14)).foregroundStyle(Palette.redDeep).frame(minHeight: 40) }.buttonStyle(.plain)
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

/// `.notice-error`: the message and « Réessayer ».
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

/// `.skeleton`: mist block with a faint red shimmer.
struct Skeleton: View {
    var height: CGFloat
    var radius: CGFloat = Palette.radius
    @State private var phase: CGFloat = -1
    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.mist)
                .overlay(
                    LinearGradient(colors: [.clear, Palette.red.opacity(0.08), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geometry.size.width)
                        .offset(x: phase * geometry.size.width)
                )
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .frame(height: height)
        .onAppear { withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { phase = 1 } }
    }
}

/// `.account-details > div`: mono label left, value right, a hairline below.
struct DetailRow<Value: View>: View {
    let label: String
    var last = false
    @ViewBuilder let value: () -> Value
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(label).typo(.label(13)).foregroundStyle(Palette.inkSoft)
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

/// Value with a small second line under it, right-aligned (`dd > small`).
struct StackedValue: View {
    let value: String
    let small: String?
    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(value)
            if let small, !small.isEmpty { Text(small).typo(.body(12)).foregroundStyle(Palette.inkSoft) }
        }
    }
}

/// `.switch`: 52 × 30, red when on.
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

/// `.bike-reserved`: a small red-outlined pill.
struct OutlinePill: View {
    let text: String
    var body: some View {
        Text(text).typo(.label(12)).foregroundStyle(Palette.redDeep)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .overlay(Capsule().strokeBorder(Palette.red, lineWidth: 1))
    }
}

/// A hairline under list rows.
struct Hairline: View {
    var color = Palette.line
    var body: some View { Rectangle().fill(color).frame(height: 1) }
}

/// `details.bike-more`: « Détails » with a caret that turns.
struct Disclosure<Content: View>: View {
    var title = "Détails"
    @State private var open = false
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(.easeOut(duration: 0.2)) { open.toggle() } } label: {
                HStack(spacing: 8) {
                    Text(title).typo(.label(13))
                    Icon(.caretDown, .bold, size: 14).rotationEffect(.degrees(open ? 180 : 0))
                }
                .foregroundStyle(Palette.inkSoft).padding(.top, 18).padding(.bottom, 4)
            }
            .buttonStyle(.plain)
            if open { content() }
        }
    }
}

/// « Bientôt disponible » under an action stage 1 shows but does not send.
struct SoonNote: View {
    var text = "Bientôt disponible"
    var body: some View { Text(text).typo(.body(12)).foregroundStyle(Palette.inkSoft) }
}
