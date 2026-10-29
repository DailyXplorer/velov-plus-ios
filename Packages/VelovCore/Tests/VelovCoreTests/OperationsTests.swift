import XCTest
@testable import VelovCore

@MainActor
final class OperationsTests: XCTestCase {
    final class Clock {
        var now = date("2026-10-29T12:00:00")
    }

    let lost = Outcome.refusal("network", "Vélo’v ne répond pas.")
    let refused = Outcome(ok: false, httpStatus: 400, code: "bookings.exception.not.authorized", message: "Non.")

    func store(_ backing: OperationBacking?, _ clock: Clock, account: String? = "person@example.com") -> Operations {
        Operations(backing: backing, account: account, now: { clock.now })
    }

    func testOneActionAtATimeAndTheSameOneCannotStartTwice() {
        let clock = Clock()
        let operations = store(InMemoryOperationBacking(), clock)
        XCTAssertEqual(operations.begin("unlock:1"), .started)
        XCTAssertEqual(operations.begin("unlock:1"), .busy)
        XCTAssertEqual(operations.begin("book:2"), .busy)
        XCTAssertTrue(operations.busy())
        XCTAssertTrue(operations.sending)
        XCTAssertEqual(operations.get("unlock:1")?.status, .sending)
        XCTAssertNil(operations.get("book:2"))
        operations.clear("unlock:1")
        XCTAssertEqual(operations.get("unlock:1")?.status, .sending, "a running action cannot be cleared")
        operations.finish("unlock:1", Outcome(ok: true, httpStatus: 200))
        XCTAssertNil(operations.get("unlock:1"))
        XCTAssertFalse(operations.busy())
        XCTAssertEqual(operations.begin("book:2"), .started)
    }

    func testAKeptActionIsNeverSentWithoutStorage() {
        let clock = Clock()
        let failing = store(InMemoryOperationBacking(failing: true), clock)
        XCTAssertEqual(failing.begin("invite:x", keep: true), .unsaved)
        XCTAssertFalse(failing.sending)
        XCTAssertEqual(failing.begin("profile"), .started, "an unkept action may live in memory")
        let anonymous = store(InMemoryOperationBacking(), clock, account: nil)
        XCTAssertEqual(anonymous.begin("contact:x", keep: true), .unsaved)
        XCTAssertEqual(store(nil, clock).begin("via:x:t", keep: true), .unsaved)
        XCTAssertEqual(Messages.unsaved, "Ce téléphone ne peut pas suivre cette action. Rien n’a été envoyé.")
        XCTAssertEqual(Messages.busy, "Une autre action est en cours. Attendez sa réponse avant de recommencer.")
    }

    func testAnAnswerLostWithTheAppTurnsUncertainAfterTwoMinutesOnlyWhenKept() {
        let clock = Clock()
        let backing = InMemoryOperationBacking()
        let first = store(backing, clock)
        XCTAssertEqual(first.begin("invite:x", keep: true, meta: ["cost": "100", "balance": "250"]), .started)
        let relaunched = store(backing, clock)
        XCTAssertEqual(relaunched.get("invite:x")?.status, .sending)
        XCTAssertTrue(relaunched.busy(), "a send left by the closed app still blocks for two minutes")
        XCTAssertEqual(relaunched.begin("book:1"), .busy)
        clock.now += 121
        let entry = relaunched.get("invite:x")
        XCTAssertEqual(entry?.status, .uncertain)
        XCTAssertEqual(entry?.outcome, noAnswer(Messages.lost))
        XCTAssertEqual(entry?.outcome?.message, "L’app a été fermée avant la réponse. L’action a peut-être abouti.")
        XCTAssertEqual(entry?.meta, ["cost": "100", "balance": "250"])
        XCTAssertFalse(relaunched.busy())
        XCTAssertEqual(relaunched.begin("invite:x", keep: true), .busy, "an uncertain debit is never sent again blindly")
        clock.now += 3600
        XCTAssertEqual(relaunched.get("invite:x")?.status, .uncertain)

        let other = Clock()
        let again = InMemoryOperationBacking()
        XCTAssertEqual(store(again, other).begin("book:1"), .started)
        other.now += 121
        let later = store(again, other)
        XCTAssertNil(later.get("book:1"))
        XCTAssertEqual(later.begin("book:1"), .started)
    }

