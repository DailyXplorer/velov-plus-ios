import Charts
import SwiftUI
import VelovCore

// stats.tsx: the Statistiques page, pushed from the Trajets tab. Six red headline cards, then white panels on the ink-line ring;
// the charts draw in red on mist only, a tap shows a datum's tip.

enum TripsRoute: Hashable { case stats }

/// The Trajets tab in its own navigation stack, so « Statistiques » and a bike sheet push over it with the tab bar kept.
struct TripsStack: View {
    let onLogout: () -> Void
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            PageScaffold(page: .trips, onLogout: onLogout)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: TripsRoute.self) { _ in StatsPage() }
                .navigationDestination(for: BikeRoute.self) { route in BikeDetail(route: route) }
        }
        .task { if let snapshot = model.snapshot, snapshot.showsStats, path.isEmpty { path.append(TripsRoute.stats) } }
    }
}

extension SnapshotScreen {
    var showsStats: Bool { [.stats, .statsCharts, .statsHeatmap, .statsRecords, .statsEnd].contains(self) }
}

/// The button at the top of the Trajets tab.
struct StatsLink: View {
    var body: some View {
        NavigationLink(value: TripsRoute.stats) {
            HStack(spacing: 10) {
                Icon(.chart, .light, size: 18)
                Text("Statistiques")
                Spacer(minLength: 0)
                Icon(.caretRight, .bold, size: 14)
            }
            .typo(.label(14))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 18)
            .frame(minHeight: 42)
            .overlay(Capsule().strokeBorder(Palette.secondaryRing, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: French formatting, as the web page writes it

private let french = Locale(identifier: "fr_FR")
private let paris = TimeZone(identifier: "Europe/Paris")!

private func number(_ value: Double) -> String { formatNumber(value.rounded(), maximumFractionDigits: 0) }
private func number(_ value: Int) -> String { number(Double(value)) }
private func plural(_ count: Int, _ word: String) -> String { "\(number(count)) \(word)\(count > 1 ? "s" : "")" }

private func hours(_ minutes: Int) -> String {
    guard minutes >= 60 else { return "\(minutes) min" }
    let rest = minutes % 60
    return "\(number(minutes / 60)) h\(rest > 0 ? " \(rest) min" : "")"
}

private func kilometres(_ metres: Double) -> String {
    formatNumber(metres / 1000, maximumFractionDigits: metres < 100_000 ? 1 : 0)
}

/// A day key ("2026-10-29") or a month key ("2026-10") read at noon UTC, formatted in Lyon.
private func keyDate(_ key: String) -> Date {
    let parts = key.split(separator: "-").compactMap { Int($0) }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts.count > 2 ? parts[2] : 15, hour: 12)) ?? Date()
}

private func format(_ date: Date, _ template: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = french
    formatter.timeZone = paris
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: date)
}

/// "29/10" under a day; a month's initial only (J F M A…), like Apple Santé: the full month is in the tip.
private func axisLabel(_ unit: PeriodStats.Unit, _ key: String) -> String {
    unit == .day ? format(keyDate(key), "dM") : format(keyDate(key), "MMMMM").uppercased(with: french)
}

/// "jeudi 29 octobre" or "octobre 2026".
private func bucketLabel(_ unit: PeriodStats.Unit, _ key: String) -> String {
    unit == .day ? format(keyDate(key), "EEEEdMMMM") : format(keyDate(key), "MMMMy")
}

private let weekdays = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]

/// 0, then a round half and top: 47 -> 25, 50.
private func niceMax(_ value: Double) -> Double {
    guard value > 0 else { return 1 }
    let step = pow(10, floor(log10(value)))
    return [1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10].map { $0 * step }.first { $0 >= value } ?? value
}

/// `.chart-axis`: DM Sans 11 in ink-soft.
private func axisText(_ text: String) -> some View {
    Text(text).typo(.body(11)).foregroundStyle(Palette.inkSoft).fixedSize()
}

/// `--stat-gap` at the phone size: one gap between the cards, the panels and everything else.
private let gap: CGFloat = 10

// MARK: The page

/// Read once per account: a period change or a return to the page reads nothing (the core keeps it 10 minutes too).
@MainActor private var cachedStats: (account: String, stats: Stats)?

