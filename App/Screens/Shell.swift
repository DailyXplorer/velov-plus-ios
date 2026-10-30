import SwiftUI
import VelovCore

struct Shell: View {
    @Environment(AppModel.self) private var model
    @State private var visited: Set<Page> = []

    var body: some View {
        @Bindable var model = model
        FloatingHost(tabBar: true) {
            ZStack {
                ForEach(Page.allCases) { page in
                    if page == model.page || visited.contains(page) {
                        let active = page == model.page
                        TabStack(page: page)
                            .opacity(active ? 1 : 0)
                            .allowsHitTesting(active)
                            .accessibilityHidden(!active)
                    }
                }
            }
            .onChange(of: model.page, initial: true) { _, page in visited.insert(page) }
            .sheet(item: $model.sheet) { sheet in
                switch sheet {
                case .logout: LogoutSheet()
                case .unlock(let booking): if let place = Place(booking) { BikeActionSheet(place: place, bookingId: booking.id, action: .unlock) }
                case .ended(let trip): TripEndedSheet(trip: trip)
                case .via: ViaSheet()
                }
            }
            .background {
                Color.clear
                    .alert("Ignorer les modifications\u{a0}?", isPresented: Binding(get: { model.leaving != nil }, set: { if !$0 { model.leaving = nil } }),
                           presenting: model.leaving) { intent in
                        Button("Ignorer", role: .destructive) { model.discard(intent) }
                        Button("Continuer la saisie", role: .cancel) {}
                    }
                    .tint(Palette.ink)
            }
        }
    }
}

struct GuestShell: View {
    var body: some View {
        FloatingHost(tabBar: false) { StationsPage() }
    }
}

struct FloatingHost<Content: View>: View {
    let tabBar: Bool
    @ViewBuilder let content: () -> Content
    @State private var homeIndicator: CGFloat = 0
    @State private var radius = Concentric.fallback
    @State private var measuredBand: CGFloat = 0

    var body: some View {
        let band = tabBar ? measuredBand : 0
        content()
            .frame(maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if tabBar {
                    TabBar(radius: radius)
                        .padding(.horizontal, Concentric.inset).padding(.bottom, Concentric.inset - homeIndicator)
                        .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { measuredBand = $0 }
                }
            }
            .background(Palette.white)
            .background {
                Color.clear.ignoresSafeArea(.keyboard).onGeometryChange(for: CGFloat.self, of: { $0.safeAreaInsets.bottom }) { homeIndicator = $0 }
            }
            .background(alignment: .bottom) {
                Color.clear.frame(height: 2 * Concentric.fallback)
                    .onGeometryChange(for: CGFloat.self, of: { Concentric.radius($0) }) { radius = $0 }
                    .padding(.horizontal, Concentric.inset).padding(.bottom, Concentric.inset)
                    .ignoresSafeArea()
            }
            .environment(\.floatingRadius, radius)
            .environment(\.tabBarBand, band)
            .environment(\.tabBarClearance, homeIndicator + band)
            .environment(\.floatingFloor, homeIndicator + band + Concentric.gap)
    }
}

struct TabStack: View {
    let page: Page
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: Binding(get: { model.paths[page] ?? [] }, set: { model.paths[page] = $0 })) {
            root
                .navigationTitle(page.title)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: Route.self) { route in destination(route) }
        }
        .onLeaving(page) { if !model.operations.sending { model.paths[page] = [] } }
    }

    @ViewBuilder
    private var root: some View {
        if page == .stations { StationsPage() } else { PageScaffold(page: page) }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .stats: StatsPage()
        case .trip(let trip): TripPage(trip: trip.trip)
        case .bike(let bike): BikeDetail(route: bike)
        case .profile: ProfilePage()
        case .contact: ContactPage()
        case .journal: JournalPage()
        }
    }
}

struct PageTitle: View {
    let title: String
    var body: some View {
        Text(title).typo(.title(.page)).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
    }
}

struct BarAction {
    let icon: IconName
    let label: String
    var pending = false
    let action: () -> Void
}

struct PushedPage<Header: View, Content: View>: View {
    let title: String
    var close: (() -> Void)?
    var refresh: (() async -> Void)?
    var extra: BarAction?
    @ViewBuilder let header: () -> Header
    @ViewBuilder let content: () -> Content
    @Environment(AppModel.self) private var model
    @Environment(\.tabBarBand) private var tabBarBand

