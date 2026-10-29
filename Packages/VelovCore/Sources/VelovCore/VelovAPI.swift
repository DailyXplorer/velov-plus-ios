import Foundation

public final class VelovAPI: Sendable {
    public let client: ReadClient
    public let appToken: AppToken
    private let stationsMemo = Memo<StationData>(ttl: 45, stale: true)
    private let stationBikesMemo = Memo<[Bike]>(ttl: 15)
    private let accountIds = Memo<String>(ttl: 10 * 60)
    private let offers = Memo<[JSON]>(ttl: 10 * 60)
    private let rules = Memo<[JSON]>(ttl: 10 * 60)
    let statsMemo = Memo<Stats>(ttl: { statsTTL($0) })

    public init(transport: HTTPTransport, pause: @escaping @Sendable (Double) async -> Void = { try? await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000)) }) {
        let client = ReadClient(transport: transport, pause: pause)
        self.client = client
        appToken = AppToken {
            let body = try JSONSerialization.data(withJSONObject: ["code": Cyclocity.appTokenCode, "key": Cyclocity.appTokenKey], options: [.sortedKeys])
            let request = makeRequest(URL(string: "https://api.cyclocity.fr/auth/environments/PRD/client_tokens")!, method: "POST",
                                      headers: ["Content-Type": "application/json"], body: body, timeout: ReadClient.attemptTimeout)
            let response = try await client.fetchTransient(request)
            guard response.ok, let token = response.json?["accessToken"]?.string else { throw VelovError(.unavailable, "Vélo’v ne répond pas pour le moment.") }
            return token
        }
    }

    private func gbfs(_ file: String) async throws -> JSON {
        let response = try await client.fetchTransient(makeRequest(URL(string: "\(Cyclocity.base)/gbfs/v3/\(file)")!, timeout: ReadClient.attemptTimeout))
        guard response.ok, let value = response.json else { throw VelovError(.unavailable, Messages.stationsUnavailable) }
        return value
    }

    public func stations() async throws -> StationData {
        try await stationsMemo.get("lyon") { [self] in
            async let information = gbfs("station_information.json")
            async let status = gbfs("station_status.json")
            do { return try parseStations(information: try await information, status: try await status) }
            catch is ShapeError { throw VelovError(.unavailable, Messages.stationsUnavailable) }
        }
    }

    public func rawBikes(_ query: String, unavailable: String) async throws -> [RawBike] {
        let response = try await getWithAppToken(client, appToken, URL(string: "\(Cyclocity.base)/bikes?\(query)")!) { token in
            ["Authorization": "Taknv1 \(token)", "Accept": "application/vnd.bikes.v4+json"]
        }
        guard response.ok, let value = response.json, let bikes = try? RawBike.list(value) else { throw VelovError(.unavailable, unavailable) }
        return bikes
    }

    public func stationBikes(_ station: Int) async throws -> [Bike] {
        try await stationBikesMemo.get(String(station)) { [self] in
            try await rawBikes("stationNumber=\(station)", unavailable: Messages.stationBikesUnavailable).map(normalizeBike).sorted {
                let left = $0.standNumber ?? .max, right = $1.standNumber ?? .max
                return left != right ? left < right : $0.number < $1.number
            }
        }
    }

    public func bike(_ number: Int) async throws -> Bike? {
        try await rawBikes("number=\(number)", unavailable: Messages.bikeUnavailable).map(normalizeBike).first { $0.number == number }
    }

    func read(_ path: String, _ identity: Identity, accept: String = "application/json") async throws -> JSON {
        let response = try await getWithAppToken(client, appToken, URL(string: "\(Cyclocity.base)\(path)")!) { token in
            ["Authorization": "Taknv1 \(token)", "Identity": identity.accessToken, "Accept": accept]
        }
        if response.status == 401 { throw VelovError(.expired, Messages.sessionToRenew) }
        guard response.ok, let value = response.json else { throw VelovError(.unavailable, Messages.accountUnavailable) }
        return value
    }

    public func accountId(_ identity: Identity) async throws -> String {
        try await accountIds.get(identity.email) { [self] in
            guard let id = try await read("/accounts/\(pathSegment(identity.email))/id", identity).string, UUID(uuidString: id) != nil else {
                throw VelovError(.unavailable, Messages.accountUnavailable)
            }
            return id
        }
    }

    func stationsByNumber() async -> [Int: Station] {
        guard let data = try? await stations() else { return [:] }
        return Dictionary(data.stations.map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
    }

    public func bookings(_ identity: Identity) async throws -> [Booking] {
        let account = try await accountId(identity)
        let value = try await read("/accounts/\(account)/bookings", identity, accept: "*/*")
        guard let bookings = try? RawBooking.list(value) else { throw VelovError(.unavailable, Messages.bookingsUnreadable) }
        if bookings.isEmpty { return [] }
        let numbers = Array(Set(bookings.map(\.stationNumber)))
        async let stations = stationsByNumber()
        var bikeNumbers: [String: Int] = [:]
        await withTaskGroup(of: [RawBike].self) { group in
            for number in numbers { group.addTask { (try? await self.rawBikes("stationNumber=\(number)", unavailable: "")) ?? [] } }
            for await bikes in group { for bike in bikes { if let id = bike.id { bikeNumbers[id] = bike.number } } }
        }
        let byNumber = await stations
        return bookings.map { toBooking($0, stations: byNumber, bikeNumbers: bikeNumbers) }
    }

    public func tripCheck(_ identity: Identity) async throws -> TripCheck {
        let account = "/accounts/\(try await accountId(identity))"
        let trips = { [self] (path: String) in try RawTrip.list(try await read("\(account)/\(path)", identity, accept: "application/vnd.trip.v6+json")) }
        let ongoing: [RawTrip]?
        do { ongoing = try await trips("trips/ongoing") } catch let error as VelovError where error.code == .expired { throw error } catch { ongoing = nil }
        if let ongoing, ongoing.isEmpty {
            async let history = try? trips("trips?status=FINISHED")
            async let stations = stationsByNumber()
            let (finished, byNumber) = await (history, stations)
            return TripCheck(ongoing: [], latest: latestFinished((finished ?? []).map { normalizeTrip($0, stations: byNumber) }), historyRead: finished != nil)
        }
        let byNumber = ongoing == nil ? [:] : await stationsByNumber()
        return TripCheck(ongoing: ongoing?.map { normalizeTrip($0, stations: byNumber) }, latest: nil, historyRead: false)
    }

    public func dashboard(_ identity: Identity, now: Date = Date()) async throws -> Dashboard {
        let account = "/accounts/\(try await accountId(identity))"
        let reads = DashboardReads()
        @Sendable func optional<T: Sendable>(_ warning: String, _ load: @escaping @Sendable () async throws -> T) async throws -> T? {
            do { return try await load() } catch let error as VelovError where error.code == .expired { throw error } catch {
                await reads.warn(warning)
                return nil
            }
        }
        let current = "\(account)/subscriptions?periods=CURRENT&typeList=ST&typeList=LT&isLocked=false"
        async let profile = read(account, identity, accept: "application/vnd.account.v4+json")
        async let rewards = optional("Le solde de points est momentanément indisponible.") {
            let value = try await self.read("\(account)/rewards", identity, accept: "application/vnd.rewards.v5+json")
            guard value["balance"]?.number != nil else { throw ShapeError("rewards balance") }
            return value
        }
        async let subscriptions = optional("L’abonnement n’a pas pu être actualisé.") { try await self.read(current, identity, accept: "application/vnd.subscription.v6+json") }
        async let history = optional("L’historique des trajets est momentanément indisponible.") { try RawTrip.list(try await self.read("\(account)/trips?status=FINISHED&status=ERROR&status=REVERSED", identity, accept: "application/vnd.trip.v6+json")) }
        async let ongoing = optional("Le trajet en cours n’a pas pu être vérifié.") { try RawTrip.list(try await self.read("\(account)/trips/ongoing", identity, accept: "application/vnd.trip.v6+json")) }
        async let payment = optional("Le moyen de paiement n’a pas pu être vérifié.") { try await self.read("\(account)/payment", identity, accept: "application/vnd.payment.v3+json") }
        async let movements = optional("L’historique des points est momentanément indisponible.") { try await self.read("\(account)/rewards/history?page=0", identity, accept: "application/vnd.rewards.v5+json") }
        async let offerList = optional("Le nom de la formule n’a pas pu être actualisé.") { try await self.offers.get("all") { try await self.read("/offers", identity, accept: "application/vnd.offer.v2+json").array ?? [] } }
        async let ruleList = optional("Les règles de fidélité n’ont pas pu être actualisées.") { try await self.rules.get("all") { try await self.read("/rewards/configurations", identity, accept: "application/vnd.rewards.v5+json").array ?? [] } }
        async let stationData = optional("Les noms des stations sont momentanément indisponibles.") { try await self.stations() }
        async let bookings = optional("Les réservations en cours n’ont pas pu être actualisées.") { try await self.read("\(account)/bookings", identity) }
        async let allSubscriptions = optional("Les reçus d’abonnement sont momentanément indisponibles.") { try await self.read("\(account)/subscriptions?periods=PAST,CURRENT,FUTURE&sort=DESC", identity, accept: "application/vnd.subscription.v6+json") }

        let parts = DashboardParts(
            profile: try await profile, rewards: try await rewards, subscriptions: try await subscriptions, history: try await history, ongoing: try await ongoing,
            payment: try await payment, movements: try await movements, offers: try await offerList, rules: try await ruleList,
            stations: try await stationData, bookings: try await bookings, allSubscriptions: try await allSubscriptions)
        return try assembleDashboard(parts, warnings: await reads.warnings, now: now)
    }
}

