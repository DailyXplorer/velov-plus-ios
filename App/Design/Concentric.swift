import SwiftUI

/// Every floating surface (tab bar, station card, sheets) takes one radius on all four corners: the tab bar's, concentric with the
/// display. A surface floating `inset` from the screen's edges takes the display radius minus `inset`, and what sits inside it that
/// radius minus its padding, so every curve runs parallel to the glass.
enum Concentric {
    /// The floating tab bar's gap to the screen's sides and bottom; the station card's sides too.
    static let inset: CGFloat = 24
    /// The station card's gap above the tab bar.
    static let gap: CGFloat = 12
    /// The display corner radius where the system does not give it (before iOS 27): iPhone 14 Pro to 16.
    static let display: CGFloat = 55
    static let fallback = display - inset

    /// The radius concentric with the display for this frame: the system's from iOS 27, else `display - inset`; never squarer than a card.
    static func radius(_ proxy: GeometryProxy) -> CGFloat {
        if #available(iOS 27, *), let radii = proxy.concentricCornerRadii {
            return max(radii.bottomLeading, radii.bottomTrailing, Palette.radius)
        }
        return fallback
    }
}

extension EnvironmentValues {
    /// The tab bar's radius, measured by the shell: every floating card and sheet uses it on all four corners.
    @Entry var floatingRadius: CGFloat = Concentric.fallback
}

/// A system sheet's top corners at the floating radius, so they match its bottom ones and the tab bar.
struct SheetCorners: ViewModifier {
    @Environment(\.floatingRadius) private var radius
    func body(content: Content) -> some View { content.presentationCornerRadius(radius) }
}

extension View {
    func sheetCorners() -> some View { modifier(SheetCorners()) }
}
