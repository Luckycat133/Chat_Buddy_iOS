import SwiftUI
import SwiftData

/// Chats root view per skill §"Root navigation" + §"Chats tab".
///
///   - Default landing destination (replaces Dashboard).
///   - Pull-to-refresh triggers delta sync, not a full reload.
///   - Connection/offline banner only when relevant.
///   - Proactive messages look identical to incoming friend messages.
public struct ChatsRootView: View {
    @EnvironmentObject private var app: CloudAppState
    @State private var conversations: [ConversationRepository.ConversationListItem] = []
    @State private var isRefreshing = false
    @State private var error: String?

    public init() {}

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle("Chats")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            Task { await refresh() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityLabel("Refresh")
                    }
                }
                .refreshable { await refresh() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 36))
                Text(error).multilineTextAlignment(.center)
                Button("Retry") { Task { await refresh() } }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
        } else if conversations.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 36))
                Text("No conversations yet.")
                Text("Mira will reach out as soon as you sign in.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        } else {
            List(conversations) { item in
                ChatRow(item: item)
            }
            .listStyle(.plain)
        }
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            conversations = try await app.conversations.listConversations()
            error = nil
        } catch {
            self.error = String(describing: error)
        }
    }
}

private struct ChatRow: View {
    let item: ConversationRepository.ConversationListItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 4) {
                Text(item.publicName ?? typeLabel)
                    .font(.headline)
                Text(item.lastMessagePreview ?? "Tap to start")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            if item.unreadCount > 0 {
                Text("\(item.unreadCount)")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.tint, in: Capsule())
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var typeLabel: String {
        item.type == "group" ? "Group" : "Chat"
    }

    private var avatar: some View {
        Circle()
            .fill(.quaternary)
            .frame(width: 44, height: 44)
            .overlay(
                Text(initials)
                    .font(.headline)
                    .foregroundStyle(.secondary),
            )
    }

    private var initials: String {
        let label = item.publicName ?? typeLabel
        let parts = label.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first }.map(String.init).joined()
    }
}