    var body: some View {
        let sending = model.operations.sending
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header().padding(.top, Space.label).padding(.bottom, Layout.headerBottom)
                content()
            }
            .padding(.horizontal, Layout.margin).padding(.bottom, Space.state)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, tabBarBand, for: .scrollContent)
        .fadesUnderTabBar()
        .background(Palette.white)
        .modifier(Refreshing(refresh: refresh))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
            if let extra {
                ToolbarItem(placement: .topBarTrailing) {
                    IconButton(icon: extra.icon, pending: extra.pending, label: extra.label, action: extra.action)
                }
            }
            if let close {
                ToolbarItem(placement: .topBarTrailing) {
                    IconButton(icon: .x, label: "Fermer", action: close).disabled(sending)
                }
            }
        }
        .heldWhile(sending)
    }
}

extension PushedPage where Header == PageTitle {
    init(_ title: String, close: (() -> Void)? = nil, refresh: (() async -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, close: close, refresh: refresh, header: { PageTitle(title: title) }, content: content)
    }
}

private struct UnderTabBarFade: ViewModifier {
    @Environment(\.tabBarBand) private var band
    @Environment(\.tabBarClearance) private var clearance

    func body(content: Content) -> some View {
        if band > 0 {
            content.mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: Space.actions)
                    Color.clear.frame(height: clearance)
                }
                .ignoresSafeArea(.container, edges: .bottom)
            }
        } else {
            content
        }
    }
}

extension View {
    func fadesUnderTabBar() -> some View { modifier(UnderTabBarFade()) }
}

private struct Refreshing: ViewModifier {
    let refresh: (() async -> Void)?
    func body(content: Content) -> some View {
        if let refresh { content.refreshable { await refresh() } } else { content }
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
    @State private var motion = PillMotion(at: 0)
    @State private var moving = false
    private let padding: CGFloat = 10

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Page.allCases) { page in
                let active = model.page == page
                Button {
                    guard !active else { return model.reselect(page) }
                    if model.select(page) { Haptics.selection() }
                } label: {
                    label(page)
                        .hidden()
                        .anchorPreference(key: TabBounds.self, value: .bounds) { [page: $0] }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(page.tab)
                .accessibilityAddTraits(active ? .isSelected : [])
            }
        }
        .backgroundPreferenceValue(TabBounds.self) { bounds in
            GeometryReader { proxy in
                let tabs = Page.allCases.compactMap { bounds[$0].map { proxy[$0] } }
                if tabs.count == Page.allCases.count {
                    TimelineView(.animation(minimumInterval: nil, paused: !moving)) { context in
                        let pill = Pill(edges: moving ? motion.edges(at: context.date) : motion.targets, tabs: tabs, radius: radius - padding)
                        ZStack(alignment: .topLeading) {
                            pill.fill(Palette.red)
                            ZStack {
                                Palette.ink
                                pill.fill(Palette.white)
                            }
                            .mask(alignment: .topLeading) {
                                ForEach(Array(zip(Page.allCases, tabs)), id: \.0) { page, tab in
                                    label(page).frame(width: tab.width, height: tab.height).offset(x: tab.minX, y: tab.minY)
                                }
                            }
                        }
                    }
                }
            }
            .accessibilityHidden(true)
        }
        .padding(padding)
        .floatingGlass(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .onAppear { motion = PillMotion(at: model.page.index) }
        .onChange(of: model.page) { _, page in
            motion.retarget(page.index, at: .now, reduceMotion: reduceMotion)
            moving = true
        }
        .task(id: motion.start) {
            try? await Task.sleep(for: .seconds(1.2))
            if !Task.isCancelled { moving = false }
        }
    }

    private func label(_ page: Page) -> some View {
        VStack(spacing: 5) {
            Icon(page.icon, .light, size: 22)
            Text(page.tab).typo(.body(.micro))
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .padding(4)
    }
}

private struct TabBounds: PreferenceKey {
    static let defaultValue: [Page: Anchor<CGRect>] = [:]
    static func reduce(value: inout [Page: Anchor<CGRect>], nextValue: () -> [Page: Anchor<CGRect>]) {
        value.merge(nextValue()) { $1 }
    }
}

private extension Page {
    var index: Int { Page.allCases.firstIndex(of: self) ?? 0 }
}

private struct Pill: Shape {
    let edges: (CGFloat, CGFloat)
    let tabs: [CGRect]
    let radius: CGFloat

