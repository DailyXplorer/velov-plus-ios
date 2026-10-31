import ActivityKit
import SwiftUI

struct TripActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var tripId: String?
        var startedAt: Date
        var endedAt: Date?
        var station: String
        var bikeNumber: Int?
    }
}

extension TripActivityAttributes.ContentState {
    var bikeLine: String { "Vélo \(bikeNumber.map(String.init) ?? "—")" }
    var status: String { endedAt == nil ? "En trajet" : "Terminé" }

    func spoken(at now: Date = .now) -> String {
        let minutes = max(1, Int((endedAt ?? now).timeIntervalSince(startedAt) / 60))
        return endedAt == nil ? "\(bikeLine), en trajet depuis \(minutes)\u{a0}min" : "\(bikeLine), trajet terminé après \(minutes)\u{a0}min"
    }
}

struct TripElapsed: View {
    let state: TripActivityAttributes.ContentState
    var size: CGFloat
    var color: Color

    var body: some View {
        Group {
            if let endedAt = state.endedAt {
                Text(timerInterval: state.startedAt...max(state.startedAt, endedAt), pauseTime: max(state.startedAt, endedAt), countsDown: false)
            } else {
                Text(timerInterval: state.startedAt...Date.distantFuture, countsDown: false)
            }
        }
        .font(ActivityStyle.timer(size)).foregroundStyle(color)
    }
}

struct TripLockScreenView: View {
    let state: TripActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    ActivityPill(icon: .personSimpleBike, text: state.status)
                    Text(state.bikeLine).font(ActivityStyle.title(19)).foregroundStyle(.white).lineLimit(1)
                }
                Spacer(minLength: 0)
                TripElapsed(state: state, size: 34, color: .white).multilineTextAlignment(.trailing).frame(width: 150, alignment: .trailing)
            }
            Text(state.station).font(ActivityStyle.label(13)).foregroundStyle(.white.opacity(0.8)).lineLimit(2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.spoken())
        .accessibilityHint("Départ \(state.station)")
        .padding(14)
    }
}

struct TripIslandLeading: View {
    let state: TripActivityAttributes.ContentState
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.status).font(ActivityStyle.label(13)).tracking(0.26).textCase(.uppercase).foregroundStyle(ActivityStyle.red)
            Text(state.bikeLine).font(ActivityStyle.title(19)).foregroundStyle(.white)
        }
        .padding(.leading, 6)
    }
}

struct TripIslandTrailing: View {
    let state: TripActivityAttributes.ContentState
    var body: some View {
        TripElapsed(state: state, size: 26, color: ActivityStyle.red).multilineTextAlignment(.trailing).frame(width: 116, alignment: .trailing).padding(.trailing, 6)
    }
}

struct TripIslandBottom: View {
    let state: TripActivityAttributes.ContentState
    var body: some View {
        HStack(spacing: 6) {
            Icon(.personSimpleBike, size: 16).foregroundStyle(ActivityStyle.red)
            Text(state.station).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
        }
        .font(ActivityStyle.label(13))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }
}

struct TripIslandCompact: View {
    let state: TripActivityAttributes.ContentState
    var body: some View {
        TripElapsed(state: state, size: 14, color: ActivityStyle.red).multilineTextAlignment(.trailing).frame(width: 62)
    }
}
