import Combine
import Foundation
import SwiftUI
import SwiftData
import os

/// Cloud-backed chat view model per skill §"Chat UI" + §"Make offline
/// behavior explicit":
///   - Server is authoritative for sequence numbers and burst closure.
///   - Composer never blocks while AI replies; rapid messages flow as
///     individual sends (burst closing is a server decision).
///   - Optimistic row + outbox replay handles offline + reconnect.
///   - Failed sends stay visible; `retry(row:)` re-flushes them.
@MainActor
public final class CloudChatViewModel: ObservableObject {
    @Published public private(set) var rows: [ChatRowModel] = []
    @Published public var draft: String = ""
    @Published public private(set) var error: String?
    @Published public private(set) var conversationTitle: String = ""
    @Published public private(set) var nextRestoreCursor: Int?
    @Published public private(set) var loadingRestorePage = false

    public let conversationId: String
    private let initialMessageCursor: Int?
    public var isReadOnlyRestoreWindow: Bool { initialMessageCursor != nil }
    private var messagePageSize: Int { initialMessageCursor == nil ? 50 : 200 }
    private weak var boundApp: CloudAppState?
    private var generation: UUID?
    private var app: CloudAppState? {
        guard let boundApp, boundApp.sessionGeneration == generation else { return nil }
        return boundApp
    }
    private let logger = CloudLogger.realtime
    /// Authoritative rows read from the server/cache; merged with outbox
    /// snapshots through the pure reducer.
    private var serverMessages: [RemoteMessageDTO] = []
    private var outboxSnapshots: [OutboxMutationSnapshot] = []
    private var accountId: String?
    /// Non-isolated teardown on purpose — see `LegacyImporter.nonisolated deinit`.
    /// Under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` this type gets an isolated
    /// deinit, so releasing it off the main actor frees the instance twice.
    nonisolated deinit {}

    public init(conversationId: String, app: CloudAppState? = nil, initialMessageCursor: Int? = nil) {
        self.conversationId = conversationId
        self.initialMessageCursor = initialMessageCursor
        if let app { bind(app: app) }
    }

    /// Bind the live `CloudAppState` once the SwiftUI environment is wired.
    public func bind(app: CloudAppState) {
        guard generation == nil else { return }
        boundApp = app
        generation = app.sessionGeneration
    }

