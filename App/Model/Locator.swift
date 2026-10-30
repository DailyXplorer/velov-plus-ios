import CoreLocation
import VelovCore

@MainActor
final class Locator: NSObject, CLLocationManagerDelegate {
    static let shared = Locator()

    private let manager = CLLocationManager()
    private var request = LocationRequest<CLLocation>()
    private var waiting: [CheckedContinuation<CLLocation, Error>] = []
    private var timeout: Task<Void, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    var allowed: Bool { LocationAuth(manager.authorizationStatus).allowed }

    func locate() async throws -> CLLocation {
        if allowed, let recent = manager.location, recent.timestamp.timeIntervalSinceNow > -30 { return recent }
        let services = await Task.detached { CLLocationManager.locationServicesEnabled() }.value
        return try await withCheckedThrowingContinuation { continuation in
            waiting.append(continuation)
            apply(request.start(servicesEnabled: services, auth: LocationAuth(manager.authorizationStatus)))
        }
    }

    private func apply(_ effect: LocationRequest<CLLocation>.Effect?) {
        switch effect {
        case nil: break
        case .requestPermission: manager.requestWhenInUseAuthorization()
        case .requestLocation:
            manager.requestLocation()
            timeout?.cancel()
            timeout = Task {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { return }
                apply(request.timedOut())
            }
        case .succeed(let location): finish(.success(location))
        case .fail(let reason): finish(.failure(reason))
        }
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        timeout?.cancel()
        timeout = nil
        let callers = waiting
        waiting = []
        for caller in callers { caller.resume(with: result) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let auth = LocationAuth(manager.authorizationStatus)
        Task { @MainActor in self.apply(self.request.authorizationChanged(auth)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.apply(self.request.located(location)) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let code = (error as NSError).code
        Task { @MainActor in self.apply(self.request.failed(code: code)) }
    }
}

private extension LocationAuth {
    init(_ status: CLAuthorizationStatus) {
        switch status {
        case .restricted: self = .restricted
        case .denied: self = .denied
        case .authorizedAlways: self = .authorizedAlways
        case .authorizedWhenInUse: self = .authorizedWhenInUse
        case .notDetermined: self = .notDetermined
        @unknown default: self = .notDetermined
        }
    }
}
