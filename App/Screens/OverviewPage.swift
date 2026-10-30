import MapKit
import SwiftUI
import VelovCore

struct OverviewPage: View {
    let data: Dashboard
    @Environment(AppModel.self) private var model
    @State private var camera = StationMapView.lyon

    private var minutes: Int { Int((data.trips?.reduce(0) { $0 + ($1.duration ?? 0) } ?? 0).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let ongoing = data.ongoing?.first { OngoingBanner(trip: ongoing) }
            summary
            section("Stations", padding: Space.section) { mapCard }
            section("Derniers trajets", padding: Space.section, link: .trips) {
                if let trips = data.trips { TripsList(trips: Array(trips.prefix(4))) } else { StateView("\(Messages.missing).", pending: model.refreshing) { Task { await model.manualRefresh() } } }
            }
        }
    }

    private var summary: some View {
        let subscription = data.subscription.subscription
        let missing = data.subscription == .unavailable
        return VStack(spacing: Space.cards) {
            HStack(spacing: Space.cards) {
                SummaryCard(tag: (.starFour, "Points"), detail: data.rewards.total.map { "\(formatNumber($0)) gagnés au total" } ?? Messages.missing, action: { model.page = .points }) {
                    Text(data.rewards.balance.map { formatNumber($0).glyphic } ?? "—").typo(.title(.figure))
                }
                SummaryCard(tag: (.personSimpleBike, "Trajets"), detail: data.trips == nil ? Messages.missing : minutes >= 60 ? "\(formatNumber(minutes / 60)) h \(minutes % 60) min" : "\(minutes) min", action: { model.page = .trips }) {
                    Text(data.trips.map { formatNumber($0.count).glyphic } ?? "—").typo(.title(.figure))
                }
            }
            SummaryCard(tag: (.ticket, "Abonnement"),
                        detail: missing ? Messages.missing : subscription?.validUntil.map { "Jusqu’au \(formatDate($0, .dayMonthYear))" } ?? "Voir les formules",
                        minHeight: 150, action: { model.page = .account }) {
                Text(missing ? "—" : shortPlan(subscription?.title)).typo(.title(.card)).lineLimit(2)
            }
        }
    }

    private func section<Content: View>(_ title: String, padding: CGFloat, link: Page = .stations, @ViewBuilder content: @escaping () -> Content) -> some View {
        OverviewSection(title: title, padding: padding, link: { model.page = link }, content: content)
    }

    private var mapCard: some View {
        ZStack {
            StationMapView(stations: model.stations.value?.stations ?? [], camera: $camera, interactive: false)
            if case .failed(let failure) = model.stations {
                VStack {
                    ErrorNotice(failure: failure, pending: model.stationsPending) { Task { await model.loadStations() } }
                        .card(.ringed, compact: true)
                        .padding(Space.cardCompact)
                    Spacer()
                }
            } else {
                Button { model.page = .stations } label: {
                    Color.clear.contentShape(MapTapArea())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Explorer les stations")
            }
        }
        .frame(height: overviewMapHeight)
        .clipShape(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous).strokeBorder(Palette.inkLine, lineWidth: 1))
        .padding(.bottom, Concentric.gap)
        .id("stations-map")
    }
}

private let overviewMapHeight: CGFloat = 310

private struct MapTapArea: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRect(CGRect(x: rect.minX, y: rect.maxY - 40, width: rect.width / 2, height: 40))
        return path.normalized(eoFill: true)
    }
}

struct OverviewSection<Content: View>: View {
    let title: String
    let padding: CGFloat
    var ghost = false
    let link: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: title) { TextLink(title: "Tout voir", action: link).ghost(ghost) }
            content()
        }
        .padding(.top, padding)
    }
}

struct OverviewSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: Space.cards) {
                HStack(spacing: Space.cards) {
                    SummaryCard(tag: (.starFour, "Points"), detail: "1 380 gagnés au total", action: {}) { Text(verbatim: "0").typo(.title(.figure)) }.skeleton()
                    SummaryCard(tag: (.personSimpleBike, "Trajets"), detail: "12 h 40 min", action: {}) { Text(verbatim: "0").typo(.title(.figure)) }.skeleton()
                }
                SummaryCard(tag: (.ticket, "Abonnement"), detail: "Jusqu’au 1 mars 2027", minHeight: 150, action: {}) { Text(verbatim: "Plus 1 an").typo(.title(.card)).lineLimit(2) }.skeleton()
            }
            OverviewSection(title: "Stations", padding: Space.section, ghost: true, link: {}) {
                Skeleton(height: overviewMapHeight).padding(.bottom, Concentric.gap)
            }
            OverviewSection(title: "Derniers trajets", padding: Space.section, ghost: true, link: {}) { GhostTrips(rows: 4) }
        }
        .accessibilityLabel("Chargement du compte")
    }
}

private func elapsedClock(_ seconds: Int) -> String {
    seconds < 3600 ? clock(seconds) : String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
}

struct OngoingBanner: View {
    let trip: Trip
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = trip.startedAt.map { max(0, Int(context.date.timeIntervalSince($0).rounded())) }
            HStack(spacing: Space.cards) {
                Group {
                    if let elapsed { Text(elapsedClock(elapsed)).typo(.countdown).fixedSize() }
                }
                .foregroundStyle(Palette.white)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(elapsed.map { "Trajet en cours depuis \(max(1, $0 / 60)) min" } ?? "Trajet en cours")
                Spacer(minLength: 0)
                OnRedPill(icon: .timer, title: "15 minutes de plus") { model.sheet = .via }
            }
            .padding(.leading, Space.row).padding(.trailing, 6).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(Palette.red))
            .padding(.bottom, Layout.margin)
        }
    }
}
