import XCTest
@testable import VelovCore

final class TripTests: XCTestCase {
    static func station(_ number: Int, _ name: String, _ lat: Double, _ lon: Double) -> Station {
        Station(id: String(number), number: number, name: name, address: "", lat: lat, lon: lon, mechanical: 0, electrical: 0, stands: 0, open: true)
    }
    let bellecour = station(2002, "Bellecour / St Exupéry", 45.7578, 4.8320)
    let partDieu = station(3001, "Part-Dieu", 45.7606, 4.8594)
    var stations: [Int: Station] { [2002: bellecour, 3001: partDieu] }
    let finished: [String: Any] = [
        "id": "3a4b5c6d", "status": "FINISHED", "bikeNumber": 20449, "startDateTime": "2026-03-02T09:32:14", "startStation": 2002, "endDateTime": "2026-03-02T09:34:34", "endStation": 3001,
        "startStand": 1, "endStand": 12, "duration": 3, "rewardsEarned": 5, "rewardsSpent": 10, "price": 180, "discount": 80, "reducedPrice": 100,
        "litigious": true, "isSpecial": false, "isRated": false, "token": "ABCDEFGHIJABCDEFGHIJ", "bikeType": 0, "origin": 4
    ]

    func trip(_ value: [String: Any]) throws -> Trip {
        let json = JSON.parse(try JSONSerialization.data(withJSONObject: value))!
        return normalizeTrip(try RawTrip(json), stations: stations)
    }

    func with(_ changes: [String: Any?]) -> [String: Any] {
        var value = finished
        for (key, change) in changes { value[key] = change ?? NSNull() }
        return value
    }

    func without(_ keys: String...) -> [String: Any] {
        var value = finished
        for key in keys { value[key] = nil }
        return value
    }

    func testHaversineMeasuresGreatCircleMetres() {
        XCTAssertLessThan(abs(haversine(GeoPoint(lat: 0, lon: 0), GeoPoint(lat: 1, lon: 0)) - 111_195), 1)
        XCTAssertEqual(haversine(bellecour.point, bellecour.point), 0)
        let across = haversine(bellecour.point, partDieu.point)
        XCTAssert(across > 2_100 && across < 2_250, String(across))
        XCTAssertEqual(across, haversine(partDieu.point, bellecour.point), accuracy: 1e-6)
    }

    func testAFinishedTripKeepsStandsPricesPointsFlagsAndItsUTCTimes() throws {
        let value = try trip(finished)
        XCTAssertEqual(value.startedAt.map(isoString), "2026-03-02T09:32:14.000Z")
        XCTAssertEqual(value.endedAt.map(isoString), "2026-03-02T09:34:34.000Z")
        XCTAssertEqual(value.startStation, "Bellecour / St Exupéry")
        XCTAssertEqual(value.endStation, "Part-Dieu")
        XCTAssertEqual([value.startStationNumber, value.endStationNumber, value.startStand, value.endStand], [2002, 3001, 1, 12])
        XCTAssertEqual(value.distance, Int(haversine(bellecour.point, partDieu.point).rounded()))
        XCTAssertEqual([value.price, value.fullPrice, value.discount, value.pointsEarned, value.pointsSpent], [100, 180, 80, 5, 10])
        XCTAssertEqual(value.litigious, true)
        XCTAssertEqual(value.isRated, false)
        XCTAssertEqual(value.token, "ABCDEFGHIJABCDEFGHIJ")
        XCTAssertEqual(value.origin, 4)
        XCTAssertEqual(value.bikeType, .mechanical)
    }

    func testWithoutAReducedPriceThePaidAmountIsThePriceLessTheDiscount() throws {
        XCTAssertEqual(try trip(without("reducedPrice")).price, 100)
        XCTAssertEqual(try trip(without("reducedPrice", "discount")).price, 180)
    }

    func testATripBackAtItsStartStationOrOffTheStationListHasNoDistance() throws {
        XCTAssertNil(try trip(with(["endStation": 2002])).distance)
        let unknown = try trip(with(["endStation": 9999]))
        XCTAssertNil(unknown.distance)
        XCTAssertEqual(unknown.endStation, "Station 9999")
    }

