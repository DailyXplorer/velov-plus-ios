import ActivityKit
import CoreText
import SwiftUI

struct BookingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endsAt: Date
    }

    var bookingId: String
    var bikeNumber: Int?
    var standNumber: Int?
    var stationName: String
}

enum ActivityStyle {
    static let red = Palette.red
    static let ink = Palette.ink

    static let proportionalFigures = [[kCTFontOpenTypeFeatureTag: "pnum", kCTFontOpenTypeFeatureValue: 1]] as CFArray

    static func title(_ size: CGFloat) -> Font {
        let attributes = [kCTFontNameAttribute: "VelovGlyphic-Regular", kCTFontFeatureSettingsAttribute: proportionalFigures] as CFDictionary
        return Font(CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes(attributes), size, nil))
    }
    static func timer(_ size: CGFloat) -> Font { .custom("VelovGlyphicTimer-Regular", fixedSize: size) }
    static func label(_ size: CGFloat) -> Font { .custom("DM Sans", fixedSize: size).weight(.medium) }
}

extension BookingActivityAttributes {
    var bikeLine: String { "Vélo \(bikeNumber.map(String.init) ?? "—")" }
    var placeLine: String { "Borne \(standNumber.map(String.init) ?? "—") · \(stationName)" }

    func spoken(endsAt: Date, stale: Bool, now: Date = .now) -> String {
        let bike = "Vélo \(bikeNumber.map(String.init) ?? "")"
        guard !stale, endsAt > now else { return "\(bike), réservation expirée" }
        return "\(bike) réservé, \(max(1, Int(endsAt.timeIntervalSince(now) / 60)))\u{a0}min restantes"
    }
}

struct BookingCountdown: View {
    let endsAt: Date
    var size: CGFloat
    var color: Color

    var body: some View {
        Text(timerInterval: Date.now...max(Date.now, endsAt), countsDown: true)
            .font(ActivityStyle.timer(size)).foregroundStyle(color)
    }
}

struct ActivityPill: View {
    let icon: IconName
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Icon(icon, .bold, size: 11).foregroundStyle(.white)
                .frame(width: 20, height: 20).background(Circle().fill(ActivityStyle.red))
            Text(text).font(ActivityStyle.label(13)).tracking(0.26).textCase(.uppercase).foregroundStyle(ActivityStyle.ink)
        }
        .padding(.leading, 3).padding(.trailing, 10).padding(.vertical, 3)
        .background(Capsule().fill(.white))
    }
}

struct BookingLockScreenView: View {
    let attributes: BookingActivityAttributes
    let endsAt: Date
    var stale = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    ActivityPill(icon: .clock, text: "Réservé")
                    Text(attributes.bikeLine).font(ActivityStyle.title(19)).foregroundStyle(.white).lineLimit(1)
                }
                Spacer(minLength: 0)
                if stale {
                    Text("Expirée").font(ActivityStyle.label(15)).foregroundStyle(.white)
                } else {
                    BookingCountdown(endsAt: endsAt, size: 34, color: .white).multilineTextAlignment(.trailing).frame(width: 118, alignment: .trailing)
                }
            }
            Text(attributes.placeLine).font(ActivityStyle.label(13)).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(attributes.spoken(endsAt: endsAt, stale: stale))
        .accessibilityHint("Borne \(attributes.standNumber.map(String.init) ?? "non renseignée"), \(attributes.stationName)")
        .padding(14)
    }
}

struct BookingIslandLeading: View {
    let attributes: BookingActivityAttributes
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Réservé").font(ActivityStyle.label(13)).tracking(0.26).textCase(.uppercase).foregroundStyle(ActivityStyle.red)
            Text(attributes.bikeLine).font(ActivityStyle.title(19)).foregroundStyle(.white)
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

struct BookingIslandMinimal: View {
    let endsAt: Date
    var body: some View {
        BookingCountdown(endsAt: endsAt, size: 11, color: ActivityStyle.red).multilineTextAlignment(.center).lineLimit(1).minimumScaleFactor(0.5).frame(width: 36)
    }
}

struct BookingIslandBottom: View {
    let attributes: BookingActivityAttributes
    var body: some View {
        HStack(spacing: 6) {
            Icon(.personSimpleBike, size: 16).foregroundStyle(ActivityStyle.red)
            Text(attributes.placeLine).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
        }
        .font(ActivityStyle.label(13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }
}