    func testAnUncertainOutcomeIsHeldTwoMinutesUnlessKeptAndARefusalIsForgotten() {
        let clock = Clock()
        let operations = store(InMemoryOperationBacking(), clock)
        XCTAssertEqual(operations.begin("rate:t-1"), .started)
        operations.finish("rate:t-1", lost)
        XCTAssertEqual(operations.get("rate:t-1")?.status, .uncertain)
        XCTAssertEqual(operations.get("rate:t-1")?.outcome, lost)
        XCTAssertFalse(operations.busy())
        XCTAssertEqual(operations.begin("rate:t-1"), .busy)
        XCTAssertEqual(operations.begin("contact:x", keep: true), .started)
        operations.finish("contact:x", lost)
        clock.now += 119
        XCTAssertEqual(operations.get("rate:t-1")?.status, .uncertain)
        clock.now += 2
        XCTAssertNil(operations.get("rate:t-1"))
        XCTAssertEqual(operations.get("contact:x")?.status, .uncertain)
        operations.clear("contact:x")
        XCTAssertNil(operations.get("contact:x"))

        XCTAssertEqual(operations.begin("book:3"), .started)
        operations.finish("book:3", refused)
        XCTAssertNil(operations.get("book:3"))
    }

    func testEntriesAreStoredPerAccountAndSurviveANewStore() {
        let clock = Clock()
        let backing = InMemoryOperationBacking()
        let operations = store(backing, clock, account: "person@example.com")
        XCTAssertEqual(operations.begin("via:x:t-1", keep: true), .started)
        operations.finish("via:x:t-1", lost)
        XCTAssertEqual(Array(backing.values.keys), ["velov:operations:v1:" + accountDigest("person@example.com")])
        XCTAssertEqual(PromoStore.key(account: "person@example.com"), "velov:promocodes:v1:" + accountDigest("person@example.com"))
        XCTAssertEqual(accountDigest(" Person@Example.COM "), accountDigest("person@example.com"))
        XCTAssertEqual(accountDigest("a").count, 64)

        XCTAssertEqual(store(backing, clock, account: " PERSON@example.com").get("via:x:t-1")?.status, .uncertain)
        let other = store(backing, clock, account: "other@example.com")
        XCTAssertNil(other.get("via:x:t-1"))
        XCTAssertEqual(other.begin("via:x:t-1"), .started)
        other.use(account: "person@example.com")
        XCTAssertEqual(other.get("via:x:t-1")?.status, .sending, "the running send is still tracked")
        XCTAssertEqual(other.digest, accountDigest("person@example.com"))
        other.finish("via:x:t-1", Outcome(ok: true, httpStatus: 200))
        XCTAssertNil(other.get("via:x:t-1"))
    }

    func testRunOnceSendsOnlyWhenItCanAndTurnsAThrowIntoAnUncertainNoAnswer() async {
        let clock = Clock()
        let operations = store(InMemoryOperationBacking(), clock)
        var sent = 0
        let thrown = await operations.runOnce("profile") { () async throws -> Outcome in
            sent += 1
            XCTAssertEqual(operations.begin("autoSpend"), .busy)
            throw URLError(.timedOut)
        }
        XCTAssertEqual(thrown, .finished(noAnswer("Le serveur ne répond pas.")))
        XCTAssertEqual(operations.get("profile")?.status, .uncertain)
        let blocked = await operations.runOnce("profile") { sent += 1; return Outcome(ok: true, httpStatus: 200) }
        XCTAssertEqual(blocked, .busy)
        let unsaved = await store(nil, clock).runOnce("invite:x", keep: true) { sent += 1; return Outcome(ok: true, httpStatus: 200) }
        XCTAssertEqual(unsaved, .unsaved)
        XCTAssertEqual(sent, 1)
        let version = operations.version
        let done = await operations.runOnce("favorite:2002") { Outcome(ok: true, httpStatus: 204) }
        XCTAssertEqual(done, .finished(Outcome(ok: true, httpStatus: 204)))
        XCTAssertGreaterThan(operations.version, version)
    }

