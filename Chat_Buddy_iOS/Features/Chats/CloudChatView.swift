import SwiftUI
import SwiftData

/// Cloud-backed chat view per skill §"Chat UI".
///
///   - Replaces the legacy `ChatView` (which routes through `ChatStore`
///     and `AIPipeline`) when the cloud runtime is enabled.
///   - Uses `CloudChatViewModel` for sending/receiving and SwiftData
///     cache for offline render.
///   - Streaming AI messages arrive via `RealtimeClient`; the local
///     placeholder is updated in place until the server message replaces
///     it.
///   - Composer never blocks while AI replies; rapid messages flow.
public struct CloudChatView: View {
    @StateObject private var viewModel: CloudChatViewModel
    @EnvironmentObject private var cloud: CloudAppState

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
        // The view surfaces only the public name; private remark is
        // never shown to other actors per skill §"Settled product decisions".
        .navigationTitle("Chat")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Bind to the live app state once the SwiftUI environment is
            // wired, then load cached + remote messages.
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
                    ForEach(viewModel.messages, id: \.id) { message in
                        CloudMessageRow(message: message)
                            .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: viewModel.messages.last?.id) { _, newID in
                guard let newID else { return }
                withAnimation { proxy.scrollTo(newID, anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private var composer: some View {
        HStack(spacing: 8) {
            TextField(
                "Say something…",
                text: $viewModel.draft,
                axis: .vertical,
            )
            .textFieldStyle(.roundedBorder)
            .lineLimit(1...4)
            .disabled(viewModel.sending)
            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "paperplane.fill")
            }
            .disabled(viewModel.draft.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.sending)
            .accessibilityLabel("Send")
        }
        .padding()
        .background(.thinMaterial)
    }
}

private struct CloudMessageRow: View {
    let message: RemoteMessageDTO

    // Single source of truth for human-vs-character alignment, shared
    // with OnboardingChatView (see `RemoteMessageDTO.isFromHuman`).
    private var isHuman: Bool { message.isFromHuman }

    var body: some View {
        // Human messages hug the trailing (right) edge: leading Spacer.
        HStack {
            if isHuman { Spacer() }
            Text(message.content)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(isHuman ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .accessibilityLabel(Text("\(isHuman ? "You" : "Contact") said \(message.content)"))
            if !isHuman { Spacer() }
        }
    }
}