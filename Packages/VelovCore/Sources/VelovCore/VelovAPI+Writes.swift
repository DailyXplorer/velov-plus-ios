import Foundation

// The writes as the app calls them (the web client's `lib/velov.ts`): the reads a write depends on, the local refusals
// that send nothing, then exactly one state-changing request from `Writes`.

private let currentSubscriptions = "subscriptions?periods=CURRENT&typeList=ST&typeList=LT&isLocked=false"
private let noSubscription = Outcome.refusal("local.no.subscription", "Aucun abonnement valide : achetez un ticket ou un abonnement dans l’app Vélo’v.")

extension VelovAPI {
    /// The account, the app token and the user's token, as every write needs them.
    public func writer(_ identity: Identity) async throws -> WriteAuth {
        WriteAuth(accountId: try await accountId(identity), token: try await appToken.get(), identity: identity.accessToken)
    }

    private var http: HTTPTransport { client.transport }

    private func currentSubscriptionList(_ account: String, _ identity: Identity, accept: String = Guesses.subscriptionMediaType) async throws -> [JSON] {
        guard let list = try await read("\(account)/\(currentSubscriptions)", identity, accept: accept).array else { throw ShapeError("subscriptions is not a list") }
        return list
    }

    private func currentSubscriptionId(_ account: String, _ identity: Identity) async throws -> String? {
        try await currentSubscriptionList(account, identity).first {
            $0["id"]?.string != nil && $0["isLocked"]?.bool != true && ($0["periods"]?.array?.isEmpty == false)
        }?["id"]?.string
    }

    // MARK: Booking and release

    /// The station's id in the v4 answer, read with the app token; nil when Vélo’v does not give it.
    private func stationUUID(_ number: Int) async throws -> String? {
        let response = try await getWithAppToken(client, appToken, URL(string: "\(Cyclocity.base)/stations/\(number)")!) { token in
            ["Authorization": "Taknv1 \(token)", "Accept": "application/vnd.station.v4+json"]
        }
        return response.ok ? response.json?["id"]?.string : nil
    }

    /// The booking body wants the station's and the bike's ids, not their numbers (§ 5.9): both are read just before the one POST.
    public func book(_ identity: Identity, stationNumber: Int, bikeNumber: Int) async throws -> (outcome: Outcome, booking: Booking?) {
        let account = "/accounts/\(try await accountId(identity))"
        async let subscription = currentSubscriptionId(account, identity)
        async let stationId = stationUUID(stationNumber)
        async let bikes = rawBikes("stationNumber=\(stationNumber)", unavailable: Messages.stationBikesUnavailable)
        let (subscriptionId, station, list) = try await (subscription, stationId, bikes)
        let bike = list.first { $0.number == bikeNumber }
        guard let subscriptionId else { return (noSubscription, nil) }
        guard let bike, bike.status == "AVAILABLE" else { return (.refusal("local.bike.gone", "Ce vélo n’est plus disponible à cette station."), nil) }
        if bike.isReserved == true { return (.refusal("local.bike.reserved", "Ce vélo est déjà réservé."), nil) }
        guard let standNumber = bike.standNumber else { return (.refusal("local.bike.no.stand", "Ce vélo n’est pas accroché à une borne : il ne peut pas être réservé."), nil) }
        guard let bikeId = bike.id, let station else {
            return (.refusal("local.missing.id", "Vélo’v n’a pas donné l’identifiant de la station ou du vélo. Réessayez dans un instant."), nil)
        }
        let (outcome, booking) = try await Writes.book(try await writer(identity), stationId: station, stationNumber: stationNumber, standNumber: standNumber,
                                                       subscriptionId: subscriptionId, bikeId: bikeId, http: http)
        guard let booking else { return (outcome, nil) }
        return (outcome, toBooking(booking, stations: await stationsByNumber(), bikeNumbers: [bikeId: bike.number]))
    }

    /// One release, then one look at the ongoing trip: it usually appears ~10 s after the bike leaves the borne.
    public func unlock(_ identity: Identity, stationNumber: Int, standNumber: Int, bikeNumber: Int) async throws -> (outcome: Outcome, ongoing: [Trip]?) {
        let auth = try await writer(identity)
        let account = "/accounts/\(auth.accountId)"
        guard let subscriptionId = try await currentSubscriptionId(account, identity) else { return (noSubscription, nil) }
        let outcome = try await Writes.release(auth, subscriptionId: subscriptionId, stationNumber: stationNumber, standNumber: standNumber, bikeNumber: bikeNumber, http: http)
        if outcome.httpStatus == 0 { return (outcome, nil) }
        await client.pause(2)
        async let ongoing = try? RawTrip.list(try await read("\(account)/trips/ongoing", identity, accept: "application/vnd.trip.v6+json"))
        async let stations = stationsByNumber()
        let (trips, byNumber) = await (ongoing, stations)
        return (outcome, trips?.map { normalizeTrip($0, stations: byNumber) })
    }

    // MARK: Account

    public func rate(_ identity: Identity, tripId: String, bikeNumber: Int, vote: RateVote) async throws {
        try await Writes.rate(try await writer(identity), tripId: tripId, bikeNumber: bikeNumber, vote: vote, http: http)
    }

    public func setAutoSpend(_ identity: Identity, _ value: Bool) async throws -> (outcome: Outcome, autoSpend: Bool?) {
        try await Writes.setAutoSpend(try await writer(identity), value, http: http)
    }

    public func setFavorite(_ identity: Identity, station: Int, on: Bool) async throws -> Outcome {
        try await Writes.setFavorite(try await writer(identity), station: station, on: on, http: http)
    }

