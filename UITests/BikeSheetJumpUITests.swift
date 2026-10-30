import XCTest

final class BikeSheetJumpUITests: XCTestCase {
    func testPushingABikeFromTheStationBikesDoesNotJump() {
        let app = XCUIApplication()
        app.launchArguments = ["-VelovSample", "YES", "-VelovScreen", "bikePush"]
        app.launch()
        XCTAssertTrue(app.buttons["Actualiser les vélos"].waitForExistence(timeout: 30), "the station's bikes are shown")
        let back = app.navigationBars.buttons.firstMatch
        var frames: [(time: TimeInterval, png: Data, back: CGRect?)] = []
        let start = Date()
        while Date().timeIntervalSince(start) < 6 {
            let png = XCUIScreen.main.screenshot().pngRepresentation
            frames.append((Date().timeIntervalSince(start), png, back.exists ? back.frame : nil))
        }
        if let dir = ProcessInfo.processInfo.environment["VELOV_SHOT_DIR"] {
            for (index, frame) in frames.enumerated() {
                let name = String(format: "jump-%02d-%04dms.png", index, Int(frame.time * 1000))
                try? frame.png.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name))
            }
        }
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "Vélo 20449")).firstMatch.waitForExistence(timeout: 10), "the bike page is pushed")
        let settled = back.frame
        XCTAssertLessThan(settled.minX, app.frame.width / 2, "the first bar button of the bike page is its back button")
        let landed = frames.compactMap { frame in frame.back.map { (frame.time, $0) } }.filter { abs($0.1.minX - settled.minX) < 2 }
        XCTAssertFalse(landed.isEmpty, "the back button was seen in place during the capture")
        let off = landed.filter { abs($0.1.minY - settled.minY) > 1 }
        XCTAssertTrue(off.isEmpty, "the back button settles at y \(settled.minY) but sat at \(off.map { String(format: "%.0f ms: y %.1f", $0.0 * 1000, $0.1.minY) })")
    }
}
