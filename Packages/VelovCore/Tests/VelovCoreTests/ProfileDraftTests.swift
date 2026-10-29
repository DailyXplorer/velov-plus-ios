import XCTest
@testable import VelovCore

final class ProfileDraftTests: XCTestCase {
    let profile = Profile(firstName: "jean-pierre", lastName: "de la tour", email: "jp@example.com", locked: false, complete: true, phoneNumber: "+33600000000",
                          address: "1 rue Exemple", addressComplement: nil, zipCode: "69002", city: "Lyon", country: "FR", favorites: [])

    func testTheDraftShowsTheNamesCapitalisedAndSendsNothingUntouched() {
        let draft = ProfileDraft(profile)
        XCTAssertEqual([draft.firstName, draft.lastName], ["Jean-Pierre", "De la Tour"])
        XCTAssertNil(reviewProfile(profile, draft))
        var spaced = draft
        spaced.firstName = "  Jean-Pierre "
        XCTAssertNil(reviewProfile(profile, spaced), "only the capitals differ from what Vélo’v stores")
    }

    func testAChangedNameIsSentCleanedAndAloneOrRefusedWithItsMessage() throws {
        var draft = ProfileDraft(profile)
        draft.lastName = " Dupont   Lajoie "
        XCTAssertEqual(try reviewProfile(profile, draft)?.get(), ProfileBody(lastName: "Dupont Lajoie"))
        draft.lastName = " "
        XCTAssertEqual(reviewProfile(profile, draft).map { if case .failure(let problem) = $0 { problem.message } else { "" } }, "Saisissez votre nom.")
        draft.lastName = "Dupont"
        draft.firstName = "J3an"
        guard case .failure(let problem)? = reviewProfile(profile, draft) else { return XCTFail("accepted") }
        XCTAssertEqual(problem.message, "Prénom invalide : lettres, espaces, apostrophes et traits d’union uniquement, 50 caractères au plus.")
    }

    func testTheOtherFieldsKeepTheirChecksAndOnlyWhatChangedIsSent() throws {
        var draft = ProfileDraft(profile)
        draft.city = "Villeurbanne"
        draft.phone = "06 12 34 56 78"
        XCTAssertEqual(try reviewProfile(profile, draft)?.get(), ProfileBody(city: "Villeurbanne", phoneNumber: "+33612345678"))
        draft.address = ""
        guard case .failure(let problem)? = reviewProfile(profile, draft) else { return XCTFail("accepted") }
        XCTAssertEqual(problem.message, "Saisissez une adresse.")
    }
}
