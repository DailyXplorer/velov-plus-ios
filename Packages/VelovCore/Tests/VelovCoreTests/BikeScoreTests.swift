import XCTest
@testable import VelovCore

final class BikeScoreTests: XCTestCase {
    let now = date("2026-10-28T12:00:00Z")
    func hoursAgo(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }

    func bike(_ number: Int, _ change: (inout Bike) -> Void = { _ in }) -> Bike {
        var value = Bike(number: number, type: .mechanical, standNumber: number, status: "AVAILABLE", statusLabel: "Accroché", isReserved: false,
                         rating: .init(value: 80, count: 10, lastAt: hoursAgo(30)), lastTripAt: hoursAgo(20))
        change(&value)
        return value
    }

    func verdicts(_ bikes: [Bike]) -> [Int: Verdict] {
        Dictionary(uniqueKeysWithValues: assessBikes(bikes, now: now).map { ($0.bike.number, $0.verdict) })
    }

    func only(_ value: Bike) -> AssessedBike { assessBikes([value], now: now)[0] }

    func testEachDoubtfulConditionIsEnoughToAvoidABikeWithItsReason() {
        let cases: [((inout Bike) -> Void, String)] = [
            ({ $0.rating = .init(value: 56, count: 5, lastAt: nil) }, "Note basse (2,8/5)"),
            ({ $0.nextCheckAt = self.hoursAgo(31 * 24) }, "Contrôle en retard"),
            ({ $0.type = .electrical; $0.batteryPercent = 12 }, "Batterie faible (12 %)"),
            ({ $0.lastTripAt = self.hoursAgo(4 * 24 + 3) }, "Pas utilisé depuis 4 j"),
            ({ $0.status = "RENTED"; $0.statusLabel = "En location" }, "Indisponible (En location)"),
            ({ $0.isReserved = true }, "Réservé")
        ]
        for (change, reason) in cases {
            let result = only(bike(1, change))
            XCTAssertEqual(result.verdict, .avoid, reason)
            XCTAssertEqual(result.reasons, [reason])
        }
    }

    func testMissingDataAndThresholdsJustInsideTheLimitsDoNotCountAgainstABike() {
        let cases: [(inout Bike) -> Void] = [
            { $0.rating = .init(value: 50, count: 4, lastAt: nil) }, { $0.lastTripAt = nil }, { $0.lastTripAt = self.hoursAgo(71) },
            { $0.nextCheckAt = self.hoursAgo(5 * 24) }, { $0.type = .electrical; $0.batteryPercent = 20 }, { $0.type = .electrical; $0.batteryPercent = nil },
            { $0.status = nil; $0.statusLabel = nil }
        ]
        for (index, change) in cases.enumerated() { XCTAssertNotEqual(only(bike(1, change)).verdict, .avoid, "case \(index)") }
    }

    func testAPerfectRatingFromOneVoteRanksBelowASolidRatingFromMany() {
        let result = assessBikes([bike(1) { $0.rating = .init(value: 100, count: 1, lastAt: nil) }, bike(2) { $0.rating = .init(value: 85, count: 20, lastAt: nil) }], now: now)
        XCTAssertEqual(result[1].score, 71.5, accuracy: 1e-9)
        XCTAssertEqual(result[0].bike.number, 2)
        XCTAssertEqual(result[0].score, 85, accuracy: 1e-9)
    }

    func testOnlyTheBestBikeOfEachTypeIsRecommended() {
        XCTAssertEqual(verdicts([
            bike(1) { $0.rating = .init(value: 80, count: 10, lastAt: nil) },
            bike(2) { $0.rating = .init(value: 92, count: 30, lastAt: nil) },
            bike(3) { $0.type = .electrical; $0.batteryPercent = 90; $0.rating = .init(value: 90, count: 12, lastAt: nil) },
            bike(4) { $0.type = .electrical; $0.batteryPercent = 40; $0.rating = .init(value: 90, count: 12, lastAt: nil) }
        ]), [1: .neutral, 2: .recommended, 3: .recommended, 4: .neutral])
        XCTAssertEqual(only(bike(2) { $0.rating = .init(value: 92, count: 30, lastAt: nil); $0.lastTripAt = self.hoursAgo(2) }).reasons,
                       ["Bien noté (4,6/5 · 30 avis)", "Utilisé il y a moins de 12 h"])
    }

