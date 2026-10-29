import SwiftUI

/// Free Hugeicons (stroke-rounded, MIT), drawn from `Icons.xcassets` in the app and the widget extension.
/// Each raw value is the Hugeicons name in kebab case: `scripts/fetch-assets.py` reads this table to build the assets.
enum IconName: String {
    case house = "home-03"
    case personSimpleBike = "bike"
    case starFour = "sparkle"
    case mapPin = "location-01"
    case userCircle = "user-circle"
    case signOut = "logout-05"
    case arrowClockwise = "refresh-01"
    case warningCircle = "alert-circle"
    case x = "cancel-01"
    case lightning = "flash"
    case letterCircleP = "parking-area-circle"
    case caretRight = "arrow-right-01"
    case caretDown = "arrow-down-01"
    case magnifyingGlass = "search-01"
    case navigationArrow = "navigation-03"
    case timer = "timer-02"
    case star = "star"
    case starHalf = "star-half"
    case ticket = "ticket-01"
    case trendUp = "trending-up"
    case arrowRight = "arrow-right-02"
    case arrowUpRight = "arrow-up-right-01"
    case arrowLeft = "arrow-left-02"
    case check = "tick-02"
    case spinnerGap = "loading-03"
    case copy = "copy-01"
    case thumbsUp = "thumbs-up"
    case thumbsDown = "thumbs-down"
    case warning = "alert-02"
    case clock = "clock-01"
    case lockOpen = "square-unlock-02"
    case batteryEmpty = "battery-empty"
    case batteryLow = "battery-low"
    case batteryMedium = "battery-medium-01"
    case batteryHigh = "battery-medium-02"
    case batteryFull = "battery-full"
    case downloadSimple = "download-01"
    case envelopeSimple = "mail-01"
}

/// Stroke width 1.5 (light) or 2 (bold); `fill` exists for `star` and `starHalf` only.
enum IconWeight { case light, bold, fill }

struct Icon: View {
    let name: IconName
    var weight: IconWeight = .light
    var size: CGFloat = 20

    init(_ name: IconName, _ weight: IconWeight = .light, size: CGFloat = 20) {
        self.name = name
        self.weight = weight
        self.size = size
    }

    private var asset: String {
        switch weight {
        case .light: "Hugeicons/\(name.rawValue)"
        case .bold: "Hugeicons/\(name.rawValue)-bold"
        case .fill: "Hugeicons/\(name.rawValue)-fill"
        }
    }

    var body: some View {
        Image(asset)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
