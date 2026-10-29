import Charts
import SwiftUI
import VelovCore

// stats.tsx: the Statistiques page, pushed from the Trajets tab. Red headline cards, then white panels on the ink-line ring;
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

/// "29/10" or "Oct" under the bars.
private func axisLabel(_ unit: PeriodStats.Unit, _ key: String) -> String {
    unit == .day ? format(keyDate(key), "dM") : capitalize(format(keyDate(key), "MMM")).replacingOccurrences(of: ".", with: "")
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

// MARK: The page

/// Read once per account: a period change or a return to the page reads nothing (the core keeps it 10 minutes too).
@MainActor private var cachedStats: (account: String, stats: Stats)?

struct StatsPage: View {
    private static let unavailable = "Vos statistiques sont momentanément indisponibles."

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var state: Resource<Stats> = .loading

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
                    Color.clear.frame(height: 0).id("stats-end")
                }
            }
            .scrollIndicators(.hidden)
            .background(Palette.white)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                if let cachedStats, cachedStats.account == account { state = .ready(cachedStats.stats) } else { await load() }
                // The snapshot run reviews the whole page in four screens.
                let anchors: [SnapshotScreen: (String, UnitPoint)] = [.statsCharts: ("panel-charts", .top), .statsHeatmap: ("panel-heatmap", .top),
                                                                       .statsRecords: ("panel-points", .top), .statsEnd: ("stats-end", .bottom)]
                if let snapshot = model.snapshot, let target = anchors[snapshot] {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    proxy.scrollTo(target.0, anchor: target.1)
                }
            }
        }
    }

    private var skeleton: some View {
        VStack(spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(0..<6, id: \.self) { _ in Skeleton(height: 140) }
            }
            Skeleton(height: 310).padding(.top, 30)
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
        .init(value: .days30, label: "30 derniers jours", short: "30 jours"),
        .init(value: .months12, label: "12 derniers mois", short: "12 mois"),
        .init(value: .all, label: "Depuis le début", short: "Tout")
    ]

    var body: some View {
        let data = stats[period]
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SelectField(label: "Période", hideLabel: true, value: $period, options: Self.periods)
                Spacer(minLength: 8)
                Text(plural(data.trips, "trajet")).typo(.label(11)).foregroundStyle(Palette.inkMuted)
            }
            .zIndex(2)
            .padding(.bottom, 24)
            if data.withoutStations > 0 { notice("\(plural(data.withoutStations, "trajet")) sans stations : Vélo’v a effacé ces données.") }
            if !stats.complete { notice("Une partie de l’historique n’a pas pu être lue : les chiffres peuvent être incomplets.") }
            Headline(data: data)
            if data.trips == 0 {
                EmptyState(stats.all.trips > 0 ? "Aucun trajet sur cette période." : "Aucun trajet pour l’instant. Vos statistiques apparaîtront après votre premier trajet.")
            } else {
                VStack(spacing: 12) {
                    Panel(title: data.unit == .day ? "Minutes par jour" : "Minutes par mois") { MinutesChart(data: data) }.id("panel-charts")
                    Panel(title: "Type de vélo") { BikeTypes(data: data) }
                    Panel(title: "Quand vous roulez", note: "Départs par jour et par heure") { Heatmap(data: data) }.id("panel-heatmap")
                    Panel(title: "Durée des trajets", note: "En minutes") { Durations(data: data) }
                    Panel(title: "Évolution des points", note: stats.pointsAvailable ? "Solde en fin de période" : nil) {
                        if stats.pointsAvailable { PointsChart(data: data) } else { EmptyState("L’historique des points est momentanément indisponible.") }
                    }
                    .id("panel-points")
                    Panel(title: "Records") { Records(data: data) }
                    Panel(title: "Stations de départ") { Ranking(items: data.starts.map { (label: $0.name, count: $0.count) }) }
                    Panel(title: "Stations d’arrivée") { Ranking(items: data.ends.map { (label: $0.name, count: $0.count) }) }
                    Panel(title: "Trajets favoris") {
                        Ranking(items: data.pairs.map { (label: $0.from == $0.to ? "\($0.from) (boucle)" : "\($0.from) → \($0.to)", count: $0.count) },
                                empty: "Aucun trajet refait deux fois.")
                    }
                }
                .padding(.top, 24)
            }
        }
    }

    private func notice(_ text: String) -> some View {
        Text(text).typo(.body(13)).foregroundStyle(Palette.notice).fixedSize(horizontal: false, vertical: true).padding(.bottom, 20)
    }
}

