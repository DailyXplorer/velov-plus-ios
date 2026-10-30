import XCTest
@testable import VelovCore

final class FormattingTests: XCTestCase {
    func testFrenchPhoneNumbersAreGroupedWithNonBreakingSpaces() {
        XCTAssertEqual(formatPhone("+33612345678"), "+33\u{a0}6\u{a0}12\u{a0}34\u{a0}56\u{a0}78")
        XCTAssertEqual(formatPhone("0612345678"), "06\u{a0}12\u{a0}34\u{a0}56\u{a0}78")
        XCTAssertEqual(formatPhone("06 12 34 56 78"), "06\u{a0}12\u{a0}34\u{a0}56\u{a0}78")
        XCTAssertEqual(formatPhone("+33 4.78.00.00.00"), "+33\u{a0}4\u{a0}78\u{a0}00\u{a0}00\u{a0}00")
    }

    func testTitlesKeepTheirPunctuationOnTheSameLine() {
        XCTAssertEqual(frenchSpaced("Retirer des favoris ?"), "Retirer des favoris\u{a0}?")
        XCTAssertEqual(frenchSpaced("Batterie 40 %"), "Batterie 40\u{a0}%")
        XCTAssertEqual(frenchSpaced("Adresse copiée : a ; b !"), "Adresse copiée\u{a0}: a\u{a0}; b\u{a0}!")
        XCTAssertEqual(frenchSpaced("Se déconnecter\u{a0}?"), "Se déconnecter\u{a0}?")
        XCTAssertEqual(frenchSpaced("Vélo 20449 · Borne 4"), "Vélo 20449 · Borne 4")
    }

    func testOtherPhoneNumbersAreShownAsGiven() {
        XCTAssertEqual(formatPhone("+41791234567"), "+41791234567")
        XCTAssertEqual(formatPhone("061234567"), "061234567")
        XCTAssertEqual(formatPhone(" 12 "), "12")
    }
}
