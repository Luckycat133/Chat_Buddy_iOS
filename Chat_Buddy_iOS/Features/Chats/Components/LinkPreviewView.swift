import SwiftUI

/// Extracts URLs from text and renders a preview card with domain, favicon, and open action.
struct LinkPreviewView: View {
    let url: URL
    let isUser: Bool

    var body: some View {
        Button {
            UIApplication.shared.open(url)
        } label: {
            HStack(spacing: DSSpacing.sm) {
                // Favicon via Google
                AsyncImage(url: faviconURL) { image in
                    image.resizable().aspectRatio(contentMode: .fit)
                } placeholder: {
                    Image(systemName: "globe")
                        .foregroundStyle(isUser ? .white.opacity(0.7) : .secondary)
                }
                .frame(width: 20, height: 20)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                VStack(alignment: .leading, spacing: 2) {
                    Text(domain)
                        .font(DSTypography.caption1.weight(.semibold))
                        .foregroundStyle(isUser ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .lineLimit(1)

                    Text(url.absoluteString)
                        .font(DSTypography.caption2)
                        .foregroundStyle(isUser ? AnyShapeStyle(.white.opacity(0.7)) : AnyShapeStyle(.secondary))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "arrow.up.right.square")
                    .font(.caption)
                    .foregroundStyle(isUser ? .white.opacity(0.7) : .secondary)
            }
            .padding(DSSpacing.sm)
            .background(
                (isUser ? Color.white.opacity(0.15) : Color.secondary.opacity(0.08)),
                in: RoundedRectangle(cornerRadius: DSRadius.sm)
            )
        }
        .buttonStyle(.plain)
    }

    private var domain: String {
        url.host?.replacingOccurrences(of: "www.", with: "") ?? url.absoluteString
    }

    private var faviconURL: URL? {
        guard let host = url.host else { return nil }
        return URL(string: "https://www.google.com/s2/favicons?domain=\(host)&sz=64")
    }

    // MARK: - Static URL Detector

    /// Extracts the first HTTP(S) URL from a text string.
    static func extractURL(from text: String) -> URL? {
        let pattern = "https?://[\\w\\-._~:/?#\\[\\]@!$&'()*+,;=%]+"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else {
            return nil
        }
        return URL(string: String(text[range]))
    }
}
