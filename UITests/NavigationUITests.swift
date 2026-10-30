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

    private func visible(_ app: XCUIApplication, _ predicate: NSPredicate, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if app.staticTexts.matching(predicate).allElementsBoundByIndex.contains(where: { $0.isHittable }) { return true }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        return false
    }

    private func visible(_ app: XCUIApplication, _ label: String, timeout: TimeInterval = 5) -> Bool {
        visible(app, NSPredicate(format: "label == %@", label), timeout: timeout)
    }

    func testBikeInStationSheetSwipesBackToList() {
        let app = launch("bikeSheet")
        XCTAssertTrue(visible(app, "Vélo 20449", timeout: 30), "the bike page is pushed inside the bikes sheet")
        sleep(2)
        swipeBack(app)
        XCTAssertTrue(visible(app, "Bellecour / St Exupéry"), "the bike page swipes back to the station's bikes")
        shot("swipe-bikeSheet")
    }

    func testRecordsBikeSwipesBackToStats() {
        let app = launch("statsBike")
        XCTAssertTrue(visible(app, NSPredicate(format: "label MATCHES %@", "Vélo [0-9]+"), timeout: 30), "the favourite bike is pushed from Records")
        sleep(2)
        swipeBack(app)
        XCTAssertTrue(visible(app, "Records"), "the bike page swipes back to Statistiques")
        shot("swipe-statsBike")
    }

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
        swipeBack(app)
        sleep(1)
        XCTAssertTrue(title.exists, "an edge swipe does not close the dialog while sending")
        shot("held-while-sending")
        XCTAssertTrue(title.waitForNonExistence(timeout: 20), "the dialog closes itself once the booking is sent")
        XCTAssertTrue(visible(app, "Vélo 20449"), "the edge swipe did not pop the bike page behind the dialog")
    }

    func testAnEditedFormAsksBeforeItIsLeft() {
        let app = launch("profilePage")
        XCTAssertTrue(visible(app, "Modifier mes coordonnées", timeout: 30))
        let country = app.buttons["Pays, France"]
        XCTAssertTrue(country.waitForExistence(timeout: 5))
        country.tap()
        let belgium = app.buttons["Belgique"]
        XCTAssertTrue(belgium.waitForExistence(timeout: 5))
        belgium.tap()
        XCTAssertTrue(app.buttons["Pays, Belgique"].waitForExistence(timeout: 5), "the form is edited")
        let ask = header(app, "Ignorer les modifications\u{a0}?")
        let keep = { app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.1)).tap() }

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(ask.waitForExistence(timeout: 5), "the system back button asks before discarding")
        shot("leave-back")
        keep()
        XCTAssertTrue(ask.waitForNonExistence(timeout: 5), "tapping outside keeps the edits")
        XCTAssertTrue(visible(app, "Modifier mes coordonnées"), "keeping the edits stays on the form")

        swipeBack(app)
        XCTAssertTrue(ask.waitForExistence(timeout: 5), "swipe-back asks before discarding")
        keep()
        XCTAssertTrue(ask.waitForNonExistence(timeout: 5))
        XCTAssertTrue(visible(app, "Modifier mes coordonnées"), "the swipe left the form in place")

        app.buttons["Accueil"].tap()
        XCTAssertTrue(ask.waitForExistence(timeout: 5), "switching tab asks before discarding")
        shot("leave-tab")
        app.buttons["Ignorer"].tap()
        XCTAssertTrue(visible(app, "Vue d’ensemble"), "discarding goes to the tapped tab")
        app.buttons.matching(NSPredicate(format: "label == %@", "Compte")).firstMatch.tap()
        XCTAssertTrue(visible(app, "Compte"), "the discarded form is no longer on the Compte stack")
        XCTAssertFalse(visible(app, "Modifier mes coordonnées", timeout: 1))
    }
}