    public func receipt(_ identity: Identity, subscriptionId: String, periodId: String) async throws -> (outcome: Outcome, filename: String?, pdf: Data?) {
        try await Writes.receipt(try await writer(identity), subscriptionId: subscriptionId, periodId: periodId, http: http)
    }

    /// An invalid body never leaves the phone.
    public func updateProfile(_ identity: Identity, _ body: ProfileBody) async throws -> Outcome {
        if body.problem() != nil { return .refusal("local.profile.invalid", "Coordonnées invalides.") }
        return try await Writes.setProfile(try await writer(identity), body, http: http)
    }

    // MARK: Experimental

    /// Verify permission before writing, then read the real server value rather than assuming the requested state.
    public func setAutoRenewal(_ identity: Identity, subscriptionId: String, autoRenewal: Bool) async throws -> AutoRenewalResult {
        let auth = try await writer(identity)
        let account = "/accounts/\(pathSegment(auth.accountId))"
        let readState = { [self] in renewalState(of: try await currentSubscriptionList(account, identity).first { $0["id"]?.string == subscriptionId }) }
        let before = try await readState()
        guard before.allowed, before.autoRenewal != nil else {
            return AutoRenewalResult(outcome: .refusal("local.renewal.not.allowed", "Le renouvellement automatique ne peut pas être modifié pour cet abonnement."),
                                     autoRenewal: before.autoRenewal, autoRenewalAllowed: before.allowed, verified: true)
        }
        // A failed verification is not a failed PATCH: never repeat the write or invent the state.
        let outcome = try await Writes.setAutoRenewal(auth, subscriptionId: subscriptionId, autoRenewal: autoRenewal, http: http)
        guard outcome.ok else { return AutoRenewalResult(outcome: outcome, autoRenewal: nil, autoRenewalAllowed: false, verified: false) }
        guard let after = try? await readState() else { return AutoRenewalResult(outcome: outcome, autoRenewal: nil, autoRenewalAllowed: false, verified: false) }
        return AutoRenewalResult(outcome: outcome, autoRenewal: after.autoRenewal, autoRenewalAllowed: after.allowed, verified: true)
    }

    /// Find the subscription actually renting a bike, not simply the first valid ticket, and recheck the full station before writing.
    public func requestExtraTime(_ identity: Identity, stationNumber: Int) async throws -> Outcome {
        let auth = try await writer(identity)
        let account = "/accounts/\(auth.accountId)"
        let candidates = try await currentSubscriptionList(account, identity, accept: Guesses.viaMediaType).compactMap { item -> String? in
            item["isLocked"]?.bool == true ? nil : item["id"]?.string
        }
        var renting: [String] = []
        for id in candidates {
            guard let ongoing = try await read("\(account)/subscriptions/\(pathSegment(id))/rentbike", identity, accept: Guesses.viaMediaType).bool else {
                throw ShapeError("rentbike is not a boolean")
            }
            if ongoing { renting.append(id) }
        }
        guard renting.count == 1 else {
            return .refusal("local.via.trip", renting.isEmpty ? "Aucun trajet en cours : les minutes supplémentaires ne peuvent pas être demandées."
                                                              : "Plusieurs locations sont en cours : utilisez l’app Vélo’v pour choisir le trajet.")
        }
        // v4 gives the UUID too; GBFS station.id is only a station number and cannot be used as the UUID fallback.
        let station = try await read("/stations/\(stationNumber)", identity, accept: "application/vnd.station.v4+json")
        guard let uuid = station["id"]?.string, let number = station["number"]?.int, let open = station["open"]?.bool,
              let stands = station["availabilities"]?["main"]?["stands"]?.number else { throw ShapeError("station v4") }
        guard number == stationNumber, open, stands == 0 else {
            return .refusal("local.via.not.full", "Cette station n’est plus pleine ou n’est pas ouverte. Choisissez une autre station.")
        }
        let target: ViaStation = Guesses.viaStationIdentifier == .uuid ? .uuid(uuid) : .number(number)
        return try await Writes.via(auth, subscriptionId: renting[0], station: target, http: http)
    }

    /// Sends one customer-service message after the confirmation. An invalid body never leaves the phone.
    public func contactSupport(_ identity: Identity, _ body: ContactBody) async throws -> Outcome {
        guard body.isValid else { return .refusal("local.contact.invalid", "Saisissez un message et une catégorie valides (4 Ko au maximum).") }
        return try await Writes.contactMail(try await writer(identity), body, http: http)
    }

    /// Check the displayed price against the current configuration before the one debit.
    public func consumePromoCode(_ identity: Identity, expectedCost: Int) async throws -> PromoResult {
        let auth = try await writer(identity)
        async let configuration = read("/rewards/configurations", identity, accept: Guesses.promocodeAccept)
        async let rewards = read("/accounts/\(auth.accountId)/rewards", identity, accept: Guesses.promocodeAccept)
        let (rules, account) = try await (configuration, rewards)
        guard let list = rules.array, let balance = account["balance"]?.number else { throw ShapeError("rewards") }
        let rule = list.first { $0["name"]?.string == Guesses.promocodeReward && $0["enable"]?.bool == true }
        guard let cost = rule?["reward"]?.number, cost == Double(expectedCost) else {
            return PromoResult(outcome: .refusal("local.promo.price.changed", "L’offre ou son coût a changé. Actualisez les points avant de confirmer."), promoCode: nil)
        }
        if balance < cost {
            return PromoResult(outcome: .refusal("local.promo.balance", "Votre solde ne permet plus cet échange. Actualisez les points."), promoCode: nil)
        }
        return try await Writes.promoCode(auth, http: http)
    }
}
