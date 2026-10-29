import SwiftUI

/// The curves along the bottom edge follow the display's corners: a surface floating `inset` from the screen's edges takes the
/// display radius minus `inset`, and what sits inside it that radius minus its padding, so every curve runs parallel to the glass.
enum Concentric {
    /// The floating tab bar's gap to the screen's sides and bottom.
    static let inset: CGFloat = 24
    /// The display corner radius where the system does not give it (before iOS 27): iPhone 14 Pro to 16.
    static let display: CGFloat = 55

    /// The radius concentric with the display for this frame: the system's from iOS 27, else `display - inset`; never squarer than a card.
    static func radius(_ proxy: GeometryProxy) -> CGFloat {
        if #available(iOS 27, *), let radii = proxy.concentricCornerRadii {
            return max(radii.bottomLeading, radii.bottomTrailing, Palette.radius)
        }
        return display - inset
    }
}
