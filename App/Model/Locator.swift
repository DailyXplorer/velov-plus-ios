import CoreLocation
import VelovCore

/// One position fix on demand, with the permission asked the first time. A single instance for the app: CoreLocation
/// holds its delegate weakly, so a locator made per call could be gone before the answer comes.
@MainActor
final class Locator: NSObject, CLLocationManagerDelegate {
    static let shared = Locator()

    struct Failure: Error {
        let reason: LocationFailure
        /// « CLError … · auth … · services … ».
        let raw: String
        var message: String { reason.message }
    }

    private let manager = CLLocationManager()
    private var request = LocationRequest<CLLocation>()
    private var waiting: [CheckedContinuation<CLLocation, Error>] = []
    private var timeout: Task<Void, Never>?
    private var servicesEnabled = true

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    var allowed: Bool { LocationAuth(manager.authorizationStatus).allowed }

    /// Callers during a running request share its answer. A reduced-accuracy fix is accepted as is.
    func locate() async throws -> CLLocation {
        if allowed, let recent = manager.location, recent.timestamp.timeIntervalSinceNow > -30 { return recent }
        // Off the main thread: CoreLocation warns that this check can block the UI.
        let services = await Task.detached { CLLocationManager.locationServicesEnabled() }.value
        return try await withCheckedThrowingContinuation { continuation in
            waiting.append(continuation)
            servicesEnabled = services
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
        case .fail(let reason):
            let raw = locationRawLine(errorCode: request.errorCode, auth: LocationAuth(manager.authorizationStatus), servicesEnabled: servicesEnabled)
            finish(.failure(Failure(reason: reason, raw: raw)))
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