// MARK: Headline

private struct Headline: View {
    let data: PeriodStats

    var body: some View {
        let distance = data.distance
        let kg = data.co2Grams / 1000
        let average = data.trips > 0 ? Int((Double(data.minutes) / Double(data.trips)).rounded()) : 0
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                StatCard(icon: .personSimpleBike, label: "Trajets", value: number(data.trips), detail: data.trips > 0 ? "\(hours(average)) en moyenne" : "Aucun trajet")
                StatCard(icon: .clock, label: "Minutes à vélo", value: number(data.minutes), detail: data.minutes >= 60 ? "Soit \(hours(data.minutes))" : "Moins d’une heure")
                StatCard(icon: .route, label: "Km estimés", value: kilometres(distance.metres),
                         detail: distance.unknown > 0 ? "Sur \(number(distance.known)) trajets sur \(number(data.trips))" : "Entre stations, détours inclus")
                StatCard(icon: .leaf, label: "CO₂ évité estimé", value: kg >= 1 ? formatNumber(kg, maximumFractionDigits: kg < 10 ? 1 : 0) : number(data.co2Grams),
                         unit: kg >= 1 ? "kg" : "g", detail: "Face à la voiture*")
                StatCard(icon: .coins, label: "Dépenses", value: formatPrice(data.spentCents),
                         detail: data.savedCents > 0 ? "\(formatPrice(data.savedCents)) économisés" : data.spentCents > 0 ? "Aucune réduction" : "Trajets compris")
                StatCard(icon: .starFour, label: "Points gagnés", value: number(data.pointsEarned), detail: "Trajets, notes et bonus")
            }
            Text("Km estimés : distance entre les stations de départ et d’arrivée, majorée de \(Int(((StatsRules.detourFactor - 1) * 100).rounded())) % pour les détours (0 km pour un retour à la même station).\(distance.unknown > 0 ? " \(plural(distance.unknown, "trajet")) sans distance estimable." : "") *CO₂ évité : \(Int(StatsRules.co2GramsPerKm)) g par km, ordre de grandeur d’une voiture thermique en ville.")
                .typo(.body(12)).foregroundStyle(Palette.inkSoft).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// `.summary-card.stat-card` at the phone size: red, dotted, the tag, the number and its line; nothing to tap.
private struct StatCard: View {
    let icon: IconName
    let label: String
    let value: String
    var unit: String?
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTag(icon: icon, text: label, compact: true)
            (Text(value) + Text(unit.map { " \($0)" } ?? "").font(Typo.title(15).font))
                .typo(.title(32)).foregroundStyle(Palette.white).lineLimit(1).minimumScaleFactor(0.5).padding(.top, 18)
            Spacer(minLength: 12)
            Text(detail).typo(.body(12)).foregroundStyle(Palette.onDark).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 14)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .topLeading)
        .background(ZStack { Palette.red; DottedTexture() })
        .clipShape(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

// MARK: Panels

/// `.stat-panel`: white on the ink-line ring, the title and its note stacked on a phone.
private struct Panel<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).typo(.title(20)).foregroundStyle(Palette.ink)
                if let note { Text(note).typo(.label(10)).foregroundStyle(Palette.inkSoft) }
            }
            .padding(.bottom, 14)
            content()
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 18)
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

private struct Bar: Identifiable {
    let key: String
    let axis: String
    let value: Int
    let tipTitle: String
    let tipDetail: String
    var id: String { key }
}

