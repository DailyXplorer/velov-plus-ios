import Foundation
import Observation
import VelovCore

enum Page: String, CaseIterable, Identifiable {
    case overview, trips, points, stations, account
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Vue d’ensemble"
        case .trips: "Trajets"
        case .points: "Points"
        case .stations: "Stations"
        case .account: "Compte"
        }
    }

    var tab: String { self == .overview ? "Accueil" : title }

    var icon: IconName {
        switch self {
        case .overview: .house
        case .trips: .personSimpleBike
        case .points: .starFour
        case .stations: .mapPin
        case .account: .userCircle
        }
    }
}

enum Resource<T> {
    case loading
    case ready(T)
    case failed(LoadFailure)

    var value: T? {
        if case .ready(let value) = self { return value }
        return nil
    }
}

enum SnapshotScreen: String {
    case overview, overviewMap, trips, tripSheet, rateCard, points, stations, stationSheet, stationSheetLong, bikeList, bikeSheet, account, accountEnd, accountEdit
    case bookingBanner, unlockConfirm, bookConfirm, unlockUncertain, liveActivityLock, liveActivityIsland, tripActivityLock, tripActivityIsland
    case tripEnded, tripEndedStars
    case ongoingBanner, profilePage, contactPage, journalPage, bikePage, logoutDialog, toggleDialog, choiceSheet
    case viaPick, viaChoices, viaChosen, viaReview, viaUncertain, inviteDialog, inviteCode, renewalToggle, renewalDialog, contactUncertain
    case stationsSearch, stationsEmptyFilter, locationError, locationTimeout, pageFailure, bikeListFailure, bikeOwnBooking, bigBalance, dockWhileBikes
    case stats, statsCharts, statsTipFirst, statsTipMiddle, statsTipLast, statsHeatmap, statsHeatTip, statsDonut, statsRecords, statsBike, statsEnd
    case login, loginError, guestFailed, guestStations, guestStationSheet, guestBikeSheet, bikePush
    case expiredSession, bookingWithoutAccount
    case ongoingLong
    case stationsFailure
    case tripDisputed

    var asGuest: Bool { [.guestStations, .guestStationSheet, .guestBikeSheet].contains(self) }

    var signedOut: Bool { self == .login || self == .loginError || self == .guestFailed || asGuest }

    var isLiveActivity: Bool { [.liveActivityLock, .liveActivityIsland, .tripActivityLock, .tripActivityIsland].contains(self) }

    var withBooking: Bool { [.bookingBanner, .unlockConfirm, .unlockUncertain, .bikeOwnBooking].contains(self) }

    var riding: Bool { [.ongoingBanner, .viaPick, .viaChoices, .viaChosen, .viaReview, .viaUncertain].contains(self) }

    var opensBikes: Bool { [.bikeList, .bikePush, .bikeSheet, .bookConfirm, .bikeListFailure, .bikeOwnBooking, .dockWhileBikes, .guestBikeSheet].contains(self) }

    var pushesBike: Bool { [.bikeSheet, .bookConfirm, .bikeOwnBooking, .guestBikeSheet].contains(self) }
}

@MainActor
@Observable
final class AppModel {
    enum Phase {
        case launching
        case signedOut(String?)
        case guest
        case loading
        case ready(Dashboard)
        case failed(LoadFailure)
    }

    let service: VelovService
    let snapshot: SnapshotScreen?
    var phase: Phase = .launching
    var page: Page = .overview
    var stations: Resource<StationData> = .loading
    var bookings: [Booking] = []
    var stationsPending = false
    var sheet: ActiveSheet?
    var paths: [Page: [Route]] = [:]
    var tops: [Page: Int] = [:]
    var unsaved: Page?
    var leaving: Leave?
    var ratedHere: Set<String> = []
    var contactRequest: ContactRequest?
    var foreground = true
    private(set) var toasts = ToastSlot()
    private(set) var guestFavorites: [Int] = []
    private var docked: Set<String> = []
    private var openSheets = 0
    private var queuedEnded: Trip?
    private var greeted = false
    @ObservationIgnored private let session = SessionGeneration(open: false)
    @ObservationIgnored private lazy var forgetter = Forgetter { [service] in await service.forgetSession() }
    @ObservationIgnored private let bookingsFlight = SingleFlight()
    private let dashboardLoad = LatestLoad()
    @ObservationIgnored let statsCache = StatsScreenCache()
    @ObservationIgnored private lazy var dockWatch: DockWatch = DockWatch(
        check: { [unowned self] in
            guard let result = await session.load({ try await service.tripCheck() }) else { throw CancellationError() }
            switch result {
            case .success(let answer):
                rides.observed(answer.ongoing, latest: answer.latest)
                if let trip = answer.ongoing?.first, dashboard?.ongoing?.contains(where: { $0.id == trip.id }) == false { Task { await loadDashboard() } }
                return answer
            case .failure(let error as VelovError) where error.code == .expired:
                expire()
                throw error
            case .failure(let error):
                throw error
            }
        },
        docked: { [unowned self] tripId, latest in tripDocked(tripId, latest: latest) },
        visible: { [unowned self] in foreground })
    let promoBacking: PromoBacking
    let operations: Operations
    @ObservationIgnored private let guestStore: GuestStore
    @ObservationIgnored private let refreshGate = RefreshGate()
    private let activities = BookingActivities()
    @ObservationIgnored private lazy var rides = TripActivities(host: TripActivityKit(bookings: activities))

