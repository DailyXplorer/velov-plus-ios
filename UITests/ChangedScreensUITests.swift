import XCTest

final class ChangedScreensUITests: XCTestCase {
    private func capture(_ screen: String, _ name: String, until label: String, wait: UInt32 = 4) {
        let app = XCUIApplication()
        app.launchArguments = ["-VelovSample", "YES", "-VelovScreen", screen]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch.waitForExistence(timeout: 30), "\(screen) shows \(label)")
        sleep(wait)
        guard let dir = ProcessInfo.processInfo.environment["VELOV_SHOT_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    func testOverviewMap() { capture("overviewMap", "01b-overview-map", until: "Explorer les stations", wait: 5) }
    func testBikeList() { capture("bikeList", "05-bike-list", until: "Actualiser les vélos") }
    func testBikePage() { capture("bikeSheet", "06-bike-sheet", until: "Vélo 20449") }
    func testGuestBikePage() { capture("guestBikeSheet", "46-guest-bike-sheet", until: "Se connecter pour réserver ou déverrouiller") }
    func testProfilePage() { capture("profilePage", "21-profile-page", until: "Modifier mes coordonnées") }
    func testViaChoices() { capture("viaChoices", "27b-via-choices", until: "Choisir une station", wait: 6) }
    func testViaChosen() { capture("viaChosen", "27c-via-chosen", until: "Continuer", wait: 5) }
    func testViaReview() { capture("viaReview", "28-via-review", until: "Confirmer", wait: 5) }

    func testAccountEnd() { capture("accountEnd", "40-account-end", until: "Ouvrir le journal", wait: 3) }

    func testLeaveAlert() {
        let app = XCUIApplication()
        app.launchArguments = ["-VelovSample", "YES", "-VelovScreen", "profilePage"]
        app.launch()
        let country = app.buttons["Pays, France"]
        XCTAssertTrue(country.waitForExistence(timeout: 30))
        country.tap()
        XCTAssertTrue(app.buttons["Belgique"].waitForExistence(timeout: 5))
        app.buttons["Belgique"].tap()
        XCTAssertTrue(app.buttons["Pays, Belgique"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["Continuer la saisie"].waitForExistence(timeout: 5), "leaving the edited form asks first")
        sleep(1)
        guard let dir = ProcessInfo.processInfo.environment["VELOV_SHOT_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("48-leave-alert.png"))
    }
}