/// `BarChart`: red bars, the tapped one deeper with its tip; axis labels thinned to fit.
private struct BarChart: View {
    let bars: [Bar]
    let label: String
    @State private var selected: String?
    @State private var width: CGFloat = 320

    var body: some View {
        let top = niceMax(Double(bars.map(\.value).max() ?? 0))
        let every = max(1, Int(ceil(Double(bars.count) * 38 / max(1, width - 34))))
        let shown = bars.enumerated().filter { (bars.count - 1 - $0.offset) % every == 0 }.map { $0.element.key }
        Chart(bars) { bar in
            BarMark(x: .value("Période", bar.key), y: .value("Valeur", bar.value), width: .ratio(0.68))
                .foregroundStyle(selected == bar.key ? Palette.redDeep : Palette.red)
                .cornerRadius(3)
                .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                    if selected == bar.key { ChartTip(title: bar.tipTitle, detail: bar.tipDetail) }
                }
        }
        .chartYScale(domain: 0...top)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, top / 2, top]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Palette.line)
                AxisValueLabel { if let amount = value.as(Double.self) { Text(number(amount)).typo(.mono(10)).foregroundStyle(Palette.inkSoft) } }
            }
        }
        .chartXAxis {
            // A categorical axis marks every bar: the thinned-out ones get an empty label.
            AxisMarks(values: bars.map(\.key)) { value in
                AxisValueLabel(centered: true) {
                    if let key = value.as(String.self), shown.contains(key) {
                        Text(bars.first { $0.key == key }?.axis ?? "").typo(.mono(10)).foregroundStyle(Palette.inkSoft).fixedSize()
                    }
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
        .frame(height: 190)
        .accessibilityLabel(label)
    }
}

private struct MinutesChart: View {
    let data: PeriodStats
    var body: some View {
        BarChart(bars: data.buckets.map { bucket in
            Bar(key: bucket.key, axis: axisLabel(data.unit, bucket.key), value: bucket.minutes,
                tipTitle: capitalize(bucketLabel(data.unit, bucket.key)), tipDetail: "\(hours(bucket.minutes)) · \(plural(bucket.trips, "trajet"))")
        }, label: "Minutes à vélo par \(data.unit == .day ? "jour" : "mois"), \(hours(data.minutes)) au total")
    }
}

private struct Durations: View {
    let data: PeriodStats
    var body: some View {
        let most = data.durations.max { $0.count < $1.count }?.label ?? ""
        BarChart(bars: data.durations.map { bucket in
            Bar(key: bucket.label, axis: bucket.label, value: bucket.count,
                tipTitle: bucket.label == "30+" ? "30 min et plus" : "De \(bucket.label.replacingOccurrences(of: "-", with: " à ")) min",
                tipDetail: plural(bucket.count, "trajet"))
        }, label: "Durée des trajets, la plus fréquente \(most) min")
    }
}

/// Departures by weekday and hour. A cell's red square grows with its count (no tint: red and mist only); empty cells stay mist.
private struct Heatmap: View {
    let data: PeriodStats
    @State private var selected: (day: Int, hour: Int)?

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
                        if active { ChartTip(title: "\(weekdays[cell.day]), \(cell.hour) h - \(cell.hour + 1) h", detail: plural(cell.count, "départ")) }
                    }
            }
        }
        .chartXScale(domain: 0...24)
        .chartYScale(domain: 0...7)
        .chartYAxis {
            AxisMarks(position: .leading, values: Array(0..<7).map { Double($0) + 0.5 }) { value in
                AxisValueLabel { if let row = value.as(Double.self) { Text(weekdays[6 - Int(row)].prefix(1)).typo(.mono(10)).foregroundStyle(Palette.inkSoft) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 23].map { Double($0) + 0.5 }) { value in
                AxisValueLabel { if let hour = value.as(Double.self) { Text("\(Int(hour)) h").typo(.mono(10)).foregroundStyle(Palette.inkSoft).fixedSize() } }
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
        .frame(height: 7 * 15 + 24)
        .accessibilityLabel("Départs par jour et par heure. Créneau le plus fréquent : \(weekdays[busiest.day].lowercased()) de \(busiest.hour) h à \(busiest.hour + 1) h")
    }
}

/// The donut: électrique in red, mécanique in mist, both ringed so the mist reads on white.
private struct BikeTypes: View {
    let data: PeriodStats
    @State private var selected: String?

    private struct Part: Identifiable {
        let key: String
        let label: String
        let count: Int
        let color: Color
        var id: String { key }
    }

    var body: some View {
        let parts = [
            Part(key: "electrical", label: "Électrique", count: data.bikeTypes.electrical, color: Palette.red),
            Part(key: "mechanical", label: "Mécanique", count: data.bikeTypes.mechanical, color: Palette.mist),
            Part(key: "unknown", label: "Non renseigné", count: data.bikeTypes.unknown, color: Palette.white)
        ].filter { $0.count > 0 }
        let total = max(1, data.trips)
        let share = { (count: Int) in "\(Int((Double(count) / Double(total) * 100).rounded())) %" }
        let size: CGFloat = 168
        let thickness: CGFloat = 24
        VStack(spacing: 18) {
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
                        Text("\(plural(part.count, "trajet")) · \(share(part.count))").typo(.body(12)).foregroundStyle(Palette.inkSoft)
                    }
                    .multilineTextAlignment(.center)
                    .frame(width: size - 2 * thickness - 8)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Circle())
            .onTapGesture { selected = selected == nil ? parts.first?.key : parts.firstIndex { $0.key == selected }.flatMap { $0 + 1 < parts.count ? parts[$0 + 1].key : nil } }
            .accessibilityLabel("Répartition par type de vélo : \(parts.map { "\($0.label.lowercased()) \(share($0.count))" }.joined(separator: ", "))")
            VStack(spacing: 8) {
                ForEach(parts) { part in
                    Button { selected = selected == part.key ? nil : part.key } label: {
                        HStack(spacing: 10) {
                            Circle().fill(part.color).frame(width: 10, height: 10).overlay(Circle().strokeBorder(part.key == "electrical" ? .clear : Palette.inkLine, lineWidth: 1))
                            Text(part.label).typo(.body(13)).foregroundStyle(Palette.ink)
                            Spacer(minLength: 0)
                            Text(share(part.count)).typo(.mono(12)).foregroundStyle(Palette.ink)
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

/// The points balance at the end of each day or month: a red line; a tap puts the cursor and the dot on the nearest point.
private struct PointsChart: View {
    let data: PeriodStats
    @State private var selected: Int?
    @State private var width: CGFloat = 320

    var body: some View {
        let values = data.buckets.map { $0.balance ?? 0 }
        let low = values.min() ?? 0, high = values.max() ?? 0
        let upper = high > low ? high : low + 1
        let every = max(1, Int(ceil(Double(values.count) * 38 / max(1, width - 34))))
        let shown = values.indices.filter { (values.count - 1 - $0) % every == 0 }
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                LineMark(x: .value("Période", index), y: .value("Points", value))
                    .foregroundStyle(Palette.red)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let selected {
                RuleMark(x: .value("Période", selected)).foregroundStyle(Palette.inkLine).lineStyle(StrokeStyle(lineWidth: 1))
                PointMark(x: .value("Période", selected), y: .value("Points", values[selected]))
                    .symbol { Circle().fill(Palette.white).overlay(Circle().strokeBorder(Palette.red, lineWidth: 2)).frame(width: 11, height: 11) }
                    .annotation(position: .top, spacing: 6, overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        ChartTip(title: capitalize(bucketLabel(data.unit, data.buckets[selected].key)), detail: plural(Int(values[selected]), "point"))
                    }
            }
        }
        .chartXScale(domain: 0...max(1, values.count - 1))
        .chartYScale(domain: low...upper)
        .chartYAxis {
            AxisMarks(position: .leading, values: Array(Set([low, high])).sorted()) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Palette.line)
                AxisValueLabel { if let amount = value.as(Double.self) { Text(number(amount)).typo(.mono(10)).foregroundStyle(Palette.inkSoft) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: shown) { value in
                AxisValueLabel {
                    if let index = value.as(Int.self), data.buckets.indices.contains(index) {
                        Text(axisLabel(data.unit, data.buckets[index].key)).typo(.mono(10)).foregroundStyle(Palette.inkSoft).fixedSize()
                    }
                }
            }
        }
        .chartOverlay { proxy in
            TapLayer(proxy: proxy) { point in
                guard let position = proxy.value(atX: point.x, as: Double.self) else { return }
                let index = min(values.count - 1, max(0, Int(position.rounded())))
                selected = selected == index ? nil : index
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .frame(height: 190)
        .accessibilityLabel("Solde de points, de \(number(values.first ?? 0)) à \(number(values.last ?? 0))")
    }
}

// MARK: Records and rankings

private struct Records: View {
    let data: PeriodStats

    var body: some View {
        let records = data.records
        VStack(alignment: .leading, spacing: 16) {
            record("Plus long trajet", records.longest.map { hours($0.minutes) }, small: records.longest.map { longest in
                let route = longest.from.flatMap { from in longest.to.map { from == $0 ? from : "\(from) → \($0)" } }
                return [longest.startedAt.map { format($0, "dMMMMy") }, route].compactMap { $0 }.joined(separator: " · ")
            })
            record("Jour le plus actif", records.busiestDay.map { plural($0.trips, "trajet") },
                   small: records.busiestDay.map { capitalize(format(keyDate($0.day), "EEEEdMMMMy")) })
            record("Série de jours consécutifs", records.streak.map { plural($0.days, "jour") },
                   small: records.streak.flatMap { $0.days > 1 ? "Du \(format(keyDate($0.from), "dMMMM")) au \(format(keyDate($0.to), "dMMMMy"))" : nil })
            VStack(alignment: .leading, spacing: 4) {
                Text("Vélo le plus emprunté").typo(.label(11)).foregroundStyle(Palette.inkSoft)
                if let bike = records.bike {
                    NavigationLink(value: BikeRoute(number: bike.number, station: nil)) {
                        Text(verbatim: "N° \(bike.number)").typo(.title(22)).foregroundStyle(Palette.redDeep).underline()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Voir la fiche du vélo \(bike.number)")
                    Text(plural(bike.count, "trajet") + (bike.type == .electrical ? " · Électrique" : bike.type == .mechanical ? " · Mécanique" : ""))
                        .typo(.body(12)).foregroundStyle(Palette.inkSoft)
                } else {
                    Text("—").typo(.title(22)).foregroundStyle(Palette.ink)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func record(_ label: String, _ value: String?, small: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).typo(.label(11)).foregroundStyle(Palette.inkSoft)
            Text(value ?? "—").typo(.title(22)).foregroundStyle(Palette.ink)
            if let small, !small.isEmpty { Text(small).typo(.body(12)).foregroundStyle(Palette.inkSoft).fixedSize(horizontal: false, vertical: true) }
        }
    }
}

/// `.stat-ranking`: rank, label, count, and a red bar on mist relative to the first.
private struct Ranking: View {
    let items: [(label: String, count: Int)]
    var empty = "Aucune station renseignée."

    var body: some View {
        if items.isEmpty {
            EmptyState(empty).padding(.vertical, -16)
        } else {
            let top = Double(items[0].count)
            VStack(spacing: 14) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1)").typo(.mono(11)).foregroundStyle(Palette.inkSoft).frame(width: 20, alignment: .leading)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(item.label).typo(.body(14)).foregroundStyle(Palette.ink).fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                                Text(number(item.count)).typo(.mono(12)).foregroundStyle(Palette.ink)
                            }
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Palette.mist)
                                    Capsule().fill(Palette.red).frame(width: geometry.size.width * Double(item.count) / top)
                                }
                            }
                            .frame(height: 4)
                        }
                    }
                }
            }
        }
    }
}
