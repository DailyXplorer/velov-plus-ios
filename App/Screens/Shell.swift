import SwiftUI
import VelovCore

struct Shell: View {
    @Environment(AppModel.self) private var model
    @State private var homeIndicator: CGFloat = 0
    @State private var radius = Concentric.fallback
    @State private var tabBarBand: CGFloat = 0
    @State private var visited: Set<Page> = []

    var body: some View {
        @Bindable var model = model
        ZStack {
            ForEach(Page.allCases) { page in
                if page == model.page || visited.contains(page) {
                    let active = page == model.page
                    screen(page)
                        .opacity(active ? 1 : 0)
                        .allowsHitTesting(active)
                        .accessibilityHidden(!active)
                }
            }
        }
        .onChange(of: model.page, initial: true) { _, page in visited.insert(page) }
        .frame(maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            TabBar(radius: radius)
                .onGeometryChange(for: CGFloat.self, of: { Concentric.radius($0) }) { radius = $0 }
                .padding(.horizontal, Concentric.inset).padding(.bottom, Concentric.inset - homeIndicator)
                .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { tabBarBand = $0 }
        }
        .background(Palette.white)
        .background {
            Color.clear.ignoresSafeArea(.keyboard).onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.bottom }) { homeIndicator = $0 }
        }
        .sheet(isPresented: $model.logoutOpen) { LogoutSheet() }
        .sheet(item: $model.unlocking) { booking in
            if let place = Place(booking) { BikeActionSheet(place: place, bookingId: booking.id, action: .unlock) }
        }
        .sheet(item: $model.ended) { TripEndedSheet(trip: $0) }
        .environment(\.floatingRadius, radius)
        .environment(\.tabBarBand, tabBarBand)
    }

    @ViewBuilder
    private func screen(_ page: Page) -> some View {
        switch page {
        case .stations: StationsPage()
        case .trips: TripsStack()
        default: PageScaffold(page: page)
        }
    }
}

struct LeavingPage: ViewModifier {
    let page: Page
    let action: () -> Void
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.onChange(of: model.page) { left, _ in
            if left == page { action() }
        }
    }
}

extension View {
    func onLeaving(_ page: Page, perform action: @escaping () -> Void) -> some View {
        modifier(LeavingPage(page: page, action: action))
    }
}

struct TabBar: View {
    let radius: CGFloat
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection
    @State private var picks = 0
    private let padding: CGFloat = 10

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Page.allCases) { page in
                let active = model.page == page
                Button {
                    guard !active else { return }
                    model.page = page
                    picks += 1
                } label: {
                    VStack(spacing: 5) {
                        Icon(page.icon, .light, size: 22)
                        Text(page.tab).typo(.body(11))
                    }
                    .foregroundStyle(active ? Palette.white : Palette.ink)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .padding(4)
                    .background {
                        if active {
                            RoundedRectangle(cornerRadius: radius - padding, style: .continuous).fill(Palette.red)
                                .matchedGeometryEffect(id: reduceMotion ? page.id : "active", in: selection)
                                .transition(reduceMotion ? .opacity : .identity)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(page.title)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .padding(padding)
        .floatingGlass(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.22), value: model.page)
        .sensoryFeedback(.selection, trigger: picks)
    }
}

struct Header: View {
    let title: String
    @Environment(AppModel.self) private var model
    private var fullName: String { model.dashboard.map { formatName("\($0.profile.firstName) \($0.profile.lastName)") } ?? "" }

    var body: some View {
        HStack(spacing: 3) {
            Text(title).typo(.title(28)).foregroundStyle(Palette.ink).lineLimit(1)
            Spacer(minLength: 8)
            Button { Task { await model.manualRefresh() } } label: {
                Group {
                    if model.refreshing { Spinner(size: 20) } else { Icon(.arrowClockwise, .light, size: 20) }
                }
                .foregroundStyle(Palette.inkSoft).frame(width: 40, height: 40)
                .floatingGlass(Circle(), interactive: true, fallback: .clear)
            }
            .buttonStyle(.plain)
            .disabled(model.refreshing)
            .accessibilityLabel(model.dashboard.map { "Actualisé à \(formatDate($0.updatedAt, .time))" } ?? "Actualiser")
            Button { model.page = .account } label: {
                Group {
                    if let initial = model.dashboard.flatMap({ formatName($0.profile.firstName).first }) {
                        Text(String(initial)).typo(.title(18))
                    } else {
                        Icon(.userCircle, .light, size: 22)
                    }
                }
                .foregroundStyle(Palette.ink)
                .frame(width: 40, height: 40)
                .floatingGlass(Circle(), interactive: true, fallback: Palette.mist)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
            .accessibilityLabel(fullName.isEmpty ? "Mon compte" : "Mon compte, \(fullName)")
        }
        .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 28)
    }
}

struct PageScaffold: View {
    let page: Page
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            scroll
                .onLeaving(page) { proxy.scrollTo("page-top", anchor: .top) }
                .task {
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
                Header(title: page.title).id("page-top")
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
                        PageSkeleton(page: page)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
                Color.clear.frame(height: 0).id("page-end")
            }
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.manualRefresh() }
    }

    @ViewBuilder
    private func content(_ data: Dashboard) -> some View {
        switch page {
        case .overview: OverviewPage(data: data)
        case .trips: TripsPage(data: data)
        case .points: PointsPage(data: data)
        case .account: AccountPage(data: data, onLogout: { model.logoutOpen = true })
        case .stations: EmptyView()
        }
    }
}

