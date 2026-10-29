import ActivityKit
import SwiftUI
import WidgetKit

private let red = Color(red: 0xdf / 255, green: 0x25 / 255, blue: 0x37 / 255)

@main
struct VelovWidgets: WidgetBundle {
    var body: some Widget {
        BookingLiveActivity()
    }
}

/// "Réservé" + vélo + borne and the countdown to the end of the booking. Stage 1 draws it; the app starts it in stage 2.
struct BookingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BookingActivityAttributes.self) { context in
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("RÉSERVÉ").font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(.white.opacity(0.8))
                    Text("Vélo \(context.attributes.bikeNumber) · borne \(context.attributes.standNumber)").font(.headline).foregroundStyle(.white)
                    Text(context.attributes.stationName).font(.footnote).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                }
                Spacer()
                Text(timerInterval: Date.now...max(Date.now, context.state.endsAt), countsDown: true)
                    .font(.system(size: 28, weight: .medium, design: .monospaced)).monospacedDigit().foregroundStyle(.white)
                    .multilineTextAlignment(.trailing).frame(width: 96)
            }
            .padding(16)
            .activityBackgroundTint(red)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("Vélo \(context.attributes.bikeNumber)").font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date.now...max(Date.now, context.state.endsAt), countsDown: true).monospacedDigit().foregroundStyle(red)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Réservé · borne \(context.attributes.standNumber) · \(context.attributes.stationName)").font(.footnote).lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "bicycle").foregroundStyle(red)
            } compactTrailing: {
                Text(timerInterval: Date.now...max(Date.now, context.state.endsAt), countsDown: true).monospacedDigit().frame(width: 44).foregroundStyle(red)
            } minimal: {
                Image(systemName: "bicycle").foregroundStyle(red)
            }
        }
    }
}