private actor DashboardReads {
    var warnings: [String] = []
    func warn(_ warning: String) { warnings.append(warning) }
}

public struct DashboardParts: Sendable {
    public var profile: JSON
    public var rewards: JSON?
    public var subscriptions: JSON?
    public var history: [RawTrip]?
    public var ongoing: [RawTrip]?
    public var payment: JSON?
    public var movements: JSON?
    public var offers: [JSON]?
    public var rules: [JSON]?
    public var stations: StationData?
    public var bookings: JSON?
    public var allSubscriptions: JSON?
}

private func titleOf(_ subscription: JSON, period: JSON?, offers: [JSON]) -> String {
    let offerId = period?["offerId"]?.number
    if let offerId, let title = offers.first(where: { $0["id"]?.number == offerId })?["title"]?.string { return title }
    return subscription["type"]?.string == "LT" ? "Abonnement longue durée" : "Ticket Vélo’v"
}

private func currentSubscription(_ list: [JSON]) -> JSON? {
    list.first { $0["isLocked"]?.bool != true && ($0["periods"]?.array?.isEmpty == false) }
}

func receiptsOf(_ subscriptions: [JSON], offers: [JSON]) -> [Receipt] {
    var receipts: [(receipt: Receipt, start: String)] = []
    for subscription in subscriptions {
        guard let id = subscription["id"]?.string else { continue }
        for period in subscription["periods"]?.array ?? [] {
            guard let periodId = period["id"]?.string else { continue }
            let start = utcDate(period["validityStart"]?.string)
            receipts.append((Receipt(subscriptionId: id, periodId: periodId, title: titleOf(subscription, period: period, offers: offers),
                                     start: cyclocityDate(period["validityStart"]?.string), end: cyclocityDate(period["validityEnd"]?.string)), start ?? ""))
        }
    }
    return receipts.enumerated().sorted { $0.element.start != $1.element.start ? $0.element.start > $1.element.start : $0.offset < $1.offset }.prefix(12).map(\.element.receipt)
}

