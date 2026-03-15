import SwiftUI

/// Shared avatar display for both 1v1 and group sessions.
/// - 1v1: shows a single circular initial badge.
/// - Group: shows up to 4 persona initials in a 2×2 grid (WeChat-style).
struct SessionAvatarView: View {
    let personas: [Persona]
    let size: CGFloat

    init(personas: [Persona], size: CGFloat = 48) {
        self.personas = personas
        self.size = size
    }

    var body: some View {
        if personas.count == 1, let p = personas.first {
            singleAvatar(p)
        } else {
            groupAvatar
        }
    }

    // MARK: - Single

    private func singleAvatar(_ persona: Persona) -> some View {
        ZStack {
            Circle()
                .fill(persona.accentColor.opacity(0.18))
            Circle()
                .strokeBorder(persona.accentColor.opacity(0.35), lineWidth: 1.5)
            Text(String(persona.name.prefix(1)))
                .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                .foregroundStyle(persona.accentColor)
        }
        .frame(width: size, height: size)
    }

    // MARK: - Group Grid

    private var groupAvatar: some View {
        let displayed = Array(personas.prefix(4))
        let cellSize = size * 0.46
        let gap = size * 0.04

        return ZStack {
            // Rounded square background
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: size * 0.22)
                        .strokeBorder(.white.opacity(0.15), lineWidth: 1)
                )

            let cols = displayed.count <= 2 ? 1 : 2
            VStack(spacing: gap) {
                ForEach(Array(displayed.enumerated().chunked(by: cols)), id: \.first?.offset) { row in
                    HStack(spacing: gap) {
                        ForEach(row, id: \.offset) { _, persona in
                            ZStack {
                                Circle().fill(persona.accentColor.opacity(0.25))
                                Text(String(persona.name.prefix(1)))
                                    .font(.system(size: cellSize * 0.45, weight: .semibold, design: .rounded))
                                    .foregroundStyle(persona.accentColor)
                            }
                            .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Array chunking helper

private extension Array {
    func chunked(by size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
