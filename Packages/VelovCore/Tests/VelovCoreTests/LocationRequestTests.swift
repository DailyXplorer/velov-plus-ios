import XCTest
@testable import VelovCore

final class LocationRequestTests: XCTestCase {
    func testServicesOffFailsBeforeAnyPrompt() {
        var request = LocationRequest<String>()
        XCTAssertEqual(request.start(servicesEnabled: false, auth: .notDetermined), .fail(.servicesOff))
        XCTAssertEqual(request.phase, .idle)
        XCTAssertEqual(LocationFailure.servicesOff.message, "Le service de localisation est désactivé sur ce téléphone.")
    }

    func testDeniedOrRestrictedFailsWithTheSettingsPath() {
        for auth in [LocationAuth.denied, .restricted] {
            var request = LocationRequest<String>()
            XCTAssertEqual(request.start(servicesEnabled: true, auth: auth), .fail(.denied))
        }
        XCTAssertEqual(LocationFailure.denied.message, "Localisation refusée. Autorisez-la dans Réglages > Vélo’v+ > Position.")
    }

    func testNoTimeoutWhileThePermissionPromptIsPending() {
        var request = LocationRequest<String>()
        XCTAssertEqual(request.start(servicesEnabled: true, auth: .notDetermined), .requestPermission)
        XCTAssertNil(request.timedOut())
        XCTAssertNil(request.authorizationChanged(.notDetermined))
        XCTAssertEqual(request.phase, .awaitingPermission)
        XCTAssertEqual(request.authorizationChanged(.authorizedWhenInUse), .requestLocation)
        XCTAssertEqual(request.timedOut(), .fail(.timedOut))
    }

    func testAlreadyAllowedAsksForAFixRightAway() {
        var request = LocationRequest<String>()
        XCTAssertEqual(request.start(servicesEnabled: true, auth: .authorizedAlways), .requestLocation)
        XCTAssertEqual(request.located("fix"), .succeed("fix"))
        XCTAssertEqual(request.phase, .idle)
    }

    func testRefusingThePromptFails() {
        var request = LocationRequest<String>()
        _ = request.start(servicesEnabled: true, auth: .notDetermined)
        XCTAssertEqual(request.authorizationChanged(.denied), .fail(.denied))
        XCTAssertEqual(request.phase, .idle)
    }

    func testLocationUnknownKeepsWaitingUntilAFixOrTheTimeout() {
        var request = LocationRequest<String>()
        _ = request.start(servicesEnabled: true, auth: .authorizedWhenInUse)
        XCTAssertNil(request.failed(code: LocationErrorCode.locationUnknown))
        XCTAssertEqual(request.phase, .locating)
        XCTAssertEqual(request.located("fix"), .succeed("fix"))

        _ = request.start(servicesEnabled: true, auth: .authorizedWhenInUse)
        XCTAssertNil(request.failed(code: LocationErrorCode.locationUnknown))
        XCTAssertEqual(request.timedOut(), .fail(.timedOut))
        XCTAssertEqual(request.errorCode, LocationErrorCode.locationUnknown)
    }

    func testDeniedAndOtherErrorsFail() {
        var request = LocationRequest<String>()
        _ = request.start(servicesEnabled: true, auth: .authorizedWhenInUse)
        XCTAssertEqual(request.failed(code: LocationErrorCode.denied), .fail(.denied))
        _ = request.start(servicesEnabled: true, auth: .authorizedWhenInUse)
        XCTAssertNil(request.errorCode)
        XCTAssertEqual(request.failed(code: 2), .fail(.unavailable))
        XCTAssertEqual(request.errorCode, 2)
    }

    func testASecondCallerJoinsTheRunningRequest() {
        var request = LocationRequest<String>()
        _ = request.start(servicesEnabled: true, auth: .notDetermined)
        XCTAssertNil(request.start(servicesEnabled: true, auth: .notDetermined))
        XCTAssertEqual(request.phase, .awaitingPermission)
    }

    func testEventsAfterTheEndDoNothing() {
        var request = LocationRequest<String>()
        _ = request.start(servicesEnabled: true, auth: .authorizedWhenInUse)
        _ = request.located("fix")
        XCTAssertNil(request.timedOut())
        XCTAssertNil(request.located("late"))
        XCTAssertNil(request.failed(code: 2))
        XCTAssertNil(request.authorizationChanged(.denied))
    }

    func testRawLine() {
        XCTAssertEqual(locationRawLine(errorCode: 0, auth: .authorizedWhenInUse, servicesEnabled: true),
                       "CLError 0 · auth authorizedWhenInUse · services on")
        XCTAssertEqual(locationRawLine(errorCode: nil, auth: .notDetermined, servicesEnabled: false),
                       "CLError — · auth notDetermined · services off")
    }
}
