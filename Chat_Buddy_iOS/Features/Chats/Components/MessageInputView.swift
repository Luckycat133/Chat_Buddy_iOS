import SwiftUI

/// Chat message input bar with multiline text field and send button
struct MessageInputView: View {
    @Binding var text: String
    let placeholder: String
    let isDisabled: Bool
    let onSend: () -> Void
    var quotedMessage: ChatMessage? = nil
    var quotedSenderName: String = ""
    var quotedAccentColor: Color = .accentColor
    var onClearQuote: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            if let quoted = quotedMessage {
                QuotedMessageView(
                    senderName: quotedSenderName,
                    content: quoted.content,
                    accentColor: quotedAccentColor,
                    onClear: onClearQuote
                )
                .padding(.horizontal, DSSpacing.md)
                .padding(.top, DSSpacing.sm)
                .padding(.bottom, DSSpacing.xxs)
            }

            HStack(alignment: .bottom, spacing: DSSpacing.sm) {
                TextField(placeholder, text: $text, axis: .vertical)
                    .font(DSTypography.body)
                    .lineLimit(1...5)
                    .padding(.horizontal, DSSpacing.sm)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: DSRadius.lg))
                    .disabled(isDisabled)

                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.35))
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().opacity(0.3)
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isDisabled
    }
}
