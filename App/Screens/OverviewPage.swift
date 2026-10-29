import MapKit
import SwiftUI
import VelovCore

/// dashboard.tsx `Overview` on a phone: summary cards, the stations map card, the last trips.
struct OverviewPage: View {
    let data: Dashboard
    @Environment(AppModel.self) private var model
    @State private var camera = StationMapView.lyon

    private var minutes: Int { Int(data.trips?.reduce(0) { $0 + ($1.duration ?? 0) } ?? 0) }

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
                    Text(data.rewards.balance.map { formatNumber($0) } ?? "—").typo(.title(40))
                }
                SummaryCard(tag: (.personSimpleBike, "Trajets"), detail: data.trips == nil ? Messages.missing : minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min", action: { model.page = .trips }) {
                    Text(data.trips.map { "\($0.count)" } ?? "—").typo(.title(40))
                }
            }
            SummaryCard(tag: (.ticket, "Abonnement"),
                        detail: missing ? Messages.missing : subscription?.validUntil.map { "Jusqu’au \(formatDate($0, .dayMonthYear))" } ?? "Voir les formules",
                        minHeight: 150, action: { model.page = .account }) {
                Text(missing ? "—" : shortPlan(subscription?.title)).typo(.title(20)).lineLimit(2)
            }
        }
    }

    private func section<Content: View>(_ title: String, padding: CGFloat, link: Page = .stations, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(title: title) { TextButton(title: "Tout voir") { model.page = link } }
            content()
        }
        .padding(.top, padding)
    }

    /// Phones: no preselected station; the map invites to the Stations tab.
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
                Button { model.page = .stations } label: {
                    Text("Toucher pour explorer").typo(.label(12)).foregroundStyle(Palette.redDeep)
                        .padding(.horizontal, 18).frame(minHeight: 40)
                        .background(Capsule().fill(Palette.white))
                        .shadow(color: Palette.ink.opacity(0.1), radius: 18, y: 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 310)
        .clipShape(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
    }
}

/// `.ongoing-banner`: « Trajet en cours » and the start station; « 15 minutes de plus » shown, not sent.
struct OngoingBanner: View {
    let trip: Trip
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Eyebrow(icon: .personSimpleBike, text: "Trajet en cours")
                Text(trip.startStation ?? "Trajet Vélo’v").typo(.body(13)).foregroundStyle(Palette.inkSoft).lineLimit(1)
            }
            HStack(spacing: 10) {
                PillButton(variant: .secondary, action: {}) { Icon(.timer, .light, size: 17); Text("15 minutes de plus") }.disabled(true)
                SoonNote()
            }
        }
        .padding(.bottom, 16)
        .overlay(alignment: .bottom) { Hairline() }
        .padding(.bottom, 24)
    }
}
