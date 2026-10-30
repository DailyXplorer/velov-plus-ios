import Foundation

public enum Verdict: Int, Sendable, Comparable {
    case recommended = 0, neutral = 1, avoid = 2
    public static func < (left: Verdict, right: Verdict) -> Bool { left.rawValue < right.rawValue }
}

public struct AssessedBike: Equatable, Sendable, Identifiable {
    public var bike: Bike
    public var verdict: Verdict
    public var score: Double
    public var reasons: [String]
    public var id: Int { bike.number }
}

private let hour: TimeInterval = 3600

private func hoursSince(_ date: Date?, _ now: Date) -> Double? {
    date.map { now.timeIntervalSince($0) / hour }
}

private let overdueGrace: TimeInterval = 30 * 24 * hour

public func isCheckOverdue(_ bike: Bike, now: Date = Date()) -> Bool {
    guard let next = bike.nextCheckAt else { return false }
    return now.timeIntervalSince(next) > overdueGrace
}

public struct StackedText: Equatable, Sendable {
    public let value: String
    public let detail: String?
}

public func upcomingText(_ next: Date?, relative: Bool = true, now: Date = Date()) -> StackedText? {
    guard let next else { return nil }
    if next < now { return StackedText(value: "En retard", detail: "Prévu le \(formatDate(next, .dayMonthYear))") }
    guard relative else { return StackedText(value: formatDate(next, .dayMonthYear), detail: nil) }
    return StackedText(value: capitalize(fromNow(next, now: now) ?? ""), detail: formatDate(next, .dayMonthYearTime))
}

private func avoidReasons(_ bike: Bike, _ now: Date) -> [String] {
    var reasons: [String] = []
    let idle = hoursSince(bike.lastTripAt, now)
    if bike.isReserved { reasons.append("Réservé") }
    if let status = bike.status, status != "AVAILABLE" {
        reasons.append(bike.statusLabel.map { $0.isEmpty ? "Indisponible" : "Indisponible (\($0))" } ?? "Indisponible")
    }
    if let rating = bike.rating, rating.value < 60, rating.count >= 5 { reasons.append("Note basse (\(outOfFive(rating.value))/5)") }
    if isCheckOverdue(bike, now: now) { reasons.append("Contrôle en retard") }
    if bike.type == .electrical, let battery = bike.batteryPercent, battery < 20 { reasons.append("Batterie faible (\(battery) %)") }
    if let idle, idle > 72 { reasons.append("Pas utilisé depuis \(Int((idle / 24).rounded(.down))) j") }
    return reasons
}

private func scoreBike(_ bike: Bike, _ now: Date) -> Double {
    let weight = Double(min(bike.rating?.count ?? 0, 20)) / 20
    let idle = hoursSince(bike.lastTripAt, now)
    return (bike.rating?.value ?? 0) * weight + 70 * (1 - weight)
        + (idle.map { $0 < 12 } == true ? 5 : 0)
        + (bike.type == .electrical ? Double(bike.batteryPercent ?? 0) / 10 : 0)
}

private func strengths(_ bike: Bike, _ now: Date) -> [String] {
    let idle = hoursSince(bike.lastTripAt, now)
    return [
        bike.rating.map { "Bien noté (\(outOfFive($0.value))/5 · \($0.count) avis)" },
        bike.type == .electrical ? bike.batteryPercent.map { "Batterie \($0) %" } : nil,
        idle.map { $0 < 12 } == true ? "Utilisé il y a moins de 12 h" : nil
    ].compactMap { $0 }
}

public func assessBikes(_ bikes: [Bike], now: Date = Date()) -> [AssessedBike] {
    var assessed = bikes.map { bike -> AssessedBike in
        let reasons = avoidReasons(bike, now)
        return AssessedBike(bike: bike, verdict: reasons.isEmpty ? .neutral : .avoid, score: scoreBike(bike, now), reasons: reasons)
    }
    for type in [Bike.Kind.mechanical, .electrical] {
        var best: Int?
        for (index, item) in assessed.enumerated() {
            guard item.bike.type == type, item.verdict != .avoid, let rating = item.bike.rating, rating.count >= 3, rating.value >= 75 else { continue }
            if best == nil || item.score > assessed[best!].score { best = index }
        }
        guard let best else { continue }
        assessed[best].verdict = .recommended
        assessed[best].reasons = strengths(assessed[best].bike, now)
    }
    return assessed.enumerated().sorted { left, right in
        if left.element.verdict != right.element.verdict { return left.element.verdict < right.element.verdict }
        if left.element.verdict != .avoid, left.element.score != right.element.score { return left.element.score > right.element.score }
        return left.offset < right.offset
    }.map(\.element)
}
