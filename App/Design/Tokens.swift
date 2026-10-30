import SwiftUI

enum Space {
    static let pair: CGFloat = 4
    static let label: CGFloat = 8
    static let group: CGFloat = 8
    static let cards: CGFloat = 12
    static let titleToContent: CGFloat = 16
    static let field: CGFloat = 16
    static let row: CGFloat = 16
    static let cardCompact: CGFloat = 16
    static let card: CGFloat = 20
    static let actions: CGFloat = 24
    static let section: CGFloat = 32
    static let state: CGFloat = 40
}

enum Layout {
    static let margin: CGFloat = 24
    static let headerTop: CGFloat = 24
    static let headerBottom: CGFloat = 24
    static let dialog: CGFloat = 24
    static let control: CGFloat = 44
    static let largeControl: CGFloat = 48
    static let hit: CGFloat = 44
    static let glyph: CGFloat = 20
    static let iconGap: CGFloat = 10
    static let mapKitMargin: CGFloat = 11
    static let bleed: CGFloat = -(hit - glyph) / 2
}

enum Radius {
    static let card = Palette.radius
    static let inner: CGFloat = 12
    static let text: CGFloat = 6
    static let capsule = CGFloat.infinity
}

enum Motion {
    static let standard = Animation.easeOut(duration: 0.2)
    static let panel = Animation.snappy(duration: 0.3)
    static let camera = Animation.easeInOut(duration: 0.5)
    static let pressIn = Animation.easeOut(duration: 0.12)
    static let pressOut = Animation.easeOut(duration: 0.2)

    static func panelTransition(still: Bool) -> AnyTransition {
        still ? .opacity : .move(edge: .bottom).combined(with: .opacity)
    }
}

struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Pressed(pressed: configuration.isPressed) { configuration.label }
    }

    private struct Pressed<Label: View>: View {
        let pressed: Bool
        @ViewBuilder let label: () -> Label
        @Environment(\.accessibilityReduceMotion) private var still
        var body: some View {
            label()
                .scaleEffect(pressed && !still ? 0.97 : 1)
                .opacity(pressed && still ? 0.7 : 1)
                .animation(pressed ? Motion.pressIn : Motion.pressOut, value: pressed)
        }
    }
}

struct RowPressStyle: ButtonStyle {
    var bleed = Layout.margin
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Palette.mist.opacity(configuration.isPressed ? 1 : 0).padding(.horizontal, -bleed))
    }
}

extension ButtonStyle where Self == PressStyle {
    static var press: PressStyle { PressStyle() }
}

extension ButtonStyle where Self == RowPressStyle {
    static var row: RowPressStyle { RowPressStyle() }
    static func row(bleed: CGFloat) -> RowPressStyle { RowPressStyle(bleed: bleed) }
}

extension View {
    func bleed(_ edges: Edge.Set, visible: CGFloat = Layout.glyph) -> some View { padding(edges, -(Layout.hit - visible) / 2) }
}