struct StatsPage: View {
    private static let unavailable = "Vos statistiques sont momentanément indisponibles."

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.tabBarBand) private var tabBarBand
    @State private var state: Resource<Stats> = .loading
    @State private var position = ScrollPosition()

    private var account: String { model.dashboard?.profile.email ?? "" }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        IconButton(icon: .arrowLeft, color: Palette.ink, label: "Retour aux trajets") { dismiss() }.padding(.leading, -10)
                        Text("Statistiques").typo(.title(28)).foregroundStyle(Palette.ink).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 28)
                    VStack(alignment: .leading, spacing: 0) {
                        BookingBanners()
                        switch state {
                        case .loading: skeleton
                        case .failed(let message):
                            VStack(spacing: 24) {
                                Text(message).typo(.body(14)).foregroundStyle(Palette.inkSoft).multilineTextAlignment(.center)
                                PillButton("Réessayer", variant: .secondary) { Task { await load() } }
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 100).padding(.horizontal, 20)
                        case .ready(let stats): StatsView(stats: stats)
                        }
                    }
                    .padding(.horizontal, 22).padding(.bottom, 40)
                }
            }
            .scrollPosition($position)
            .contentMargins(.bottom, tabBarBand, for: .scrollContent)
            .scrollIndicators(.hidden)
            .background(Palette.white)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                if let cachedStats, cachedStats.account == account { state = .ready(cachedStats.stats) } else { await load() }
                // The snapshot run reviews the whole page in four screens; the last one at the true end, above the tab bar.
                let anchors: [SnapshotScreen: String] = [.statsCharts: "panel-charts", .statsHeatmap: "panel-heatmap", .statsRecords: "panel-records"]
                guard let snapshot = model.snapshot, snapshot != .stats, snapshot.showsStats else { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if let anchor = anchors[snapshot] { proxy.scrollTo(anchor, anchor: .top) } else { position.scrollTo(edge: .bottom) }
            }
        }
    }

    private var skeleton: some View {
        VStack(spacing: gap) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: gap), GridItem(.flexible(), spacing: gap)], spacing: gap) {
                ForEach(0..<6, id: \.self) { _ in Skeleton(height: 132) }
            }
            Skeleton(height: 310)
        }
        .accessibilityLabel("Chargement des statistiques")
    }

    private func load() async {
        state = .loading
        do {
            let stats = try await model.service.stats()
            cachedStats = (account, stats)
            state = .ready(stats)
        } catch {
            state = .failed((error as? VelovError)?.message ?? Self.unavailable)
        }
    }
}

struct StatsView: View {
    let stats: Stats
    @State private var period = StatsPeriod.months12

    private static let periods: [SelectOption<StatsPeriod>] = [
        .init(value: .days30, label: "30 derniers jours"),
        .init(value: .months12, label: "12 derniers mois"),
        .init(value: .all, label: "Depuis le début")
    ]

    var body: some View {
        let data = stats[period]
        VStack(alignment: .leading, spacing: gap) {
            SelectField(label: "Période", hideLabel: true, value: $period, options: Self.periods)
                .zIndex(2)
                .padding(.bottom, 6)
            Headline(data: data, balance: stats.balance)
            if data.trips == 0 {
                EmptyState(stats.all.trips > 0 ? "Aucun trajet sur cette période." : "Vos statistiques apparaîtront après votre premier trajet.")
            } else {
                Panel(title: data.unit == .day ? "Temps à vélo par jour" : "Temps à vélo par mois") { MinutesChart(data: data) }.id("panel-charts")
                Panel(title: "Horaires de départ") { Heatmap(data: data) }.id("panel-heatmap")
                Panel(title: "Répartition par type de vélo") { BikeTypes(data: data) }
                Panel(title: "Records") { Records(records: data.records) }.id("panel-records")
                if !data.stations.isEmpty { Panel(title: "Stations les plus utilisées") { Ranking(items: data.stations) } }
            }
        }
    }
}

// MARK: Headline

private struct Headline: View {
    let data: PeriodStats
    let balance: Double?

