import SwiftUI
import UIKit

enum Concentric {
    static let inset: CGFloat = 24
    static let gap: CGFloat = 12
    static let display: CGFloat = displayCorner(UIScreen.main.bounds.size)
    static let fallback = display - inset

    static func displayCorner(_ size: CGSize) -> CGFloat {
        let points = (min(size.width, size.height), max(size.width, size.height))
        switch points {
        case (402, 874), (440, 956), (420, 912): return 62
        case (393, 852), (430, 932): return 55
        case (428, 926): return 53.33
        case (390, 844): return 47.33
        case (414, 896): return 41.5
        case (375, 812): return 39
        default: return 55
        }
    }

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
