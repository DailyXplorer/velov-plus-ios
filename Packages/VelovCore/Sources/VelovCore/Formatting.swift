import Foundation

private let french = Locale(identifier: "fr_FR")

/// "2002 - SAINT-EXUPÉRY / GARE D’OULLINS" -> "Saint-Exupéry / Gare d’Oullins": each word, hyphen part and elided word capitalised, inner d’ and l’ kept low.
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
    // " D’Oullins" -> " d’Oullins": only after a space, so a leading "L’Arbresle" keeps its capital.
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

/// "1,80 €" from cents.
public func formatPrice(_ cents: Double) -> String {
    numberFormatter { $0.numberStyle = .currency; $0.currencyCode = "EUR" }.string(from: NSNumber(value: cents / 100)) ?? "\(cents / 100) €"
}

/// "1 234" with the French grouping.
public func formatNumber(_ value: Double, maximumFractionDigits: Int = 3, minimumFractionDigits: Int = 0) -> String {
    numberFormatter {
        $0.numberStyle = .decimal
        $0.maximumFractionDigits = maximumFractionDigits
        $0.minimumFractionDigits = minimumFractionDigits
    }.string(from: NSNumber(value: value)) ?? String(value)
}

/// "il y a 3 h" -> "Il y a 3 h": a generated text that opens a line or follows a separator.
public func capitalize(_ text: String) -> String {
    guard let first = text.first else { return text }
    return String(first).uppercased(with: french) + text.dropFirst()
}

/// "350 m", "1,2 km", "14 km".
public func formatDistance(_ metres: Double) -> String {
    if metres < 1000 { return "\(max(10, Int((metres / 10).rounded()) * 10)) m" }
    return "\(formatNumber(metres / 1000, maximumFractionDigits: metres < 10_000 ? 1 : 0)) km"
}

/// A rating out of 100 as a mark out of 5 with one decimal: "4,6".
public func outOfFive(_ value: Double) -> String {
    formatNumber(value / 20, maximumFractionDigits: 1, minimumFractionDigits: 1)
}

/// Card headline: plan name without the brand prefix and payment suffix ("Vélo’v Plus 1 an Jeunes – paiement comptant" -> "Plus 1 an Jeunes").
public func shortPlan(_ title: String?) -> String {
    guard let title else { return "Aucun" }
    let head = title.split(separator: /\s[–-]\s/, maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? title
    let short = head.replacing(/^(?i)V[ée]lo[’']v\s+/, with: "")
    return short.isEmpty ? title : short
}
