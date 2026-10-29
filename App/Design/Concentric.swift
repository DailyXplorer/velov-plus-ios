import SwiftUI

enum Concentric {
    static let inset: CGFloat = 24
    static let gap: CGFloat = 12
    static let display: CGFloat = 55
    static let fallback = display - inset

    static func radius(_ proxy: GeometryProxy) -> CGFloat {
        if #available(iOS 27, *), let radii = proxy.concentricCornerRadii {
            return max(radii.bottomLeading, radii.bottomTrailing, Palette.radius)
        }
        return fallback
    }
}

extension EnvironmentValues {
    @Entry var floatingRadius: CGFloat = Concentric.fallback
    @Entry var tabBarBand: CGFloat = 0
}

struct SheetCorners: ViewModifier {
    @Environment(\.floatingRadius) private var radius
    func body(content: Content) -> some View { content.presentationCornerRadius(radius) }
}

extension View {
    func sheetCorners() -> some View { modifier(SheetCorners()) }
}
