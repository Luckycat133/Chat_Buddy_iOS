import SwiftUI
import SwiftData

/// Cloud-backed chat view per skill §"Chat UI":
///
///   - Optimistic local messages: rows appear instantly as `queued`.
///   - The composer NEVER locks while an AI is responding; rapid
///     consecutive sends flow as individual messages (server closes the
///     burst — no local AI decisions).
///   - Failed sends stay visible with a retry affordance.
///   - Cache-first timeline; server refresh + realtime deltas reconcile.
public struct CloudChatView: View {
    @StateObject private var viewModel: CloudChatViewModel
    @EnvironmentObject private var cloud: CloudAppState
    @Environment(LocalizationManager.self) private var loc

    public let conversationId: String

    public init(conversationId: String) {
        self.conversationId = conversationId
        _viewModel = StateObject(
            wrappedValue: CloudChatViewModel(conversationId: conversationId, app: nil),
        )
    }

    public var body: some View {
        VStack(spacing: 0) {
            timeline
            Divider()
            composer
        }
        .navigationTitle(viewModel.conversationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.bind(app: cloud)
            await viewModel.load()
        }
    }

    @ViewBuilder
    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if let error = viewModel.error {
                        Label(error, systemImage: "exclamationmark.bubble")
                            .foregroundStyle(.red)
                    }
                    ForEach(viewModel.rows) { row in
                        CloudMessageRow(row: row) {
                            Task { await viewModel.retry(row: row) }
                        }
                        .id(row.id)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.rows.last?.id) { _, newID in
                guard let newID else { return }
                withAnimation { proxy.scrollTo(newID, anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private var composer: some View {
        HStack(spacing: 8) {
            TextField(
                loc.t("cloud_chat_composer_hint"),
                text: $viewModel.draft,
                axis: .vertical,
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...4)
            // NOTE: never disabled by AI activity; only by nothing to send.
            .accessibilityLabel(loc.t("cloud_chat_composer_a11y"))
            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "paperplane.fill")
            }
            .disabled(!viewModel.canSend)
            .accessibilityLabel(loc.t("cloud_chat_send_a11y"))
        }
        .padding()
        .background(.thinMaterial)
    }
}

private struct CloudMessageRow: View {
    let row: ChatRowModel
    let onRetry: () -> Void
    @Environment(LocalizationManager.self) private var loc

    private var isHuman: Bool { row.isFromHuman }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isHuman { Spacer() }
            if !isHuman {
                statusAccessory
            }
            Text(row.content)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isHuman ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel(
                    Text("\(isHuman ? loc.t("cloud_chat_a11y_you") : loc.t("cloud_chat_a11y_contact")) \(row.content)"),
                )
            if isHuman {
                statusAccessory
            }
            if !isHuman { Spacer() }
        }
    }

    /// Queued/failed markers live next to the sender's own bubbles only.
    @ViewBuilder
    private var statusAccessory: some View {
        switch row.status {
        case .delivered:
            EmptyView()
        case .queued, .sending:
            Image(systemName: "clock")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel(loc.t("cloud_chat_status_queued"))
        case .failed, .conflict:
            Button(action: onRetry) {
                Image(systemName: "exclamationmark.arrow.circlepath")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
            .accessibilityLabel(loc.t("cloud_chat_status_retry_a11y"))
        }
    }
}
