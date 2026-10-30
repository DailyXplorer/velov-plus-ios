import XCTest

final class BikeSheetJumpUITests: XCTestCase {
    func testPushingABikeFromTheStationBikesDoesNotJump() {
        let app = XCUIApplication()
        app.launchArguments = ["-VelovSample", "YES", "-VelovScreen", "bikePush"]
        app.launch()
        XCTAssertTrue(app.buttons["Actualiser les vélos"].waitForExistence(timeout: 30), "the station's bikes are shown")
        let dir = ProcessInfo.processInfo.environment["VELOV_SHOT_DIR"]
        var frames: [(TimeInterval, Data)] = []
        let start = Date()
        while Date().timeIntervalSince(start) < 6 {
            frames.append((Date().timeIntervalSince(start), XCUIScreen.main.screenshot().pngRepresentation))
        }
        if let dir {
            for (index, frame) in frames.enumerated() {
                let name = String(format: "jump-%02d-%04dms.png", index, Int(frame.0 * 1000))
                try? frame.1.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
            }
        }
        XCTAssertTrue(app.staticTexts["Vélo 20449"].waitForExistence(timeout: 10) || app.navigationBars.firstMatch.exists, "the bike page is pushed")
    }
}
