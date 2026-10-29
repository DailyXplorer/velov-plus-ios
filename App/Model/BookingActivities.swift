import ActivityKit
import Foundation
import OSLog
import VelovCore

@MainActor
final class BookingActivities {
    private let log = Logger(subsystem: "io.github.dailyxplorer.velov", category: "live-activity")
    private var expiries: [String: Task<Void, Never>] = [:]
    private(set) var lastError: String?

    private var running: [Activity<BookingActivityAttributes>] { Activity<BookingActivityAttributes>.activities }

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

    private func scheduleEnd(_ activity: Activity<BookingActivityAttributes>, at date: Date) {
        expiries[activity.id]?.cancel()
        expiries[activity.id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, date.timeIntervalSinceNow) * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.end(activity)
        }
    }
}
