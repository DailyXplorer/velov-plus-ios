import Foundation

public enum Check: Equatable, Sendable { case applied, unchanged, unknown }

public enum Settled: Equatable, Sendable {
    case done
    case refused(Outcome)
    case uncertain(Outcome)
}

public enum Reconcile {
    public static let historyLag: TimeInterval = 2 * 60
    public static let dockWindow: TimeInterval = 2 * 60
}

public func settle(_ outcome: Outcome, at: Date, now: () -> Date = Date.init, check: () async throws -> Check) async -> Settled {
    if outcome.ok { return .done }
    if !outcome.isUncertain { return .refused(outcome) }
    let state = (try? await check()) ?? .unknown
    switch state {
    case .applied: return .done
    case .unchanged where now().timeIntervalSince(at) >= Reconcile.historyLag:
        var refused = outcome
        refused.message = Messages.notApplied
        return .refused(refused)
    case .unchanged, .unknown: return .uncertain(outcome)
    }
}

public enum Intent {
    public static func wanted(_ value: Bool) -> [String: String] { ["wanted": value ? "true" : "false"] }
    public static func wanted(_ meta: [String: String]) -> Bool? { meta["wanted"].flatMap(Bool.init) }
}

public func unlockCheck(_ check: TripCheck, bike: Int, since: Date, now: Date, booking: String? = nil, bookings: [Booking]? = nil) -> Check {
    guard let ongoing = check.ongoing else { return .unknown }
    if ongoing.contains(where: { $0.bikeNumber == bike }) { return .applied }
    if let latest = check.latest, latest.bikeNumber == bike, let start = latest.startedAt, start >= since.addingTimeInterval(-Reconcile.dockWindow) { return .applied }
    guard check.historyRead, now.timeIntervalSince(since) >= Reconcile.dockWindow else { return .unknown }
    if let booking, !(bookings ?? []).contains(where: { $0.id == booking }) { return .unknown }
    return .unchanged
}

public func bookingCheck(_ bookings: [Booking], bike: Int) -> Check {
    bookings.contains { $0.bikeNumber == bike } ? .applied : .unchanged
}

public func compare<T: Equatable>(_ actual: T?, _ wanted: T) -> Check {
    guard let actual else { return .unknown }
    return actual == wanted ? .applied : .unchanged
}

public func autoSpendCheck(_ data: Dashboard, _ wanted: Bool) -> Check {
    compare(data.rewards.autoSpend, wanted)
}

public func favoriteCheck(_ data: Dashboard, station: Int, wanted: Bool) -> Check {
    compare(data.profile.favorites.contains(station), wanted)
}

public func renewalCheck(_ data: Dashboard, subscriptionId: String, wanted: Bool) -> Check {
    guard let subscription = data.subscription.subscription, subscription.id == subscriptionId else { return .unknown }
    return compare(subscription.autoRenewal, wanted)
}

public func ratingCheck(_ data: Dashboard, tripId: String) -> Check {
    compare(data.trips?.first { $0.id == tripId }?.isRated, true)
}

private let french = Locale(identifier: "fr_FR")

private func lowered(_ fields: [[String]?]) -> [[String]?] {
    fields.map { $0?.map { $0.lowercased(with: french) } }
}

private func fields(_ profile: Profile, _ mask: [[String]?]) -> [[String]?] {
    let all = [[profile.firstName], [profile.lastName], [profile.address ?? "", profile.addressComplement ?? ""], [profile.zipCode ?? ""],
               [profile.city ?? ""], [profile.country ?? ""], [profile.phoneNumber ?? ""]]
    return lowered(zip(all, mask).map { $1 == nil ? nil : $0 })
}

private func wanted(_ body: ProfileBody) -> [[String]?] {
    let body = body.trimmedForSending
    return lowered([body.firstName.map { [$0] }, body.lastName.map { [$0] }, body.address.map { [$0.name, $0.complement] },
                    body.zipCode.map { [$0] }, body.city.map { [$0] }, body.country.map { [$0] }, body.phoneNumber.map { [$0] }])
}

private struct ProfileChange: Codable {
    var before: [[String]?]
    var wanted: [[String]?]
}

public func profileIntent(before: Profile, body: ProfileBody) -> [String: String] {
    let target = wanted(body)
    let change = ProfileChange(before: fields(before, target), wanted: target)
    return ["profile": String(decoding: (try? JSONEncoder().encode(change)) ?? Data(), as: UTF8.self)]
}

public func profileCheck(_ intent: [String: String], after: Profile) -> Check {
    guard let raw = intent["profile"], let change = try? JSONDecoder().decode(ProfileChange.self, from: Data(raw.utf8)) else { return .unknown }
    let now = fields(after, change.wanted)
    if now == change.wanted { return .applied }
    return now == change.before ? .unchanged : .unknown
}

public enum DebitCheck: Equatable, Sendable { case debited, notDebited, unknown }

public struct DebitBefore: Equatable, Sendable {
    public var at: Date
    public var cost: Int
    public init(at: Date, cost: Int) { self.at = at; self.cost = cost }
}

public func inviteDebit(_ before: DebitBefore, ledger: RewardLedger, now: Date) -> DebitCheck {
    let since = before.at.addingTimeInterval(-5 * 60)
    let costs = ledger.movements.filter { $0.amount == -Double(before.cost) }
    let debited = costs.contains { movement in
        guard let date = movement.date else { return false }
        return (movement.dateOnly ? date.addingTimeInterval(86_399) : date) >= since
    }
    if debited { return .debited }
    guard ledger.complete, !costs.contains(where: { $0.date == nil }), now.timeIntervalSince(before.at) >= Reconcile.historyLag else { return .unknown }
    return .notDebited
}

public final class RefreshGate {
    public static let interval: TimeInterval = 5
    private let interval: TimeInterval
    private let now: () -> Date
    private var last: Date?

    public init(interval: TimeInterval = RefreshGate.interval, now: @escaping () -> Date = Date.init) {
        self.interval = interval
        self.now = now
    }

    public func allow(busy: Bool) -> Bool {
        if busy { return false }
        if let last, now().timeIntervalSince(last) < interval { return false }
        last = now()
        return true
    }
}

@MainActor
public final class SingleFlight {
    private let interval: TimeInterval
    private let now: () -> Date
    private var last: Date?
    private var running: Task<Void, Never>?

    public init(interval: TimeInterval = RefreshGate.interval, now: @escaping () -> Date = Date.init) {
        self.interval = interval
        self.now = now
    }

    public func run(force: Bool = false, _ work: @escaping @MainActor () async -> Void) async {
        while let running {
            await running.value
            if self.running == running { self.running = nil }
            if !force { return }
        }
        if !force, let last, now().timeIntervalSince(last) < interval { return }
        last = now()
        let task = Task { await work() }
        running = task
        await task.value
        if running == task { running = nil }
    }

    public func reset() {
        running = nil
        last = nil
    }
}