    func testNothingIsRecommendedWhenTheBestBikesAreWeakOrBarelyRated() {
        XCTAssertEqual(verdicts([
            bike(1) { $0.rating = .init(value: 74, count: 40, lastAt: nil) },
            bike(2) { $0.rating = nil },
            bike(3) { $0.type = .electrical; $0.batteryPercent = 80; $0.rating = .init(value: 100, count: 2, lastAt: nil) },
            bike(4) { $0.type = .electrical; $0.batteryPercent = 10; $0.rating = .init(value: 95, count: 40, lastAt: nil) }
        ]), [1: .neutral, 2: .neutral, 3: .neutral, 4: .avoid])
    }

    func testTheListPutsTheRecommendedBikesFirstAndTheOnesToAvoidLast() {
        let order = assessBikes([
            bike(1) { $0.isReserved = true },
            bike(2) { $0.rating = .init(value: 70, count: 20, lastAt: nil) },
            bike(3) { $0.rating = .init(value: 95, count: 20, lastAt: nil) },
            bike(4) { $0.rating = .init(value: 78, count: 20, lastAt: nil) }
        ], now: now).map(\.bike.number)
        XCTAssertEqual(order, [3, 4, 2, 1])
    }

    func testAnUpcomingDateInThePastReadsAsOverdue() {
        let plain = { (text: String?) in text?.replacingOccurrences(of: "\u{00A0}", with: " ").replacingOccurrences(of: "\u{202F}", with: " ") }
        let past = upcomingText(date("2026-10-12T07:25:00Z"), now: now)
        XCTAssertEqual(past?.value, "En retard")
        XCTAssertEqual(plain(past?.detail), "Prévu le 12 oct. 2026")
        XCTAssertEqual(upcomingText(date("2026-10-12T07:25:00Z"), relative: false, now: now), past)
        let soon = upcomingText(date("2026-10-30T15:47:00Z"), now: now)
        XCTAssertEqual(plain(soon?.value), "Dans 2 j")
        XCTAssertEqual(plain(soon?.detail), "30 oct. 2026, 16:47")
        let review = upcomingText(date("2026-12-03T10:00:00Z"), relative: false, now: now)
        XCTAssertEqual(plain(review?.value), "3 déc. 2026")
        XCTAssertNil(review?.detail)
        XCTAssertNil(upcomingText(nil, now: now))
    }

    func testABikeAnswerIsNormalisedLeniently() {
        let raw = RawBike(JSON.parse(Data(#"{"id":"b-1","number":20449,"type":"ELECTRICAL","frameId":"0","standNumber":"3","status":"AVAILABLE","isReserved":"no","rating":{"value":81.27,"count":7,"lastRatingDateTime":"2026-10-20T10:00:00"},"battery":{"percentage":104.4},"lastTripDateTime":"2026-10-28T08:00:00"}"#.utf8))!)!
        let bike = normalizeBike(raw)
        XCTAssertEqual(bike.type, .electrical)
        XCTAssertNil(bike.standNumber)
        XCTAssertEqual(bike.isReserved, false)
        XCTAssertEqual(bike.rating, .init(value: 81.3, count: 7, lastAt: date("2026-10-20T10:00:00Z")))
        XCTAssertEqual(bike.batteryPercent, 100)
        XCTAssertNil(bike.frameId)
        XCTAssertEqual(bike.lastTripAt, date("2026-10-28T08:00:00Z"))
        XCTAssertNil(RawBike(JSON.parse(Data(#"{"number":"x"}"#.utf8))!))
    }
}
