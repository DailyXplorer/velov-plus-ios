import Foundation

public struct GeoPoint: Equatable, Sendable, Hashable {
    public var lat: Double
    public var lon: Double
    public init(lat: Double, lon: Double) { self.lat = lat; self.lon = lon }
}

public func haversine(_ from: GeoPoint, _ to: GeoPoint) -> Double {
    let radians = Double.pi / 180
    let latitude = (to.lat - from.lat) * radians
    let longitude = (to.lon - from.lon) * radians
    let arc = pow(sin(latitude / 2), 2) + cos(from.lat * radians) * cos(to.lat * radians) * pow(sin(longitude / 2), 2)
    return 6_371_000 * 2 * atan2(sqrt(arc), sqrt(1 - arc))
}
