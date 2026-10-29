import Foundation

// trip-end.ts: the end of a ride, kept free of SwiftUI so tests can drive it: star ratings, the dock watch, and the « Plus tard » memory.

/// Vélo’v stores three levels only (100, 60, 30): 5 and 4 stars recommend, 3 and 2 report a minor problem, 1 a serious one.
public enum StarRating {
    public static let labels: [Int: String] = [5: "Parfait", 4: "Bien", 3: "Moyen", 2: "Décevant", 1: "À réparer"]

    public static func vote(_ stars: Int) -> RateVote {
        stars >= 4 ? .recommend : .warn(stars <= 1 ? 30 : 60)
    }
}

/// Where « Trajet terminé » remembers the trips closed on this phone (`UserDefaults` in the app).
public protocol TripEndStore: AnyObject {
    func string(forKey key: String) -> String?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: TripEndStore {}

private func dismissedKey(_ tripId: String) -> String { "velov:trip-ended:v1:\(tripId)" }

/// Closing the « Trajet terminé » sheet, by « Plus tard » or otherwise, keeps it from opening again for that trip.
public func dismissTrip(_ store: TripEndStore, _ tripId: String) {
    store.set("1", forKey: dismissedKey(tripId))
}

public func wasDismissed(_ store: TripEndStore, _ tripId: String) -> Bool {
    store.string(forKey: dismissedKey(tripId)) != nil
}

public func latestFinished(_ trips: [Trip]) -> Trip? {
    var latest: Trip?
    for trip in trips where trip.status == "FINISHED" {
        guard let ended = trip.endedAt else { continue }
        if latest == nil || ended > latest!.endedAt! { latest = trip }
    }
    return latest
}

/// On launch: the latest finished trip, still rateable and never dismissed here.
public func tripToGreet(_ trips: [Trip], store: TripEndStore, now: Date = Date()) -> Trip? {
    guard let latest = latestFinished(trips), canRate(latest, now: now), !wasDismissed(store, latest.id) else { return nil }
    return latest
}

/// The dock watch's poll: the ongoing trips (nil when Vélo’v did not answer), and the latest finished trip once none is ongoing.
public struct TripCheck: Equatable, Sendable {
    public var ongoing: [Trip]?
    public var latest: Trip?
    public init(ongoing: [Trip]?, latest: Trip?) { self.ongoing = ongoing; self.latest = latest }
}

/// Polls while a trip is ongoing, every 20 s and only while the app is in the foreground, one request at a time, 3 h at most.
/// `docked` fires once, when a trip seen ongoing is gone; the watch then stops.
@MainActor
public final class DockWatch {
    public static let interval: TimeInterval = 20
    public static let cap: TimeInterval = 3 * 3600
    /// After an unlock the trip shows up ~10 s after the bike leaves the borne; past this, the release is taken as not used.
    public static let unlockGrace: TimeInterval = 2 * 60

    /// Runs `fire` after a delay; the closure it returns cancels it.
    public typealias Scheduler = @MainActor (TimeInterval, @escaping @MainActor () async -> Void) -> () -> Void

    private enum State {
        case idle
        case unlocked(since: Date, startedAt: Date)
        case riding(tripId: String, startedAt: Date)

        var startedAt: Date? {
            switch self {
            case .idle: nil
            case .unlocked(_, let startedAt), .riding(_, let startedAt): startedAt
            }
        }
    }

    private let check: @MainActor () async throws -> TripCheck
    private let docked: @MainActor (String, Trip?) -> Void
    private let visible: @MainActor () -> Bool
    private let now: () -> Date
    private let schedule: Scheduler
    private var state = State.idle
    private var cancelTimer: (() -> Void)?
    private var inFlight = false
    /// Bumped by `stop()`: an answer to a request sent before it is ignored.
    private var generation = 0

    public init(check: @escaping @MainActor () async throws -> TripCheck, docked: @escaping @MainActor (String, Trip?) -> Void,
                visible: @escaping @MainActor () -> Bool, now: @escaping () -> Date = Date.init, schedule: Scheduler? = nil) {
        self.check = check
        self.docked = docked
        self.visible = visible
        self.now = now
        self.schedule = schedule ?? { delay, fire in
            let task = Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if !Task.isCancelled { await fire() }
            }
            return { task.cancel() }
        }
    }

    public var active: Bool { if case .idle = state { false } else { true } }

    /// A trip known to be ongoing, or nil right after an unlock, before the trip shows up.
    public func follow(_ tripId: String?) {
        let startedAt = state.startedAt ?? now()
        if let tripId {
            state = .riding(tripId: tripId, startedAt: startedAt)
        } else if case .idle = state {
            state = .unlocked(since: now(), startedAt: startedAt)
        }
        if cancelTimer == nil && !inFlight { plan() }
    }

    /// Back in the foreground: check at once. In the background the timer finds the app hidden and waits for this call.
    public func becameVisible() async {
        guard active else { return }
        cancel()
        await tick()
    }

    public func stop() {
        state = .idle
        generation += 1
        cancel()
    }

    private func cancel() {
        cancelTimer?()
        cancelTimer = nil
    }

    private func plan() {
        cancel()
        guard active else { return }
        cancelTimer = schedule(Self.interval) { [weak self] in await self?.tick() }
    }

    private func tick() async {
        cancelTimer = nil
        guard let startedAt = state.startedAt, !inFlight, visible() else { return }
        if now().timeIntervalSince(startedAt) >= Self.cap { return stop() }
        let sent = generation
        inFlight = true
        // Network or Vélo’v down: try again next round.
        let answer = try? await check()
        inFlight = false
        guard sent == generation else { return }
        if let ongoing = answer?.ongoing, let first = ongoing.first {
            state = .riding(tripId: first.id, startedAt: startedAt)
        } else if answer?.ongoing != nil, case .riding(let tripId, _) = state {
            stop()
            return docked(tripId, answer?.latest)
        } else if answer?.ongoing != nil, case .unlocked(let since, _) = state, now().timeIntervalSince(since) >= Self.unlockGrace {
            return stop()
        }
        plan()
    }
}
