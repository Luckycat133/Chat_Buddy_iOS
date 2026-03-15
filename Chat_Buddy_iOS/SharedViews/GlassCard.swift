import SwiftUI

/// A reusable glass-styled card container
struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat
    @ViewBuilder var content: () -> Content

    init(cornerRadius: CGFloat = DSRadius.lg, @ViewBuilder content: @escaping () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content
    }

    var body: some View {
        content()
            .padding(DSSpacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(cornerRadius: cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
    }
}