    public var canSend: Bool {
        !isReadOnlyRestoreWindow && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Load

    public func load() async {
        guard let app = app else { return }
        let conversations = app.conversations
        if let initialMessageCursor {
            await loadRestorePage(cursor: initialMessageCursor, replace: true)
            return
        }
        accountId = await app.auth.currentAccountId()
        guard self.app != nil else { return }
        do {
            serverMessages = try await conversations.listMessages(
                conversationId: conversationId,
            )
            error = nil
        } catch {
            // Fall back to the cache so the timeline still renders offline.
            serverMessages = await conversations.cachedMessages(conversationId: conversationId)
            self.error = String(describing: error)
        }
        await refreshOutboxSnapshots()
        rebuildRows()
        if let actorId = await app.auth.currentActorId(), self.app != nil {
            await conversations.markReadLocally(conversationId: conversationId, myActorId: actorId)
        }
    }

    public func loadNextRestorePage() async {
        guard let cursor = nextRestoreCursor else { return }
        await loadRestorePage(cursor: cursor, replace: false)
    }

    private func loadRestorePage(cursor: Int, replace: Bool) async {
        guard let app, !loadingRestorePage else { return }
        loadingRestorePage = true
        defer { loadingRestorePage = false }
        do {
            let page = try await app.conversations.listMessages(
                conversationId: conversationId, cursor: cursor, limit: messagePageSize,
            )
            guard self.app != nil, !Task.isCancelled else { return }
            let next = try Self.restorePageCursor(
                page, conversationId: conversationId, start: cursor, limit: messagePageSize,
            )
            if replace {
                serverMessages = page
            } else {
                var known = Set(serverMessages.map(\.id))
                serverMessages.append(contentsOf: page.filter { known.insert($0.id).inserted })
            }
            nextRestoreCursor = next
            error = nil
            rebuildRows()
        } catch {
            guard self.app != nil, !Task.isCancelled else { return }
            if replace { nextRestoreCursor = cursor }
            self.error = String(describing: error)
        }
    }

    static func restorePageCursor(_ page: [RemoteMessageDTO], conversationId: String,
                                  start: Int, limit: Int) throws -> Int? {
        guard page.count <= limit,
              page.allSatisfy({ $0.conversationId == conversationId && $0.sequence >= start }) else {
            throw URLError(.cannotParseResponse)
        }
        guard page.count == limit else { return nil }
        guard let last = page.map(\.sequence).max(), last < Int.max else {
            throw URLError(.cannotParseResponse)
        }
        return last + 1
    }

    /// Pull outbox rows for this conversation into pure snapshots.
    private func refreshOutboxSnapshots() async {
        guard let app else {
            outboxSnapshots = []
            return
        }
        let entries = await app.outbox.pendingSnapshots(accountId: accountId ?? "")
        outboxSnapshots = entries.filter { $0.conversationId == conversationId }
    }

    private func rebuildRows() {
        guard app != nil else { return }
        if isReadOnlyRestoreWindow {
            rows = serverMessages.filter { $0.deletedAt == nil }
                .sorted { $0.sequence < $1.sequence }
                .map(ChatRowModel.fromServer)
        } else {
            rows = ChatOutboxReducer.merge(server: serverMessages, outbox: outboxSnapshots)
        }
        if conversationTitle.isEmpty {
            conversationTitle = app?.cachedConversationTitle(conversationId: conversationId)
                ?? NSLocalizedString("cloud_chat_title_fallback", comment: "")
        }
    }

    // MARK: Send (optimistic, never locks)

    public func send() async {
        guard !isReadOnlyRestoreWindow, let app = app else { return }
        let conversations = app.conversations
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // 1. Clear the composer immediately — rapid consecutive messages
        //    flow; no waiting on the server or on AI activity.
        draft = ""
        // 2. Outbox row first (survives process death) so the optimistic
        //    bubble shows as `queued` while the network round-trip runs.
        do {
            let key = try await conversations.enqueueMessage(
                conversationId: conversationId,
                content: text,
            )
            await refreshOutboxSnapshots()
            rebuildRows()
            // 3. Flush; failure keeps the row visible with retry.
            do {
                _ = try await conversations.flushOne(idempotencyKey: key)
                error = nil
            } catch let flushError as APIError where flushError.isConflict {
                self.error = NSLocalizedString("cloud_chat_conflict_notice", comment: "")
            } catch {
                self.error = NSLocalizedString("cloud_chat_send_failed_notice", comment: "")
                logger.error("send failed: \(error.localizedDescription, privacy: .public)")
            }
        } catch {
            self.error = NSLocalizedString("cloud_chat_send_failed_notice", comment: "")
            logger.error("enqueue failed: \(error.localizedDescription, privacy: .public)")
        }
        // 4. Reconcile: server fetch first, THEN drop accepted rows, so
        //    the bubble transitions without disappearing.
        await reconcile()
    }

    /// Retry a failed optimistic row by idempotency key.
    public func retry(row: ChatRowModel) async {
        guard !isReadOnlyRestoreWindow, let app, let key = row.idempotencyKey, row.isLocalOnly else { return }
        do {
            _ = try await app.conversations.flushOne(idempotencyKey: key)
            error = nil
        } catch {
            self.error = String(describing: error)
        }
        await refreshOutboxSnapshots()
        await reconcile()
    }

    /// Server reconcile: re-read the authoritative timeline. Optimistic
    /// rows vanish once the server acknowledges their idempotency keys.
    public func reconcile() async {
        guard !isReadOnlyRestoreWindow, let app else { return }
        do {
            serverMessages = ChatOutboxReducer.reconciled(
                server: try await app.conversations.listMessages(
                    conversationId: conversationId,
                ),
            )
            error = nil
        } catch {
            logger.notice("reconcile failed: \(String(describing: error), privacy: .public)")
        }
        await refreshOutboxSnapshots()
        rebuildRows()
    }

    public func flushOutbox() async throws {
        guard !isReadOnlyRestoreWindow, let app = app else { return }
        _ = try await app.conversations.flushOutbox()
        await refreshOutboxSnapshots()
        rebuildRows()
    }
}
