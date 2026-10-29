import Foundation

extension VelovAPI {
    static let tripPageSize = 100

    public func stats(_ identity: Identity, now: @escaping @Sendable () -> Date = { Date() }) async throws -> Stats {
        try await statsMemo.get(identity.email) { [self] in
            let account = "/accounts/\(try await accountId(identity))"
            let history = try await collectPages(id: \.id) { page in
                try RawTrip.list(try await self.read("\(account)/trips?status=FINISHED&status=ERROR&status=REVERSED&page=\(page)&size=\(Self.tripPageSize)",
                                                     identity, accept: "application/vnd.trip.v6+json"))
            }
            let ledger = try? await rewardLedger(account: account, identity)
            let balance = try? await read("\(account)/rewards", identity, accept: "application/vnd.rewards.v5+json")["balance"]?.number
            let stations = await stationsByNumber()
            return buildStats(StatsInput(
                trips: history.items.map { normalizeTrip($0, stations: stations) }, coords: stations.mapValues(\.point),
                movements: ledger?.movements.map { StatsMovement(date: $0.date, amount: $0.amount) }, balance: balance, now: now(),
                complete: history.complete, pointsComplete: ledger?.complete ?? false))
        }
    }

    public func forgetStats() async {
        await statsMemo.clear()
    }

    public func rewardLedger(_ identity: Identity) async throws -> RewardLedger {
        try await rewardLedger(account: "/accounts/\(try await accountId(identity))", identity)
    }

    private func rewardLedger(account: String, _ identity: Identity) async throws -> RewardLedger {
        let pages = try await collectPages(id: \RewardMovement.id) { page in
            let value = try await self.read("\(account)/rewards/history?page=\(page)", identity, accept: "application/vnd.rewards.v5+json")
            guard let content = value["content"]?.array else { throw ShapeError("rewards history content") }
            return try content.map { item in
                guard let movement = rewardMovement(item) else { throw ShapeError("rewards history movement") }
                return movement
            }
        }
        return RewardLedger(movements: pages.items, complete: pages.complete)
    }
}
