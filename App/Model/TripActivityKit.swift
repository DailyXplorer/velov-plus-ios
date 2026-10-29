import ActivityKit
import Foundation
import OSLog
import VelovCore

@MainActor
final class TripActivityKit: TripActivityHost {
    private let log = Logger(subsystem: "io.github.dailyxplorer.velov", category: "live-activity")
    private let bookings: BookingActivities
    private var closing: Set<String> = []

    init(bookings: BookingActivities) {
        self.bookings = bookings
    }

    private var running: [Activity<TripActivityAttributes>] {
        Activity<TripActivityAttributes>.activities.filter { !closing.contains($0.id) && ($0.activityState == .active || $0.activityState == .stale) }
    }

    var rides: [RunningRide] {
        running.map { activity in
            let state = activity.content.state
            return RunningRide(id: activity.id, ride: Ride(tripId: state.tripId, startedAt: state.startedAt, endedAt: state.endedAt, station: state.station,
                                                          bikeNumber: state.bikeNumber, bikeType: BikeType(rawValue: state.bikeType) ?? .unknown))
        }
    }

    func start(_ ride: Ride, staleDate: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            _ = try Activity.request(attributes: TripActivityAttributes(), content: .init(state: Self.state(ride), staleDate: staleDate), pushType: nil)
        } catch {
            log.error("Trip Live Activity refused: \(String(describing: error), privacy: .public)")
        }
    }

    func update(_ id: String, _ ride: Ride, staleDate: Date) {
        guard let activity = running.first(where: { $0.id == id }) else { return }
        Task { await activity.update(.init(state: Self.state(ride), staleDate: staleDate)) }
    }

    func end(_ id: String, _ ride: Ride, dismissAt: Date?) {
        guard let activity = running.first(where: { $0.id == id }) else { return }
        closing.insert(id)
        Task { await activity.end(.init(state: Self.state(ride), staleDate: nil), dismissalPolicy: dismissAt.map { .after($0) } ?? .immediate) }
    }

    func endBookings() {
        bookings.endAll()
    }

    private static func state(_ ride: Ride) -> TripActivityAttributes.ContentState {
        .init(tripId: ride.tripId, startedAt: ride.startedAt, endedAt: ride.endedAt, station: ride.station, bikeNumber: ride.bikeNumber, bikeType: ride.bikeType.rawValue)
    }
}
