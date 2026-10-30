import Foundation

private let utc = TimeZone(identifier: "UTC")!
private let paris = TimeZone(identifier: "Europe/Paris")!
private let french = Locale(identifier: "fr_FR")

private var utcCalendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = utc
    return calendar
}

public func utcDate(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    if value.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil {
        return calendarDay(value) != nil ? value : nil
    }
    guard let date = instant(value) else { return nil }
    return isoString(date)
}

public func cyclocityDate(_ value: String?) -> Date? {
    guard let value, !value.isEmpty else { return nil }
    if value.wholeMatch(of: /\d{4}-\d{2}-\d{2}/) != nil { return calendarDay(value) }
    return instant(value)
}

public func isoString(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    formatter.timeZone = utc
    return formatter.string(from: date)
}

private func calendarDay(_ value: String) -> Date? {
    let parts = value.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return validDate(year: parts[0], month: parts[1], day: parts[2], hour: 0, minute: 0, second: 0)
}

private func validDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date? {
    let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    let calendar = utcCalendar
    guard let date = calendar.date(from: components) else { return nil }
    let back = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    guard back.year == year, back.month == month, back.day == day, back.hour == hour, back.minute == minute, back.second == second else { return nil }
    return date
}

private func instant(_ value: String) -> Date? {
    let pattern = /(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?(Z|([+-])(\d{2}):?(\d{2}))?/
    guard let match = value.wholeMatch(of: pattern) else { return nil }
    let output = match.output
    guard let date = validDate(year: Int(output.1)!, month: Int(output.2)!, day: Int(output.3)!, hour: Int(output.4)!, minute: Int(output.5)!, second: output.6.map { Int($0)! } ?? 0) else { return nil }
    var milliseconds = 0.0
    if let fraction = output.7 { milliseconds = Double(String(fraction.prefix(3)).padding(toLength: 3, withPad: "0", startingAt: 0))! }
    var offset = 0
    if let sign = output.9, let hours = output.10, let minutes = output.11 {
        offset = (Int(hours)! * 60 + Int(minutes)!) * 60 * (sign == "-" ? -1 : 1)
    }
    return date.addingTimeInterval(milliseconds / 1000 - Double(offset))
}

public enum DateStyle: String, Sendable {
    case dayMonth = "dMMM"
    case dayMonthYear = "dMMMy"
    case dayLongMonthYear = "dMMMMy"
    case time = "HHmm"
    case dayMonthYearTime = "dMMMyHHmm"
    case dayLongMonthYearTime = "dMMMMyHHmm"
}

private final class FormatterCache: @unchecked Sendable {
    private var formatters: [String: DateFormatter] = [:]
    private let lock = NSLock()

    func string(_ date: Date, template: String) -> String {
        lock.lock()
        defer { lock.unlock() }
        let formatter = formatters[template] ?? {
            let formatter = DateFormatter()
            formatter.locale = french
            formatter.timeZone = paris
            formatter.setLocalizedDateFormatFromTemplate(template)
            formatters[template] = formatter
            return formatter
        }()
        return formatter.string(from: date)
    }
}

private let formatterCache = FormatterCache()

public func formatDate(_ date: Date?, _ style: DateStyle = .dayMonth) -> String {
    guard let date else { return "Date indisponible" }
    if style == .dayMonthYearTime { return "\(formatDate(date, .dayMonthYear)), \(formatDate(date, .time))" }
    return formatterCache.string(date, template: style.rawValue)
}

public func fromNow(_ date: Date?, now: Date = Date()) -> String? {
    guard let date else { return nil }
    let minutes = date.timeIntervalSince(now) / 60
    var amount = abs(minutes)
    if amount < 1 { return "à l’instant" }
    let steps: [(Calendar.Component, Double)] = [(.minute, 60), (.hour, 24), (.day, 30), (.month, 12), (.year, .infinity)]
    let sign = minutes < 0 ? -1 : 1
    for (unit, size) in steps {
        if amount < size {
            let value = sign * Int(amount.rounded(.down))
            var components = DateComponents()
            components.setValue(value, for: unit)
            let formatter = RelativeDateTimeFormatter()
            formatter.locale = french
            formatter.unitsStyle = unit == .month || unit == .year ? .full : .short
            return formatter.localizedString(from: components)
        }
        amount /= size
    }
    return nil
}

public func clock(_ seconds: Int) -> String {
    String(format: "%02d:%02d", max(0, seconds) / 60, max(0, seconds) % 60)
}
