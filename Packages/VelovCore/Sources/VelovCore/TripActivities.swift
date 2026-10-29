import Foundation

public struct Ride: Equatable, Sendable {
    public var tripId: String?
    public var startedAt: Date
    public var endedAt: Date?
    public var station: String
    public var bikeNumber: Int?
    public var bikeType: BikeType

    public init(tripId: String?, startedAt: Date, endedAt: Date? = nil, station: String, bikeNumber: Int?, bikeType: BikeType) {
        self.tripId = tripId; self.startedAt = startedAt; self.endedAt = endedAt
        self.station = station; self.bikeNumber = bikeNumber; self.bikeType = bikeType
    }

    public init(_ trip: Trip, now: Date) {
        self.init(tripId: trip.id, startedAt: trip.startedAt ?? now, station: trip.startStation ?? trip.startStationNumber.map { "Station \($0)" } ?? "Vélo’v",
                  bikeNumber: trip.bikeNumber, bikeType: trip.bikeType)
    }
}

public struct RunningRide: Equatable, Sendable {
    public var id: String
    public var ride: Ride
    public init(id: String, ride: Ride) { self.id = id; self.ride = ride }
}

@MainActor
public protocol TripActivityHost: AnyObject {
    var rides: [RunningRide] { get }
    func start(_ ride: Ride, staleDate: Date)
    func update(_ id: String, _ ride: Ride, staleDate: Date)
    func end(_ id: String, _ ride: Ride, dismissAt: Date?)
    func endBookings()
}

@MainActor
public final class TripActivities {
    public static let staleAfter: TimeInterval = 4 * 3600
    public static let linger: TimeInterval = 5 * 60

    private let host: TripActivityHost
    private let now: () -> Date

    public init(host: TripActivityHost, now: @escaping () -> Date = Date.init) {
        self.host = host
        self.now = now
    }

    public func launched() {
        for running in host.rides where now() >= running.ride.startedAt.addingTimeInterval(Self.staleAfter) {
            host.end(running.id, running.ride, dismissAt: nil)
        }
    }

    public func unlocked(_ ride: Ride) {
        follow(ride, adoptPending: false, startKnown: true)
    }

    public func observed(_ ongoing: [Trip]?, latest: Trip? = nil) {
        guard let ongoing else { return }
        guard let trip = ongoing.first else { return settle(latest) }
        follow(Ride(trip, now: now()), adoptPending: true, startKnown: trip.startedAt != nil)
    }

    public func finished(_ trip: Trip) {
        let endedAt = trip.endedAt ?? now()
        for running in host.rides where running.ride.tripId == trip.id || (running.ride.tripId == nil && endedAt > running.ride.startedAt) {
            close(running, endedAt: trip.endedAt)
        }
    }

    public func endAll() {
        for running in host.rides { host.end(running.id, running.ride, dismissAt: nil) }
    }

    private func follow(_ ride: Ride, adoptPending: Bool, startKnown: Bool) {
        var kept: RunningRide?
        for running in host.rides {
            let same = ride.tripId != nil && running.ride.tripId == ride.tripId
            let pending = adoptPending && running.ride.tripId == nil
            if kept == nil && (same || pending) { kept = running } else { close(running, endedAt: nil) }
        }
        guard let kept else {
            host.start(ride, staleDate: ride.startedAt.addingTimeInterval(Self.staleAfter))
            return host.endBookings()
        }
        var next = ride
        if !startKnown { next.startedAt = kept.ride.startedAt }
        if next != kept.ride { host.update(kept.id, next, staleDate: next.startedAt.addingTimeInterval(Self.staleAfter)) }
    }

    private func settle(_ latest: Trip?) {
        for running in host.rides where now().timeIntervalSince(running.ride.startedAt) >= DockWatch.unlockGrace {
            close(running, endedAt: latest.flatMap { $0.id == running.ride.tripId ? $0.endedAt : nil })
        }
    }

    private func close(_ running: RunningRide, endedAt: Date?) {
        var ride = running.ride
        ride.endedAt = max(endedAt ?? now(), ride.startedAt)
        host.end(running.id, ride, dismissAt: now().addingTimeInterval(Self.linger))
    }
}
