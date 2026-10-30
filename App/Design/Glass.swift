import SwiftUI

extension View {
    @ViewBuilder
    func floatingGlass<S: InsettableShape>(_ shape: S, interactive: Bool = false, fallback: Color? = nil) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular.interactive(interactive), in: shape)
        } else if let fallback {
            background(shape.fill(fallback)).overlay(shape.strokeBorder(Palette.inkLine, lineWidth: 1))
        } else {
            ringed(shape)
        }
    }
}
