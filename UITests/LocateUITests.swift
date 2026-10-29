import XCTest

final class LocateUITests: XCTestCase {
    private func locate(answering choice: String) -> (XCUIApplication, XCUIElement) {
        let app = XCUIApplication()
        app.launchArguments = ["-VelovSample", "YES", "-VelovScreen", "stations"]
        addUIInterruptionMonitor(withDescription: "Localisation") { alert in
            let button = alert.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", choice)).firstMatch
            guard button.exists else { return false }
            button.tap()
            return true
        }
        app.launch()
        let locate = app.buttons["Stations autour de moi"]
        XCTAssertTrue(locate.waitForExistence(timeout: 20))
        locate.tap()
        sleep(2)
        app.swipeDown()
        let idle = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: locate)
        wait(for: [idle], timeout: 25)
        return (app, locate)
    }

    func testFirstPermissionGrantLocatesTheUser() {
        let (app, _) = locate(answering: "Autoriser lorsque")
        XCTAssertTrue(app.descendants(matching: .any)["Votre position"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["La localisation a pris trop de temps. Réessayez."].exists)
    }

    func testRefusingThePromptStopsWithTheDeniedMessage() {
        let (app, _) = locate(answering: "Ne pas autoriser")
        XCTAssertTrue(app.staticTexts["Localisation refusée. Autorisez-la dans Réglages > Vélo’v+ > Position."].exists)
        XCTAssertFalse(app.descendants(matching: .any)["Votre position"].exists)
    }
}