    init(service: VelovService, snapshot: SnapshotScreen? = nil, promoBacking: PromoBacking, operationBacking: OperationBacking, guestStore: GuestStore) {
        self.service = service
        self.snapshot = snapshot
        self.promoBacking = promoBacking
        self.guestStore = guestStore
        operations = Operations(backing: operationBacking, session: session)
        switch snapshot {
        case .trips?, .tripSheet?, .rateCard?, .bikePage?: page = .trips
        case .stats?, .statsCharts?, .statsTipFirst?, .statsTipMiddle?, .statsTipLast?, .statsHeatmap?, .statsHeatTip?, .statsDonut?, .statsRecords?, .statsBike?, .statsEnd?: page = .trips
        case .points?, .toggleDialog?, .inviteDialog?, .inviteCode?: page = .points
        case .stations?, .stationSheet?, .stationSheetLong?, .bikeList?, .bikeSheet?, .bookConfirm?, .stationsSearch?, .stationsEmptyFilter?, .locationError?, .locationTimeout?,
             .bikeListFailure?, .bikeOwnBooking?, .dockWhileBikes?, .bikePush?: page = .stations
        case .stationsFailure?: page = .stations
        case .account?, .accountEnd?, .accountEdit?, .profilePage?, .contactPage?, .journalPage?, .logoutDialog?, .choiceSheet?, .renewalToggle?, .renewalDialog?,
             .contactUncertain?: page = .account
        case .tripDisputed?: page = .trips
        default: break
        }
        paths = Self.snapshotPaths(snapshot)
        if snapshot == .logoutDialog { sheet = .logout }
        if snapshot?.riding == true, snapshot != .ongoingBanner { sheet = .via }
    }

    private static func snapshotPaths(_ snapshot: SnapshotScreen?) -> [Page: [Route]] {
        guard let snapshot, let first = SampleData.trips.first else { return [:] }
        switch snapshot {
        case .tripSheet, .rateCard: return [.trips: [.trip(TripRoute(trip: first))]]
        case .bikePage: return [.trips: [.trip(TripRoute(trip: first)), .bike(BikeRoute(number: first.bikeNumber ?? 20449, station: nil))]]
        case .accountEdit, .profilePage, .choiceSheet: return [.account: [.profile]]
        case .contactPage, .contactUncertain: return [.account: [.contact(nil)]]
        case .journalPage: return [.account: [.journal]]
        case .tripDisputed: return SampleData.trips.first(where: \.litigious).map { [.trips: [.trip(TripRoute(trip: $0))]] } ?? [:]
        default: return snapshot.showsStats ? [.trips: [.stats]] : [:]
        }
    }

    static func promoDirectory() -> URL {
        URL.applicationSupportDirectory.appending(path: "PromoCodes", directoryHint: .isDirectory)
    }

    var dashboard: Dashboard? {
        if case .ready(let data) = phase { return data }
        return nil
    }

    var isGuest: Bool {
        if case .guest = phase { return true }
        return false
    }

    var favorites: [Int] { isGuest ? guestFavorites : dashboard?.profile.favorites ?? [] }

    func start() async {
        guard case .launching = phase else { return }
        if snapshot == nil { rides.launched() }
        switch StartMode(hasSession: await service.hasSession(), guest: guestStore.isOn) {
        case .session:
            operations.use(account: await service.accountEmail())
            session.begin()
            phase = .loading
            refreshAll()
        case .guest:
            browse()
        case .signedOut:
            phase = .signedOut(nil)
        }
    }

    func continueAsGuest() async {
        guard await forgetter.forget() else {
            phase = .signedOut(Messages.guestFailed)
            return
        }
        guestStore.remember(true)
        browse()
    }

    private func browse() {
        guestFavorites = guestStore.favorites
        page = .stations
        phase = .guest
        Task { await loadStations() }
    }

