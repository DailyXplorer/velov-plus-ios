import CoreText
import SwiftUI
import UIKit

enum Palette {
    static let red = Color(hex: 0xdf2537)
    static let redDeep = Color(hex: 0xc91f30)
    static let redTint = Color(hex: 0xf9e0e3)
    static let ink = Color(hex: 0x1c1717)
    static let inkSoft = Color(hex: 0x1c1717, opacity: 0.72)
    static let inkMuted = Color(hex: 0x1c1717, opacity: 0.6)
    static let inkLine = Color(hex: 0x1c1717, opacity: 0.12)
    static let line = Color(hex: 0x1c1717, opacity: 0.08)
    static let secondaryRing = Color(hex: 0x1c1717, opacity: 0.3)
    static let mist = Color(hex: 0xf5f2f2)
    static let white = Color.white
    static let onDark = Color.white.opacity(0.7)
    static let formError = Color(hex: 0xb62938)
    static let notice = Color(hex: 0x9e5b50)
    static let dataNotice = Color(hex: 0x9c7856)
    static let radius: CGFloat = 16
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: opacity)
    }
}

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

    static func font(_ file: String, size: CGFloat, weight: CGFloat? = nil, optical: Bool = false) -> Font {
        let key = "\(file)|\(size)|\(weight ?? 0)|\(optical)"
        if let cached = cache[key] { return cached }
        register()
        guard let name = names[file] else { return .system(size: size) }
        defer { cache[key] = makeFont(name, size: size, weight: weight, optical: optical) }
        return makeFont(name, size: size, weight: weight, optical: optical)
    }

    private static func makeFont(_ name: String, size: CGFloat, weight: CGFloat?, optical: Bool) -> Font {
        var variation: [Int: CGFloat] = [:]
        if let weight { variation[weightAxis] = weight }
        if optical { variation[opticalAxis] = min(max(size, 9), 40) }
        var attributes: [CFString: Any] = [kCTFontNameAttribute: name]
        if !variation.isEmpty { attributes[kCTFontVariationAttribute] = variation as CFDictionary }
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }
}

enum Typo {
    case title(CGFloat)
    case body(CGFloat, medium: Bool = false)
    case label(CGFloat)
    case caps(CGFloat)
    case countdown(CGFloat)

    var font: Font {
        switch self {
        case .title(let size), .countdown(let size): FontBook.font("FacultyGlyphic-Regular", size: size)
        case .body(let size, let medium): FontBook.font("DMSans", size: size, weight: medium ? 500 : 400, optical: true)
        case .label(let size), .caps(let size): FontBook.font("DMSans", size: size, weight: 500, optical: true)
        }
    }

    var tracking: CGFloat {
        switch self {
        case .title(let size): -0.03 * size
        case .caps(let size): 0.02 * size
        case .body(let size, _), .label(let size), .countdown(let size): -0.02 * size
        }
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
        case .countdown: content.font(typo.font).tracking(typo.tracking).monospacedDigit()
        case .caps: content.font(typo.font).tracking(typo.tracking).textCase(.uppercase)
        default: content.font(typo.font).tracking(typo.tracking).textCase(nil)
        }
    }
}
