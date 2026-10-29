import Foundation

public enum Check: Equatable, Sendable { case applied, unchanged, unknown }

public enum Settled: Equatable, Sendable {
    case done
    case refused(Outcome)
    case uncertain(Outcome)
}

public func settle(_ outcome: Outcome, check: () async throws -> Check) async -> Settled {
    if outcome.ok { return .done }
    if !outcome.isUncertain { return .refused(outcome) }
    let state = (try? await check()) ?? .unknown
    switch state {
    case .applied: return .done
    case .unchanged:
        var refused = outcome
        refused.message = Messages.notApplied
        return .refused(refused)
    case .unknown: return .uncertain(outcome)
    }
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

private func fields(_ profile: Profile, _ body: ProfileBody) -> [[String]?] {
    lowered([
        body.firstName.map { _ in [profile.firstName] },
        body.lastName.map { _ in [profile.lastName] },
        body.address.map { _ in [profile.address ?? "", profile.addressComplement ?? ""] },
        body.zipCode.map { _ in [profile.zipCode ?? ""] },
        body.city.map { _ in [profile.city ?? ""] },
        body.country.map { _ in [profile.country ?? ""] },
        body.phoneNumber.map { _ in [profile.phoneNumber ?? ""] }
    ])
}

private func wanted(_ body: ProfileBody) -> [[String]?] {
    let body = body.trimmedForSending
    return lowered([body.firstName.map { [$0] }, body.lastName.map { [$0] }, body.address.map { [$0.name, $0.complement] },
                    body.zipCode.map { [$0] }, body.city.map { [$0] }, body.country.map { [$0] }, body.phoneNumber.map { [$0] }])
}

public func profileCheck(before: Profile, after: Profile, body: ProfileBody) -> Check {
    let now = fields(after, body)
    if now == wanted(body) { return .applied }
    return now == fields(before, body) ? .unchanged : .unknown
}

public enum DebitCheck: Equatable, Sendable { case debited, notDebited, unknown }

public struct DebitBefore: Equatable, Sendable {
    public var at: Date
    public var balance: Double?
    public var cost: Int
    public init(at: Date, balance: Double?, cost: Int) { self.at = at; self.balance = balance; self.cost = cost }
}

public func inviteDebit(_ before: DebitBefore, after: Rewards) -> DebitCheck {
    let since = before.at.addingTimeInterval(-5 * 60)
    let debited = after.movements.contains { movement in
        guard movement.amount == -Double(before.cost), let date = movement.date else { return false }
        return (movement.dateOnly ? date.addingTimeInterval(86_399) : date) >= since
    }
    if debited { return .debited }
    guard let balance = before.balance, let now = after.balance, now >= balance else { return .unknown }
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
