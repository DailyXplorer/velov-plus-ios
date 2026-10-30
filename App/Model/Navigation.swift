import Foundation
import VelovCore

struct TripRoute: Hashable {
    let trip: Trip
    static func == (left: TripRoute, right: TripRoute) -> Bool { left.trip.id == right.trip.id }
    func hash(into hasher: inout Hasher) { hasher.combine(trip.id) }
}

enum Route: Hashable {
    case stats
    case trip(TripRoute)
    case bike(BikeRoute)
    case profile
    case contact
    case journal
}

enum ActiveSheet: Identifiable {
    case logout
    case unlock(Booking)
    case ended(Trip)
    case via

    var id: String {
        switch self {
        case .logout: "logout"
        case .unlock(let booking): "unlock-\(booking.id)"
        case .ended(let trip): "ended-\(trip.id)"
        case .via: "via"
        }
    }
}
