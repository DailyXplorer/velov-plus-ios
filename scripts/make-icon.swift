import AppKit
import CoreText

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let fontURL = root.appendingPathComponent("App/Resources/Fonts/VelovGlyphic-Regular.ttf")
let set = root.appendingPathComponent("App/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.setFillColor(CGColor(srgbRed: 0xdf / 255, green: 0x25 / 255, blue: 0x37 / 255, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
for x in stride(from: 16, to: size, by: 32) {
    for y in stride(from: 16, to: size / 2, by: 32) {
        context.setFillColor(CGColor(gray: 1, alpha: 0.22 * (1 - Double(y) / Double(size / 2))))
        context.fillEllipse(in: CGRect(x: x - 4, y: y - 4, width: 8, height: 8))
    }
}
let font = CTFontCreateWithName("VelovGlyphic-Regular" as CFString, 220, nil)
let text = NSAttributedString(string: "Vélo’v+", attributes: [.font: font, .foregroundColor: CGColor(gray: 1, alpha: 1), .kern: -7.5])
let line = CTLineCreateWithAttributedString(text)
let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
context.textPosition = CGPoint(x: (CGFloat(size) - bounds.width) / 2 - bounds.minX, y: (CGFloat(size) - bounds.height) / 2 - bounds.minY)
CTLineDraw(line, context)
let image = context.makeImage()!
let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
try png.write(to: set.appendingPathComponent("AppIcon.png"))
let contents = #"{"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}"#
try contents.write(to: set.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("App/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
