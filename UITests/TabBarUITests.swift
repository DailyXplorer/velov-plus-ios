import XCTest

final class TabBarUITests: XCTestCase {
    func testTabsSelectTheTappedPage() {
        let app = XCUIApplication()
        app.launchArguments = ["-VelovSample", "YES"]
        app.launch()
        let home = app.buttons["Vue d’ensemble"]
        XCTAssertTrue(home.waitForExistence(timeout: 20))
        sleep(2)
        for title in ["Compte", "Points", "Vue d’ensemble", "Stations"] {
            let tab = app.buttons[title]
            tab.tap()
            sleep(1)
            XCTAssertTrue(tab.isSelected)
        }
    }
}
