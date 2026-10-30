import UIKit
import VelovCore

@MainActor
enum Haptics {
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func confirm() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func success() { notify(.success) }
    static func refused() { notify(.error) }
    static func uncertain() { notify(.warning) }

    static func result(_ outcome: Outcome) {
        if outcome.ok { success() } else if outcome.isUncertain { uncertain() } else { refused() }
    }

    private static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
