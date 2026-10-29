import XCTest
@testable import VelovCore

final class StationSearchTests: XCTestCase {
    func station(_ number: Int, _ name: String, lat: Double = 45.76, lon: Double = 4.83, bikes: Int = 3, electrical: Int = 0, stands: Int = 5, open: Bool = true) -> Station {
        Station(id: "\(number)", number: number, name: name, address: "", lat: lat, lon: lon, mechanical: bikes, electrical: electrical, stands: stands, open: open)
    }

    func ranked(_ stations: [Station], query: String = "", filter: StationFilter = .all, favorites: Set<Int> = [], here: GeoPoint? = nil) -> [Int] {
        StationRanking(stations: stations, query: query, filter: filter, favorites: favorites, here: here).ranked().map(\.number)
    }

    func testFavoritesComeFirstThenOpenStationsThenFrenchAlphabeticalOrder() {
        let stations = [station(1, "Zola"), station(2, "Écully"), station(3, "Ampère", open: false), station(4, "Opéra"), station(5, "Bellecour")]
        XCTAssertEqual(ranked(stations, favorites: [4]), [4, 5, 2, 1, 3])
    }

    func testAPositionOrdersByDistanceInsteadOfName() {
        let here = GeoPoint(lat: 45.76, lon: 4.83)
        let stations = [station(1, "Loin", lat: 45.80), station(2, "Proche", lat: 45.761), station(3, "Moyen", lat: 45.77)]
        XCTAssertEqual(ranked(stations, here: here), [2, 3, 1])
    }

    func testSearchIgnoresAccentsAndCaseAndMatchesTheNumber() {
        let stations = [station(2004, "Ampère / Victor Hugo"), station(1001, "Opéra")]
        XCTAssertEqual(ranked(stations, query: "  AMPERE "), [2004])
        XCTAssertEqual(ranked(stations, query: "1001"), [1001])
        XCTAssertEqual(ranked(stations, query: "nulle part"), [])
    }

    func testFiltersKeepOnlyMatchingStations() {
        let stations = [station(1, "Vide", bikes: 0, stands: 0), station(2, "Électrique", bikes: 0, electrical: 2), station(3, "Mécanique")]
        XCTAssertEqual(ranked(stations, filter: .available), [2, 3])
        XCTAssertEqual(ranked(stations, filter: .electrical), [2])
        XCTAssertEqual(ranked(stations, filter: .stands), [2, 3])
        XCTAssertEqual(ranked(stations, filter: .favorites, favorites: [1]), [1])
    }

    func testRankingALyonSizedNetwork() {
        let stations = (0..<430).map { station(20000 + $0, "Station \($0) Rue Émile Zola", lat: 45.70 + Double($0 / 21) * 0.006, lon: 4.78 + Double($0 % 21) * 0.006, open: $0 % 11 != 0) }
        let ranking = StationRanking(stations: stations, query: "", filter: .all, favorites: [20003, 20100], here: nil)
        measure { XCTAssertEqual(ranking.ranked().count, 430) }
    }
}
