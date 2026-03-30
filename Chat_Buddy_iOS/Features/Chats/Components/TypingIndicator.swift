import SwiftUI

/// Animated three-dot typing indicator shown while the AI is generating a response
struct TypingIndicator: View {
    let persona: Persona
    @Environment(ThemeManager.self) private var themeManager
    @State private var animating = false

    private var shouldAnimate: Bool {
        animating && themeManager.animationIntensity != .none
    }

    private var dotAnimation: Animation {
        let multiplier = max(0.35, themeManager.animationIntensity.durationMultiplier)
        return .easeInOut(duration: 0.4 / multiplier).repeatForever()
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: DSSpacing.xs) {
            // Persona avatar
            Circle()
                .fill(persona.accentColor.opacity(0.18))
                .frame(width: 30, height: 30)
                .overlay(
                    Text(String(persona.name.prefix(1)))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(persona.accentColor)
                )

            // Bouncing dots
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: 7, height: 7)
                        .offset(y: shouldAnimate ? -5 : 0)
                        .animation(
                            dotAnimation
                                .delay(Double(i) * 0.13),
                            value: shouldAnimate
                        )
                }
            }
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.xs)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DSRadius.lg))

            Spacer()
        }
        .onAppear { animating = true }
        .onDisappear { animating = false }
    }
}
