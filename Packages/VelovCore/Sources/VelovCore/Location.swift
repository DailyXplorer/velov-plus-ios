import Foundation

public enum LocationAuth: String, Sendable {
    case notDetermined, restricted, denied, authorizedAlways, authorizedWhenInUse

    public var allowed: Bool { self == .authorizedWhenInUse || self == .authorizedAlways }
}

public enum LocationFailure: Error, Equatable, Sendable {
    case servicesOff, denied, timedOut, unavailable

    public var message: String {
        switch self {
        case .servicesOff: "Le service de localisation est désactivé sur ce téléphone."
        case .denied: "Autorisez la localisation dans Réglages pour trouver les stations autour de vous."
        case .timedOut: "La localisation a pris trop de temps. Réessayez."
        case .unavailable: "Position introuvable pour le moment."
        }
    }

    public var action: ToastAction? {
        switch self {
        case .servicesOff, .denied: .openSettings
        case .timedOut, .unavailable: nil
        }
    }
}

public enum LocationErrorCode {
    public static let locationUnknown = 0
    public static let denied = 1
}

public struct LocationRequest<Fix> {
    public enum Phase: Equatable, Sendable { case idle, awaitingPermission, locating }

    public enum Effect {
        case requestPermission
        case requestLocation
        case succeed(Fix)
        case fail(LocationFailure)
    }

    public private(set) var phase = Phase.idle

    public init() {}

    public mutating func start(servicesEnabled: Bool, auth: LocationAuth) -> Effect? {
        guard phase == .idle else { return nil }
        if !servicesEnabled { return .fail(.servicesOff) }
        switch auth {
        case .denied, .restricted: return .fail(.denied)
        case .notDetermined:
            phase = .awaitingPermission
            return .requestPermission
        case .authorizedWhenInUse, .authorizedAlways:
            phase = .locating
            return .requestLocation
        }
    }

    public mutating func authorizationChanged(_ auth: LocationAuth) -> Effect? {
        switch (phase, auth) {
        case (.idle, _), (_, .notDetermined): return nil
        case (_, .denied), (_, .restricted): return end(.fail(.denied))
        case (.awaitingPermission, _):
            phase = .locating
            return .requestLocation
        case (.locating, _): return nil
        }
    }

    public mutating func failed(code: Int) -> Effect? {
        guard phase != .idle else { return nil }
        switch code {
        case LocationErrorCode.locationUnknown: return nil
        case LocationErrorCode.denied: return end(.fail(.denied))
        default: return end(.fail(.unavailable))
        }
    }

    public mutating func located(_ fix: Fix) -> Effect? {
        phase == .idle ? nil : end(.succeed(fix))
    }

    public mutating func timedOut() -> Effect? {
        phase == .locating ? end(.fail(.timedOut)) : nil
    }

    private mutating func end(_ effect: Effect) -> Effect {
        phase = .idle
        return effect
    }
}

extension LocationRequest.Effect: Equatable where Fix: Equatable {}
