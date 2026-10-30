import CoreText
import Foundation
import XCTest

final class BundledFontTests: XCTestCase {
    private let fonts = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "App/Resources/Fonts")

    private func font(_ file: String, size: CGFloat = 40) throws -> CTFont {
        let url = fonts.appending(path: "\(file).ttf")
        let descriptors = try XCTUnwrap(CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor], "\(file) does not load")
        let descriptor = try XCTUnwrap(descriptors.first, "\(file) has no face")
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    private func advance(_ font: CTFont, _ scalar: UInt16) -> CGFloat? {
        var characters = [scalar]
        var glyphs = [CGGlyph(0)]
        guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, 1), glyphs[0] != 0 else { return nil }
        return CTFontGetAdvancesForGlyphs(font, .horizontal, &glyphs, nil, 1)
    }

    func testEveryBundledFontResolves() throws {
        for (file, name) in [("DMSans", "DMSans"), ("VelovGlyphic-Regular", "VelovGlyphic-Regular"), ("VelovGlyphicTimer-Regular", "VelovGlyphicTimer-Regular")] {
            XCTAssertTrue((CTFontCopyPostScriptName(try font(file)) as String).hasPrefix(name), file)
        }
    }

    func testGlyphicThousandsSeparatorHasVisibleWidth() throws {
        let glyphic = try font("VelovGlyphic-Regular")
        let thin = try XCTUnwrap(advance(glyphic, 0x202F), "U+202F missing")
        let digit = try XCTUnwrap(advance(glyphic, 0x0030))
        XCTAssertGreaterThan(thin, digit * 0.15)
    }
}