    var body: some View {
        let kg = data.co2Grams / 1000
        let average = data.trips > 0 ? Int((Double(data.minutes) / Double(data.trips)).rounded()) : 0
        LazyVGrid(columns: [GridItem(.flexible(), spacing: gap), GridItem(.flexible(), spacing: gap)], spacing: gap) {
            StatCard(icon: .personSimpleBike, label: "Trajets", value: number(data.trips), detail: data.trips > 0 ? "\(hours(average)) en moyenne" : "Aucun trajet")
            StatCard(icon: .clock, label: "Minutes à vélo", value: number(data.minutes), detail: data.minutes >= 60 ? "Soit \(hours(data.minutes))" : "Moins d’une heure")
            StatCard(icon: .route, label: "Distance estimée", value: kilometres(data.distance.metres), unit: "km", detail: "Sur \(plural(data.distance.known, "trajet"))")
            StatCard(icon: .leaf, label: "CO₂ évité", value: kg >= 1 ? formatNumber(kg, maximumFractionDigits: kg < 10 ? 1 : 0) : number(data.co2Grams),
                     unit: kg >= 1 ? "kg" : "g", detail: "Face à la voiture")
            StatCard(icon: .coins, label: "Dépenses", value: formatPrice(data.spentCents),
                     detail: data.savedCents > 0 ? "\(formatPrice(data.savedCents)) économisés" : data.spentCents > 0 ? "Aucune réduction" : "Aucun supplément")
            StatCard(icon: .starFour, label: "Points gagnés", value: number(data.pointsEarned), detail: balance.map { "Solde de \(plural(Int($0), "point"))" })
        }
    }
}

/// `.summary-card.stat-card` at the phone size: red, dotted, the tag, the number and its line; nothing to tap.
private struct StatCard: View {
    let icon: IconName
    let label: String
    let value: String
    var unit: String?
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTag(icon: icon, text: label, compact: true)
            (Text(value) + Text(unit.map { " \($0)" } ?? "").font(Typo.title(15).font))
                .typo(.title(32)).foregroundStyle(Palette.white).lineLimit(1).minimumScaleFactor(0.5).padding(.top, 18)
            Spacer(minLength: 18)
            if let detail { Text(detail).typo(.body(13)).foregroundStyle(Palette.onDark).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(ZStack { Palette.red; DottedTexture() })
        .clipShape(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: Panels

/// `.stat-panel`: white on the ink-line ring, its title and the chart.
private struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).typo(.title(19)).foregroundStyle(Palette.ink)
            content()
        }
        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ringed(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous))
    }
}

/// `.chart-tip`: a white card on the ring, the datum in two lines.
private struct ChartTip: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).typo(.body(12, medium: true)).foregroundStyle(Palette.ink)
            Text(detail).typo(.body(12)).foregroundStyle(Palette.inkSoft)
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .ringed(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .fixedSize()
    }
}

/// Taps on a chart, in the plot area's coordinates: a tap never steals the page's scroll.
private struct TapLayer: View {
    let proxy: ChartProxy
    let tapped: (CGPoint) -> Void
    var body: some View {
        GeometryReader { geometry in
            Color.clear.contentShape(Rectangle()).onTapGesture { location in
                guard let frame = proxy.plotFrame else { return }
                let origin = geometry[frame].origin
                tapped(CGPoint(x: location.x - origin.x, y: location.y - origin.y))
            }
        }
    }
}

/// The minutes per day or month: red bars, the tapped one deeper with its tip; axis labels thinned to fit.
private struct MinutesChart: View {
    let data: PeriodStats
    @State private var selected: String?
    @State private var width: CGFloat = 320

    var body: some View {
        let buckets = data.buckets
        let top = niceMax(Double(buckets.map(\.minutes).max() ?? 0))
        // A day's "29/10" needs 38 pt; a month's initial fits in 16, so all twelve show.
        let every = max(1, Int(ceil(Double(buckets.count) * (data.unit == .day ? 38 : 16) / max(1, width - 34))))
        let shown = Set(buckets.enumerated().filter { (buckets.count - 1 - $0.offset) % every == 0 }.map { $0.element.key })
        Chart(buckets, id: \.key) { bucket in
            BarMark(x: .value("Période", bucket.key), y: .value("Minutes", bucket.minutes), width: .ratio(0.68))
                .foregroundStyle(selected == bucket.key ? Palette.redDeep : Palette.red)
                .cornerRadius(3)
                .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                    if selected == bucket.key {
                        ChartTip(title: capitalize(bucketLabel(data.unit, bucket.key)), detail: "\(hours(bucket.minutes)) en \(plural(bucket.trips, "trajet"))")
                    }
                }
        }
        .chartYScale(domain: 0...top)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, top / 2, top]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Palette.line)
                AxisValueLabel { if let amount = value.as(Double.self) { axisText(number(amount)) } }
            }
        }
        .chartXAxis {
            // A categorical axis marks every bar: the thinned-out ones get an empty label.
            AxisMarks(values: buckets.map(\.key)) { value in
                AxisValueLabel(centered: true) {
                    if let key = value.as(String.self), shown.contains(key) { axisText(axisLabel(data.unit, key)) }
                }
            }
        }
        .chartOverlay { proxy in
            TapLayer(proxy: proxy) { point in
                let key: String? = proxy.value(atX: point.x, as: String.self)
                selected = key == selected ? nil : key
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .frame(height: 220)
        .accessibilityLabel("Temps à vélo par \(data.unit == .day ? "jour" : "mois"), \(hours(data.minutes)) au total")
    }
}