    func leaveGuest() {
        guestStore.remember(false)
        sheet = nil
        paths = [:]
        page = .overview
        phase = .signedOut(nil)
    }

    func showToast(_ message: String, action: ToastAction? = nil) {
        toasts.show(message, action: action)
    }

    func showToast(_ failure: LocationFailure) {
        showToast(failure.message, action: failure.action)
    }

    func dismissToast(_ id: Int) {
        toasts.dismiss(id)
    }

    func setGuestFavorite(_ number: Int, _ on: Bool) {
        guestFavorites = guestStore.setFavorite(number, on)
    }

    func refreshAll() {
        Task { await loadDashboard() }
        Task { await loadStations() }
        Task { await loadBookings() }
    }

    func manualRefresh() async {
        guard refreshGate.allow(busy: refreshing || stationsPending) else { return }
        if isGuest { return await loadStations() }
        async let dashboard: Void = loadDashboard()
        async let stations: Void = loadStations()
        async let bookings: Void = loadBookings()
        _ = await (dashboard, stations, bookings)
    }

    var refreshing: Bool { dashboardLoad.running }

    func loadDashboard() async {
        await dashboardLoad.run({ [self] in await session.load { try await service.dashboard() } }) { [self] in showDashboard($0) }
    }

    private func showDashboard(_ result: Result<Dashboard, Error>) {
        switch result {
        case .success(let data):
            if let previous = dashboard?.profile.email, previous != data.profile.email { statsChanged() }
            operations.use(account: data.profile.email)
            phase = .ready(data)
            watchTrips(data)
        case .failure(let error as VelovError) where error.code == .expired:
            expire()
        case .failure(let error):
            if dashboard == nil { phase = .failed(LoadFailure(error, "Votre compte est momentanément indisponible.")) } else { showToast(Messages.refreshFailed) }
        }
    }

    func loadStations() async {
        guard !stationsPending else { return }
        stationsPending = true
        defer { stationsPending = false }
        do { stations = .ready(try await service.stations()) }
        catch {
            if stations.value == nil { stations = .failed(LoadFailure(error, Messages.stationsUnavailable)) } else { showToast(Messages.refreshFailed) }
        }
    }

    func loadBookings(force: Bool = false) async {
        await bookingsFlight.run(force: force) { [self] in
            switch await session.load({ try await service.bookings() }) {
            case .success(let value)?:
                bookings = value
                if snapshot == nil { activities.sync(value) }
                if snapshot == .unlockConfirm || snapshot == .unlockUncertain, let first = value.first { sheet = .unlock(first) }
            case .failure(let error as VelovError)? where error.code == .expired:
                expire()
            default:
                break
            }
        }
    }

    func inSession<T>(_ fetch: () async throws -> T) async -> Result<T, Error>? {
        await session.load(fetch)
    }

    func runOnce(_ key: String, meta: [String: String] = [:], _ send: () async throws -> Outcome) async -> Operations.Run {
        let run = await operations.runOnce(key, meta: meta, send)
        if case .finished(let outcome) = run, outcome.httpStatus == 401 || outcome.code == "local.expired" { expire() }
        return run
    }

    func statsChanged() {
        statsCache.clear { [service] in await service.forgetStats() }
    }

    func loadStats() async -> Result<Stats, Error>? {
        await statsCache.load(account: dashboard?.profile.email ?? "", session: session) { [service] in try await service.stats() }
    }

    func becameActive() {
        foreground = true
        guard dashboard != nil else { return }
        Task { await loadBookings() }
        Task { await dockWatch.visibilityChanged() }
    }

    func resignedActive() {
        foreground = false
        Task { await dockWatch.visibilityChanged() }
    }

    private func watchTrips(_ data: Dashboard) {
        if snapshot == .tripEnded || snapshot == .tripEndedStars {
            if let trip = SampleData.trips.first { sheet = .ended(trip) }
            return
        }
        if snapshot == .dockWhileBikes, let trip = SampleData.trips.first {
            Task {
                try? await Task.sleep(for: .seconds(3))
                showEnded(trip)
            }
            return
        }
        guard snapshot == nil else { return }
        let ongoing = data.ongoing?.filter { !docked.contains($0.id) }
        if foreground { rides.observed(ongoing, latest: data.trips.flatMap(latestFinished)) }
        if let trip = ongoing?.first { dockWatch.follow(trip.id) }
        guard !greeted else { return }
        switch greeting(trips: data.trips, ongoing: data.ongoing, store: UserDefaults.standard) {
        case .undecided: break
        case .nothing: greeted = true
        case .trip(let recent):
            greeted = true
            showEnded(recent)
        }
    }

