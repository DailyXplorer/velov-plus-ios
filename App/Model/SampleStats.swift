import Foundation
import VelovCore

extension SampleData {
    static let statsTrips: [Trip] = {
        var seed: UInt64 = 0x5eed
        func random(_ bound: Int) -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((seed >> 33) % UInt64(bound))
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let today = calendar.startOfDay(for: now)
        let numbers = stations.map(\.number)
        let bikes = [20449, 11872, 20117, 10533, 12204, 20981, 13090, 11408, 20733, 12950]
        var trips: [Trip] = []
        for back in stride(from: 360, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -back, to: today) else { continue }
            let weekend = [1, 7].contains(calendar.component(.weekday, from: day))
            let month = calendar.component(.month, from: day)
            let chance = [11, 12, 1, 2].contains(month) ? 3 : 6
            guard random(10) < chance else { continue }
            let hours = weekend ? [11 + random(6)] : random(3) == 0 ? [8, 18] : [random(2) == 0 ? 8 : 18]
            for hour in hours {
                guard let start = calendar.date(bySettingHour: hour, minute: random(55), second: 0, of: day), start < now.addingTimeInterval(-3 * 3600) else { continue }
                let commute = !weekend && random(4) > 0
                let from = commute ? (hour < 12 ? 2002 : 3001) : numbers[random(numbers.count)]
                let to = commute ? (hour < 12 ? 3001 : 2002) : numbers[random(numbers.count)]
                let minutes = Double(commute ? 11 + random(8) : 6 + random(40))
                let electrical = random(5) < 2
                let bike = random(4) == 0 ? 20449 : bikes[random(bikes.count)]
                trips.append(Trip(id: "s\(trips.count)", startedAt: start, endedAt: start.addingTimeInterval(minutes * 60),
                                  startStation: byNumber[from]!.name, endStation: byNumber[to]!.name, startStationNumber: from, endStationNumber: to,
                                  startStand: 1 + random(20), endStand: 1 + random(20), bikeNumber: bike, bikeType: electrical ? .electrical : .mechanical,
                                  duration: minutes, price: minutes > 30 ? 100 : 0, fullPrice: minutes > 30 ? 100 : 0,
                                  pointsEarned: random(3) == 0 ? 5 : 0, isRated: true))
            }
        }
        return trips.reversed()
    }()

    static var statsMovements: [StatsMovement] {
        statsTrips.enumerated().compactMap { index, trip in
            if index % 4 == 3 { return StatsMovement(date: trip.endedAt, amount: -10) }
            if index % 5 == 1 { return StatsMovement(date: trip.endedAt, amount: 10) }
            return trip.pointsEarned > 0 ? StatsMovement(date: trip.endedAt, amount: trip.pointsEarned) : nil
        }
    }

    static func stats() -> Stats {
        buildStats(StatsInput(trips: statsTrips, coords: byNumber.mapValues(\.point), movements: statsMovements,
                              balance: dashboard.rewards.balance, now: now))
    }
}

extension SampleService {
    func stats() async throws -> Stats { SampleData.stats() }
}
