import CoreText
import SwiftUI
import UIKit

enum FontBook {
    private static var names: [String: String] = [:]

    static func register() {
        guard names.isEmpty else { return }
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            if let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider), let name = font.postScriptName as String? {
                names[url.deletingPathExtension().lastPathComponent] = name
            }
        }
    }

    private static let weightAxis = 0x77676874
    private static let opticalAxis = 0x6f70737a

    private static var cache: [String: Font] = [:]

    static func font(_ file: String, size: CGFloat, weight: CGFloat? = nil, optical: Bool = false, proportional: Bool = false) -> Font {
        let key = "\(file)|\(size)|\(weight ?? 0)|\(optical)|\(proportional)"
        if let cached = cache[key] { return cached }
        register()
        guard let name = names[file] else {
            assertionFailure("Missing bundled font \(file)")
            return .system(size: size)
        }
        defer { cache[key] = makeFont(name, size: size, weight: weight, optical: optical, proportional: proportional) }
        return makeFont(name, size: size, weight: weight, optical: optical, proportional: proportional)
    }

    private static func makeFont(_ name: String, size: CGFloat, weight: CGFloat?, optical: Bool, proportional: Bool) -> Font {
        var variation: [Int: CGFloat] = [:]
        if let weight { variation[weightAxis] = weight }
        if optical { variation[opticalAxis] = min(max(size, 9), 40) }
        var attributes: [CFString: Any] = [kCTFontNameAttribute: name]
        if !variation.isEmpty { attributes[kCTFontVariationAttribute] = variation as CFDictionary }
        if proportional { attributes[kCTFontFeatureSettingsAttribute] = ActivityStyle.proportionalFigures }
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }
}

enum Typo {
    enum Title: CGFloat { case display = 48, figure = 40, figureS = 32, page = 28, section = 24, card = 20, small = 18, unit = 15 }
    enum Text: CGFloat { case input = 16, lead = 15, base = 14, small = 13, meta = 12, micro = 11 }
    enum Caps: CGFloat { case button = 14, label = 13, tag = 12 }

    case title(Title)
    case body(Text, medium: Bool = false)
    case label(Text)
    case caps(Caps)
    case countdown

    var size: CGFloat {
        switch self {
        case .title(let role): role.rawValue
        case .body(let role, _), .label(let role): role.rawValue
        case .caps(let role): role.rawValue
        case .countdown: 26
        }
    }

    var font: Font {
        switch self {
        case .title, .countdown: FontBook.font("VelovGlyphic-Regular", size: size, proportional: true)
        case .body(_, let medium): FontBook.font("DMSans", size: size, weight: medium ? 500 : 400, optical: true)
        case .label, .caps: FontBook.font("DMSans", size: size, weight: 500, optical: true)
        }
    }

    var tracking: CGFloat {
        switch self {
        case .title: -0.03 * size
        case .caps: 0.02 * size
        case .body, .label, .countdown: -0.02 * size
        }
    }
}

extension String {
    var glyphic: String {
        replacingOccurrences(of: "(?<=\\d)\u{00A0}(?=\\d)", with: "\u{202F}", options: .regularExpression)
    }
}

extension View {
    func typo(_ typo: Typo) -> some View {
        modifier(TypoModifier(typo: typo))
    }
}

private struct TypoModifier: ViewModifier {
    let typo: Typo
    func body(content: Content) -> some View {
        switch typo {
        case .caps: content.font(typo.font).tracking(typo.tracking).textCase(.uppercase)
        default: content.font(typo.font).tracking(typo.tracking).textCase(nil)
        }
    }
}
