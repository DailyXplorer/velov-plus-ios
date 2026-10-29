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
    case failed(String)

    var value: T? {
        if case .ready(let value) = self { return value }
        return nil
    }
}

enum SnapshotScreen: String {
    case overview, overviewMap, trips, tripSheet, rateCard, points, stations, stationSheet, bikeList, bikeSheet, account, accountEnd, accountEdit
    case bookingBanner, unlockConfirm, bookConfirm, unlockUncertain, liveActivityLock, liveActivityIsland
    case tripEnded, tripEndedStars
    case stats, statsCharts, statsHeatmap, statsRecords, statsEnd

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
        case failed(String)
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
    var foreground = true
    private var docked: Set<String> = []
    private var greeted = false
    @ObservationIgnored private lazy var dockWatch: DockWatch = DockWatch(
        check: { [unowned self] in
            do { return try await service.tripCheck() } catch let error as VelovError where error.code == .expired {
                phase = .guest("Session expirée. Reconnectez-vous.")
                dockWatch.stop()
                throw error
            }
        },
        docked: { [unowned self] tripId, latest in tripDocked(tripId, latest: latest) },
        visible: { [unowned self] in foreground })
    let promoBacking: PromoBacking
    let operations: Operations
    @ObservationIgnored private let refreshGate = RefreshGate()
    private let activities = BookingActivities()

    init(service: VelovService, snapshot: SnapshotScreen? = nil, promoBacking: PromoBacking, operationBacking: OperationBacking) {
        self.service = service
        self.snapshot = snapshot
        self.promoBacking = promoBacking
        operations = Operations(backing: operationBacking)
        switch snapshot {
        case .trips?, .tripSheet?, .rateCard?: page = .trips
        case .stats?, .statsCharts?, .statsHeatmap?, .statsRecords?, .statsEnd?: page = .trips
        case .points?: page = .points
        case .stations?, .stationSheet?, .bikeList?, .bikeSheet?, .bookConfirm?: page = .stations
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
        defer { refreshing = false }
        do {
            let data = try await service.dashboard()
            operations.use(account: data.profile.email)
            phase = .ready(data)
            watchTrips(data)
        } catch let error as VelovError where error.code == .expired {
            dockWatch.stop()
            phase = .guest(error.revoked ? error.message : "Votre session a expiré. Reconnectez-vous.")
        } catch {
            phase = .failed((error as? VelovError)?.message ?? "Votre compte est momentanément indisponible.")
        }
    }

    func loadStations() async {
        guard !stationsPending else { return }
        stationsPending = true
        defer { stationsPending = false }
        do { stations = .ready(try await service.stations()) }
        catch { stations = .failed((error as? VelovError)?.message ?? "Les stations sont momentanément indisponibles.") }
    }

    func loadBookings() async {
        guard let value = try? await service.bookings() else { return }
        bookings = value
        if snapshot == nil { activities.sync(value) }
        if snapshot == .unlockConfirm || snapshot == .unlockUncertain { unlocking = value.first }
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
        if let trip = data.ongoing?.first(where: { !docked.contains($0.id) }) { dockWatch.follow(trip.id) }
        guard !greeted else { return }
        greeted = true
        if data.ongoing?.isEmpty != false, let trips = data.trips, let recent = tripToGreet(trips, store: UserDefaults.standard) { ended = recent }
    }

    private func tripDocked(_ tripId: String, latest: Trip?) {
        docked.insert(tripId)
        Task {
            await loadDashboard()
            if let trip = dashboard?.trips?.first(where: { $0.id == tripId }) ?? (latest?.id == tripId ? latest : nil) { ended = trip }
            await loadBookings()
        }
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
        Task { await loadBookings() }
    }

    func unlocked(bookingId: String?, tripId: String?) {
        if let bookingId {
            bookings.removeAll { $0.id == bookingId }
            activities.end(bookingId: bookingId)
        }
        if snapshot == nil { dockWatch.follow(tripId) }
        Task {
            await loadBookings()
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
        try await service.signIn(email: email, code: code)
        phase = .loading
        refreshAll()
    }

    func logout() async {
        let confirmed = await service.logout()
        dockWatch.stop()
        bookings = []
        unlocking = nil
        ended = nil
        activities.endAll()
        operations.use(account: nil)
        page = .overview
        phase = .guest(confirmed ? nil : Messages.remoteLogoutUnconfirmed)
    }
}
