import XCTest

final class SelectMenuUITests: XCTestCase {
    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["VELOV_SHOT_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-VelovSample", "YES", "-VelovScreen", screen]
        app.launch()
        return app
    }

    private func button(_ app: XCUIApplication, startingWith prefix: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
    }

    private func reveal(_ app: XCUIApplication, _ element: XCUIElement) {
        var tries = 0
        while !(element.exists && element.isHittable) && tries < 12 { app.swipeUp(velocity: .slow); tries += 1 }
    }

    private func open(_ app: XCUIApplication, _ prefix: String, shot name: String) {
        let trigger = button(app, startingWith: prefix)
        XCTAssertTrue(trigger.waitForExistence(timeout: 20))
        reveal(app, trigger)
        trigger.tap()
        sleep(1)
        shot(name)
        let close = app.buttons["Fermer"]
        if close.exists { close.tap() } else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap() }
        sleep(1)
    }

    func testStationFilterOpensItsChoices() {
        let app = launch("stations")
        let trigger = button(app, startingWith: "Afficher")
        XCTAssertTrue(trigger.waitForExistence(timeout: 20))
        trigger.tap()
        let favorites = app.buttons["Favorites"]
        XCTAssertTrue(favorites.waitForExistence(timeout: 5))
        sleep(1)
        shot("menu-1-stations")
        favorites.tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label == %@", "Afficher, Favorites")).firstMatch.waitForExistence(timeout: 5))
    }

    func testTripFilterOpensItsChoices() {
        open(launch("trips"), "Type de vélo", shot: "menu-2-trajets")
    }

    func testStatsPeriodOpensItsChoices() {
        open(launch("stats"), "Période", shot: "menu-3-statistiques")
    }

    func testCountryOpensItsChoices() {
        open(launch("accountEdit"), "Pays", shot: "menu-4-pays")
    }

    func testContactFieldsOpenTheirChoices() {
        let app = launch("account")
        let write = button(app, startingWith: "Écrire au service client")
        XCTAssertTrue(write.waitForExistence(timeout: 20))
        reveal(app, write)
        write.tap()
        open(app, "Objet", shot: "menu-5-objet")
        open(app, "Trajet (facultatif)", shot: "menu-6-trajet")
    }
}