struct PageSkeleton: View {
    let page: Page
    var body: some View {
        switch page {
        case .overview: OverviewSkeleton()
        case .trips: TripsSkeleton()
        case .points: PointsSkeleton()
        case .account: AccountSkeleton()
        case .stations: EmptyView()
        }
    }
}

struct DataNotice: View {
    let warnings: [String]
    var body: some View {
        if !warnings.isEmpty {
            Disclosure(title: "Certaines informations sont indisponibles", icon: .warningCircle) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(warnings, id: \.self) { Text(verbatim: "• \($0)").typo(.body(13)) }
                }
                .foregroundStyle(Palette.inkSoft)
                .padding(.leading, 8)
            }
            .foregroundStyle(Palette.inkSoft)
            .padding(.bottom, 24)
        }
    }
}

struct BookingBanners: View {
    var bottom: CGFloat = 24
    @Environment(AppModel.self) private var model

    var body: some View {
        ForEach(model.bookings) { booking in
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = booking.endsAt.map { max(0, Int($0.timeIntervalSince(context.date).rounded())) }
                if left != 0 {
                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Icon(.clock, .light, size: 17)
                                .frame(width: 34, height: 34)
                                .overlay(Circle().strokeBorder(Palette.white, lineWidth: 1.5))
                            if let left { Text(clock(left)).typo(.countdown(26)).fixedSize().frame(width: 78, alignment: .leading) }
                        }
                        .foregroundStyle(Palette.white)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(left.map { "Vélo réservé, \($0 / 60) min \(String(format: "%02d", $0 % 60)) restantes" } ?? "Vélo réservé")
                        Spacer(minLength: 0)
                        if Place(booking) != nil { unlock(booking) }
                    }
                    .padding(.leading, 16).padding(.trailing, 6).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous).fill(Palette.red))
                    .padding(.bottom, bottom)
                }
            }
        }
    }

    private func unlock(_ booking: Booking) -> some View {
        Button { model.unlocking = booking } label: {
            HStack(spacing: 10) {
                Icon(.lockOpen, .light, size: 15).foregroundStyle(Palette.white)
                    .frame(width: 32, height: 32).background(Circle().fill(Palette.red))
                Text("Déverrouiller").tracking(0.52).typo(.caps(13)).foregroundStyle(Palette.ink)
            }
            .padding(.leading, 5).padding(.trailing, 18)
            .frame(minHeight: 42)
            .background(Capsule().fill(Palette.white))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }
}

struct LogoutSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pending = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Se déconnecter ?").typo(.title(26)).foregroundStyle(Palette.ink)
                Spacer()
                IconButton(icon: .x, label: "Fermer") { dismiss() }.padding(.trailing, -10)
            }
            PairedActions {
                PillButton("Annuler", variant: .secondary, fullWidth: true) { dismiss() }.disabled(pending)
                PillButton("Se déconnecter", pending: pending, fullWidth: true) {
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
        .sheetCorners()
        .interactiveDismissDisabled(pending)
    }
}
