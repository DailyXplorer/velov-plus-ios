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

    var icon: Ph {
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
    case overview, trips, tripSheet, points, stations, stationSheet, bikeList, bikeSheet, account
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

    init(service: VelovService, snapshot: SnapshotScreen? = nil) {
        self.service = service
        self.snapshot = snapshot
        switch snapshot {
        case .trips?, .tripSheet?: page = .trips
        case .points?: page = .points
        case .stations?, .stationSheet?, .bikeList?, .bikeSheet?: page = .stations
        case .account?: page = .account
        default: break
        }
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

    /// Best effort: without it the app only misses the booking banner.
    func loadBookings() async {
        if let value = try? await service.bookings() { bookings = value }
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
        page = .overview
        phase = .guest(confirmed ? nil : Messages.remoteLogoutUnconfirmed)
    }
}
