import XCTest

final class SelectMenuUITests: XCTestCase {
    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["VELOV_SHOT_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testStationFilterUsesTheSystemMenu() {
        let app = XCUIApplication()
        app.launchArguments = ["-VelovSample", "YES", "-VelovScreen", "stations"]
        app.launch()
        let trigger = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Afficher")).firstMatch
        XCTAssertTrue(trigger.waitForExistence(timeout: 20))
        trigger.tap()
        let favorites = app.buttons["Favorites"]
        XCTAssertTrue(favorites.waitForExistence(timeout: 5))
        sleep(1)
        shot("menu-stations")
        favorites.tap()
        let updated = app.buttons.matching(NSPredicate(format: "label == %@", "Afficher, Favorites")).firstMatch
        XCTAssertTrue(updated.waitForExistence(timeout: 5))
    }

    func testTripFilterUsesTheSystemMenu() {
        let app = XCUIApplication()
        app.launchArguments = ["-VelovSample", "YES", "-VelovScreen", "trips"]
        app.launch()
        let trigger = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Type de vélo")).firstMatch
        XCTAssertTrue(trigger.waitForExistence(timeout: 20))
        trigger.tap()
        sleep(1)
        shot("menu-trips")
    }
}
