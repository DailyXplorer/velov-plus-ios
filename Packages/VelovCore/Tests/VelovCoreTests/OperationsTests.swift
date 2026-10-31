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

    func testNoActionIsEverSentWithoutStorage() {
        let clock = Clock()
        let failing = store(InMemoryOperationBacking(failing: true), clock)
        for key in ["invite:x", "unlock:1", "book:1", "rate:t-1", "profile", "favorite:2002", "autoSpend", "autoRenewal:sub-1"] {
            XCTAssertEqual(failing.begin(key), .unsaved, key)
        }
        XCTAssertFalse(failing.sending)
        let corrupted = InMemoryOperationBacking()
        corrupted.values["\(Operations.storageKey):\(accountDigest("person@example.com"))"] = Data("not json".utf8)
        XCTAssertEqual(store(corrupted, clock).begin("unlock:1"), .unsaved, "an unreadable registry never lets a write leave")
        let anonymous = store(InMemoryOperationBacking(), clock, account: nil)
        XCTAssertEqual(anonymous.begin("contact:x"), .unsaved)
        XCTAssertEqual(store(nil, clock).begin("via:x:t"), .unsaved)
        XCTAssertEqual(Messages.unsaved, "Ce téléphone ne peut pas suivre cette action. Rien n’a été envoyé.")
        XCTAssertEqual(Messages.busy, "Une autre action est en cours. Attendez sa réponse avant de recommencer.")
    }

    func testAnAnswerLostWithTheAppIsUncertainAtOnceAndNeverExpires() {
        let clock = Clock()
        let backing = InMemoryOperationBacking()
        let first = store(backing, clock)
        XCTAssertEqual(first.begin("invite:x", meta: ["cost": "100", "balance": "250"]), .started)
        let relaunched = store(backing, clock)
        let entry = relaunched.get("invite:x")
        XCTAssertEqual(entry?.status, .uncertain, "a send left by the closed app is uncertain at once")
        XCTAssertEqual(entry?.outcome, noAnswer(Messages.lost))
        XCTAssertEqual(entry?.outcome?.message, "L’app a été fermée avant la réponse. L’action a peut-être abouti.")
        XCTAssertEqual(entry?.meta, ["cost": "100", "balance": "250"])
        XCTAssertFalse(relaunched.busy(), "a send of the closed app blocks no other action")
        XCTAssertEqual(relaunched.begin("invite:x"), .busy, "an uncertain debit is never sent again blindly")
        clock.now += 3600
        XCTAssertEqual(relaunched.get("invite:x")?.status, .uncertain)

        let other = Clock()
        let again = InMemoryOperationBacking()
        XCTAssertEqual(store(again, other).begin("unlock:1", meta: ["bike": "1"]), .started)
        let later = store(again, other)
        XCTAssertEqual(later.get("unlock:1")?.status, .uncertain, "an unlock left by the closed app is not forgotten")
        XCTAssertEqual(later.get("unlock:1")?.meta, ["bike": "1"])
        XCTAssertEqual(later.begin("unlock:1"), .busy)
        XCTAssertEqual(later.begin("book:2"), .started)
        other.now += 86_400
        XCTAssertEqual(later.get("unlock:1")?.status, .uncertain)
    }

    func testAnUncertainOutcomeNeverExpiresByTimeAndARefusalIsForgotten() {
        let clock = Clock()
        let operations = store(InMemoryOperationBacking(), clock)
        for key in ["rate:t-1", "unlock:7", "book:7", "profile", "favorite:2002", "autoSpend", "autoRenewal:sub-1"] {
            XCTAssertEqual(operations.begin(key), .started)
            operations.finish(key, lost)
        }
        XCTAssertEqual(operations.get("rate:t-1")?.outcome, lost)
        XCTAssertFalse(operations.busy())
        clock.now += 7 * 86_400
        for key in ["rate:t-1", "unlock:7", "book:7", "profile", "favorite:2002", "autoSpend", "autoRenewal:sub-1"] {
            XCTAssertEqual(operations.get(key)?.status, .uncertain, key)
            XCTAssertEqual(operations.begin(key), .busy, key)
        }
        XCTAssertEqual(operations.begin("contact:x"), .started)
        operations.finish("contact:x", lost)
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
        XCTAssertEqual(operations.begin("via:x:t-1"), .started)
        operations.finish("via:x:t-1", lost)
        XCTAssertEqual(Array(backing.values.keys), ["velov:operations:v1:" + accountDigest("person@example.com")])
        XCTAssertEqual(PromoStore.key(account: "person@example.com"), "velov:promocodes:v1:" + accountDigest("person@example.com"))
        XCTAssertEqual(accountDigest(" Person@Example.COM "), accountDigest("person@example.com"))
        XCTAssertEqual(accountDigest("a").count, 64)

        XCTAssertEqual(store(backing, clock, account: " PERSON@example.com").get("via:x:t-1")?.status, .uncertain)
        let other = store(backing, clock, account: "other@example.com")
        XCTAssertNil(other.get("via:x:t-1"))
        XCTAssertEqual(other.begin("contact:x"), .started)
        other.use(account: "third@example.com")
        XCTAssertEqual(other.get("contact:x")?.status, .sending, "the running send is still tracked")
        XCTAssertEqual(other.digest, accountDigest("third@example.com"))
        other.finish("contact:x", lost)
        XCTAssertNil(other.get("contact:x"), "the answer is not filed under the account signed in now")
        XCTAssertEqual(store(backing, clock, account: "other@example.com").get("contact:x")?.outcome, lost, "it stays with the account that sent it")
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
        var timedOut = noAnswer("Vélo’v ne répond pas.")
        timedOut.detail = "Délai dépassé · NSURLErrorTimedOut (-1001)"
        XCTAssertEqual(thrown, .finished(timedOut))
        XCTAssertEqual(operations.get("profile")?.status, .uncertain)
        let blocked = await operations.runOnce("profile") { sent += 1; return Outcome(ok: true, httpStatus: 200) }
        XCTAssertEqual(blocked, .busy)
        let unsaved = await store(nil, clock).runOnce("invite:x") { sent += 1; return Outcome(ok: true, httpStatus: 200) }
        XCTAssertEqual(unsaved, .unsaved)
        XCTAssertEqual(sent, 1)
        let version = operations.version
        let done = await operations.runOnce("favorite:2002") { Outcome(ok: true, httpStatus: 204) }
        XCTAssertEqual(done, .finished(Outcome(ok: true, httpStatus: 204)))
        XCTAssertGreaterThan(operations.version, version)
    }

    func testSendingHoldsForTheWholeRunEvenWhenTheCallerLostItsKey() async {
        let operations = store(InMemoryOperationBacking(), Clock())
        var during: Bool?
        let result = await operations.runOnce("via:x:t-1") {
            operations.use(account: nil)
            during = operations.sending
            return Outcome(ok: true, httpStatus: 200)
        }
        XCTAssertEqual(result, .finished(Outcome(ok: true, httpStatus: 200)))
        XCTAssertEqual(during, true, "a sheet that can no longer name its operation still blocks every way out")
        XCTAssertFalse(operations.sending)
    }

    func testAWriteAnswerArrivingAfterTheSessionChangedReachesNoOne() async {
        let clock = Clock()
        let session = SessionGeneration()
        let backing = InMemoryOperationBacking()
        let operations = Operations(backing: backing, account: "person@example.com", session: session, now: { clock.now })
        let expired = Outcome(ok: false, httpStatus: 401)
        let late = await operations.runOnce("unlock:7") {
            session.invalidate()
            operations.use(account: "other@example.com")
            return expired
        }
        XCTAssertEqual(late, .superseded, "a 401 to the old session signs the next account out of nothing")
        let success = await operations.runOnce("book:2") {
            session.invalidate()
            operations.use(account: nil)
            return Outcome(ok: true, httpStatus: 200)
        }
        XCTAssertEqual(success, .superseded, "a late success starts no tracking for a guest")
        XCTAssertEqual(store(backing, clock).get("unlock:7")?.outcome, expired, "the uncertain write stays with the account that sent it")

        operations.use(account: "person@example.com")
        let checked = await operations.settleHeld("unlock:7") { _ in
            session.invalidate()
            return .applied
        }
        XCTAssertNil(checked, "a check answered after the session changed settles nothing")
        XCTAssertEqual(operations.get("unlock:7")?.status, .uncertain)
        let current = await operations.runOnce("book:3") { Outcome(ok: true, httpStatus: 200) }
        XCTAssertEqual(current, .finished(Outcome(ok: true, httpStatus: 200)))
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
        let at = date("2026-10-29T12:00:00")
        let late = { at.addingTimeInterval(Reconcile.historyLag) }
        var reads = 0
        let ok = await settle(Outcome(ok: true, httpStatus: 200), at: at, now: late) { reads += 1; return .unchanged }
        XCTAssertEqual(ok, .done)
        let refusal = await settle(refused, at: at, now: late) { reads += 1; return .applied }
        XCTAssertEqual(refusal, .refused(refused))
        XCTAssertEqual(reads, 0)
        let applied = await settle(lost, at: at, now: { at }) { .applied }
        XCTAssertEqual(applied, .done)
        var notApplied = lost
        notApplied.message = "Vélo’v n’a rien enregistré. Vous pouvez réessayer."
        let unchanged = await settle(lost, at: at, now: late) { .unchanged }
        XCTAssertEqual(unchanged, .refused(notApplied))
        let unknown = await settle(lost, at: at, now: late) { .unknown }
        XCTAssertEqual(unknown, .uncertain(lost))
        let thrown = await settle(lost, at: at, now: late) { throw URLError(.timedOut) }
        XCTAssertEqual(thrown, .uncertain(lost))
    }

    func testAnUnchangedStateRightAfterAnUncertainWriteIsNotARefusal() async {
        let at = date("2026-10-29T12:00:00")
        let early = await settle(lost, at: at, now: { at.addingTimeInterval(Reconcile.historyLag - 1) }) { .unchanged }
        XCTAssertEqual(early, .uncertain(lost))
        XCTAssertEqual(Reconcile.historyLag, 120)

        let clock = Clock()
        let operations = store(InMemoryOperationBacking(), clock)
        XCTAssertEqual(operations.begin("rate:t-1"), .started)
        operations.finish("rate:t-1", lost)
        let soon = await operations.settleHeld("rate:t-1") { _ in .unchanged }
        XCTAssertEqual(soon, .uncertain(lost))
        XCTAssertEqual(operations.begin("rate:t-1"), .busy, "a second rating cannot leave while the first may still appear")
        clock.now += 120
        let later = await operations.settleHeld("rate:t-1") { _ in .unchanged }
        guard case .refused(let answer)? = later else { return XCTFail("expected a refusal, got \(String(describing: later))") }
        XCTAssertEqual(answer.message, Messages.notApplied)
        XCTAssertNil(operations.get("rate:t-1"))
        XCTAssertEqual(operations.begin("rate:t-1"), .started)
    }

    func testAHeldWriteIsCheckedAgainstItsOriginalIntentAndAStaleCheckClearsNothingNewer() async {
        let clock = Clock()
        let operations = store(InMemoryOperationBacking(), clock)
        XCTAssertEqual(operations.begin("favorite:2002", meta: Intent.wanted(true)), .started)
        operations.finish("favorite:2002", lost)
        var seen: [String: String] = [:]
        let settled = await operations.settleHeld("favorite:2002") { intent in
            seen = intent
            return favoriteCheck(self.dashboard(favorites: [2002]), station: 2002, wanted: Intent.wanted(intent)!)
        }
        XCTAssertEqual(settled, .done)
        XCTAssertEqual(seen, ["wanted": "true"])
        XCTAssertNil(operations.get("favorite:2002"))
        let nothing = await operations.settleHeld("favorite:2002") { _ in .applied }
        XCTAssertNil(nothing)

        XCTAssertEqual(operations.begin("book:7"), .started)
        operations.finish("book:7", lost)
        let old = operations.get("book:7")!
        operations.clear("book:7")
        clock.now += 1
        XCTAssertEqual(operations.begin("book:7"), .started)
        operations.finish("book:7", lost)
        operations.clear("book:7", held: old)
        XCTAssertEqual(operations.get("book:7")?.status, .uncertain, "a late check of the old send does not erase the new one")
    }

    func testAnUnlockIsSettledOnlyByItsBikesTripOrByNoTripAfterTheDockWindow() {
        let since = date("2026-10-29T12:00:00")
        let riding = TripCheck(ongoing: [Trip(id: "t", status: "STARTED", startedAt: since, bikeNumber: 7)], latest: nil)
        XCTAssertEqual(unlockCheck(riding, bike: 7, since: since, now: since), .applied)
        let other = TripCheck(ongoing: [Trip(id: "t", status: "STARTED", startedAt: since, bikeNumber: 8)], latest: nil)
        XCTAssertEqual(unlockCheck(other, bike: 7, since: since, now: since), .unknown)
        XCTAssertEqual(unlockCheck(other, bike: 7, since: since, now: since.addingTimeInterval(180)), .unknown, "another bike riding is no proof")
        let docked = TripCheck(ongoing: [], latest: Trip(id: "t", startedAt: since.addingTimeInterval(-20), bikeNumber: 7))
        XCTAssertEqual(unlockCheck(docked, bike: 7, since: since, now: since.addingTimeInterval(600)), .applied)
        let older = TripCheck(ongoing: [], latest: Trip(id: "t", startedAt: since.addingTimeInterval(-3600), bikeNumber: 7))
        XCTAssertEqual(unlockCheck(older, bike: 7, since: since, now: since.addingTimeInterval(60)), .unknown)
        XCTAssertEqual(unlockCheck(older, bike: 7, since: since, now: since.addingTimeInterval(Reconcile.dockWindow)), .unchanged)
        XCTAssertEqual(unlockCheck(TripCheck(ongoing: nil, latest: nil), bike: 7, since: since, now: since.addingTimeInterval(3600)), .unknown)
        let unread = TripCheck(ongoing: [], latest: nil, historyRead: false)
        XCTAssertEqual(unlockCheck(unread, bike: 7, since: since, now: since.addingTimeInterval(180)), .unknown, "no history read is no proof")
        let held = Booking(id: "bk-7", stationNumber: 2002, stationName: "Bellecour", standNumber: 4, bikeNumber: 7, endsAt: nil, lat: nil, lon: nil)
        let late = since.addingTimeInterval(180)
        XCTAssertEqual(unlockCheck(older, bike: 7, since: since, now: late, booking: "bk-7", bookings: [held]), .unchanged)
        XCTAssertEqual(unlockCheck(older, bike: 7, since: since, now: late, booking: "bk-7", bookings: []), .unknown, "a consumed booking is no proof")
        XCTAssertEqual(unlockCheck(older, bike: 7, since: since, now: late, booking: "bk-7", bookings: nil), .unknown)

        let booking = Booking(id: "bk", stationNumber: 2002, stationName: "Bellecour", standNumber: 4, bikeNumber: 7, endsAt: nil, lat: nil, lon: nil)
        XCTAssertEqual(bookingCheck([booking], bike: 7), .applied)
        XCTAssertEqual(bookingCheck([booking], bike: 8), .unchanged)
        let anonymous = Booking(id: "bk-x", stationNumber: 2002, stationName: "Bellecour", standNumber: 4, bikeNumber: nil, endsAt: nil, lat: nil, lon: nil)
        XCTAssertEqual(bookingCheck([anonymous], bike: 8), .unknown, "a booking without a bike number may be ours")
        XCTAssertEqual(bookingCheck([anonymous, booking], bike: 7), .applied)
        XCTAssertEqual(bookingCheck([], bike: 7), .unchanged)
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
        let intent = profileIntent(body)
        var after = before
        after.address = "2 Place Bellecour"
        XCTAssertEqual(profileCheck(intent, after: after), .applied)
        XCTAssertEqual(profileCheck(intent, after: before), .unchanged)
        after.address = "3 rue Mercière"
        XCTAssertEqual(profileCheck(intent, after: after), .unchanged)
        var renamed = before
        renamed.lastName = "LOVELACE-BYRON"
        XCTAssertEqual(profileCheck(profileIntent(ProfileBody(lastName: "Lovelace-Byron")), after: renamed), .applied)
        XCTAssertEqual(profileCheck([:], after: renamed), .unchanged)
        let legacy = ["profile": #"{"before":[null,["Lovelace"],null,null,null,null,null],"wanted":[null,["lovelace-byron"],null,null,null,null,null]}"#]
        XCTAssertEqual(profileCheck(legacy, after: renamed), .applied)

        var edited = before
        edited.city = "Villeurbanne"
        XCTAssertEqual(profileCheck(intent, after: edited), .unchanged, "the stored intent is checked, not a later draft")
    }

    func testAProfileThatNeverMatchesTheIntentStopsHoldingTheKeyAfterTheLag() async {
        let clock = Clock()
        let operations = store(InMemoryOperationBacking(), clock)
        let intent = profileIntent(ProfileBody(phoneNumber: "06 98 76 54 32"))
        XCTAssertEqual(operations.begin(OperationKey.profile, meta: intent), .started)
        operations.finish(OperationKey.profile, lost)
        var normalized = dashboard().profile
        normalized.phoneNumber = "+33698765432"
        let soon = await operations.settleHeld(OperationKey.profile) { profileCheck($0, after: normalized) }
        XCTAssertEqual(soon, .uncertain(lost))
        XCTAssertEqual(operations.begin(OperationKey.profile), .busy)
        clock.now += Reconcile.historyLag
        let later = await operations.settleHeld(OperationKey.profile) { profileCheck($0, after: normalized) }
        guard case .refused(let answer)? = later else { return XCTFail("expected a refusal, got \(String(describing: later))") }
        XCTAssertEqual(answer.message, Messages.notApplied)
        XCTAssertNil(operations.get(OperationKey.profile))
        XCTAssertEqual(operations.begin(OperationKey.profile), .started)
    }

    func testAProfileChangeHeldInClearByAnOlderVersionIsHashedAtLoadForEveryAccount() {
        let clock = Clock()
        let backing = InMemoryOperationBacking()
        let legacy = #"{"before":[null,["Lovelace"],null,null,null,null,["+33612345678"]],"wanted":[null,["lovelace-byron"],null,null,null,null,["+33698765432"]]}"#
        let held = Operations.Entry(status: .uncertain, at: clock.now, outcome: lost, meta: ["profile": legacy])
        for account in ["person@example.com", "other@example.com"] {
            backing.values["\(Operations.storageKey):\(accountDigest(account))"] = try? JSONEncoder().encode([OperationKey.profile: held])
        }
        let operations = store(backing, clock, account: nil)
        XCTAssertEqual(backing.values.count, 2)
        for raw in backing.values.values {
            let text = String(decoding: raw, as: UTF8.self)
            XCTAssertFalse(text.lowercased().contains("lovelace") || text.contains("+33"), "no profile value stays in clear: \(text)")
        }
        operations.use(account: "other@example.com")
        let entry = operations.get(OperationKey.profile)
        XCTAssertEqual(entry?.status, .uncertain, "the change is still held")
        XCTAssertEqual(operations.begin(OperationKey.profile), .busy)
        var renamed = dashboard().profile
        renamed.lastName = "LOVELACE-BYRON"
        renamed.phoneNumber = "+33698765432"
        XCTAssertEqual(entry.map { profileCheck($0.meta, after: renamed) }, .applied, "and still checked against what was sent")
        XCTAssertEqual(entry.map { profileCheck($0.meta, after: dashboard().profile) }, .unchanged)
    }

    func testALegacyProfileEntryWithoutIntentIsReleasedAfterTheLag() async {
        let clock = Clock()
        let operations = store(InMemoryOperationBacking(), clock)
        XCTAssertEqual(operations.begin(OperationKey.profile), .started)
        operations.finish(OperationKey.profile, lost)
        clock.now += Reconcile.historyLag
        let settled = await operations.settleHeld(OperationKey.profile) { profileCheck($0, after: self.dashboard().profile) }
        guard case .refused? = settled else { return XCTFail("expected a refusal, got \(String(describing: settled))") }
        XCTAssertEqual(operations.begin(OperationKey.profile), .started)
    }

    func testANetBalanceNeverProvesAnInviteWasNotDebited() {
        let at = date("2026-10-29T12:00:00")
        let before = DebitBefore(at: at, cost: 50)
        let late = at.addingTimeInterval(Reconcile.historyLag)
        let ledger = { (movements: [RewardMovement], complete: Bool) in RewardLedger(movements: movements, complete: complete) }
        let debit = RewardMovement(id: "m", date: at.addingTimeInterval(30), label: "Invitation d’un proche", amount: -50)
        XCTAssertEqual(inviteDebit(before, ledger: ledger([debit], false), now: at), .debited)
        let sameDay = RewardMovement(id: "m", date: date("2026-10-29"), label: "Invitation d’un proche", amount: -50, dateOnly: true)
        XCTAssertEqual(inviteDebit(before, ledger: ledger([sameDay], true), now: late), .debited)

        let credit = RewardMovement(id: "c", date: at.addingTimeInterval(10), label: "Vélo évalué", amount: 1)
        XCTAssertEqual(inviteDebit(before, ledger: ledger([credit], false), now: late), .unknown, "a lost page may hold the debit, whatever the balance")
        XCTAssertEqual(inviteDebit(before, ledger: ledger([], false), now: late), .unknown)
        XCTAssertEqual(inviteDebit(before, ledger: ledger([credit], true), now: late.addingTimeInterval(-1)), .unknown, "too soon for the history to show it")
        let undated = RewardMovement(id: "u", date: nil, label: "Invitation d’un proche", amount: -50)
        XCTAssertEqual(inviteDebit(before, ledger: ledger([undated], true), now: late), .unknown)
        let older = RewardMovement(id: "o", date: at.addingTimeInterval(-301), label: "Invitation d’un proche", amount: -50)
        XCTAssertEqual(inviteDebit(before, ledger: ledger([credit, older], true), now: late), .notDebited)
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

    final class Counter { var value = 0 }
    final class Log { var items: [String] = [] }

    func testBookingReadsShareTheOneInFlightAndWaitFiveSecondsUnlessForced() async {
        let clock = Clock()
        let flight = SingleFlight(now: { clock.now })
        let runs = Counter()
        let (started, didStart) = AsyncStream<Void>.makeStream()
        let (release, doRelease) = AsyncStream<Void>.makeStream()
        let first = Task { await flight.run { runs.value += 1; didStart.yield(); for await _ in release { break } } }
        for await _ in started { break }
        let joined = Task { await flight.run { runs.value += 1 } }
        doRelease.yield()
        await first.value
        await joined.value
        XCTAssertEqual(runs.value, 1, "a read in flight is shared")
        await flight.run { runs.value += 1 }
        XCTAssertEqual(runs.value, 1, "a new read waits five seconds")
        clock.now += 5
        await flight.run { runs.value += 1 }
        XCTAssertEqual(runs.value, 2)
        await flight.run(force: true) { runs.value += 1 }
        XCTAssertEqual(runs.value, 3, "a read after a write is not throttled")
        let (slowStarted, didSlowStart) = AsyncStream<Void>.makeStream()
        let (slowRelease, doSlowRelease) = AsyncStream<Void>.makeStream()
        let order = Log()
        let stale = Task { await flight.run(force: true) { order.items.append("stale"); didSlowStart.yield(); for await _ in slowRelease { break } } }
        for await _ in slowStarted { break }
        let fresh = Task { await flight.run(force: true) { order.items.append("fresh") } }
        await Task.yield()
        doSlowRelease.yield()
        await stale.value
        await fresh.value
        XCTAssertEqual(order.items, ["stale", "fresh"], "a forced read does not reuse a read started before the write")
        flight.reset()
        await flight.run { runs.value += 1 }
        XCTAssertEqual(runs.value, 4)
    }

    func testADashboardAskedForDuringALoadRunsOnceMoreAndDropsTheStaleAnswer() async {
        let load = LatestLoad()
        let fetches = Counter()
        let applied = Log()
        let (started, didStart) = AsyncStream<Void>.makeStream()
        let (release, doRelease) = AsyncStream<Void>.makeStream()
        let fetch: @MainActor () async -> String? = {
            fetches.value += 1
            let answer = "answer \(fetches.value)"
            if fetches.value == 1 {
                didStart.yield()
                for await _ in release { break }
            }
            return answer
        }
        let first = Task { await load.run(fetch) { applied.items.append($0) } }
        for await _ in started { break }
        XCTAssertTrue(load.running)
        let second = Task { await load.run(fetch) { applied.items.append($0) } }
        let third = Task { await load.run(fetch) { applied.items.append($0) } }
        for _ in 0..<5 { await Task.yield() }
        doRelease.yield()
        await second.value
        XCTAssertEqual(applied.items, ["answer 2"], "a request waits for the load it asked for")
        await first.value
        await third.value
        XCTAssertEqual(fetches.value, 2, "requests during a load cause exactly one more load")
        XCTAssertEqual(applied.items, ["answer 2"], "the answer started before the request is dropped")
        XCTAssertFalse(load.running)

        let (patchStarted, didPatchStart) = AsyncStream<Void>.makeStream()
        let (patchRelease, doPatchRelease) = AsyncStream<Void>.makeStream()
        let held = Counter()
        let older = Task {
            await load.run({ () async -> String? in
                held.value += 1
                if held.value == 1 {
                    didPatchStart.yield()
                    for await _ in patchRelease { break }
                    return "older"
                }
                return "newer"
            }) { applied.items.append($0) }
        }
        for await _ in patchStarted { break }
        load.changed()
        doPatchRelease.yield()
        await older.value
        XCTAssertEqual(applied.items.last, "newer", "a local change during a load drops the older answer and loads again")
        XCTAssertFalse(applied.items.contains("older"))
    }

    func testAnAnswerArrivingAfterLogoutIsDropped() async {
        let generation = SessionGeneration()
        let (started, didStart) = AsyncStream<Void>.makeStream()
        let (release, doRelease) = AsyncStream<Void>.makeStream()
        let late = Task {
            await generation.load { () async -> String in
                didStart.yield()
                for await _ in release { break }
                return "old account"
            }
        }
        for await _ in started { break }
        generation.invalidate()
        doRelease.yield()
        let dropped = await late.value
        XCTAssertNil(dropped)
        let failed = await generation.load { () async throws -> String in
            generation.invalidate()
            throw VelovError.sessionRevoked
        }
        XCTAssertNil(failed)
        guard case .success(let fresh)? = await generation.load({ "new account" }) else { return XCTFail("a current answer is kept") }
        XCTAssertEqual(fresh, "new account")
    }

    func testTheStatsScreenKeepsAResultAsLongAsTheAPICacheAndForgetsItOnDemand() {
        let clock = Clock()
        let cache = StatsScreenCache(now: { clock.now })
        var stats = buildStats(StatsInput(trips: [], coords: [:], movements: [], balance: 0, now: clock.now))
        cache.put(stats, account: "a")
        XCTAssertEqual(cache.get("a"), stats)
        XCTAssertNil(cache.get("b"))
        clock.now += 599
        XCTAssertNotNil(cache.get("a"))
        clock.now += 1
        XCTAssertNil(cache.get("a"), "ten minutes, like the API cache")
        stats.complete = false
        cache.put(stats, account: "a")
        clock.now += 59
        XCTAssertNotNil(cache.get("a"))
        clock.now += 1
        XCTAssertNil(cache.get("a"), "one minute for a partial history")
        cache.put(stats, account: "a")
        cache.clear()
        XCTAssertNil(cache.get("a"), "a trip end, an account change or a write forgets it")
    }
}
