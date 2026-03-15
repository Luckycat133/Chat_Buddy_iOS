import SwiftUI

/// Compact quoted-message strip shown above the text field (dismissible) or inside a bubble (read-only)
struct QuotedMessageView: View {
    let senderName: String
    let content: String
    let accentColor: Color
    var onClear: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            Capsule()
                .fill(accentColor)
                .frame(width: 3)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(senderName)
                    .font(DSTypography.caption2.weight(.semibold))
                    .foregroundStyle(accentColor)
                    .lineLimit(1)
                Text(content)
                    .font(DSTypography.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.leading, 8)
            .padding(.vertical, 4)

            Spacer(minLength: 0)

            if let onClear {
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DSRadius.sm))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.sm)
                .strokeBorder(accentColor.opacity(0.25), lineWidth: 1)
        )
    }
}