    func testAnAnonymisedTripAndMalformedNewFieldsDegradeToEmptyValues() throws {
        let value = try trip(["id": "x", "status": "FINISHED", "startDateTime": "2026-03-02T09:32:14", "duration": 3, "price": 0, "litigious": "yes", "isRated": "no", "token": 12, "startStand": "1"])
        XCTAssertNil(value.startStation); XCTAssertNil(value.endStation); XCTAssertNil(value.startStationNumber)
        XCTAssertNil(value.startStand); XCTAssertNil(value.endStand); XCTAssertNil(value.distance); XCTAssertNil(value.bikeNumber)
        XCTAssertEqual(value.litigious, false); XCTAssertNil(value.isRated); XCTAssertNil(value.token); XCTAssertNil(value.origin)
        XCTAssertEqual(value.fullPrice, 0); XCTAssertEqual(value.discount, 0); XCTAssertNil(value.endedAt)
    }

    func testATripWithoutAPriceOrADurationKeepsThemUnknownNotZero() throws {
        let value = try trip(["id": "x", "status": "FINISHED"])
        XCTAssertNil(value.duration); XCTAssertNil(value.price); XCTAssertNil(value.fullPrice)
        XCTAssertEqual(try trip(with(["duration": 0, "reducedPrice": 0])).price, 0)
        XCTAssertEqual(try trip(with(["duration": 0])).duration, 0)
    }

    func testAnEmptyStationNameOrNumberIsNoStationAtAll() throws {
        let value = try trip(with(["startStation": "", "startStationName": "", "endStation": " ", "endStationName": "  "]))
        XCTAssertNil(value.startStation); XCTAssertNil(value.endStation); XCTAssertNil(value.startStationNumber); XCTAssertNil(value.endStationNumber)
        XCTAssertEqual(try trip(with(["startStationName": ""])).startStation, "Bellecour / St Exupéry")
        XCTAssertEqual(try trip(with(["startStation": "X12", "startStationName": nil])).startStation, "Station X12")
    }

    func testAMalformedRequiredFieldMakesTheTripUnreadable() {
        XCTAssertThrowsError(try trip(with(["bikeNumber": "20449"])))
        XCTAssertThrowsError(try trip(with(["startStation": ["number": 2002]])))
        XCTAssertThrowsError(try trip(["status": "FINISHED"]))
    }

    func testStationNamesAreCapitalisedAfterSpacesHyphensAndApostrophesWithInnerDAndLKeptLow() {
        for (raw, title) in [
            ("2002 - SAINT-EXUPÉRY", "Saint-Exupéry"), ("GARE D’OULLINS", "Gare d’Oullins"), ("gare d'oullins", "Gare d'Oullins"),
            ("L’ARBRESLE", "L’Arbresle"), ("PART-DIEU / VILLETTE", "Part-Dieu / Villette"), ("Place Jean-Jaurès (Lyon 7e)", "Place Jean-Jaurès (Lyon 7e)")
        ] { XCTAssertEqual(stationTitle(raw), title) }
    }

    func testCyclocityDateTimesAreReadAsUTCADateAloneStaysThatCalendarDate() {
        XCTAssertEqual(utcDate("2026-03-02T09:32:14"), "2026-03-02T09:32:14.000Z")
        XCTAssertEqual(utcDate("2026-03-02T09:32:14+01:00"), "2026-03-02T08:32:14.000Z")
        XCTAssertEqual(utcDate("2026-03-02T09:32:14Z"), "2026-03-02T09:32:14.000Z")
        XCTAssertEqual(utcDate("2026-03-02T09:32:14.5"), "2026-03-02T09:32:14.500Z")
        XCTAssertEqual(utcDate("2026-03-02"), "2026-03-02")
        for value in ["2026-02-30", "not a date", "", nil] { XCTAssertNil(utcDate(value), String(describing: value)) }
    }