    func testUncertainFollowsTheWebRules() {
        XCTAssertFalse(Outcome(ok: false, httpStatus: 200, transactionState: "ABORT").isUncertain)
        XCTAssertFalse(Outcome(ok: false, httpStatus: 0, code: "local.no.subscription").isUncertain)
        XCTAssertFalse(Outcome(ok: false, httpStatus: 404, code: "trips.exception").isUncertain)
        XCTAssertTrue(Outcome(ok: false, httpStatus: 401).isUncertain)
        XCTAssertTrue(Outcome(ok: false, httpStatus: 503, transactionState: "NOT_CONNECTED").isUncertain)
        XCTAssertTrue(noAnswer("x").isUncertain)
        XCTAssertTrue(Outcome(ok: false, httpStatus: 0).isUncertain)
    }

    func testSettleReadsTheRealStateOnlyWhenTheOutcomeIsUncertain() async {
        var reads = 0
        let ok = await settle(Outcome(ok: true, httpStatus: 200)) { reads += 1; return .unchanged }
        XCTAssertEqual(ok, .done)
        let refusal = await settle(refused) { reads += 1; return .applied }
        XCTAssertEqual(refusal, .refused(refused))
        XCTAssertEqual(reads, 0)
        let applied = await settle(lost) { .applied }
        XCTAssertEqual(applied, .done)
        var notApplied = lost
        notApplied.message = "Vélo’v n’a rien enregistré. Vous pouvez réessayer."
        let unchanged = await settle(lost) { .unchanged }
        XCTAssertEqual(unchanged, .refused(notApplied))
        let unknown = await settle(lost) { .unknown }
        XCTAssertEqual(unknown, .uncertain(lost))
        let thrown = await settle(lost) { throw URLError(.timedOut) }
        XCTAssertEqual(thrown, .uncertain(lost))
    }

    func dashboard(autoSpend: Bool? = true, favorites: [Int] = [2002], renewal: Bool? = false, rated: Bool? = true, balance: Double? = 150, movements: [RewardMovement] = []) -> Dashboard {
        let profile = Profile(firstName: "Ada", lastName: "Lovelace", email: "person@example.com", locked: false, complete: true, phoneNumber: "+33612345678",
                              address: "1 rue de la République", addressComplement: nil, zipCode: "69002", city: "Lyon", country: "FR", favorites: favorites)
        let rewards = Rewards(balance: balance, total: balance, autoSpend: autoSpend, movements: movements, rules: [])
        let subscription = Subscription(id: "sub-1", title: "Vélo’v Annuel", type: "LT", validUntil: nil, active: true, autoRenewal: renewal, autoRenewalAllowed: true)
        return Dashboard(profile: profile, rewards: rewards, subscription: .current(subscription), paymentValid: true, receipts: nil,
                         trips: [Trip(id: "t-1", isRated: rated)], ongoing: [], bookings: 0, updatedAt: date("2026-10-29T12:00:00"), warnings: [])
    }

