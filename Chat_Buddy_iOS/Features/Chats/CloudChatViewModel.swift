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

    public let conversationId: String
    public var app: CloudAppState?
    private let logger = CloudLogger.realtime
    /// Authoritative rows read from the server/cache; merged with outbox
    /// snapshots through the pure reducer.
    private var serverMessages: [RemoteMessageDTO] = []
    private var outboxSnapshots: [OutboxMutationSnapshot] = []
    private var accountId: String?

    public init(conversationId: String, app: CloudAppState? = nil) {
        self.conversationId = conversationId
        self.app = app
    }

    /// Bind the live `CloudAppState` once the SwiftUI environment is wired.
    public func bind(app: CloudAppState) {
        self.app = app
    }

    public var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Load

    public func load() async {
        guard let app = app else { return }
        accountId = await app.auth.currentAccountId()
        do {
            serverMessages = try await app.conversations.listMessages(
                conversationId: conversationId,
            )
            error = nil
        } catch {
            // Fall back to the cache so the timeline still renders offline.
            serverMessages = await app.conversations.cachedMessages(
                conversationId: conversationId,
            )
            self.error = String(describing: error)
        }
        await refreshOutboxSnapshots()
        rebuildRows()
        await app.conversations.markReadLocally(conversationId: conversationId)
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
        rows = ChatOutboxReducer.merge(server: serverMessages, outbox: outboxSnapshots)
        if conversationTitle.isEmpty {
            conversationTitle = app?.cachedConversationTitle(conversationId: conversationId)
                ?? NSLocalizedString("cloud_chat_title_fallback", comment: "")
        }
    }

    // MARK: Send (optimistic, never locks)

    public func send() async {
        guard let app = app else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // 1. Clear the composer immediately — rapid consecutive messages
        //    flow; no waiting on the server or on AI activity.
        draft = ""
        // 2. Outbox row first (survives process death) so the optimistic
        //    bubble shows as `queued` while the network round-trip runs.
        do {
            let key = try await app.conversations.enqueueMessage(
                conversationId: conversationId,
                content: text,
            )
            await refreshOutboxSnapshots()
            rebuildRows()
            // 3. Flush; failure keeps the row visible with retry.
            do {
                _ = try await app.conversations.flushOne(idempotencyKey: key)
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
        guard let app, let key = row.idempotencyKey, row.isLocalOnly else { return }
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
        guard let app else { return }
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
        guard let app = app else { return }
        _ = try await app.conversations.flushOutbox()
        await refreshOutboxSnapshots()
        rebuildRows()
    }
}