/// Departures by weekday and hour. A cell's red square grows with its count (no tint: red and mist only); empty cells stay mist.
private struct Heatmap: View {
    let data: PeriodStats
    @State private var selected: (day: Int, hour: Int)?
    @State private var width: CGFloat = 320

    private struct Cell: Identifiable {
        let day: Int
        let hour: Int
        let count: Int
        var id: Int { day * 24 + hour }
    }

    var body: some View {
        let rows = data.heatmap
        let cells = rows.enumerated().flatMap { day, row in row.enumerated().map { Cell(day: day, hour: $0.offset, count: $0.element) } }
        let max = Swift.max(1, cells.map(\.count).max() ?? 0)
        let busiest = cells.max { $0.count < $1.count || ($0.count == $1.count && $0.id > $1.id) }!
        let cellHeight = min(26, Swift.max(12, (width - 20) / 24))
        Chart(cells) { cell in
            RectangleMark(xStart: .value("Heure", Double(cell.hour) + 0.06), xEnd: .value("Heure", Double(cell.hour) + 0.94),
                          yStart: .value("Jour", Double(6 - cell.day) + 0.06), yEnd: .value("Jour", Double(6 - cell.day) + 0.94))
                .foregroundStyle(Palette.mist)
                .cornerRadius(2)
            if cell.count > 0 {
                let half = 0.44 * (0.35 + 0.65 * (Double(cell.count) / Double(max)).squareRoot())
                let active = selected.map { $0.day == cell.day && $0.hour == cell.hour } ?? false
                RectangleMark(xStart: .value("Heure", Double(cell.hour) + 0.5 - half), xEnd: .value("Heure", Double(cell.hour) + 0.5 + half),
                              yStart: .value("Jour", Double(6 - cell.day) + 0.5 - half), yEnd: .value("Jour", Double(6 - cell.day) + 0.5 + half))
                    .foregroundStyle(active ? Palette.redDeep : Palette.red)
                    .cornerRadius(2)
                    .annotation(position: .top, spacing: 4, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        if active { ChartTip(title: "\(weekdays[cell.day]), de \(cell.hour) h à \(cell.hour + 1) h", detail: plural(cell.count, "départ")) }
                    }
            }
        }
        .chartXScale(domain: 0...24)
        .chartYScale(domain: 0...7)
        .chartYAxis {
            AxisMarks(position: .leading, values: Array(0..<7).map { Double($0) + 0.5 }) { value in
                AxisValueLabel { if let row = value.as(Double.self) { axisText(String(weekdays[6 - Int(row)].prefix(1))) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 23].map { Double($0) + 0.5 }) { value in
                // Centred, « 23 h » would run past the plot's edge and be dropped: it hangs from its trailing edge instead.
                let hour = value.as(Double.self) ?? 0
                AxisValueLabel(anchor: hour > 23 ? .topTrailing : .top, collisionResolution: .disabled) { axisText("\(Int(hour)) h") }
            }
        }
        .chartOverlay { proxy in
            TapLayer(proxy: proxy) { point in
                guard let hour = proxy.value(atX: point.x, as: Double.self), let row = proxy.value(atY: point.y, as: Double.self), row >= 0, hour >= 0 else { return }
                let cell = (day: 6 - Int(row), hour: Int(hour))
                guard (0..<7).contains(cell.day), (0..<24).contains(cell.hour), rows[cell.day][cell.hour] > 0 else { selected = nil; return }
                selected = selected.map { $0.day == cell.day && $0.hour == cell.hour } == true ? nil : cell
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .frame(height: 7 * cellHeight + 20)
        .accessibilityLabel("Départs selon le jour et l’heure, le plus souvent le \(weekdays[busiest.day].lowercased()) entre \(busiest.hour) h et \(busiest.hour + 1) h")
    }
}

/// The donut: électrique in red, mécanique in mist, both ringed so the mist reads on white.
private struct BikeTypes: View {
    let data: PeriodStats
    @State private var selected: String?

    private struct Part: Identifiable {
        let key: String
        let label: String
        let spoken: String
        let count: Int
        let color: Color
        var id: String { key }
    }

    var body: some View {
        let parts = [
            Part(key: "electrical", label: "Électrique", spoken: "en électrique", count: data.bikeTypes.electrical, color: Palette.red),
            Part(key: "mechanical", label: "Mécanique", spoken: "en mécanique", count: data.bikeTypes.mechanical, color: Palette.mist),
            Part(key: "unknown", label: "Non renseigné", spoken: "sans type connu", count: data.bikeTypes.unknown, color: Palette.white)
        ].filter { $0.count > 0 }
        let total = max(1, data.trips)
        let share = { (count: Int) in "\(Int((Double(count) / Double(total) * 100).rounded()))\u{a0}%" }
        let size: CGFloat = 152
        let thickness: CGFloat = 22
        VStack(spacing: 20) {
            ZStack {
                Circle().strokeBorder(Palette.inkLine, lineWidth: 1)
                Circle().strokeBorder(Palette.inkLine, lineWidth: 1).padding(thickness)
                Chart(parts) { part in
                    SectorMark(angle: .value("Trajets", part.count), innerRadius: .fixed(size / 2 - thickness), outerRadius: .fixed(size / 2), angularInset: parts.count > 1 ? 1 : 0)
                        .foregroundStyle(selected == part.key && part.key == "electrical" ? Palette.redDeep : part.color)
                }
                .chartLegend(.hidden)
                if let part = parts.first(where: { $0.key == selected }) {
                    VStack(spacing: 2) {
                        Text(part.label).typo(.body(12, medium: true)).foregroundStyle(Palette.ink)
                        Text("\(plural(part.count, "trajet")), soit \(share(part.count))").typo(.body(12)).foregroundStyle(Palette.inkSoft)
                    }
                    .multilineTextAlignment(.center)
                    .frame(width: size - 2 * thickness - 8)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .onTapGesture { selected = selected == nil ? parts.first?.key : parts.firstIndex { $0.key == selected }.flatMap { $0 + 1 < parts.count ? parts[$0 + 1].key : nil } }
            .accessibilityLabel("Trajets \(parts.map { "\($0.spoken) à \(share($0.count))" }.joined(separator: ", "))")
            VStack(spacing: 8) {
                ForEach(parts) { part in
                    Button { selected = selected == part.key ? nil : part.key } label: {
                        HStack(spacing: 10) {
                            Circle().fill(part.color).frame(width: 10, height: 10).overlay(Circle().strokeBorder(part.key == "electrical" ? .clear : Palette.inkLine, lineWidth: 1))
                            Text(part.label).typo(.body(13)).foregroundStyle(Palette.ink)
                            Spacer(minLength: 0)
                            Text(share(part.count)).typo(.label(13)).foregroundStyle(Palette.ink)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: Records and stations

/// `.stat-records` at the phone size: four tiles in two columns, a hairline before the second one of each row.
private struct Records: View {
    let records: StatsRecords

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 22) {
            GridRow {
                tile("Plus long trajet", first: true) { value(records.longestMinutes.map(hours)) }
                tile("Jour record", first: false) { value(records.busiestDayTrips.map { plural($0, "trajet") }) }
            }
            GridRow {
                tile("Série", first: true) { value(records.streakDays.map { plural($0, "jour") }) }
                tile("Vélo favori", first: false) {
                    if let bike = records.bike {
                        NavigationLink(value: BikeRoute(number: bike, station: nil)) {
                            Text(verbatim: "N° \(bike)").typo(.title(23)).foregroundStyle(Palette.ink).underline(color: Palette.inkLine)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Voir la fiche du vélo \(bike)")
                    } else {
                        value(nil)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func value(_ text: String?) -> some View {
        Text(text ?? "—").typo(.title(23)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.7)
    }

    private func tile(_ label: String, first: Bool, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).typo(.label(13)).foregroundStyle(Palette.inkSoft).lineLimit(1)
            content()
        }
        .padding(.leading, first ? 0 : 14).padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { if !first { Rectangle().fill(Palette.line).frame(width: 1) } }
    }
}

/// `.stat-ranking`: rank, station and count, one hairline between rows.
private struct Ranking: View {
    let items: [StationCount]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Hairline() }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(index + 1)").typo(.label(13)).foregroundStyle(Palette.inkSoft).frame(width: 18, alignment: .leading)
                    Text(item.name).typo(.body(15)).foregroundStyle(Palette.ink).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                    Text(number(item.count)).typo(.label(13)).foregroundStyle(Palette.ink).accessibilityLabel("\(number(item.count)) passages")
                }
                .padding(.top, index > 0 ? 13 : 0).padding(.bottom, index < items.count - 1 ? 13 : 0)
            }
        }
    }
}
