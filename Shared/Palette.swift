import SwiftUI

enum Palette {
    static let red = Color(hex: 0xdf2537)
    static let redDeep = Color(hex: 0xc91f30)
    static let ink = Color(hex: 0x1c1717)
    static let inkSoft = Color(hex: 0x1c1717, opacity: 0.72)
    static let inkLine = Color(hex: 0x1c1717, opacity: 0.12)
    static let line = Color(hex: 0x1c1717, opacity: 0.08)
    static let secondaryRing = Color(hex: 0x1c1717, opacity: 0.3)
    static let disabledInk = secondaryRing
    static let mist = Color(hex: 0xf5f2f2)
    static let segment = Color(hex: 0xe9e4e4)
    static let segmentSelected = Color(hex: 0xd6cfcf)
    static let white = Color.white
    static let formError = Color(hex: 0xb62938)
    static let radius: CGFloat = 16
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(red: Double(hex >> 16 & 0xff) / 255, green: Double(hex >> 8 & 0xff) / 255, blue: Double(hex & 0xff) / 255, opacity: opacity)
    }
}
