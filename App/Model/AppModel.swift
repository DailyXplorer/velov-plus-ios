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
    case stats, statsCharts, statsTipFirst, statsTipMiddle, statsTipLast, statsHeatmap, statsHeatTip, statsDonut, statsRecords, statsBike, statsEnd

    var isLiveActivity: Bool { [.liveActivityLock, .liveActivityIsland, .tripActivityLock, .tripActivityIsland].contains(self) }

    var withBooking: Bool { [.bookingBanner, .unlockConfirm, .unlockUncertain].contains(self) }
}

@MainActor
@Observable
final class AppModel {
    enum Phase {
        case launching
        case guest(String?)
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
    var refreshing = false
    var stationsPending = false
    var unlocking: Booking?
    var ratedHere: Set<String> = []
    var ended: Trip?
    var logoutOpen = false
    var contactRequested = false
    var foreground = true
    private var docked: Set<String> = []
    private var greeted = false
    @ObservationIgnored private let session = SessionGeneration()
    @ObservationIgnored private let bookingsFlight = SingleFlight()
    @ObservationIgnored let statsCache = StatsScreenCache()
    @ObservationIgnored private lazy var dockWatch: DockWatch = DockWatch(
        check: { [unowned self] in
            guard let result = await session.load({ try await service.tripCheck() }) else { throw CancellationError() }
            switch result {
            case .success(let answer):
                rides.observed(answer.ongoing, latest: answer.latest)
                return answer
            case .failure(let error as VelovError) where error.code == .expired:
                phase = .guest("Session expirée. Reconnectez-vous.")
                dockWatch.stop()
                throw error
            case .failure(let error):
                throw error
            }
        },
        docked: { [unowned self] tripId, latest in tripDocked(tripId, latest: latest) },
        visible: { [unowned self] in foreground })
    let promoBacking: PromoBacking
    let operations: Operations
    @ObservationIgnored private let refreshGate = RefreshGate()
    private let activities = BookingActivities()
    @ObservationIgnored private lazy var rides = TripActivities(host: TripActivityKit(bookings: activities))

    init(service: VelovService, snapshot: SnapshotScreen? = nil, promoBacking: PromoBacking, operationBacking: OperationBacking) {
        self.service = service
        self.snapshot = snapshot
        self.promoBacking = promoBacking
        operations = Operations(backing: operationBacking)
        switch snapshot {
        case .trips?, .tripSheet?, .rateCard?: page = .trips
        case .stats?, .statsCharts?, .statsTipFirst?, .statsTipMiddle?, .statsTipLast?, .statsHeatmap?, .statsHeatTip?, .statsDonut?, .statsRecords?, .statsBike?, .statsEnd?: page = .trips
        case .points?: page = .points
        case .stations?, .stationSheet?, .stationSheetLong?, .bikeList?, .bikeSheet?, .bookConfirm?: page = .stations
        case .account?, .accountEnd?, .accountEdit?: page = .account
        default: break
        }
    }

    static func promoDirectory() -> URL {
        URL.applicationSupportDirectory.appending(path: "PromoCodes", directoryHint: .isDirectory)
    }

    var dashboard: Dashboard? {
        if case .ready(let data) = phase { return data }
        return nil
    }

    func start() async {
        guard case .launching = phase else { return }
        if snapshot == nil { rides.launched() }
        if await service.hasSession() {
            phase = .loading
            refreshAll()
        } else {
            phase = .guest(nil)
        }
    }

    func refreshAll() {
        Task { await loadDashboard() }
        Task { await loadStations() }
        Task { await loadBookings() }
    }

    func manualRefresh() async {
        guard refreshGate.allow(busy: refreshing || stationsPending) else { return }
        async let dashboard: Void = loadDashboard()
        async let stations: Void = loadStations()
        async let bookings: Void = loadBookings()
        _ = await (dashboard, stations, bookings)
    }

    func loadDashboard() async {
        guard !refreshing else { return }
        refreshing = true
        guard let result = await session.load({ try await service.dashboard() }) else { return }
        refreshing = false
        switch result {
        case .success(let data):
            if let previous = dashboard?.profile.email, previous != data.profile.email { statsChanged() }
            operations.use(account: data.profile.email)
            phase = .ready(data)
            watchTrips(data)
        case .failure(let error as VelovError) where error.code == .expired:
            dockWatch.stop()
            phase = .guest(error.revoked ? error.message : "Votre session a expiré. Reconnectez-vous.")
        case .failure(let error):
            phase = .failed(LoadFailure(error, "Votre compte est momentanément indisponible."))
        }
    }

    func loadStations() async {
        guard !stationsPending else { return }
        stationsPending = true
        defer { stationsPending = false }
        do { stations = .ready(try await service.stations()) }
        catch { stations = .failed(LoadFailure(error, Messages.stationsUnavailable)) }
    }

    func loadBookings(force: Bool = false) async {
        await bookingsFlight.run(force: force) { [self] in
            guard case .success(let value)? = await session.load({ try await service.bookings() }) else { return }
            bookings = value
            if snapshot == nil { activities.sync(value) }
            if snapshot == .unlockConfirm || snapshot == .unlockUncertain { unlocking = value.first }
        }
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
            ended = SampleData.trips.first
            return
        }
        guard snapshot == nil else { return }
        if foreground { rides.observed(data.ongoing, latest: data.trips.flatMap(latestFinished)) }
        if let trip = data.ongoing?.first(where: { !docked.contains($0.id) }) { dockWatch.follow(trip.id) }
        guard !greeted else { return }
        greeted = true
        if data.ongoing?.isEmpty != false, let trips = data.trips, let recent = tripToGreet(trips, store: UserDefaults.standard) { showEnded(recent) }
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
        ended = trip
        rides.finished(trip)
    }

    func closeEnded(_ trip: Trip) {
        if snapshot == nil { dismissTrip(UserDefaults.standard, trip.id) }
        if ended?.id == trip.id { ended = nil }
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
        try await service.signIn(email: email, code: code)
        phase = .loading
        refreshAll()
    }

    private func endSession() {
        session.invalidate()
        refreshing = false
        bookingsFlight.reset()
        statsChanged()
    }

    func logout() async {
        endSession()
        dockWatch.stop()
        let confirmed = await service.logout()
        endSession()
        bookings = []
        unlocking = nil
        ended = nil
        activities.endAll()
        rides.endAll()
        operations.use(account: nil)
        page = .overview
        phase = .guest(confirmed ? nil : Messages.remoteLogoutUnconfirmed)
    }
}
