import Charts
import SwiftUI
import VelovCore

enum TripsRoute: Hashable { case stats }

struct TripsStack: View {
    @Environment(AppModel.self) private var model
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            PageScaffold(page: .trips)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: TripsRoute.self) { _ in StatsPage().heldWhile(model.operations.sending) }
        }
        .task { if let snapshot = model.snapshot, snapshot.showsStats, path.isEmpty { path.append(TripsRoute.stats) } }
        .onLeaving(.trips) { path = NavigationPath() }
    }
}

extension SnapshotScreen {
    var showsStats: Bool { [.stats, .statsCharts, .statsTipFirst, .statsTipMiddle, .statsTipLast, .statsHeatmap, .statsHeatTip, .statsDonut, .statsRecords, .statsBike, .statsEnd].contains(self) }
}

struct StatsLink: View {
    var body: some View {
        NavigationLink(value: TripsRoute.stats) {
            HStack(spacing: 10) {
                Icon(.chart, .light, size: 18)
                Text("Statistiques")
                Spacer(minLength: 0)
                Icon(.caretRight, .bold, size: 14)
            }
            .typo(.caps(14))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 18)
            .frame(minHeight: 42)
            .overlay(Capsule().strokeBorder(Palette.secondaryRing, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

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

private func axisLabel(_ unit: PeriodStats.Unit, _ key: String) -> String {
    unit == .day ? format(keyDate(key), "dM") : format(keyDate(key), "MMMMM").uppercased(with: french)
}

private func bucketLabel(_ unit: PeriodStats.Unit, _ key: String) -> String {
    unit == .day ? format(keyDate(key), "EEEEdMMMM") : format(keyDate(key), "MMMMy")
}

private let weekdays = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]

private func niceMax(_ value: Double) -> Double {
    guard value > 0 else { return 1 }
    let step = pow(10, floor(log10(value)))
    return [1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10].map { $0 * step }.first { $0 >= value } ?? value
}

private func axisText(_ text: String) -> some View {
    Text(text).typo(.body(11)).foregroundStyle(Palette.inkSoft).fixedSize()
}

private let gap: CGFloat = 10

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
                if let cached = model.statsCache.get(account) { state = .ready(cached) } else { await load() }
                let anchors: [SnapshotScreen: String] = [.statsCharts: "panel-charts", .statsTipFirst: "panel-charts", .statsTipMiddle: "panel-charts", .statsTipLast: "panel-charts", .statsHeatTip: "panel-heatmap", .statsDonut: "panel-donut", .statsHeatmap: "panel-heatmap", .statsRecords: "panel-records", .statsBike: "panel-records"]
                guard let snapshot = model.snapshot, snapshot != .stats, snapshot.showsStats else { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                if let anchor = anchors[snapshot] { proxy.scrollTo(anchor, anchor: .top) } else { position.scrollTo(edge: .bottom) }
            }
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: gap) {
            SelectField(label: "Période", hideLabel: true, value: .constant(StatsPeriod.months12), options: StatsView.periods).skeleton(21).padding(.bottom, 6)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: gap), GridItem(.flexible(), spacing: gap)], spacing: gap) {
                ForEach(headlines, id: \.label) { card in
                    StatCard(icon: card.icon, label: card.label, value: card.value, unit: card.unit, detail: "—").skeleton()
                }
            }
            Panel(title: "Temps à vélo par mois", chart: true, tips: true) { Skeleton(height: 220) }
            Panel(title: "Horaires de départ", chart: true, tips: true) { HeatmapSkeleton() }
            Panel(title: "Répartition par type de vélo", chart: true) {
                VStack(spacing: 20) {
                    Shimmer(radius: 76).frame(width: 152, height: 152).mask(Circle().strokeBorder(.black, lineWidth: 22)).accessibilityHidden(true)
                    VStack(spacing: 8) {
                        ForEach(["Électrique", "Mécanique"], id: \.self) { label in
                            HStack(spacing: 10) {
                                Circle().frame(width: 10, height: 10).skeleton(5)
                                Text(label).typo(.body(13)).ghost()
                                Spacer(minLength: 0)
                                Text(verbatim: "50\u{a0}%").typo(.label(13)).ghost()
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            Panel(title: "Records") { Records(records: nil) }
            Panel(title: "Stations les plus utilisées") { Ranking(items: ghostStations.map { StationCount(name: $0, count: 12) }, ghost: true) }
        }
        .accessibilityLabel("Chargement des statistiques")
    }

    private func load() async {
        state = .loading
        switch await model.loadStats() {
        case .success(let stats)?: state = .ready(stats)
        case .failure(let error)?: state = .failed(failureMessage(error, Self.unavailable))
        case nil: break
        }
    }
}

private let headlines: [(icon: IconName, label: String, value: String, unit: String?)] = [
    (.personSimpleBike, "Trajets", "0", nil), (.clock, "Minutes à vélo", "0", nil), (.route, "Distance", "0", "km"),
    (.leaf, "CO₂ évité", "0", "kg"), (.coins, "Dépenses", "0,00\u{a0}€", nil), (.starFour, "Points gagnés", "0", nil)
]
private let ghostStations = ["Bellecour", "Part-Dieu Villette", "Hôtel de Ville", "Saxe-Gambetta", "Croix-Rousse"]

private struct HeatmapSkeleton: View {
    @State private var width: CGFloat = 320
    var body: some View {
        Skeleton(height: 7 * min(26, max(12, (width - 20) / 24)) + 20)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

struct StatsView: View {
    let stats: Stats
    @Environment(AppModel.self) private var model
    @State private var period = StatsPeriod.months12
    @State private var focus: ChartFocus?

    static let periods: [SelectOption<StatsPeriod>] = [
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
            if !stats.complete { Text("Historique partiel").typo(.body(12)).foregroundStyle(Palette.inkSoft).padding(.top, 4) }
            Headline(data: data, balance: stats.balance)
            if data.trips == 0 {
                EmptyState(stats.all.trips > 0 ? "Aucun trajet sur cette période." : "Vos statistiques apparaîtront après votre premier trajet.")
            } else {
                Panel(title: data.unit == .day ? "Temps à vélo par jour" : "Temps à vélo par mois", chart: true, tips: true) { MinutesChart(data: data, focus: $focus) }.id("panel-charts")
                Panel(title: "Horaires de départ", chart: true, tips: true) { Heatmap(data: data, focus: $focus) }.id("panel-heatmap")
                Panel(title: "Répartition par type de vélo", chart: true) { BikeTypes(data: data, focus: $focus) }.id("panel-donut")
                Panel(title: "Records") { Records(records: data.records) }.id("panel-records")
                if !data.stations.isEmpty { Panel(title: "Stations les plus utilisées") { Ranking(items: data.stations) } }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focus = nil }
        .onChange(of: period) { focus = nil }
        .task {
            let keys = stats[period].buckets.map(\.key)
            switch model.snapshot {
            case .statsTipFirst: focus = keys.first.map(ChartFocus.bucket)
            case .statsTipMiddle: focus = keys.isEmpty ? nil : .bucket(keys[keys.count / 2])
            case .statsTipLast: focus = keys.last.map(ChartFocus.bucket)
            case .statsDonut: focus = .part("electrical")
            case .statsHeatTip:
                let rows = stats[period].heatmap
                focus = (0..<24).reversed().lazy.compactMap { hour in rows.indices.first { rows[$0][hour] > 0 }.map { ChartFocus.cell(day: $0, hour: hour) } }.first
            default: break
            }
        }
    }
}

private struct Headline: View {
    let data: PeriodStats
    let balance: Double?

    var body: some View {
        let kg = data.co2Grams / 1000
        let average = data.trips > 0 ? Int((Double(data.minutes) / Double(data.trips)).rounded()) : 0
        LazyVGrid(columns: [GridItem(.flexible(), spacing: gap), GridItem(.flexible(), spacing: gap)], spacing: gap) {
            StatCard(icon: .personSimpleBike, label: "Trajets", value: number(data.trips), detail: data.trips > 0 ? "\(hours(average)) en moyenne" : "Aucun trajet")
            StatCard(icon: .clock, label: "Minutes à vélo", value: number(data.minutes), detail: data.minutes >= 60 ? "Soit \(hours(data.minutes))" : "Moins d’une heure")
            StatCard(icon: .route, label: "Distance", value: kilometres(data.distance.metres), unit: "km", detail: "Sur \(plural(data.distance.known, "trajet"))")
            StatCard(icon: .leaf, label: "CO₂ évité", value: kg >= 1 ? formatNumber(kg, maximumFractionDigits: kg < 10 ? 1 : 0) : number(data.co2Grams),
                     unit: kg >= 1 ? "kg" : "g", detail: "Plutôt qu’en voiture")
            StatCard(icon: .coins, label: "Dépenses", value: formatPrice(data.spentCents),
                     detail: data.savedCents > 0 ? "\(formatPrice(data.savedCents)) économisés" : data.spentCents > 0 ? "Aucune réduction" : "Aucun supplément")
            StatCard(icon: .starFour, label: "Points gagnés", value: number(data.pointsEarned), detail: balance.map { "Solde de \(plural(Int($0), "point"))" })
        }
    }
}

private struct StatCard: View {
    let icon: IconName
    let label: String
    let value: String
    var unit: String?
    let detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardTag(icon: icon, text: label, size: .stat)
            (Text(value.glyphic) + Text(unit.map { " \($0)" } ?? "").font(Typo.title(15).font))
                .typo(.title(32)).foregroundStyle(Palette.white).lineLimit(1).minimumScaleFactor(0.5).padding(.top, 18)
            Spacer(minLength: 18)
            if let detail { Text(detail).typo(.body(11)).foregroundStyle(Palette.white).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(ZStack { Palette.red; DottedTexture() })
        .clipShape(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct Panel<Content: View>: View {
    let title: String
    var chart = false
    var tips = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: tips ? 34 + tipBand : chart ? 34 : 18) {
            Text(title).typo(.title(19)).foregroundStyle(Palette.ink)
            content()
        }
        .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .ringed(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous))
    }
}

private enum ChartFocus: Equatable {
    case bucket(String)
    case cell(day: Int, hour: Int)
    case part(String)
}

private let tipBand: CGFloat = 40
private let tipGap: CGFloat = 10

private struct ChartTip: View {
    let title: String
    let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).typo(.body(12, medium: true)).foregroundStyle(Palette.ink)
            Text(detail).typo(.body(12)).foregroundStyle(Palette.inkSoft)
        }
        .padding(.horizontal, 11).padding(.vertical, 8)
        .ringed(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct PlacedTip: View {
    let proxy: ChartProxy
    let x: CGFloat?
    let y: CGFloat?
    let tip: ChartTip
    @State private var size = CGSize.zero

    var body: some View {
        GeometryReader { geometry in
            if let frame = proxy.plotFrame, let x, let y {
                let plot = geometry[frame]
                let width = geometry.size.width
                let left = min(max(0, plot.minX + x - size.width / 2), max(0, width - size.width))
                let bottom = plot.minY - tipGap
                Rectangle().fill(Palette.inkLine)
                    .frame(width: 1, height: max(0, plot.minY + y - bottom))
                    .offset(x: plot.minX + x - 0.5, y: bottom)
                tip
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
                    .frame(maxWidth: width, alignment: .leading)
                    .offset(x: left, y: bottom - size.height)
                    .opacity(size == .zero ? 0 : 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

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

private struct MinutesChart: View {
    let data: PeriodStats
    @Binding var focus: ChartFocus?
    @State private var width: CGFloat = 320

    var body: some View {
        let buckets = data.buckets
        let selected: String? = if case .bucket(let key) = focus { key } else { nil }
        let top = niceMax(Double(buckets.map(\.minutes).max() ?? 0))
        let every = max(1, Int(ceil(Double(buckets.count) * (data.unit == .day ? 38 : 16) / max(1, width - 34))))
        let shown = Set(buckets.enumerated().filter { (buckets.count - 1 - $0.offset) % every == 0 }.map { $0.element.key })
        Chart(buckets, id: \.key) { bucket in
            BarMark(x: .value("Période", bucket.key), y: .value("Minutes", bucket.minutes), width: .ratio(0.68))
                .foregroundStyle(selected == bucket.key ? Palette.redDeep : Palette.red)
                .cornerRadius(3)
        }
        .chartYScale(domain: 0...top)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, top / 2, top]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Palette.line)
                AxisValueLabel { if let amount = value.as(Double.self) { axisText(number(amount)) } }
            }
        }
        .chartXAxis {
            AxisMarks(values: buckets.map(\.key)) { value in
                AxisValueLabel(centered: true) {
                    if let key = value.as(String.self), shown.contains(key) { axisText(axisLabel(data.unit, key)) }
                }
            }
        }
        .chartOverlay { proxy in
            ZStack {
                TapLayer(proxy: proxy) { point in
                    let key: String? = proxy.value(atX: point.x, as: String.self)
                    focus = key == nil || key == selected ? nil : key.map(ChartFocus.bucket)
                }
                if let selected, let bucket = buckets.first(where: { $0.key == selected }) {
                    PlacedTip(proxy: proxy, x: proxy.position(forX: selected), y: proxy.position(forY: bucket.minutes),
                              tip: ChartTip(title: capitalize(bucketLabel(data.unit, bucket.key)), detail: "\(hours(bucket.minutes)) en \(plural(bucket.trips, "trajet"))"))
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .frame(height: 220)
        .accessibilityLabel("Temps à vélo par \(data.unit == .day ? "jour" : "mois"), \(hours(data.minutes)) au total")
    }
}

private struct Heatmap: View {
    let data: PeriodStats
    @Binding var focus: ChartFocus?
    @State private var width: CGFloat = 320

    private struct Cell: Identifiable {
        let day: Int
        let hour: Int
        let count: Int
        var id: Int { day * 24 + hour }
    }

    var body: some View {
        let rows = data.heatmap
        let selected: (day: Int, hour: Int)? = if case .cell(let day, let hour) = focus { (day, hour) } else { nil }
        let cells = rows.enumerated().flatMap { day, row in row.enumerated().map { Cell(day: day, hour: $0.offset, count: $0.element) } }
        let max = Swift.max(1, cells.map(\.count).max() ?? 0)
        let busiest = cells.max { $0.count < $1.count || ($0.count == $1.count && $0.id > $1.id) }!
        let cellHeight = min(26, Swift.max(12, (width - 20) / 24))
        let cellWidth = Swift.max(1, (width - 20) / 24)
        let insetX = 1 / cellWidth, insetY = 1 / cellHeight
        let side = Swift.max(1, Swift.min(cellWidth, cellHeight) - 2)
        Chart(cells) { cell in
            let active = selected.map { $0.day == cell.day && $0.hour == cell.hour } ?? false
            RectangleMark(xStart: .value("Heure", Double(cell.hour) + insetX), xEnd: .value("Heure", Double(cell.hour + 1) - insetX),
                          yStart: .value("Jour", Double(6 - cell.day) + insetY), yEnd: .value("Jour", Double(7 - cell.day) - insetY))
                .foregroundStyle(active ? Palette.redDeep : Palette.mist)
                .cornerRadius(3)
            if cell.count > 0, !active {
                let inner = (side * (0.4 + 0.6 * Double(cell.count) / Double(max))).rounded()
                RectangleMark(x: .value("Heure", Double(cell.hour) + 0.5), y: .value("Jour", Double(6 - cell.day) + 0.5), width: .fixed(inner), height: .fixed(inner))
                    .foregroundStyle(Palette.red)
                    .cornerRadius(3 * inner / side)
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
                let hour = value.as(Double.self) ?? 0
                AxisValueLabel(anchor: hour > 23 ? .topTrailing : .top, collisionResolution: .disabled) { axisText("\(Int(hour)) h") }
            }
        }
        .chartOverlay { proxy in
            ZStack {
                TapLayer(proxy: proxy) { point in
                    guard let hour = proxy.value(atX: point.x, as: Double.self), let row = proxy.value(atY: point.y, as: Double.self), row >= 0, hour >= 0 else { focus = nil; return }
                    let cell = (day: 6 - Int(row), hour: Int(hour))
                    guard (0..<7).contains(cell.day), (0..<24).contains(cell.hour), rows[cell.day][cell.hour] > 0 else { focus = nil; return }
                    focus = selected.map { $0.day == cell.day && $0.hour == cell.hour } == true ? nil : .cell(day: cell.day, hour: cell.hour)
                }
                if let selected {
                    PlacedTip(proxy: proxy, x: proxy.position(forX: Double(selected.hour) + 0.5), y: proxy.position(forY: 7.0),
                              tip: ChartTip(title: "\(weekdays[selected.day]), de \(selected.hour) h à \(selected.hour + 1) h", detail: plural(rows[selected.day][selected.hour], "départ")))
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .frame(height: 7 * cellHeight + 20)
        .accessibilityLabel("Départs selon le jour et l’heure, le plus souvent le \(weekdays[busiest.day].lowercased()) entre \(busiest.hour) h et \(busiest.hour + 1) h")
    }
}

private struct BikeTypes: View {
    let data: PeriodStats
    @Binding var focus: ChartFocus?

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
            Part(key: "mechanical", label: "Mécanique", spoken: "en mécanique", count: data.bikeTypes.mechanical, color: Color(hex: 0xe9e4e4)),
            Part(key: "unknown", label: "Non renseigné", spoken: "sans type connu", count: data.bikeTypes.unknown, color: Palette.mist)
        ].filter { $0.count > 0 }
        let selected: String? = if case .part(let key) = focus { key } else { nil }
        let total = max(1, data.trips)
        let share = { (count: Int) in "\(Int((Double(count) / Double(total) * 100).rounded()))\u{a0}%" }
        let size: CGFloat = 152
        let thickness: CGFloat = 22
        VStack(spacing: 20) {
            ZStack {
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
            .onTapGesture { focus = (selected == nil ? parts.first?.key : parts.firstIndex { $0.key == selected }.flatMap { $0 + 1 < parts.count ? parts[$0 + 1].key : nil }).map(ChartFocus.part) }
            .accessibilityLabel("Trajets \(parts.map { "\($0.spoken) à \(share($0.count))" }.joined(separator: ", "))")
            VStack(spacing: 8) {
                ForEach(parts) { part in
                    Button { focus = selected == part.key ? nil : .part(part.key) } label: {
                        HStack(spacing: 10) {
                            Circle().fill(part.color).frame(width: 10, height: 10).overlay(Circle().strokeBorder(part.key == "unknown" ? Palette.inkLine : .clear, lineWidth: 1))
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

private struct Records: View {
    let records: StatsRecords?
    @Environment(AppModel.self) private var model
    @State private var bikeOpen = false

    var body: some View {
        grid
            .sheet(isPresented: $bikeOpen) {
                if let bike = records?.bike {
                    BikeDetail(route: BikeRoute(number: bike, station: nil))
                        .presentationDetents([.large])
                        .interactiveDismissDisabled(model.operations.sending)
                        .presentationBackground(Palette.white)
                        .sheetCorners()
                }
            }
            .task(id: records?.bike) {
                guard model.snapshot == .statsBike, records?.bike != nil else { return }
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                bikeOpen = true
            }
    }

    private var grid: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 22) {
            GridRow {
                tile("Plus long trajet", first: true) { value(records.map { $0.longestMinutes.map(hours) }) }
                tile("Jour record", first: false) { value(records.map { $0.busiestDayTrips.map { plural($0, "trajet") } }) }
            }
            GridRow {
                tile("Série", first: true) { value(records.map { $0.streakDays.map { plural($0, "jour") } }) }
                tile("Vélo favori", first: false) {
                    if let bike = records?.bike {
                        Button { bikeOpen = true } label: {
                            Text(verbatim: "N° \(bike)").typo(.title(23)).foregroundStyle(Palette.ink).underline(color: Palette.inkLine)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Voir la fiche du vélo \(bike)")
                    } else {
                        value(records == nil ? nil : String??.some(nil))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func value(_ text: String??) -> some View {
        if let text {
            Text((text ?? "—").glyphic).typo(.title(23)).foregroundStyle(Palette.ink).lineLimit(1).minimumScaleFactor(0.7)
        } else {
            Text(verbatim: "12 min").typo(.title(23)).lineLimit(1).ghost()
        }
    }

    private func tile(_ label: String, first: Bool, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label).typo(.caps(13)).foregroundStyle(Palette.inkSoft).lineLimit(1)
            content()
        }
        .padding(.leading, first ? 0 : 14).padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) { if !first { Rectangle().fill(Palette.line).frame(width: 1) } }
    }
}

private struct Ranking: View {
    let items: [StationCount]
    var ghost = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                if index > 0 { Hairline() }
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(index + 1)").typo(.label(13)).foregroundStyle(Palette.inkSoft).frame(width: 18, alignment: .leading)
                    Text(item.name).typo(.body(15)).foregroundStyle(Palette.ink).lineLimit(1).truncationMode(.tail).ghost(ghost)
                    Spacer(minLength: 0)
                    Text(number(item.count)).typo(.label(13)).foregroundStyle(Palette.ink).ghost(ghost).accessibilityLabel("\(number(item.count)) passages")
                }
                .padding(.top, index > 0 ? 13 : 0).padding(.bottom, index < items.count - 1 ? 13 : 0)
            }
        }
    }
}
