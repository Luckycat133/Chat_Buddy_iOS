import SwiftUI

/// A view modifier that applies a glass-like frosted effect.
/// Uses .glassEffect on iOS 26+ and falls back to .ultraThinMaterial on older versions.
struct LiquidGlassModifier: ViewModifier {
    var cornerRadius: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius))
        }
    }
}

extension View {
    /// Apply a liquid glass / frosted glass effect
    func liquidGlass(cornerRadius: CGFloat = DSRadius.lg) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius))
    }
}