    func testARatingIsARecommendationWithoutARatingOrAWarningRated30Or60() {
        XCTAssertEqual(RateVote.make(recommended: true, rating: nil), .recommend)
        XCTAssertEqual(RateVote.make(recommended: false, rating: 30), .warn(30))
        XCTAssertEqual(RateVote.make(recommended: false, rating: 60), .warn(60))
        XCTAssertNil(RateVote.make(recommended: true, rating: 30))
        XCTAssertNil(RateVote.make(recommended: false, rating: nil))
        XCTAssertNil(RateVote.make(recommended: false, rating: 50))
    }

    func testOnlyAnUnratedFinishedTripWithABikeEndedLessThan3HoursAgoCanBeRated() throws {
        let value = try trip(finished)
        let end = value.endedAt!
        XCTAssertTrue(canRate(value, now: end.addingTimeInterval(2 * 3600)))
        XCTAssertFalse(canRate(value, now: end.addingTimeInterval(3 * 3600)))
        var copy = value; copy.isRated = true; XCTAssertFalse(canRate(copy, now: end))
        copy = value; copy.isRated = nil; XCTAssertFalse(canRate(copy, now: end))
        copy = value; copy.bikeNumber = nil; XCTAssertFalse(canRate(copy, now: end))
        copy = value; copy.status = "ERROR"; XCTAssertFalse(canRate(copy, now: end))
    }

    func testFrenchFormatsMatchTheWebApp() {
        XCTAssertEqual(formatDistance(347), "350\u{a0}m")
        XCTAssertEqual(formatDistance(3), "10\u{a0}m")
        XCTAssertEqual(formatDistance(1_234), "1,2\u{a0}km")
        XCTAssertEqual(formatDistance(2_000), "2\u{a0}km")
        XCTAssertEqual(formatDistance(14_400), "14\u{a0}km")
        XCTAssertEqual(formatPrice(180).filter { !$0.isWhitespace }, "1,80€")
        XCTAssertEqual(outOfFive(56), "2,8")
        XCTAssertEqual(formatDate(nil), "Date indisponible")
        let summer = date("2026-07-14T08:05:00Z")
        XCTAssertEqual(formatDate(summer, .time), "10:05")
        XCTAssertEqual(formatDate(summer, .dayMonth), "14 juil.")
        XCTAssertEqual(formatDate(summer, .dayLongMonthYear), "14 juillet 2026")
        XCTAssertEqual(formatDate(summer, .dayMonthYearTime), "14 juil. 2026, 10:05")
        XCTAssertEqual(formatDate(date("2026-03-01T23:30:00Z"), .dayMonth), "2 mars")
        XCTAssertEqual(clock(305), "05:05")
        let plain = { (text: String?) in text?.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ") }
        XCTAssertEqual(plain(fromNow(date("2026-07-14T05:00:00Z"), now: summer)), "il y a 3 h")
        XCTAssertEqual(plain(fromNow(date("2026-07-16T09:00:00Z"), now: summer)), "dans 2 j")
        XCTAssertEqual(fromNow(summer, now: summer.addingTimeInterval(20)), "à l’instant")
        XCTAssertEqual(capitalize("à l’instant"), "À l’instant")
        XCTAssertEqual(capitalize(""), "")
    }

    func testPlanNamesAndPhonesAreShortenedLikeTheWebApp() {
        XCTAssertEqual(shortPlan("Vélo’v Plus 1 an Jeunes – paiement comptant"), "Plus 1 an Jeunes")
        XCTAssertEqual(shortPlan("Ticket 24h"), "Ticket 24h")
        XCTAssertEqual(shortPlan(nil), "Aucun")
        XCTAssertEqual(normalizePhone("06 12 34 56 78", country: "FR"), "+33612345678")
        XCTAssertEqual(normalizePhone("0041 79 123 45 67", country: "CH"), "+41791234567")
        XCTAssertEqual(normalizePhone("06 12 34 56 78", country: "BE"), "0612345678")
    }
}
