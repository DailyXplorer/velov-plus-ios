import XCTest

final class NavigationUITests: XCTestCase {
    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["VELOV_SHOT_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func launch(_ screen: String, slow: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-VelovSample", "YES", "-VelovScreen", screen] + (slow ? ["-VelovSlow", "YES"] : [])
        app.launch()
        return app
    }

    private func swipeBack(_ app: XCUIApplication) {
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.005, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
    }

    private func header(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "label == %@", title)).firstMatch
    }

    private func assertSwipeBack(_ screen: String, page: String, parent: String) {
        let app = launch(screen)
        XCTAssertTrue(header(app, page).waitForExistence(timeout: 20), "\(screen) shows \(page)")
        sleep(2)
        swipeBack(app)
        let back = header(app, parent)
        XCTAssertTrue(back.waitForExistence(timeout: 5) && back.isHittable, "\(screen) swipes back to \(parent)")
        shot("swipe-\(screen)")
    }

    func testStatsSwipesBackToTrips() { assertSwipeBack("stats", page: "Statistiques", parent: "Trajets") }
    func testTripSwipesBackToTrips() { assertSwipeBack("tripSheet", page: "Trajet", parent: "Trajets") }
    func testBikeSwipesBackToTrip() { assertSwipeBack("bikePage", page: "Vélo 20449", parent: "Trajet") }
    func testProfileSwipesBackToAccount() { assertSwipeBack("profilePage", page: "Modifier mes coordonnées", parent: "Compte") }
    func testContactSwipesBackToAccount() { assertSwipeBack("contactPage", page: "Écrire au service client", parent: "Compte") }
    func testJournalSwipesBackToAccount() { assertSwipeBack("journalPage", page: "Journal technique", parent: "Compte") }

    func testEveryWayOutIsHeldWhileSending() {
        let app = launch("bookConfirm", slow: true)
        let confirm = app.buttons["Confirmer"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 30))
        confirm.tap()
        sleep(1)
        let title = header(app, "Réserver le vélo 20449\u{a0}?")
        XCTAssertTrue(title.exists, "dialog open while sending")
        XCTAssertFalse(app.buttons["Annuler"].isEnabled, "Annuler disabled while sending")
        for close in app.buttons.matching(NSPredicate(format: "label == %@", "Fermer")).allElementsBoundByIndex where close.isHittable { close.tap() }
        sleep(1)
        XCTAssertTrue(title.exists, "X does not close the dialog while sending")
        title.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.98)))
        sleep(1)
        XCTAssertTrue(title.exists, "drag down does not close the dialog while sending")
        shot("held-while-sending")
    }
}
