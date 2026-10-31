import Foundation

private let currentSubscriptions = "subscriptions?periods=CURRENT&typeList=ST&typeList=LT&isLocked=false"
private let noSubscription = Outcome.refusal("local.no.subscription", "Aucun abonnement valide : achetez un ticket ou un abonnement dans l’app Vélo’v.")

extension VelovAPI {
    public func writer(_ identity: Identity) async throws -> WriteAuth {
        try await beforeSending { WriteAuth(accountId: try await accountId(identity), token: try await appToken.get(), identity: identity.accessToken) }
    }

    private func http(_ identity: Identity) async throws -> HTTPTransport {
        guard await identity.live() else { throw VelovError.sessionRevoked }
        return writes
    }

    private func currentSubscriptionList(_ account: String, _ identity: Identity, accept: String = Guesses.subscriptionMediaType) async throws -> [JSON] {
        guard let list = try await read("\(account)/\(currentSubscriptions)", identity, accept: accept).array else { throw ShapeError("subscriptions is not a list") }
        return list
    }

    private func currentSubscriptionId(_ account: String, _ identity: Identity) async throws -> String? {
        try await currentSubscriptionList(account, identity).first {
            $0["id"]?.string != nil && $0["isLocked"]?.bool != true && ($0["periods"]?.array?.isEmpty == false)
        }?["id"]?.string
    }

    private func stationUUID(_ number: Int) async throws -> String? {
        let response = try await getWithAppToken(client, appToken, URL(string: "\(Cyclocity.base)/stations/\(number)")!) { token in
            ["Authorization": "Taknv1 \(token)", "Accept": "application/vnd.station.v4+json"]
        }
        return response.ok ? response.json?["id"]?.string : nil
    }

    public func book(_ identity: Identity, stationNumber: Int, bikeNumber: Int) async throws -> (outcome: Outcome, booking: Booking?) {
        let (subscriptionId, station, list) = try await beforeSending {
            let account = "/accounts/\(try await accountId(identity))"
            async let subscription = currentSubscriptionId(account, identity)
            async let stationId = stationUUID(stationNumber)
            async let bikes = rawBikes("stationNumber=\(stationNumber)", unavailable: Messages.stationBikesUnavailable)
            return try await (subscription, stationId, bikes)
        }
        let bike = list.first { $0.number == bikeNumber }
        guard let subscriptionId else { return (noSubscription, nil) }
        guard let bike, bike.status == "AVAILABLE" else { return (.refusal("local.bike.gone", "Ce vélo n’est plus disponible à cette station."), nil) }
        if bike.isReserved == true { return (.refusal("local.bike.reserved", "Ce vélo est déjà réservé."), nil) }
        guard let standNumber = bike.standNumber else { return (.refusal("local.bike.no.stand", "Ce vélo n’est pas accroché à une borne : il ne peut pas être réservé."), nil) }
        guard let bikeId = bike.id, let station else {
            return (.refusal("local.missing.id", "Ce vélo ne peut pas être réservé pour le moment. Réessayez dans un instant."), nil)
        }
        let (outcome, booking) = try await Writes.book(try await writer(identity), stationId: station, stationNumber: stationNumber, standNumber: standNumber,
                                                       subscriptionId: subscriptionId, bikeId: bikeId, http: try await http(identity))
        guard let booking else { return (outcome, nil) }
        return (outcome, toBooking(booking, stations: await stationsByNumber(), bikeNumbers: [bikeId: bike.number]))
    }

    public func unlock(_ identity: Identity, stationNumber: Int, standNumber: Int, bikeNumber: Int) async throws -> (outcome: Outcome, ongoing: [Trip]?) {
        let auth = try await writer(identity)
        let account = "/accounts/\(auth.accountId)"
        guard let subscriptionId = try await beforeSending({ try await currentSubscriptionId(account, identity) }) else { return (noSubscription, nil) }
        let outcome = try await Writes.release(auth, subscriptionId: subscriptionId, stationNumber: stationNumber, standNumber: standNumber, bikeNumber: bikeNumber, http: try await http(identity))
        if outcome.httpStatus == 0 { return (outcome, nil) }
        await client.pause(2)
        async let ongoing = try? RawTrip.list(try await read("\(account)/trips/ongoing", identity, accept: "application/vnd.trip.v6+json"))
        async let stations = stationsByNumber()
        let (trips, byNumber) = await (ongoing, stations)
        return (outcome, trips?.map { normalizeTrip($0, stations: byNumber) })
    }

    public func watchUnlock(_ identity: Identity, bikeNumber: Int) async throws -> Trip? {
        let account = "/accounts/\(try await accountId(identity))"
        for wait in Reconcile.unlockPolls {
            await client.pause(wait)
            if Task.isCancelled { return nil }
            do {
                let trips = try RawTrip.list(try await read("\(account)/trips/ongoing", identity, accept: "application/vnd.trip.v6+json"))
                if let trip = trips.first(where: { $0.bikeNumber == Double(bikeNumber) }) { return normalizeTrip(trip, stations: await stationsByNumber()) }
            } catch let error as VelovError where error.code == .expired { throw error } catch {}
        }
        return nil
    }

    public func rate(_ identity: Identity, tripId: String, bikeNumber: Int, vote: RateVote) async throws -> Outcome {
        try await Writes.rate(try await writer(identity), tripId: tripId, bikeNumber: bikeNumber, vote: vote, http: try await http(identity))
    }

