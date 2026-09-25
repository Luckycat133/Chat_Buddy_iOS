import SwiftUI
import SwiftData

/// Chats root view per skill §"Root navigation / Chats tab":
///
///   - Default landing destination (Dashboard removed).
///   - Cache-first render; pull-to-refresh triggers a delta sync, never a
///     full reload.
///   - Unread and proactive messages are prominent (bold + badge).
///   - Search across conversation titles and last messages.
///   - Connection/offline banner only when relevant (disconnected while
///     content is cached).
///   - Proactive messages look identical to incoming friend messages.
public struct ChatsRootView: View {
    @EnvironmentObject private var app: CloudAppState
    @Environment(LocalizationManager.self) private var loc
    @State private var conversations: [ConversationRepository.ConversationListItem] = []
    @State private var error: String?
    @State private var searchText = ""

    public init() {}

    private var filtered: [ConversationRepository.ConversationListItem] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else {
            return conversations
        }
        let query = searchText.lowercased()
        return conversations.filter {
            ($0.publicName ?? "").lowercased().contains(query)
                || ($0.lastMessagePreview ?? "").lowercased().contains(query)
        }
    }

    public var body: some View {
        NavigationStack {
            content
                .navigationTitle(loc.t("nav_chats"))
                .searchable(
                    text: $searchText,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: Text(loc.t("cloud_chats_search_prompt")),
                )
                .refreshable { await deltaSyncAndReload() }
                .task {
                    await reloadFromCache()
                    await deltaSyncAndReload()
                }
                .onAppear { Task { await reloadFromCache() } }
        }
    }

    @ViewBuilder
    private var content: some View {
        ZStack(alignment: .top) {
            list
            if app.stage == .offline {
                offlineBanner
            }
        }
    }

    private var offlineBanner: some View {
        Label(loc.t("cloud_chats_offline_banner"), systemImage: "wifi.slash")
            .font(.footnote)
            .padding(.vertical, 6)
            .padding(.horizontal, 12)
            .background(.yellow.opacity(0.85), in: Capsule())
            .padding(.top, 4)
            .accessibilityAddTraits(.isStaticText)
    }

    @ViewBuilder
    private var list: some View {
        if let error, conversations.isEmpty {
            errorState
        } else if filtered.isEmpty && conversations.isEmpty {
            emptyState
        } else {
            List(filtered) { item in
                NavigationLink(value: item.id) {
                    ChatRow(item: item)
                }
            }
            .listStyle(.plain)
            .navigationDestination(for: String.self) { conversationId in
                CloudChatView(conversationId: conversationId)
            }
        }
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
            Text(error).multilineTextAlignment(.center)
            Button(loc.t("cloud_retry")) {
                Task { await deltaSyncAndReload() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 36))
            Text(loc.t("cloud_chats_empty"))
            Text(loc.t("cloud_chats_empty_hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    /// Pull-to-refresh = delta sync against the last durable cursor, then
    /// re-read the cache. Never a full snapshot replacement.
    private func deltaSyncAndReload() async {
        do {
            if let accountId = await app.auth.currentAccountId() {
                try await app.sync.runSync(accountId: accountId)
            }
            error = nil
        } catch {
            self.error = String(describing: error)
        }
        await reloadFromCache()
    }

    private func reloadFromCache() async {
        conversations = await app.conversations.cachedConversationList()
    }
}

private struct ChatRow: View {
    let item: ConversationRepository.ConversationListItem
    @Environment(LocalizationManager.self) private var loc

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 4) {
                Text(item.publicName ?? fallbackTitle)
                    .font(item.unreadCount > 0 ? .headline.bold() : .headline)
                    .lineLimit(1)
                Text(item.lastMessagePreview ?? loc.t("cloud_chats_tap_to_start"))
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
                    .accessibilityLabel(
                        loc.t("cloud_chats_unread_a11y", params: ["count": "\(item.unreadCount)"]),
                    )
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var fallbackTitle: String {
        item.type == "group" ? loc.t("cloud_chats_group_fallback") : loc.t("cloud_chats_chat_fallback")
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
            .accessibilityHidden(true)
    }

    private var initials: String {
        let label = item.publicName ?? fallbackTitle
        let parts = label.split(separator: " ")
        return parts.prefix(2).compactMap { $0.first }.map(String.init).joined()
    }
}
