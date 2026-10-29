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
            let movements = try? await collectPages(id: { (movement: (id: String, movement: StatsMovement)) in movement.id }) { page in
                let value = try await self.read("\(account)/rewards/history?page=\(page)", identity, accept: "application/vnd.rewards.v5+json")
                guard let content = value["content"]?.array else { throw ShapeError("rewards history content") }
                return content.compactMap { item -> (id: String, movement: StatsMovement)? in
                    guard let id = item["id"]?.string, let amount = item["amount"]?.number else { return nil }
                    return (id, StatsMovement(date: cyclocityDate(item["createdAt"]?.string), amount: amount * (item["direction"]?.string == "DEBIT" ? -1 : 1)))
                }
            }
            let balance = try? await read("\(account)/rewards", identity, accept: "application/vnd.rewards.v5+json")["balance"]?.number
            let stations = await stationsByNumber()
            return buildStats(StatsInput(
                trips: history.items.map { normalizeTrip($0, stations: stations) }, coords: stations.mapValues(\.point),
                movements: movements?.items.map { $0.movement }, balance: balance, now: now(), complete: history.complete))
        }
    }
}