    public func setAutoSpend(_ identity: Identity, _ value: Bool) async throws -> (outcome: Outcome, autoSpend: Bool?) {
        try await Writes.setAutoSpend(try await writer(identity), value, http: try await http(identity))
    }

    public func setFavorite(_ identity: Identity, station: Int, on: Bool) async throws -> Outcome {
        try await Writes.setFavorite(try await writer(identity), station: station, on: on, http: try await http(identity))
    }

    public func receipt(_ identity: Identity, subscriptionId: String, periodId: String) async throws -> (outcome: Outcome, filename: String?, pdf: Data?) {
        try await Writes.receipt(try await writer(identity), subscriptionId: subscriptionId, periodId: periodId, http: try await http(identity))
    }

    public func updateProfile(_ identity: Identity, _ body: ProfileBody) async throws -> Outcome {
        if body.problem() != nil { return .refusal("local.profile.invalid", "Coordonnées invalides.") }
        return try await Writes.setProfile(try await writer(identity), body, http: try await http(identity))
    }

    public func setAutoRenewal(_ identity: Identity, subscriptionId: String, autoRenewal: Bool) async throws -> AutoRenewalResult {
        let auth = try await writer(identity)
        let account = "/accounts/\(pathSegment(auth.accountId))"
        let readState = { [self] in renewalState(of: try await currentSubscriptionList(account, identity).first { $0["id"]?.string == subscriptionId }) }
        let before = try await beforeSending(readState)
        guard before.allowed, before.autoRenewal != nil else {
            return AutoRenewalResult(outcome: .refusal("local.renewal.not.allowed", "Le renouvellement automatique ne peut pas être modifié pour cet abonnement."),
                                     autoRenewal: before.autoRenewal, autoRenewalAllowed: before.allowed, verified: true)
        }
        let outcome = try await Writes.setAutoRenewal(auth, subscriptionId: subscriptionId, autoRenewal: autoRenewal, http: try await http(identity))
        guard outcome.ok else { return AutoRenewalResult(outcome: outcome, autoRenewal: nil, autoRenewalAllowed: false, verified: false) }
        guard let after = try? await readState() else { return AutoRenewalResult(outcome: outcome, autoRenewal: nil, autoRenewalAllowed: false, verified: false) }
        return AutoRenewalResult(outcome: outcome, autoRenewal: after.autoRenewal, autoRenewalAllowed: after.allowed, verified: true)
    }

    public func requestExtraTime(_ identity: Identity, stationNumber: Int) async throws -> Outcome {
        let auth = try await writer(identity)
        let account = "/accounts/\(auth.accountId)"
        let renting: [String] = try await beforeSending {
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
            return renting
        }
        guard renting.count == 1 else {
            return .refusal("local.via.trip", renting.isEmpty ? "Vous n’avez aucun trajet en cours."
                                                              : "Vous avez plusieurs trajets en cours. Utilisez l’app Vélo’v.")
        }
        let (uuid, number, open, stands) = try await beforeSending {
            let station = try await read("/stations/\(stationNumber)", identity, accept: "application/vnd.station.v4+json")
            guard let uuid = station["id"]?.string, let number = station["number"]?.int, let open = station["open"]?.bool,
                  let stands = station["availabilities"]?["main"]?["stands"]?.number else { throw ShapeError("station v4") }
            return (uuid, number, open, stands)
        }
        guard number == stationNumber, open, stands == 0 else {
            return .refusal("local.via.not.full", "Cette station n’est plus pleine ou est fermée. Choisissez-en une autre.")
        }
        let target: ViaStation = Guesses.viaStationIdentifier == .uuid ? .uuid(uuid) : .number(number)
        return try await Writes.via(auth, subscriptionId: renting[0], station: target, http: try await http(identity))
    }

    public func contactSupport(_ identity: Identity, _ body: ContactBody) async throws -> Outcome {
        guard body.isValid else { return .refusal("local.contact.invalid", "Votre message est vide ou trop long.") }
        return try await Writes.contactMail(try await writer(identity), body, http: try await http(identity))
    }

    public func consumePromoCode(_ identity: Identity, expectedCost: Int) async throws -> PromoResult {
        let auth = try await writer(identity)
        let (list, balance) = try await beforeSending {
            async let configuration = read("/rewards/configurations", identity, accept: Guesses.promocodeAccept)
            async let rewards = read("/accounts/\(auth.accountId)/rewards", identity, accept: Guesses.promocodeAccept)
            let (rules, account) = try await (configuration, rewards)
            guard let list = rules.array, let balance = account["balance"]?.number else { throw ShapeError("rewards") }
            return (list, balance)
        }
        let rule = list.first { $0["name"]?.string == Guesses.promocodeReward && $0["enable"]?.bool == true }
        guard let cost = rule?["reward"]?.number, cost == Double(expectedCost) else {
            return PromoResult(outcome: .refusal("local.promo.price.changed", "L’offre a changé. Actualisez avant de confirmer."), promoCode: nil)
        }
        if balance < cost {
            return PromoResult(outcome: .refusal("local.promo.balance", "Votre solde de points est insuffisant."), promoCode: nil)
        }
        return try await Writes.promoCode(auth, http: try await http(identity))
    }
}
