import ActivityKit
import Foundation
import OSLog
import VelovCore

/// The booking Live Activity, driven from the app only (no push token is ever requested).
/// Started on a successful booking or when a running booking is found; ended after an unlock, at expiry, or once the booking is gone.
/// When ActivityKit refuses (Live Activities off, or not allowed for this build), nothing else depends on it: the in-app banner stays.
@MainActor
final class BookingActivities {
    private let log = Logger(subsystem: "io.github.dailyxplorer.velov", category: "live-activity")
    private var expiries: [String: Task<Void, Never>] = [:]
    /// The last refusal, kept for the diagnostics only.
    private(set) var lastError: String?

    private var running: [Activity<BookingActivityAttributes>] { Activity<BookingActivityAttributes>.activities }

    /// Matches the running activities to the account's bookings: one per live booking, none for the others.
    func sync(_ bookings: [Booking], now: Date = Date()) {
        let live = bookings.filter { ($0.endsAt ?? .distantPast) > now }
        for activity in running where !live.contains(where: { $0.id == activity.attributes.bookingId }) {
            end(activity)
        }
        for booking in live { start(booking) }
    }

    func start(_ booking: Booking) {
        guard let endsAt = booking.endsAt, endsAt > Date() else { return }
        if let current = running.first(where: { $0.attributes.bookingId == booking.id }) {
            scheduleEnd(current, at: endsAt)
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            lastError = "Live Activities disabled"
            return
        }
        let attributes = BookingActivityAttributes(bookingId: booking.id, bikeNumber: booking.bikeNumber, standNumber: booking.standNumber, stationName: booking.stationName)
        do {
            let activity = try Activity.request(attributes: attributes, content: .init(state: .init(endsAt: endsAt), staleDate: endsAt), pushType: nil)
            scheduleEnd(activity, at: endsAt)
        } catch {
            lastError = String(describing: error)
            log.error("Live Activity refused: \(String(describing: error), privacy: .public)")
        }
    }

    /// After a successful unlock the booking is spent: its activity goes at once.
    func end(bookingId: String) {
        for activity in running where activity.attributes.bookingId == bookingId { end(activity) }
    }

    func endAll() {
        for activity in running { end(activity) }
    }

    private func end(_ activity: Activity<BookingActivityAttributes>) {
        expiries.removeValue(forKey: activity.id)?.cancel()
        let content = activity.content
        Task { await activity.end(content, dismissalPolicy: .immediate) }
    }

    /// While the app runs, the activity leaves the Lock Screen at expiry; otherwise it turns stale and the next `sync` ends it.
    private func scheduleEnd(_ activity: Activity<BookingActivityAttributes>, at date: Date) {
        expiries[activity.id]?.cancel()
        expiries[activity.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, date.timeIntervalSinceNow) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.end(activity)
        }
    }
}
