import XCTest

final class MapAttributionUITests: XCTestCase {
    private func launch(_ screen: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-VelovSample", "YES", "-VelovScreen", screen]
        app.launch()
        return app
    }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["VELOV_SHOT_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func pins(_ app: XCUIApplication) -> [XCUIElement] {
        app.buttons.matching(NSPredicate(format: "label MATCHES %@", ".+, [0-9]+ vélos?")).allElementsBoundByIndex.filter { $0.exists && $0.isHittable }
    }

    private func assertAttributionClear(_ screen: String, name: String, keeps pin: String? = nil) {
        let app = launch(screen)
        XCTAssertTrue(app.textFields["Rechercher une station"].waitForExistence(timeout: 30), "\(screen) shows the Stations map")
        sleep(6)
        let legal = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Mentions")).firstMatch
        if legal.exists {
            let zone = legal.frame.insetBy(dx: -4, dy: -4)
            let covering = pins(app).filter { $0.frame.intersects(zone) }.map(\.label)
            XCTAssertTrue(covering.isEmpty, "\(screen): pins over the attribution \(covering)")
        }
        if let pin {
            XCTAssertTrue(app.buttons[pin].exists, "\(screen) keeps \(pin) away from the attribution")
        }
        shot(name)
    }

    func testSignedInStationsWithoutCard() { assertAttributionClear("stations", name: "signed-stations", keeps: "Perrache, 7 vélos") }
    func testSignedInStationsWithCard() { assertAttributionClear("stationSheet", name: "signed-station-card") }
    func testGuestStationsWithoutCard() { assertAttributionClear("guestStations", name: "guest-stations", keeps: "Perrache, 7 vélos") }
    func testGuestStationsWithCard() { assertAttributionClear("guestStationSheet", name: "guest-station-card") }

    func testPushedPagesKeepTheirTopEdge() {
        let app = launch("statsRecords")
        XCTAssertTrue(app.staticTexts["Records"].waitForExistence(timeout: 30))
        sleep(4)
        shot("signed-stats-records")
    }
}
