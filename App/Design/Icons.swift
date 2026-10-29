import SwiftUI

/// Phosphor icons (MIT), same names and weights as the web app, from the asset catalog.
enum Ph: String {
    case house, personSimpleBike = "person-simple-bike", starFour = "star-four", mapPin = "map-pin", userCircle = "user-circle"
    case signOut = "sign-out", arrowClockwise = "arrow-clockwise", warningCircle = "warning-circle", x, lightning
    case letterCircleP = "letter-circle-p", caretRight = "caret-right", caretDown = "caret-down", magnifyingGlass = "magnifying-glass"
    case navigationArrow = "navigation-arrow", timer, star, starHalf = "star-half", ticket, trendUp = "trend-up"
    case arrowRight = "arrow-right", arrowUpRight = "arrow-up-right", arrowLeft = "arrow-left", check, spinnerGap = "spinner-gap"
    case copy, thumbsUp = "thumbs-up", thumbsDown = "thumbs-down", warning, clock, lockOpen = "lock-open"
    case batteryEmpty = "battery-empty", batteryFull = "battery-full", batteryHigh = "battery-high", batteryLow = "battery-low", batteryMedium = "battery-medium"
    case downloadSimple = "download-simple", envelopeSimple = "envelope-simple"

    enum Weight: String { case light, regular, bold, fill }
}

struct Icon: View {
    let name: Ph
    var weight: Ph.Weight = .light
    var size: CGFloat = 20

    init(_ name: Ph, _ weight: Ph.Weight = .light, size: CGFloat = 20) {
        self.name = name
        self.weight = weight
        self.size = size
    }

    var body: some View {
        Image("Phosphor/\(name.rawValue)-\(weight.rawValue)")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
