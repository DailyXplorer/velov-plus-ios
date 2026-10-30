import Foundation

public enum StarRating {
    public static let labels: [Int: String] = [5: "Parfait", 4: "Bien", 3: "Moyen", 2: "Décevant", 1: "À réparer"]

    public static func vote(_ stars: Int) -> RateVote {
        stars >= 4 ? .recommend : .warn(stars <= 1 ? 30 : 60)
    }
}

public protocol TripEndStore: AnyObject {
    func string(forKey key: String) -> String?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: TripEndStore {}

private func dismissedKey(_ tripId: String) -> String { "velov:trip-ended:v1:\(tripId)" }

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

public func tripToGreet(_ trips: [Trip], store: TripEndStore, now: Date = Date()) -> Trip? {
    guard let latest = latestFinished(trips), canRate(latest, now: now), !wasDismissed(store, latest.id) else { return nil }
    return latest
}

public enum Greeting: Equatable, Sendable {
    case undecided, nothing
    case trip(Trip)
}

public func greeting(trips: [Trip]?, ongoing: [Trip]?, store: TripEndStore, now: Date = Date()) -> Greeting {
    guard let trips, let ongoing else { return .undecided }
    guard ongoing.isEmpty, let recent = tripToGreet(trips, store: store, now: now) else { return .nothing }
    return .trip(recent)
}

public struct TripCheck: Equatable, Sendable {
    public var ongoing: [Trip]?
    public var latest: Trip?
    public var historyRead: Bool
    public init(ongoing: [Trip]?, latest: Trip?, historyRead: Bool = true) { self.ongoing = ongoing; self.latest = latest; self.historyRead = historyRead }
}

@MainActor
public final class DockWatch {
    public static let interval: TimeInterval = 20
    public static let cap: TimeInterval = 3 * 3600
    public static let unlockGrace: TimeInterval = 2 * 60
    public static let backoffCap: TimeInterval = 2 * 60

    public typealias Scheduler = @MainActor (TimeInterval, @escaping @MainActor () async -> Void) -> () -> Void

    private enum State {
        case idle
        case unlocked(since: Date, startedAt: Date)
        case riding(tripId: String, startedAt: Date)
        case ended(tripId: String, since: Date, startedAt: Date)

        var startedAt: Date? {
            switch self {
            case .idle: nil
            case .unlocked(_, let startedAt), .riding(_, let startedAt), .ended(_, _, let startedAt): startedAt
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
    private var generation = 0
    private var delay = DockWatch.interval
    private var nextCheckAt: Date?

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

    public func follow(_ tripId: String?) {
        let startedAt = state.startedAt ?? now()
        if let tripId {
            state = .riding(tripId: tripId, startedAt: startedAt)
        } else if case .idle = state {
            state = .unlocked(since: now(), startedAt: startedAt)
        }
        if cancelTimer == nil && !inFlight { plan() }
    }

    public func visibilityChanged() async {
        guard active, !inFlight else { return }
        cancel()
        guard visible() else { return }
        let wait = nextCheckAt.map { $0.timeIntervalSince(now()) } ?? 0
        if wait > 0 { plan(wait) } else { await tick() }
    }

    public func stop() {
        state = .idle
        generation += 1
        delay = Self.interval
        nextCheckAt = nil
        cancel()
    }

    private func cancel() {
        cancelTimer?()
        cancelTimer = nil
    }

    private func plan(_ wait: TimeInterval? = nil) {
        cancel()
        guard active else { return }
        let wait = wait ?? delay
        nextCheckAt = now().addingTimeInterval(wait)
        cancelTimer = schedule(wait) { [weak self] in await self?.tick() }
    }

    private func tick() async {
        cancelTimer = nil
        guard let startedAt = state.startedAt, !inFlight, visible() else { return }
        if now().timeIntervalSince(startedAt) >= Self.cap { return stop() }
        let sent = generation
        inFlight = true
        let answer = try? await check()
        inFlight = false
        guard sent == generation else {
            if cancelTimer == nil { plan() }
            return
        }
        delay = answer?.ongoing != nil ? Self.interval : min(delay * 2, Self.backoffCap)
        if let ongoing = answer?.ongoing, let first = ongoing.first {
            state = .riding(tripId: first.id, startedAt: startedAt)
        } else if answer?.ongoing != nil {
            let latest = answer?.latest
            switch state {
            case .riding(let tripId, _) where latest?.id != tripId:
                state = .ended(tripId: tripId, since: now(), startedAt: startedAt)
            case .riding(let tripId, _), .ended(let tripId, _, _) where latest?.id == tripId:
                stop()
                return docked(tripId, latest)
            case .ended(let tripId, let since, _) where now().timeIntervalSince(since) >= Reconcile.historyLag:
                stop()
                return docked(tripId, latest)
            case .unlocked(let since, _):
                if let latest, let start = latest.startedAt, let ended = latest.endedAt,
                   start >= since.addingTimeInterval(-Reconcile.dockWindow), ended > since {
                    stop()
                    return docked(latest.id, latest)
                }
                if now().timeIntervalSince(since) >= Self.unlockGrace { return stop() }
            default: break
            }
        }
        plan()
    }
}
