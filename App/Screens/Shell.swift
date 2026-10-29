import SwiftUI
import VelovCore

/// The signed-in app: the page, its header, and the web's mobile bottom navigation.
struct Shell: View {
    @Environment(AppModel.self) private var model
    @State private var logoutOpen = false
    @State private var homeIndicator: CGFloat = 0

    var body: some View {
        @Bindable var model = model
        Group {
            switch model.page {
            case .stations: StationsPage(onLogout: { logoutOpen = true })
            default: PageScaffold(page: model.page, onLogout: { logoutOpen = true }).id(model.page) // a fresh scroll view per tab: every tab opens at the top
            }
        }
        .frame(maxHeight: .infinity)
        // The bar floats `inset` from the sides and the bottom, over the home indicator's band. The page scrolls behind it
        // and the end of every scroll view stops above it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TabBar().padding(.horizontal, Concentric.inset).padding(.bottom, Concentric.inset - homeIndicator)
        }
        .background(Palette.white)
        .background {
            Color.clear.ignoresSafeArea(.keyboard).onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.bottom }) { homeIndicator = $0 }
        }
        .sheet(isPresented: $logoutOpen) { LogoutSheet() }
        .sheet(item: $model.unlocking) { booking in
            if let place = Place(booking) { BikeActionSheet(place: place, bookingId: booking.id, action: .unlock) }
        }
    }
}

/// The web's mobile navigation as a floating white bar with the site's shadow ring, its corners concentric with the display's,
/// the active tab's red pill concentric with the bar.
struct TabBar: View {
    @Environment(AppModel.self) private var model
    @State private var radius = Concentric.display - Concentric.inset
    private let padding: CGFloat = 10

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Page.allCases) { page in
                let active = model.page == page
                Button { model.page = page } label: {
                    VStack(spacing: 5) {
                        Icon(page.icon, .light, size: 22)
                        Text(page.tab).typo(.body(11))
                    }
                    .foregroundStyle(active ? Palette.white : Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: radius - padding, style: .continuous).fill(active ? Palette.red : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(page.title)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(padding)
        .background {
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.white)
                .shadow(color: Palette.ink.opacity(0.1), radius: 18, y: 12)
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        }
        .onGeometryChange(for: CGFloat.self, of: { Concentric.radius($0) }) { radius = $0 }
    }
}

/// `.app-header` on phones: the page title, refresh and the initial.
struct Header: View {
    let title: String
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 3) {
            Text(title).typo(.title(28)).foregroundStyle(Palette.ink).lineLimit(1)
            Spacer(minLength: 8)
            Button { model.refreshAll() } label: {
                Group {
                    if model.refreshing { Spinner(size: 20) } else { Icon(.arrowClockwise, .light, size: 20) }
                }
                .foregroundStyle(Palette.inkSoft).frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .disabled(model.refreshing)
            .accessibilityLabel(model.dashboard.map { "Actualisé à \(formatDate($0.updatedAt, .time))" } ?? "Actualiser")
            Button { model.page = .account } label: {
                Group {
                    if let initial = model.dashboard?.profile.firstName.first {
                        Text(String(initial).uppercased()).typo(.title(18))
                    } else {
                        Icon(.userCircle, .light, size: 22)
                    }
                }
                .foregroundStyle(Palette.ink)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Palette.mist))
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .accessibilityLabel("Mon compte")
        }
        .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 28)
    }
}

