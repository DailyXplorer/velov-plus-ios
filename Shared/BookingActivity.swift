import ActivityKit
import SwiftUI

/// The booking countdown shown on the Lock Screen and in the Dynamic Island. Updated locally only: no push.
struct BookingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endsAt: Date
    }

    var bookingId: String
    var bikeNumber: Int?
    var standNumber: Int?
    var stationName: String
}

// The views are shared so the app can draw them for the snapshots; the widget extension puts them in its regions.
// SF Symbols and system fonts: the extension bundles neither the Phosphor catalogue nor the web fonts.

enum ActivityStyle {
    static let red = Color(red: 0xdf / 255, green: 0x25 / 255, blue: 0x37 / 255)
    static let ink = Color(red: 0x1c / 255, green: 0x17 / 255, blue: 0x17 / 255)

    static func mono(_ size: CGFloat) -> Font { .system(size: size, weight: .medium, design: .monospaced) }
}

extension BookingActivityAttributes {
    var bikeLine: String { "Vélo \(bikeNumber.map(String.init) ?? "—") · borne \(standNumber.map(String.init) ?? "—")" }
}

/// mm:ss to the end of the booking, ticking on its own; 00:00 once it has run out.
struct BookingCountdown: View {
    let endsAt: Date
    var size: CGFloat
    var color: Color

    var body: some View {
        Text(timerInterval: Date.now...max(Date.now, endsAt), countsDown: true)
            .font(ActivityStyle.mono(size)).monospacedDigit().foregroundStyle(color)
    }
}

/// The white « RÉSERVÉ » pill with its red clock, like the in-app banner.
struct ReservedPill: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "clock.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(Circle().fill(ActivityStyle.red))
            Text("RÉSERVÉ").font(ActivityStyle.mono(11)).foregroundStyle(ActivityStyle.ink)
        }
        .padding(.leading, 3).padding(.trailing, 10).padding(.vertical, 3)
        .background(Capsule().fill(.white))
    }
}

/// Lock Screen and banner presentation: the pill, the bike and its borne, the station, the countdown.
struct BookingLockScreenView: View {
    let attributes: BookingActivityAttributes
    let endsAt: Date
    var stale = false

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                ReservedPill()
                Text(attributes.bikeLine).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                Text(attributes.stationName).font(.footnote).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
            }
            Spacer(minLength: 0)
            if stale {
                Text("EXPIRÉE").font(ActivityStyle.mono(14)).foregroundStyle(.white)
            } else {
                BookingCountdown(endsAt: endsAt, size: 34, color: .white).multilineTextAlignment(.trailing).frame(width: 118, alignment: .trailing)
            }
        }
        .padding(16)
    }
}

/// The expanded Dynamic Island regions, one view each.
struct BookingIslandLeading: View {
    let attributes: BookingActivityAttributes
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("RÉSERVÉ").font(ActivityStyle.mono(11)).foregroundStyle(ActivityStyle.red)
            Text("Vélo \(attributes.bikeNumber.map(String.init) ?? "—")").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
        }
        .padding(.leading, 6)
    }
}

struct BookingIslandTrailing: View {
    let endsAt: Date
    var body: some View {
        BookingCountdown(endsAt: endsAt, size: 26, color: ActivityStyle.red).multilineTextAlignment(.trailing).frame(width: 96, alignment: .trailing).padding(.trailing, 6)
    }
}

struct BookingIslandBottom: View {
    let attributes: BookingActivityAttributes
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "bicycle").foregroundStyle(ActivityStyle.red)
            Text("Borne \(attributes.standNumber.map(String.init) ?? "—") · \(attributes.stationName)").foregroundStyle(.white.opacity(0.85)).lineLimit(1)
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }
}
