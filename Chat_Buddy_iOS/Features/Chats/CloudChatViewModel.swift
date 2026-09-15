import Foundation
import SwiftUI
import SwiftData
import os

/// Cloud-backed chat view model per skill §"Chat UI" + §"Make offline
/// behavior explicit":
///   - Server is authoritative for sequence numbers and burst closure.
///   - Composer must NOT block while AI replies; rapid messages flow.
///   - Optimistic local message + outbox replay handles offline + reconnect.
///   - Streaming is delivered via RealtimeClient; placeholder row updates
///     in place, then server message replaces the stream buffer.
@MainActor
public final class CloudChatViewModel: ObservableObject {
    @Published public private(set) var messages: [RemoteMessageDTO] = []
    @Published public var draft: String = ""
    @Published public private(set) var sending = false
    @Published public private(set) var error: String?

    public let conversationId: String
    public var app: CloudAppState?
    private let logger = CloudLogger.realtime

    public init(conversationId: String, app: CloudAppState? = nil) {
        self.conversationId = conversationId
        self.app = app
    }

    /// Bind the live `CloudAppState` once the SwiftUI environment is wired.
    /// Required because `StateObject` cannot capture an env value at init.
    public func bind(app: CloudAppState) {
        self.app = app
    }

    public func load() async {
        guard let app = app else { return }
        do {
            messages = try await app.conversations.listMessages(
                conversationId: conversationId,
            )
        } catch {
            self.error = String(describing: error)
        }
    }

    public func send() async {
        guard let app = app else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        sending = true
        defer { sending = false }
        do {
            _ = try await app.conversations.sendMessage(
                conversationId: conversationId,
                content: text,
            )
            draft = ""
            try await flushOutbox()
            messages = try await app.conversations.listMessages(
                conversationId: conversationId,
            )
        } catch let error as APIError where error.isConflict {
            self.error = "Server already has this message"
            await load()
        } catch {
            self.error = String(describing: error)
            logger.error("send failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func flushOutbox() async throws {
        guard let app = app else { return }
        _ = try await app.conversations.flushOutbox()
    }

    public func closeBurst() async {
        guard let app = app else { return }
        do {
            try await app.conversations.closeBurst(conversationId: conversationId)
        } catch {
            self.error = String(describing: error)
        }
    }
}