import SwiftUI

// MARK: - Image Message

/// Displays an image message with a lightbox tap-to-zoom gesture.
struct ImageMessageView: View {
    let base64Data: String
    let isUser: Bool

    @State private var showLightbox = false

    var body: some View {
        if let data = Data(base64Encoded: base64Data),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(maxWidth: 240, maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.md))
                .onTapGesture { showLightbox = true }
                .fullScreenCover(isPresented: $showLightbox) {
                    ImageLightboxView(image: uiImage) { showLightbox = false }
                }
        } else {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "photo")
                Text("Image")
                    .font(DSTypography.caption1)
            }
            .foregroundStyle(isUser ? .white : .secondary)
        }
    }
}

/// Full‑screen lightbox with pinch‑to‑zoom.
private struct ImageLightboxView: View {
    let image: UIImage
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .scaleEffect(scale)
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in scale = max(0.5, min(3.0, value.magnification)) }
                        .onEnded { _ in withAnimation { scale = 1 } }
                )
                .onTapGesture(count: 2) {
                    withAnimation { scale = scale > 1 ? 1 : 2 }
                }

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .foregroundStyle(.white.opacity(0.8))
                    .padding()
            }
        }
    }
}

// MARK: - File Message

/// Displays a file attachment preview with icon and metadata.
struct FileMessageView: View {
    let fileName: String
    let fileSize: Int
    let previewText: String?
    let isUser: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: fileIcon)
                    .font(.title3)
                    .foregroundStyle(isUser ? .white.opacity(0.9) : .accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(fileName)
                        .font(DSTypography.footnote.weight(.semibold))
                        .foregroundStyle(isUser ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .lineLimit(1)

                    Text(formatFileSize(fileSize))
                        .font(DSTypography.caption2)
                        .foregroundStyle(isUser ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                }
            }

            if let preview = previewText, !preview.isEmpty {
                Text(String(preview.prefix(200)))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(isUser ? AnyShapeStyle(.white.opacity(0.7)) : AnyShapeStyle(.secondary))
                    .lineLimit(4)
            }
        }
    }

    private var fileIcon: String {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "txt", "md":          return "doc.text"
        case "json":               return "curlybraces"
        case "js", "ts", "py", "swift": return "chevron.left.forwardslash.chevron.right"
        case "html", "xml":        return "globe"
        case "css":                return "paintbrush"
        case "csv":                return "tablecells"
        case "yaml", "yml":        return "list.bullet"
        case "pdf":                return "doc.richtext"
        case "zip", "rar", "gz":   return "doc.zipper"
        default:                   return "doc"
        }
    }

    private func formatFileSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1_048_576 { return String(format: "%.1f KB", Double(bytes) / 1024.0) }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
    }
}

// MARK: - Voice Message

/// Simulated voice waveform player with animated bars.
struct VoiceMessageView: View {
    let duration: TimeInterval
    let isUser: Bool

    @State private var isPlaying = false
    @State private var progress: Double = 0
    @State private var timer: Timer?
    @State private var barHeights: [CGFloat] = (0..<16).map { _ in CGFloat.random(in: 0.2...0.8) }

    var body: some View {
        HStack(spacing: DSSpacing.sm) {
            Button {
                togglePlayback()
            } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.body)
                    .foregroundStyle(isUser ? .white : .accentColor)
            }
            .buttonStyle(.plain)

            // Waveform bars
            HStack(spacing: 2) {
                ForEach(0..<barHeights.count, id: \.self) { i in
                    let barProgress = Double(i) / Double(barHeights.count)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(barProgress <= progress
                              ? (isUser ? Color.white : Color.accentColor)
                              : (isUser ? Color.white.opacity(0.4) : Color.secondary.opacity(0.3)))
                        .frame(width: 3, height: 20 * barHeights[i])
                }
            }
            .frame(height: 20)

            Text(formatDuration(duration))
                .font(DSTypography.caption2)
                .foregroundStyle(isUser ? .white.opacity(0.85) : .secondary)
                .monospacedDigit()
        }
    }

    private func togglePlayback() {
        if isPlaying {
            timer?.invalidate()
            timer = nil
            isPlaying = false
        } else {
            isPlaying = true
            progress = 0
            let interval = 0.1
            let increment = interval / duration
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { t in
                progress += increment
                if progress >= 1.0 {
                    t.invalidate()
                    timer = nil
                    isPlaying = false
                    progress = 0
                }
            }
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
