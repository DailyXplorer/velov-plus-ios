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
            section("Stations", padding: 32) { mapCard }
            section("Derniers trajets", padding: 32, link: .trips) {
                if let trips = data.trips { TripsList(trips: Array(trips.prefix(4))) } else { EmptyState("\(Messages.missing).") }
            }
        }
    }

    private var summary: some View {
        let subscription = data.subscription.subscription
        let missing = data.subscription == .unavailable
        return VStack(spacing: 10) {
            HStack(spacing: 10) {
                SummaryCard(tag: (.starFour, "Points"), detail: data.rewards.total.map { "\(formatNumber($0)) gagnés au total" } ?? Messages.missing, action: { model.page = .points }) {
                    Text(data.rewards.balance.map { formatNumber($0).glyphic } ?? "—").typo(.title(40))
                }
                SummaryCard(tag: (.personSimpleBike, "Trajets"), detail: data.trips == nil ? Messages.missing : minutes >= 60 ? "\(formatNumber(minutes / 60)) h \(minutes % 60) min" : "\(minutes) min", action: { model.page = .trips }) {
                    Text(data.trips.map { formatNumber($0.count).glyphic } ?? "—").typo(.title(40))
                }
            }
            SummaryCard(tag: (.ticket, "Abonnement"),
                        detail: missing ? Messages.missing : subscription?.validUntil.map { "Jusqu’au \(formatDate($0, .dayMonthYear))" } ?? "Voir les formules",
                        minHeight: 150, action: { model.page = .account }) {
                Text(missing ? "—" : shortPlan(subscription?.title)).typo(.title(20)).lineLimit(2)
            }
        }
    }

    private func section<Content: View>(_ title: String, padding: CGFloat, link: Page = .stations, @ViewBuilder content: @escaping () -> Content) -> some View {
        OverviewSection(title: title, padding: padding, link: { model.page = link }, content: content)
    }

    private var mapCard: some View {
        ZStack {
            StationMapView(stations: model.stations.value?.stations ?? [], camera: $camera, interactive: false)
            if case .failed(let message) = model.stations {
                VStack {
                    ErrorNotice(message: message, pending: model.stationsPending) { Task { await model.loadStations() } }
                        .padding(.horizontal, 14).padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.white))
                        .padding(16)
                    Spacer()
                }
            } else {
                Button { model.page = .stations } label: { Color.clear.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Explorer les stations")
            }
        }
        .frame(height: overviewMapHeight)
        .clipShape(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .padding(.bottom, Concentric.gap)
        .id("stations-map")
    }
}

private let overviewMapHeight: CGFloat = 310

struct OverviewSection<Content: View>: View {
    let title: String
    let padding: CGFloat
    var ghost = false
    let link: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: title) { TextButton(title: "Tout voir", action: link).ghost(ghost) }
            content()
        }
        .padding(.top, padding)
    }
}

struct OverviewSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    SummaryCard(tag: (.starFour, "Points"), detail: "1 380 gagnés au total", action: {}) { Text(verbatim: "0").typo(.title(40)) }.skeleton()
                    SummaryCard(tag: (.personSimpleBike, "Trajets"), detail: "12 h 40 min", action: {}) { Text(verbatim: "0").typo(.title(40)) }.skeleton()
                }
                SummaryCard(tag: (.ticket, "Abonnement"), detail: "Jusqu’au 1 mars 2027", minHeight: 150, action: {}) { Text(verbatim: "Plus 1 an").typo(.title(20)).lineLimit(2) }.skeleton()
            }
            OverviewSection(title: "Stations", padding: 32, ghost: true, link: {}) {
                Skeleton(height: overviewMapHeight).padding(.bottom, Concentric.gap)
            }
            OverviewSection(title: "Derniers trajets", padding: 32, ghost: true, link: {}) { GhostTrips(rows: 4) }
        }
        .accessibilityLabel("Chargement du compte")
    }
}

struct OngoingBanner: View {
    let trip: Trip
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Eyebrow(icon: .personSimpleBike, text: "Trajet en cours")
                Text(trip.startStation ?? "Trajet Vélo’v").typo(.body(13)).foregroundStyle(Palette.inkSoft).lineLimit(1)
            }
            ViaAction()
        }
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) { Hairline() }
        .padding(.bottom, 24)
    }
}