/// A scrolling page: header, booking banners, warnings, then the page itself once the account is read.
struct PageScaffold: View {
    let page: Page
    let onLogout: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            scroll.task {
                if model.snapshot == .overviewMap || model.snapshot == .accountEnd {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    proxy.scrollTo(model.snapshot == .overviewMap ? "stations-map" : "page-end", anchor: .bottom)
                }
            }
        }
    }

    private var scroll: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Header(title: page.title)
                VStack(alignment: .leading, spacing: 0) {
                    BookingBanners()
                    switch model.phase {
                    case .ready(let data):
                        DataNotice(warnings: data.warnings)
                        content(data)
                    case .failed(let message):
                        VStack(spacing: 24) {
                            Text(message).typo(.body(14)).foregroundStyle(Palette.inkSoft).multilineTextAlignment(.center)
                            PillButton("Réessayer", variant: .secondary, pending: model.refreshing) { Task { await model.loadDashboard() } }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 100).padding(.horizontal, 20)
                    default:
                        DashboardSkeleton()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
                Color.clear.frame(height: 0).id("page-end")
            }
        }
        .scrollIndicators(.hidden)
        .refreshable {
            async let dashboard: Void = model.loadDashboard()
            async let stations: Void = model.loadStations()
            async let bookings: Void = model.loadBookings()
            _ = await (dashboard, stations, bookings)
        }
    }

    @ViewBuilder
    private func content(_ data: Dashboard) -> some View {
        switch page {
        case .overview: OverviewPage(data: data)
        case .trips: TripsPage(data: data)
        case .points: PointsPage(data: data)
        case .account: AccountPage(data: data, onLogout: onLogout)
        case .stations: EmptyView()
        }
    }
}

struct DashboardSkeleton: View {
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) { Skeleton(height: 168); Skeleton(height: 168) }
            Skeleton(height: 150)
            Skeleton(height: 310).padding(.top, 40)
        }
        .accessibilityLabel("Chargement du compte")
    }
}

/// `details.data-notice`: the reads that failed, folded.
struct DataNotice: View {
    let warnings: [String]
    var body: some View {
        if !warnings.isEmpty {
            Disclosure(title: "Informations indisponibles") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(warnings, id: \.self) { Text(verbatim: "• \($0)").typo(.body(13)) }
                }
                .foregroundStyle(Palette.dataNotice)
                .padding(.leading, 8)
            }
            .foregroundStyle(Palette.dataNotice)
            .padding(.bottom, 24)
        }
    }
}

/// `.booking-banner`: a solid red card, « Réservé », the countdown and « Déverrouiller », on every tab; gone once the booking has run out.
struct BookingBanners: View {
    var bottom: CGFloat = 24
    @Environment(AppModel.self) private var model

    var body: some View {
        ForEach(model.bookings) { booking in
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = booking.endsAt.map { max(0, Int($0.timeIntervalSince(context.date).rounded())) }
                if left != 0 {
                    // The web's phone sizes: a tighter tag, 18 pt digits, the button without its icon.
                    HStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Icon(.clock, .bold, size: 13).foregroundStyle(Palette.white).frame(width: 26, height: 26).background(Circle().fill(Palette.red))
                            Text("Réservé").typo(.label(12)).foregroundStyle(Palette.ink)
                        }
                        .padding(.leading, 5).padding(.trailing, 12).padding(.vertical, 5)
                        .background(Capsule().fill(Palette.white))
                        .fixedSize()
                        if let left { Text(clock(left)).typo(.clock(18)).foregroundStyle(Palette.white).fixedSize().accessibilityLabel("Reste \(clock(left))") }
                        Spacer(minLength: 0)
                        if Place(booking) != nil {
                            PillButton(variant: .onRed, height: 40, action: { model.unlocking = booking }) { Text("Déverrouiller").typo(.label(12)) }
                                .fixedSize()
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous).fill(Palette.red))
                    .padding(.bottom, bottom)
                }
            }
        }
    }
}

/// « Se déconnecter ? »: the logout ends the session at Vélo’v, then forgets the tokens here; the device id stays.
struct LogoutSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Se déconnecter ?").typo(.title(26)).foregroundStyle(Palette.ink)
                Spacer()
                IconButton(icon: .x, label: "Fermer") { dismiss() }.padding(.trailing, -10)
            }
            HStack(spacing: 10) {
                Spacer()
                PillButton("Annuler", variant: .secondary) { dismiss() }.disabled(pending)
                PillButton("Se déconnecter", pending: pending) {
                    pending = true
                    Task {
                        await model.logout()
                        dismiss()
                    }
                }
            }
            .padding(.top, 30)
        }
        .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 24)
        .presentationDetents([.height(190)])
        .presentationBackground(Palette.white)
        .interactiveDismissDisabled(pending)
    }
}
