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

    func testAGuestOnlySeesStationsAndIsAskedToSignInOnABike() {
        let app = launch("guestBikeSheet")
        let signIn = app.buttons["Se connecter pour réserver ou déverrouiller"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 30), "the bike page offers sign-in in place of its actions")
        XCTAssertFalse(app.buttons["Réserver"].exists || app.buttons["Déverrouiller"].exists, "a guest has no bike action")
        shot("guest-bike-page")
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(signIn.waitForExistence(timeout: 10), "returning to the app starts no account request")
        signIn.tap()
        let guest = app.buttons["Continuer sans compte"]
        XCTAssertTrue(guest.waitForExistence(timeout: 10), "the link opens the login screen")
        guest.tap()
        XCTAssertTrue(guest.waitForNonExistence(timeout: 10), "Continuer sans compte leaves the login screen")
    }

    func testAGuestHasNoAccountTabs() {
        let app = launch("guestStations")
        let signIn = app.buttons["Se connecter"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 30) && signIn.isHittable, "Se connecter is in the Stations header")
        XCTAssertTrue(visible(app, "Stations"))
        for tab in ["Accueil", "Trajets", "Points", "Compte", "Mon compte"] {
            XCTAssertFalse(app.buttons[tab].exists, "a guest has no \(tab)")
        }
        shot("guest-stations")
        signIn.tap()
        XCTAssertTrue(app.buttons["Continuer sans compte"].waitForExistence(timeout: 10), "Se connecter opens the login screen")
    }

    private func bookingShown(_ app: XCUIApplication) -> Bool {
        app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Vélo réservé")).count > 0 || app.buttons["Déverrouiller"].exists
    }

    func testAnExpiredSessionLeavesNothingOfTheAccountToTheGuest() {
        let app = launch("expiredSession")
        let guest = app.buttons["Continuer sans compte"]
        XCTAssertTrue(guest.waitForExistence(timeout: 30), "the expired session goes back to the login screen")
        XCTAssertTrue(visible(app, "Votre session a expiré. Reconnectez-vous."))
        sleep(2)
        guest.tap()
        XCTAssertTrue(visible(app, "Stations", timeout: 10), "Continuer sans compte opens the guest map")
        sleep(1)
        XCTAssertFalse(bookingShown(app), "the guest map shows no booking of the expired account")
        shot("expired-guest")
        app.terminate()
        app.launchArguments += ["-VelovRelaunch", "YES"]
        app.launch()
        XCTAssertTrue(visible(app, "Stations", timeout: 30), "the relaunch starts as guest")
        XCTAssertFalse(guest.exists, "the relaunch does not go back to the login screen")
        sleep(3)
        XCTAssertEqual(app.state, .runningForeground, "the relaunch sends no account request")
        XCTAssertFalse(bookingShown(app))
    }

    func testABookedBikeUnlocksWhileTheAccountIsUnavailable() {
        let app = launch("bookingWithoutAccount")
        let unlock = app.buttons["Déverrouiller"]
        XCTAssertTrue(unlock.waitForExistence(timeout: 30), "the booking banner shows although the account failed")
        unlock.tap()
        let confirm = app.buttons["Confirmer"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        confirm.tap()
        XCTAssertFalse(visible(app, NSPredicate(format: "label CONTAINS %@", "ne peut pas suivre cette action"), timeout: 3), "the unlock is not refused as unsaved")
        XCTAssertTrue(confirm.waitForNonExistence(timeout: 10), "the unlock is sent and the sheet closes")
        shot("booking-without-account")
    }

    private func tap(_ app: XCUIApplication, _ label: String, scroll: Bool = false) {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", label))
        XCTAssertTrue(matches.firstMatch.waitForExistence(timeout: 10), "\(label) is shown")
        for _ in 0..<5 {
            if let button = matches.allElementsBoundByIndex.last(where: { $0.isHittable }) { return button.tap() }
            if scroll { app.swipeUp() } else { sleep(1) }
        }
        XCTFail("\(label) can be tapped")
    }

    func testATripChosenForSupportIsForgottenAtLogout() {
        let app = launch("contactUncertain")
        let restart = app.buttons["Écrire un nouveau message"]
        XCTAssertTrue(restart.waitForExistence(timeout: 30), "the first message is uncertain")
        tap(app, "Fermer")
        tap(app, "Annuler")
        tap(app, "Ignorer")
        tap(app, "Trajets")
        let disputed = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Trajet de Terreaux")).firstMatch
        XCTAssertTrue(disputed.waitForExistence(timeout: 10), "the disputed trip is listed")
        disputed.tap()
        tap(app, "Écrire au service client", scroll: true)
        XCTAssertTrue(restart.waitForExistence(timeout: 10), "support asked from the disputed trip shows the uncertain message")
        tap(app, "Fermer")
        tap(app, "Se déconnecter", scroll: true)
        let title = header(app, "Se déconnecter\u{a0}?")
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        sleep(1)
        let below = app.descendants(matching: .any).matching(NSPredicate(format: "label ==[c] %@", "Se déconnecter")).allElementsBoundByIndex.filter { $0.frame.minY > title.frame.maxY }
        if let confirm = below.first { confirm.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() } else {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.width * 0.72, dy: title.frame.midY + 66)).tap()
        }
        let email = app.textFields["Adresse e-mail"]
        XCTAssertTrue(email.waitForExistence(timeout: 10), "the logout opens the login screen")
        email.tap()
        email.typeText("person@example.com")
        let code = app.secureTextFields["Code secret à 6 chiffres"]
        code.tap()
        code.typeText("123456")
        tap(app, "Se connecter")
        tap(app, "Compte")
        tap(app, "Écrire au service client", scroll: true)
        XCTAssertTrue(restart.waitForExistence(timeout: 10))
        restart.tap()
        let tripField = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Trajet (facultatif)")).firstMatch
        XCTAssertTrue(tripField.waitForExistence(timeout: 10), "the new message form is open")
        XCTAssertEqual(tripField.label, "Trajet (facultatif), Aucun", "the trip chosen before the logout is not chosen for the next session")
        shot("contact-after-logout")
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
        let keep = { app.buttons["Continuer la saisie"].tap() }

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(ask.waitForExistence(timeout: 5), "the system back button asks before discarding")
        XCTAssertTrue(app.buttons["Ignorer"].isHittable && app.buttons["Continuer la saisie"].isHittable, "both choices are shown")
        shot("leave-back")
        keep()
        XCTAssertTrue(ask.waitForNonExistence(timeout: 5), "Continuer la saisie keeps the edits")
        XCTAssertTrue(visible(app, "Modifier mes coordonnées"), "keeping the edits stays on the form")

        swipeBack(app)
        XCTAssertTrue(ask.waitForExistence(timeout: 5), "swipe-back asks before discarding")
        keep()
        XCTAssertTrue(ask.waitForNonExistence(timeout: 5))
        XCTAssertTrue(visible(app, "Modifier mes coordonnées"), "the swipe left the form in place")

        app.buttons["Accueil"].tap()
        XCTAssertTrue(ask.waitForExistence(timeout: 5), "switching tab asks before discarding")
        app.buttons["Ignorer"].tap()
        XCTAssertTrue(visible(app, "Vue d’ensemble"), "discarding goes to the tapped tab")
        shot("leave-tab")
        app.buttons.matching(NSPredicate(format: "label == %@", "Compte")).firstMatch.tap()
        XCTAssertTrue(visible(app, "Compte"), "the discarded form is no longer on the Compte stack")
        XCTAssertFalse(visible(app, "Modifier mes coordonnées", timeout: 1))
    }
}