func rewardMovement(_ movement: JSON) -> RewardMovement? {
    guard let id = movement["id"]?.string, let amount = movement["amount"]?.number, amount.isFinite, amount >= 0,
          let sign = ["DEBIT": -1.0, "CREDIT": 1.0][movement["direction"]?.string ?? ""] else { return nil }
    return RewardMovement(id: id, date: cyclocityDate(movement["createdAt"]?.string),
                          label: Messages.rewardReasons[movement["reason"]?.string ?? ""] ?? "Mouvement de points",
                          amount: amount * sign,
                          dateOnly: movement["createdAt"]?.string?.count == 10)
}

public func assembleDashboard(_ parts: DashboardParts, warnings: [String], now: Date) throws -> Dashboard {
    let raw = parts.profile
    guard let email = raw["email"]?.string else { throw VelovError(.unavailable, Messages.accountUnavailable) }
    let text = { (key: String) -> String? in raw[key]?.string.flatMap { $0.isEmpty ? nil : $0 } }
    var favorites: [Int] = []
    for item in raw["stations"]?.array ?? [] {
        let candidate: JSON? = item.object == nil ? item : item["number"] ?? item["stationNumber"]
        let number: Int? = candidate?.int ?? candidate?.string.flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if let number, number > 0, !favorites.contains(number) { favorites.append(number) }
    }
    let profile = Profile(firstName: raw["firstName"]?.string ?? "", lastName: raw["lastName"]?.string ?? "", email: email,
                          locked: raw["isLocked"]?.bool ?? false, complete: (raw["completion"]?.number ?? 0) >= 1,
                          phoneNumber: text("phoneNumber"), address: raw["address"]?["name"]?.string.flatMap { $0.isEmpty ? nil : $0 },
                          addressComplement: raw["address"]?["complement"]?.string.flatMap { $0.isEmpty ? nil : $0 },
                          zipCode: text("zipCode"), city: text("city"), country: text("country"), favorites: favorites)

    let rewardsValue = parts.rewards.flatMap { $0["balance"]?.number != nil ? $0 : nil }
    let movements = (parts.movements?["content"]?.array ?? []).compactMap(rewardMovement)
    let rules = (parts.rules ?? []).compactMap { rule -> RewardRule? in
        guard rule["enable"]?.bool == true, let name = rule["name"]?.string, let label = Messages.rewardReasons[name], let points = rule["reward"]?.number else { return nil }
        return RewardRule(name: name, label: label, points: points, kind: rule["type"]?.string == "RULE" ? .earn : .spend)
    }
    let rewards = Rewards(balance: rewardsValue?["balance"]?.number, total: rewardsValue.map { $0["total"]?.number ?? $0["balance"]!.number! },
                          autoSpend: rewardsValue.map { $0["autoSpend"]?.bool ?? false }, movements: movements, rules: rules)

    let offers = parts.offers ?? []
    let subscription: SubscriptionState
    if let list = parts.subscriptions?.array {
        if let current = currentSubscription(list) {
            let period = current["periods"]?.array?.last
            let renewal = renewalState(of: current)
            subscription = .current(Subscription(id: current["id"]?.string, title: titleOf(current, period: period, offers: offers), type: current["type"]?.string ?? "",
                                                 validUntil: cyclocityDate(period?["validityEnd"]?.string), active: current["isLocked"]?.bool != true,
                                                 autoRenewal: renewal.autoRenewal, autoRenewalAllowed: renewal.allowed))
        } else {
            subscription = .none
        }
    } else {
        subscription = .unavailable
    }
    let byNumber = Dictionary((parts.stations?.stations ?? []).map { ($0.number, $0) }, uniquingKeysWith: { first, _ in first })
    return Dashboard(profile: profile, rewards: rewards, subscription: subscription, paymentValid: parts.payment?["paymentValid"]?.bool,
                     receipts: parts.allSubscriptions?.array.map { receiptsOf($0, offers: offers) },
                     trips: parts.history?.map { normalizeTrip($0, stations: byNumber) }, ongoing: parts.ongoing?.map { normalizeTrip($0, stations: byNumber) },
                     bookings: parts.bookings?.array?.count, updatedAt: now, warnings: warnings)
}