    func testEachCheckComparesTheRereadStateWithTheWantedOne() {
        XCTAssertEqual(autoSpendCheck(dashboard(autoSpend: true), true), .applied)
        XCTAssertEqual(autoSpendCheck(dashboard(autoSpend: false), true), .unchanged)
        XCTAssertEqual(autoSpendCheck(dashboard(autoSpend: nil), true), .unknown)
        XCTAssertEqual(favoriteCheck(dashboard(favorites: [2002]), station: 2002, wanted: true), .applied)
        XCTAssertEqual(favoriteCheck(dashboard(favorites: []), station: 2002, wanted: true), .unchanged)
        XCTAssertEqual(favoriteCheck(dashboard(favorites: []), station: 2002, wanted: false), .applied)
        XCTAssertEqual(renewalCheck(dashboard(renewal: true), subscriptionId: "sub-1", wanted: true), .applied)
        XCTAssertEqual(renewalCheck(dashboard(renewal: false), subscriptionId: "sub-1", wanted: true), .unchanged)
        XCTAssertEqual(renewalCheck(dashboard(renewal: true), subscriptionId: "sub-2", wanted: true), .unknown)
        XCTAssertEqual(renewalCheck(dashboard(renewal: nil), subscriptionId: "sub-1", wanted: true), .unknown)
        XCTAssertEqual(ratingCheck(dashboard(rated: true), tripId: "t-1"), .applied)
        XCTAssertEqual(ratingCheck(dashboard(rated: false), tripId: "t-1"), .unchanged)
        XCTAssertEqual(ratingCheck(dashboard(rated: true), tripId: "t-2"), .unknown)

        let before = dashboard().profile
        let body = ProfileBody(address: ProfileAddress(name: " 2 place Bellecour ", complement: ""), city: "Lyon ")
        var after = before
        after.address = "2 Place Bellecour"
        XCTAssertEqual(profileCheck(before: before, after: after, body: body), .applied)
        XCTAssertEqual(profileCheck(before: before, after: before, body: body), .unchanged)
        after.address = "3 rue Mercière"
        XCTAssertEqual(profileCheck(before: before, after: after, body: body), .unknown)
        var renamed = before
        renamed.lastName = "LOVELACE-BYRON"
        XCTAssertEqual(profileCheck(before: before, after: renamed, body: ProfileBody(lastName: "Lovelace-Byron")), .applied)
    }

    func testAnUncertainInviteIsDebitedOnlyWhenTheMovementOrTheBalanceProvesIt() {
        let at = date("2026-10-29T12:00:00")
        let before = DebitBefore(at: at, balance: 250, cost: 100)
        let debit = RewardMovement(id: "m", date: at.addingTimeInterval(30), label: "Invitation d’un proche", amount: -100)
        XCTAssertEqual(inviteDebit(before, after: dashboard(balance: 150, movements: [debit]).rewards), .debited)
        let sameDay = RewardMovement(id: "m", date: date("2026-10-29"), label: "Invitation d’un proche", amount: -100, dateOnly: true)
        XCTAssertEqual(inviteDebit(before, after: dashboard(balance: 150, movements: [sameDay]).rewards), .debited)
        let older = RewardMovement(id: "m", date: at.addingTimeInterval(-301), label: "Invitation d’un proche", amount: -100)
        XCTAssertEqual(inviteDebit(before, after: dashboard(balance: 250, movements: [older]).rewards), .notDebited)
        let otherAmount = RewardMovement(id: "m", date: at, label: "Réservation d’un vélo", amount: -10)
        XCTAssertEqual(inviteDebit(before, after: dashboard(balance: 240, movements: [otherAmount]).rewards), .unknown)
        XCTAssertEqual(inviteDebit(before, after: dashboard(balance: nil).rewards), .unknown)
        XCTAssertEqual(inviteDebit(DebitBefore(at: at, balance: nil, cost: 100), after: dashboard(balance: 300).rewards), .unknown)
        XCTAssertEqual(inviteDebit(before, after: dashboard(balance: 255).rewards), .notDebited)
    }

    func testAManualRefreshWaitsForTheOneInFlightAndFiveSeconds() {
        let clock = Clock()
        let gate = RefreshGate(now: { clock.now })
        XCTAssertFalse(gate.allow(busy: true))
        XCTAssertTrue(gate.allow(busy: false))
        clock.now += 4.9
        XCTAssertFalse(gate.allow(busy: false))
        clock.now += 0.2
        XCTAssertFalse(gate.allow(busy: true))
        XCTAssertTrue(gate.allow(busy: false))
        XCTAssertFalse(gate.allow(busy: false))
        XCTAssertEqual(RefreshGate.interval, 5)
    }
}
