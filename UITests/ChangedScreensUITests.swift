import XCTest

final class ChangedScreensUITests: XCTestCase {
    private func launch(_ screen: String, until label: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-VelovSample", "YES", "-VelovScreen", screen]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch.waitForExistence(timeout: 30), "\(screen) shows \(label)")
        return app
    }

    private func shot(_ name: String) {
        guard let dir = ProcessInfo.processInfo.environment["VELOV_SHOT_DIR"] else { return }
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
    }

    private func capture(_ screen: String, _ name: String, until label: String, wait: UInt32 = 4) {
        _ = launch(screen, until: label)
        sleep(wait)
        shot(name)
    }

    func testOverviewMap() { capture("overviewMap", "01b-overview-map", until: "Explorer les stations", wait: 5) }
    func testStationCard() { capture("stationSheet", "04-stations-sheet", until: "Bellecour") }
    func testStations() { capture("stations", "04a-stations", until: "Rechercher une station") }
    func testStationCardLong() { capture("stationSheetLong", "04b-stations-sheet-long", until: "Part-Dieu Villette") }
    func testBikeList() { capture("bikeList", "05-bike-list", until: "Actualiser les vélos") }
    func testBikePage() { capture("bikeSheet", "06-bike-sheet", until: "Vélo 20449") }
    func testPoints() { capture("points", "07-points", until: "Solde actuel") }
    func testBookingBanner() { capture("bookingBanner", "09-booking-banner", until: "Vélo réservé") }
    func testBookingLockScreen() { capture("liveActivityLock", "10-live-activity-lock", until: "Vélo 20449") }
    func testTripIsland() { capture("tripActivityIsland", "11b-trip-activity-island", until: "Vélo 20449") }
    func testUnlockConfirm() { capture("unlockConfirm", "12-unlock-confirm", until: "Confirmer", wait: 5) }
    func testUnlockUncertain() { capture("unlockUncertain", "13-unlock-uncertain", until: "Fermer", wait: 6) }
    func testStats() { capture("stats", "16a-stats", until: "Minutes à vélo", wait: 5) }
    func testStatsBike() { capture("statsBike", "16f-stats-bike-sheet", until: "Vélo", wait: 5) }
    func testHeatmapTip() { capture("statsHeatTip", "16i-stats-heatmap-tooltip", until: "Horaires de départ", wait: 6) }
    func testTripEnded() { capture("tripEnded", "17-trip-ended", until: "Plus tard", wait: 5) }
    func testOngoingBanner() throws {
        let app = launch("ongoingBanner", until: "Trajet en cours")
        sleep(4)
        shot("19-ongoing-banner")
        try XCTSkipIf(app.windows.firstMatch.frame.width < 400, "the pill stacks under the clock on a small iPhone")
        let clock = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Trajet en cours")).firstMatch.frame
        let pill = app.buttons["15 minutes de plus"].firstMatch.frame
        XCTAssertTrue(pill.minY < clock.midY && clock.midY < pill.maxY, "the trip clock and its pill share one row: clock \(clock), pill \(pill)")
    }
    func testOngoingBannerLong() { capture("ongoingLong", "19b-ongoing-banner-long", until: "Trajet en cours") }
    func testBikePushedFromTrip() { capture("bikePage", "20-bike-page", until: "Vélo 20449", wait: 5) }
    func testProfilePage() { capture("profilePage", "21-profile-page", until: "Modifier mes coordonnées") }
    func testToggleDialog() { capture("toggleDialog", "24-toggle-dialog", until: "Confirmer", wait: 5) }
    func testChoiceSheet() { capture("choiceSheet", "26-choice-sheet", until: "Pays", wait: 5) }
    func testViaPick() { capture("viaPick", "27-via-pick", until: "Les plus proches", wait: 5) }
    func testViaChoices() { capture("viaChoices", "27b-via-choices", until: "Station pleine", wait: 6) }
    func testViaChosen() { capture("viaChosen", "27c-via-chosen", until: "Continuer", wait: 5) }
    func testViaReview() { capture("viaReview", "28-via-review", until: "Confirmer", wait: 5) }
    func testViaUncertain() { capture("viaUncertain", "29-via-uncertain", until: "Fermer", wait: 6) }
    func testInviteCode() { capture("inviteCode", "31-invite-code", until: "Copier", wait: 5) }
    func testRenewalToggle() { capture("renewalToggle", "32-renewal-toggle", until: "Télécharger le reçu", wait: 5) }
    func testContactUncertain() { capture("contactUncertain", "34-contact-uncertain", until: "Fermer", wait: 6) }
    func testStationsSearch() { capture("stationsSearch", "35-stations-search", until: "Part-Dieu", wait: 5) }
    func testStationsEmptyFilter() { capture("stationsEmptyFilter", "36-stations-empty-filter", until: "Toutes les stations", wait: 5) }
    func testAccountEnd() { capture("accountEnd", "40-account-end", until: "Ouvrir le journal", wait: 3) }
    func testOwnBookedBike() { capture("bikeOwnBooking", "40b-bike-own-booking", until: "Vélo réservé", wait: 5) }
    func testGuestStations() { capture("guestStations", "44-guest-stations", until: "Se connecter") }
    func testGuestBikePage() { capture("guestBikeSheet", "46-guest-bike-sheet", until: "Se connecter pour réserver ou déverrouiller") }
    func testStationsFailure() { capture("stationsFailure", "47-stations-failure", until: "Réessayer", wait: 3) }

    func testDisputedTrip() {
        let app = launch("tripDisputed", until: "Écrire au service client")
        sleep(3)
        shot("49-trip-disputed")
        app.buttons["Écrire au service client"].firstMatch.tap()
        sleep(3)
        shot("49b-trip-disputed-contact")
    }

    func testExpiredSessionAsGuest() {
        let app = launch("expiredSession", until: "Continuer sans compte")
        sleep(2)
        shot("50-expired-login")
        app.buttons["Continuer sans compte"].tap()
        sleep(4)
        shot("50b-expired-guest")
    }

    func testGuestRefusedWhileTheSessionStaysStored() {
        let app = launch("guestFailed", until: "Continuer sans compte")
        app.buttons["Continuer sans compte"].tap()
        XCTAssertTrue(app.staticTexts["Impossible de continuer sans compte. Réessayez."].waitForExistence(timeout: 10), "a failed forget says so")
        XCTAssertTrue(app.buttons["Continuer sans compte"].exists, "a failed forget stays on the login screen")
        sleep(1)
        shot("50c-guest-failed")
    }

    func testBookingWithoutAccount() { capture("bookingWithoutAccount", "51-booking-without-account", until: "Déverrouiller", wait: 4) }

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
        shot("48-leave-alert")
    }
}
