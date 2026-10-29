import Foundation

private let french = Locale(identifier: "fr_FR")

public func stationTitle(_ name: String) -> String {
    let stripped = name.replacing(/^\d+\s*[-–\/]\s*/, with: "")
    var characters = Array(stripped.lowercased(with: french))
    let openers: Set<Character> = ["/", "(", "-", "’", "'"]
    for index in characters.indices where characters[index].isLetter {
        let before = index == 0 ? nil : characters[index - 1]
        if before == nil || before!.isWhitespace || openers.contains(before!) {
            characters[index] = Character(String(characters[index]).uppercased(with: french))
        }
    }
    for index in characters.indices.dropFirst().dropLast(2) where "DL".contains(characters[index]) {
        if characters[index - 1].isWhitespace, "'’".contains(characters[index + 1]), characters[index + 2].isLetter {
            characters[index] = Character(characters[index].lowercased())
        }
    }
    return String(characters)
}

private func numberFormatter(_ configure: (NumberFormatter) -> Void) -> NumberFormatter {
    let formatter = NumberFormatter()
    formatter.locale = french
    configure(formatter)
    return formatter
}

public func formatPrice(_ cents: Double) -> String {
    numberFormatter { $0.numberStyle = .currency; $0.currencyCode = "EUR" }.string(from: NSNumber(value: cents / 100)) ?? "\(cents / 100) €"
}

public func formatNumber(_ value: Double, maximumFractionDigits: Int = 3, minimumFractionDigits: Int = 0) -> String {
    numberFormatter {
        $0.numberStyle = .decimal
        $0.maximumFractionDigits = maximumFractionDigits
        $0.minimumFractionDigits = minimumFractionDigits
    }.string(from: NSNumber(value: value)) ?? String(value)
}

public func capitalize(_ text: String) -> String {
    guard let first = text.first else { return text }
    return String(first).uppercased(with: french) + text.dropFirst()
}

private let particles: Set<String> = ["de", "du", "des", "la", "le"]

public func formatName(_ name: String) -> String {
    let words = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(with: french).split(whereSeparator: \.isWhitespace).map(String.init)
    return words.enumerated().map { index, word in
        if index > 0 && particles.contains(word) { return word }
        return word.split(separator: "-", omittingEmptySubsequences: false).enumerated().map { partIndex, part -> String in
            let characters = Array(part)
            if characters.count >= 3, characters[0] == "d", "’'".contains(characters[1]) {
                return (index > 0 || partIndex > 0 ? "d" : "D") + String(characters[1]) + capitalize(String(characters[2...]))
            }
            var pieces = [""]
            for character in part {
                pieces[pieces.count - 1].append(character)
                if "’'".contains(character) { pieces.append("") }
            }
            return pieces.map(capitalize).joined()
        }.joined(separator: "-")
    }.joined(separator: " ")
}

public func formatDistance(_ metres: Double) -> String {
    if metres < 1000 { return "\(max(10, Int((metres / 10).rounded()) * 10)) m" }
    return "\(formatNumber(metres / 1000, maximumFractionDigits: metres < 10_000 ? 1 : 0)) km"
}

public func outOfFive(_ value: Double) -> String {
    formatNumber(value / 20, maximumFractionDigits: 1, minimumFractionDigits: 1)
}

public func shortPlan(_ title: String?) -> String {
    guard let title else { return "Aucun" }
    let head = title.split(separator: /\s[–-]\s/, maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? title
    let short = head.replacing(/^(?i)V[ée]lo[’']v\s+/, with: "")
    return short.isEmpty ? title : short
}
