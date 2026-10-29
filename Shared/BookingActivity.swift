import ActivityKit
import Foundation

/// The booking countdown shown on the Lock Screen and in the Dynamic Island. Updated locally only: no push.
struct BookingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var endsAt: Date
    }

    var bikeNumber: Int
    var standNumber: Int
    var stationName: String
}