    private func tripDocked(_ tripId: String, latest: Trip?) {
        docked.insert(tripId)
        statsChanged()
        let started = session.current
        Task {
            await loadDashboard()
            guard started == session.current else { return }
            if let trip = dashboard?.trips?.first(where: { $0.id == tripId }) ?? (latest?.id == tripId ? latest : nil) { showEnded(trip) }
            await loadBookings(force: true)
        }
    }

    private func showEnded(_ trip: Trip) {
        if sheet == nil && openSheets == 0 { sheet = .ended(trip) } else { queuedEnded = trip }
        if snapshot == nil { rides.finished(trip) }
    }

    func closeEnded(_ trip: Trip) {
        if snapshot == nil { dismissTrip(UserDefaults.standard, trip.id) }
        if case .ended(let shown)? = sheet, shown.id == trip.id { sheet = nil }
        if queuedEnded?.id == trip.id { queuedEnded = nil }
    }

    func sheetAppeared() { openSheets += 1 }

    func sheetDisappeared() {
        openSheets = max(0, openSheets - 1)
        guard openSheets == 0, sheet == nil, let trip = queuedEnded else { return }
        queuedEnded = nil
        sheet = .ended(trip)
    }

    func push(_ route: Route, on page: Page) {
        paths[page, default: []].append(route)
    }

    @discardableResult
    func select(_ target: Page) -> Bool {
        guard target != page else { return false }
        if unsaved == page, !operations.sending {
            leaving = .tab(target)
            return false
        }
        page = target
        return true
    }

    func reselect(_ page: Page) {
        if unsaved == page, !operations.sending { return leave(.root(page)) }
        if paths[page]?.isEmpty == false, !operations.sending { paths[page] = [] }
        tops[page, default: 0] += 1
    }

    func leave(_ intent: Leave) {
        if unsaved != nil { leaving = intent } else { discard(intent) }
    }

    func discard(_ intent: Leave) {
        leaving = nil
        unsaved = nil
        switch intent {
        case .back(let page): if paths[page]?.isEmpty == false { paths[page]?.removeLast() }
        case .root(let page): reselect(page)
        case .tab(let target): page = target
        }
    }

    func booked(_ booking: Booking?) {
        if let booking {
            bookings.removeAll { $0.id == booking.id }
            bookings.append(booking)
            if snapshot == nil { activities.start(booking) }
        }
        statsChanged()
        Task { await loadBookings(force: true) }
    }

    func unlocked(bookingId: String?, ride: Ride) {
        if let bookingId {
            bookings.removeAll { $0.id == bookingId }
            activities.end(bookingId: bookingId)
        }
        if snapshot == nil {
            rides.unlocked(ride)
            dockWatch.follow(ride.tripId)
        }
        statsChanged()
        Task {
            await loadBookings(force: true)
            await loadDashboard()
        }
    }

    func patch(_ change: (inout Dashboard) -> Void) {
        guard case .ready(var data) = phase else { return }
        change(&data)
        phase = .ready(data)
        dashboardLoad.changed()
    }

    func setFavorite(_ number: Int, _ on: Bool) {
        patch { data in
            data.profile.favorites.removeAll { $0 == number }
            if on { data.profile.favorites.append(number) }
        }
    }

    func setAutoSpend(_ value: Bool) {
        patch { $0.rewards.autoSpend = value }
    }

    func signIn(email: String, code: String) async throws {
        endSession()
        await forgetter.settled()
        try await service.signIn(email: email, code: code)
        session.begin()
        guestStore.remember(false)
        sheet = nil
        queuedEnded = nil
        operations.use(account: await service.accountEmail())
        phase = .loading
        refreshAll()
    }

    private func endSession() {
        session.invalidate()
        dashboardLoad.reset()
        bookingsFlight.reset()
        statsChanged()
    }

    func logout() async {
        endSession()
        dockWatch.stop()
        guard let confirmed = await session.unchanged({ await service.logout() }) else { return }
        signOut(confirmed ? nil : Messages.remoteLogoutUnconfirmed)
    }

    func expire() {
        signOut(Messages.sessionExpired)
        Task { await forgetter.forget() }
    }

    private func signOut(_ notice: String?) {
        endSession()
        dockWatch.stop()
        bookings = []
        sheet = nil
        queuedEnded = nil
        paths = [:]
        unsaved = nil
        leaving = nil
        contactRequest = nil
        ratedHere = []
        docked = []
        greeted = false
        activities.endAll()
        rides.endAll()
        operations.use(account: nil)
        page = .overview
        phase = .signedOut(notice)
    }
}