    func path(in _: CGRect) -> Path {
        let left = x(edges.0), right = x(edges.1)
        let rest = tabs[min(max(Int(((edges.0 + edges.1) / 2).rounded(.down)), 0), tabs.count - 1)]
        let stretch = (right - left) / rest.width
        let height = rest.height * min(1, max(0.74, 1 - 0.2 * (stretch - 1)))
        let rect = CGRect(x: left, y: rest.midY - height / 2, width: max(right - left, 0), height: height)
        return Path(roundedRect: rect, cornerRadius: min(radius, height / 2), style: .continuous)
    }

    private func x(_ edge: CGFloat) -> CGFloat {
        let slot = min(max(Int(edge.rounded(.down)), 0), tabs.count - 1)
        return tabs[slot].minX + (edge - CGFloat(slot)) * tabs[slot].width
    }
}

private struct PillMotion {
    private var left: Track
    private var right: Track
    private(set) var start = Date.now

    init(at index: Int) {
        left = Track(rest: CGFloat(index))
        right = Track(rest: CGFloat(index + 1))
    }

    var targets: (CGFloat, CGFloat) { (left.to, right.to) }

    func edges(at date: Date) -> (CGFloat, CGFloat) {
        let time = date.timeIntervalSince(start)
        return (left.value(time), right.value(time))
    }

    mutating func retarget(_ index: Int, at date: Date, reduceMotion: Bool) {
        let time = date.timeIntervalSince(start)
        let forward = CGFloat(index) + 0.5 > (left.value(time) + right.value(time)) / 2
        let lead = reduceMotion ? Spring(response: 0.36, dampingRatio: 1) : Spring(response: 0.32, dampingRatio: 0.8)
        let trail = reduceMotion ? lead : Spring(response: 0.52, dampingRatio: 0.85)
        left = left.toward(CGFloat(index), after: time, with: forward ? trail : lead)
        right = right.toward(CGFloat(index + 1), after: time, with: forward ? lead : trail)
        start = date
    }
}

private struct Track {
    var from: CGFloat
    var to: CGFloat
    var velocity: CGFloat = 0
    var spring = Spring()

    init(rest: CGFloat) {
        from = rest
        to = rest
    }

    private init(from: CGFloat, to: CGFloat, velocity: CGFloat, spring: Spring) {
        self.from = from
        self.to = to
        self.velocity = velocity
        self.spring = spring
    }

    func value(_ time: TimeInterval) -> CGFloat {
        from + spring.value(target: to - from, initialVelocity: velocity, time: max(0, time))
    }

    func toward(_ target: CGFloat, after time: TimeInterval, with next: Spring) -> Track {
        let speed = spring.velocity(target: to - from, initialVelocity: velocity, time: max(0, time))
        return Track(from: value(time), to: target, velocity: speed, spring: next)
    }
}

struct Header: View {
    let title: String
    @Environment(AppModel.self) private var model
    private var fullName: String { model.dashboard.map { formatName("\($0.profile.firstName) \($0.profile.lastName)") } ?? "" }
    private var busy: Bool { model.refreshing || model.stationsPending }

    var body: some View {
        HStack(spacing: Space.label) {
            Text(title).typo(.title(.page)).foregroundStyle(Palette.ink).lineLimit(1).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            FloatingCircleButton(label: "Actualiser", value: model.dashboard.map { "Actualisé à \(formatDate($0.updatedAt, .time))" }) {
                Task { await model.manualRefresh() }
            } content: {
                Group {
                    if busy { Spinner(size: Layout.glyph) } else { Icon(.arrowClockwise, .light, size: Layout.glyph) }
                }
                .foregroundStyle(Palette.inkSoft)
            }
            .disabled(busy)
            if model.isGuest {
                Button { model.leaveGuest() } label: {
                    HStack(spacing: Space.label) {
                        Icon(.signIn, .light, size: Layout.glyph)
                        Text("Se connecter").typo(.caps(.button)).lineLimit(1)
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, Space.row)
                    .frame(height: Layout.control)
                    .floatingGlass(Capsule(), interactive: true, fallback: Palette.mist)
                    .contentShape(Capsule())
                }
                .buttonStyle(.press)
                .fixedSize()
            } else {
                FloatingCircleButton(label: fullName.isEmpty ? "Mon compte" : "Mon compte, \(fullName)") { model.page = .account } content: {
                    if let initial = model.dashboard.flatMap({ formatName($0.profile.firstName).first }) {
                        Text(String(initial)).typo(.title(.small))
                    } else {
                        Icon(.userCircle, .light, size: 22)
                    }
                }
            }
        }
        .padding(.horizontal, Layout.margin).padding(.top, Layout.headerTop).padding(.bottom, Layout.headerBottom)
        .opacity(toastShown ? 0 : 1)
        .accessibilityHidden(toastShown)
        .animation(Motion.standard, value: toastShown)
    }

