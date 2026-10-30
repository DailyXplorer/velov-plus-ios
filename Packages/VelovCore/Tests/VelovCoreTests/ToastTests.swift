import XCTest
@testable import VelovCore

final class ToastTests: XCTestCase {
    func testANewToastReplacesTheShownOne() {
        var slot = ToastSlot()
        let first = slot.show("Position introuvable pour le moment.")
        let second = slot.show("Les vélos de cette station sont momentanément indisponibles.")
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual(slot.current, second)
    }

    func testTheTimerOfAReplacedToastDoesNotCloseTheNewOne() {
        var slot = ToastSlot()
        let first = slot.show("La localisation a pris trop de temps. Réessayez.")
        let second = slot.show("La localisation a pris trop de temps. Réessayez.")
        slot.dismiss(first.id)
        XCTAssertEqual(slot.current, second)
        slot.dismiss(second.id)
        XCTAssertNil(slot.current)
    }

    func testTheActionTravelsWithTheToast() {
        var slot = ToastSlot()
        slot.show(LocationFailure.denied.message, action: LocationFailure.denied.action)
        XCTAssertEqual(slot.current?.action, .openSettings)
    }
}
