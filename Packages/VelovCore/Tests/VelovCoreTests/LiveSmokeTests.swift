import XCTest
@testable import VelovCore

final class LiveSmokeTests: XCTestCase {
    override func setUpWithError() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["VELOV_LIVE"] == "1", "set VELOV_LIVE=1 to run the public smoke test")
    }

    func testPublicStationsAndBikesOfStation2002() async throws {
        let api = VelovAPI(transport: URLSessionTransport())
        let data = try await api.stations()
        XCTAssertGreaterThan(data.stations.count, 300)
        let station = try XCTUnwrap(data.stations.first { $0.number == 2002 })
        let bikes = try await api.stationBikes(2002)
        print("LIVE stations=\(data.stations.count) station2002=\(station.name) bikes2002=\(bikes.count) docks=\(station.stands)")
        for bike in bikes { XCTAssertGreaterThan(bike.number, 0) }
    }
}