    private var toastShown: Bool { model.toasts.current != nil }
}

struct PageScaffold: View {
    let page: Page
    @Environment(AppModel.self) private var model
    @Environment(\.tabBarBand) private var tabBarBand

    var body: some View {
        ScrollViewReader { proxy in
            scroll
                .onLeaving(page) { proxy.scrollTo("page-top", anchor: .top) }
                .onChange(of: model.tops[page]) { withAnimation(Motion.standard) { proxy.scrollTo("page-top", anchor: .top) } }
                .task {
                    let anchors: [SnapshotScreen: (String, UnitPoint)] = [.overviewMap: ("stations-map", .bottom), .accountEnd: ("page-end", .bottom),
                                                                          .renewalToggle: ("renewal", .center), .renewalDialog: ("renewal", .center)]
                    guard page == model.page, let snapshot = model.snapshot, let (id, anchor) = anchors[snapshot] else { return }
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    proxy.scrollTo(id, anchor: anchor)
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
                    case .failed(let failure):
                        StateView(failure, pending: model.refreshing) { Task { await model.loadDashboard() } }
                    default:
                        PageSkeleton(page: page)
                    }
                }
                .padding(.horizontal, Layout.margin)
                .padding(.bottom, Space.state)
                Color.clear.frame(height: 0).id("page-end")
            }
        }
        .scrollIndicators(.hidden)
        .contentMargins(.bottom, tabBarBand, for: .scrollContent)
        .fadesUnderTabBar()
        .refreshable { await model.manualRefresh() }
    }

    @ViewBuilder
    private func content(_ data: Dashboard) -> some View {
        switch page {
        case .overview: OverviewPage(data: data)
        case .trips: TripsPage(data: data)
        case .points: PointsPage(data: data)
        case .account: AccountPage(data: data, onLogout: { model.sheet = .logout })
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
                VStack(alignment: .leading, spacing: Space.pair) {
                    ForEach(warnings, id: \.self) { Text(verbatim: "• \($0)").typo(.body(.small)) }
                }
                .foregroundStyle(Palette.inkSoft)
                .padding(.leading, Space.label)
            }
            .foregroundStyle(Palette.inkSoft)
            .padding(.bottom, Space.actions)
        }
    }
}

struct BookingBanners: View {
    var bottom = Space.actions
    @Environment(AppModel.self) private var model

    var body: some View {
        ForEach(model.bookings) { booking in
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let left = booking.endsAt.map { max(0, Int($0.timeIntervalSince(context.date).rounded())) }
                if left != 0 {
                    RedBanner(icon: .clock, value: left.map(clock), label: left.map { "Vélo réservé, \(max(1, $0 / 60))\u{a0}min restantes" } ?? "Vélo réservé", valueWidth: 78) {
                        if Place(booking) != nil { unlock(booking) }
                    }
                    .padding(.bottom, bottom)
                }
            }
        }
    }

    private func unlock(_ booking: Booking) -> some View {
        OnRedPill(icon: .lockOpen, title: "Déverrouiller") { model.sheet = .unlock(booking) }
    }
}

struct LogoutSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var pending = false

    var body: some View {
        ConfirmScaffold(title: "Se déconnecter\u{a0}?", closeDisabled: pending, close: { dismiss() }) {
            EmptyView()
        } extra: {
            EmptyView()
        } actions: {
            PillButton("Annuler", variant: .ghost, fullWidth: true) { dismiss() }.disabled(pending)
            PillButton(variant: .destructive, pending: pending, fullWidth: true, action: {
                Haptics.confirm()
                pending = true
                Task {
                    await model.logout()
                    dismiss()
                }
            }) { Text("Se déconnecter") }
        }
    }
}
