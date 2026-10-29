import XCTest
@testable import VelovCore

@MainActor
final class TripActivitiesTests: XCTestCase {
    final class FakeHost: TripActivityHost {
        var rides: [RunningRide] = []
        var started: [(ride: Ride, staleDate: Date)] = []
        var updated: [(id: String, ride: Ride, staleDate: Date)] = []
        var ended: [(id: String, ride: Ride, dismissAt: Date?)] = []
        var bookingsEnded = 0
        private var next = 0

        func start(_ ride: Ride, staleDate: Date) {
            next += 1
            started.append((ride, staleDate))
            rides.append(RunningRide(id: "act-\(next)", ride: ride))
        }

        func update(_ id: String, _ ride: Ride, staleDate: Date) {
            updated.append((id, ride, staleDate))
            if let index = rides.firstIndex(where: { $0.id == id }) { rides[index].ride = ride }
        }

        func end(_ id: String, _ ride: Ride, dismissAt: Date?) {
            ended.append((id, ride, dismissAt))
            rides.removeAll { $0.id == id }
        }

        func endBookings() { bookingsEnded += 1 }
    }

    var clock = date("2026-10-29T12:00:00")
    let host = FakeHost()
    lazy var activities = TripActivities(host: host, now: { [unowned self] in clock })

    func ongoing(_ id: String = "t1", minutesAgo: Double = 3, type: BikeType = .electrical) -> Trip {
        Trip(id: id, status: "ONGOING", startedAt: clock.addingTimeInterval(-minutesAgo * 60), startStation: "Bellecour", startStationNumber: 2002, bikeNumber: 20449, bikeType: type)
    }

    func placeRide() -> Ride {
        Ride(tripId: nil, startedAt: clock, station: "Bellecour", bikeNumber: 20449, bikeType: .unknown)
    }

    func testAnUnlockStartsOneActivityStaleAfterFourHoursAndEndsTheBooking() {
        let trip = ongoing(minutesAgo: 0)
        activities.unlocked(Ride(trip, now: clock))
        XCTAssertEqual(host.started.map(\.ride), [Ride(tripId: "t1", startedAt: clock, station: "Bellecour", bikeNumber: 20449, bikeType: .electrical)])
        XCTAssertEqual(host.started.map(\.staleDate), [clock.addingTimeInterval(4 * 3600)])
        XCTAssertEqual(host.bookingsEnded, 1)
        clock.addTimeInterval(20)
        activities.observed([trip])
        activities.unlocked(Ride(trip, now: clock))
        XCTAssertEqual(host.started.count, 1)
        XCTAssertEqual(host.rides.count, 1)
        XCTAssertTrue(host.ended.isEmpty)
        XCTAssertTrue(host.updated.isEmpty)
    }

    func testTheForegroundStartsTheActivityOnlyWhenNoneIsRunning() {
        activities.observed([ongoing(minutesAgo: 12)])
        activities.observed([ongoing(minutesAgo: 12)])
        XCTAssertEqual(host.started.count, 1)
        XCTAssertEqual(host.started.first?.ride.startedAt, clock.addingTimeInterval(-720))
        XCTAssertEqual(host.bookingsEnded, 1)
        activities.observed(nil)
        XCTAssertEqual(host.rides.count, 1)
        XCTAssertTrue(host.ended.isEmpty)
    }

    func testAnUnlockWithoutTripIdIsAdoptedByTheTripSeenNextAndSurvivesAnEmptyAnswerDuringTheGrace() {
        activities.unlocked(placeRide())
        clock.addTimeInterval(30)
        activities.observed([])
        XCTAssertTrue(host.ended.isEmpty)
        var trip = ongoing(minutesAgo: 0.6)
        trip.startedAt = nil
        activities.observed([trip])
        XCTAssertEqual(host.started.count, 1)
        XCTAssertEqual(host.rides.map(\.ride), [Ride(tripId: "t1", startedAt: clock.addingTimeInterval(-30), station: "Bellecour", bikeNumber: 20449, bikeType: .electrical)])
        XCTAssertEqual(host.updated.map(\.staleDate), [clock.addingTimeInterval(4 * 3600 - 30)])
    }

    func testTheTripSeenFinishedEndsTheActivityWithItsFinalDurationShownFiveMinutes() {
        activities.observed([ongoing(minutesAgo: 14)])
        clock.addTimeInterval(60)
        var latest = ongoing(minutesAgo: 15)
        latest.status = "FINISHED"
        latest.endedAt = clock.addingTimeInterval(-25)
        activities.observed([], latest: latest)
        XCTAssertEqual(host.ended.map(\.ride.endedAt), [latest.endedAt])
        XCTAssertEqual(host.ended.map(\.dismissAt), [clock.addingTimeInterval(300)])
        XCTAssertTrue(host.rides.isEmpty)
        activities.finished(latest)
        XCTAssertEqual(host.ended.count, 1)
    }

    func testTheTripEndedSheetEndsOnlyTheMatchingActivity() {
        activities.observed([ongoing("t1", minutesAgo: 20)])
        var other = ongoing("t0", minutesAgo: 90)
        other.endedAt = clock.addingTimeInterval(-3600)
        activities.finished(other)
        XCTAssertTrue(host.ended.isEmpty)
        var mine = ongoing("t1", minutesAgo: 20)
        mine.endedAt = nil
        activities.finished(mine)
        XCTAssertEqual(host.ended.map(\.ride.endedAt), [clock])
        XCTAssertEqual(host.ended.map(\.dismissAt), [clock.addingTimeInterval(300)])
    }

    func testANewTripReplacesTheActivityOfAnEarlierOneSoNeverTwoRun() {
        activities.observed([ongoing("t1", minutesAgo: 40)])
        activities.observed([ongoing("t2", minutesAgo: 2)])
        XCTAssertEqual(host.ended.map(\.id), ["act-1"])
        XCTAssertEqual(host.ended.first?.ride.endedAt, clock)
        XCTAssertEqual(host.rides.map(\.ride.tripId), ["t2"])
        activities.unlocked(placeRide())
        XCTAssertEqual(host.rides.map(\.ride.tripId), [nil])
        XCTAssertEqual(host.started.count, 3)
    }

    func testTheLaunchEndsStaleActivitiesAtOnceAndKeepsFreshOnes() {
        activities.observed([ongoing("old", minutesAgo: 240)])
        host.rides.append(RunningRide(id: "fresh", ride: Ride(ongoing("t2", minutesAgo: 239), now: clock)))
        activities.launched()
        XCTAssertEqual(host.ended.map(\.id), ["act-1"])
        XCTAssertEqual(host.ended.map(\.dismissAt), [nil])
        XCTAssertEqual(host.rides.map(\.id), ["fresh"])
    }
}
