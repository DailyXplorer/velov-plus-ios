import ActivityKit
import SwiftUI
import WidgetKit

@main
struct VelovWidgets: WidgetBundle {
    var body: some Widget {
        BookingLiveActivity()
    }
}

/// "Réservé" + vélo + borne and the countdown to the end of the booking, started and ended by the app (no push).
struct BookingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BookingActivityAttributes.self) { context in
            BookingLockScreenView(attributes: context.attributes, endsAt: context.state.endsAt, stale: context.isStale)
                .activityBackgroundTint(ActivityStyle.red)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { BookingIslandLeading(attributes: context.attributes) }
                DynamicIslandExpandedRegion(.trailing) { BookingIslandTrailing(endsAt: context.state.endsAt) }
                DynamicIslandExpandedRegion(.bottom) { BookingIslandBottom(attributes: context.attributes) }
            } compactLeading: {
                Image(systemName: "bicycle").foregroundStyle(ActivityStyle.red)
            } compactTrailing: {
                BookingCountdown(endsAt: context.state.endsAt, size: 14, color: ActivityStyle.red).frame(width: 46)
            } minimal: {
                Image(systemName: "bicycle").foregroundStyle(ActivityStyle.red)
            }
            .keylineTint(ActivityStyle.red)
        }
    }
}
