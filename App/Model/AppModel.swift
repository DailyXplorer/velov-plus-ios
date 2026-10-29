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

    /// The bottom bar's shorter labels.
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

/// A screen the snapshot run opens straight away (`-VelovScreen tripSheet`).
enum SnapshotScreen: String {
    case overview, overviewMap, trips, tripSheet, rateCard, points, stations, stationSheet, bikeList, bikeSheet, account, accountEdit
    case bookingBanner, unlockConfirm, unlockSuccess, liveActivityLock, liveActivityIsland

    /// The screens drawn with a running booking.
    var withBooking: Bool { [.bookingBanner, .unlockConfirm, .unlockSuccess].contains(self) }
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
    /// The booking whose unlock sheet is open, from the banner of any tab.
    var unlocking: Booking?
    /// Trips rated from this phone: the dashboard says so only after its next read.
    var ratedHere: Set<String> = []
    /// Where the invite codes are kept on this phone, before anything else happens to them.
    let promoBacking: PromoBacking
    private let activities = BookingActivities()

    init(service: VelovService, snapshot: SnapshotScreen? = nil, promoBacking: PromoBacking) {
        self.service = service
        self.snapshot = snapshot
        self.promoBacking = promoBacking
        switch snapshot {
        case .trips?, .tripSheet?, .rateCard?: page = .trips
        case .points?: page = .points
        case .stations?, .stationSheet?, .bikeList?, .bikeSheet?: page = .stations
        case .account?, .accountEdit?: page = .account
        default: break
        }
    }

    /// The app's own folder for the invite codes: Application Support, backed up with the phone.
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

    /// One load at a time: a second pull or a retry joins nothing and sends nothing.
    func loadDashboard() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            phase = .ready(try await service.dashboard())
        } catch let error as VelovError where error.code == .expired {
            phase = .guest(error.revoked ? error.message : "Session expirée. Reconnectez-vous.")
        } catch {
            phase = .failed((error as? VelovError)?.message ?? "Compte indisponible.")
        }
    }

    func loadStations() async {
        guard !stationsPending else { return }
        stationsPending = true
        defer { stationsPending = false }
        do { stations = .ready(try await service.stations()) }
        catch { stations = .failed((error as? VelovError)?.message ?? "Stations indisponibles.") }
    }

    /// Best effort: without it the app only misses the booking banner. A running booking found here gets its Live Activity.
    func loadBookings() async {
        guard let value = try? await service.bookings() else { return }
        bookings = value
        if snapshot == nil { activities.sync(value) }
        if snapshot == .unlockConfirm || snapshot == .unlockSuccess { unlocking = value.first }
    }

    /// Back in the foreground: the bookings may have run out or been used meanwhile.
    func becameActive() {
        guard dashboard != nil else { return }
        Task { await loadBookings() }
    }

    // MARK: Effects of confirmed writes, applied here instead of reading the whole account again.

    func booked(_ booking: Booking?) {
        if let booking {
            bookings.removeAll { $0.id == booking.id }
            bookings.append(booking)
            if snapshot == nil { activities.start(booking) }
        }
        Task { await loadBookings() }
    }

    /// The release spends the booking: its banner and its Live Activity go.
    func unlocked(bookingId: String?) {
        if let bookingId {
            bookings.removeAll { $0.id == bookingId }
            activities.end(bookingId: bookingId)
        }
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

    /// One login attempt; a refusal is shown as is and never retried.
    func signIn(email: String, code: String) async throws {
        try await service.signIn(email: email, code: code)
        phase = .loading
        refreshAll()
    }

    /// Returns the notice to show when Vélo’v did not confirm the end of the session.
    func logout() async {
        let confirmed = await service.logout()
        bookings = []
        unlocking = nil
        activities.endAll()
        page = .overview
        phase = .guest(confirmed ? nil : Messages.remoteLogoutUnconfirmed)
    }
}
