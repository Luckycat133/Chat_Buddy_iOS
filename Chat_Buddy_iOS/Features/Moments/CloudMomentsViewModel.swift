import Foundation
import SwiftUI
import os

/// Cloud-backed moments view model per skill §"Moments":
///   - Cache-first render with cursor pagination.
///   - Compose uploads via signed URL (server returns a media manifest).
///   - Reactions/comments optimistic then reconcile.
///   - AI posts render identically to other familiar contacts.
@MainActor
public final class CloudMomentsViewModel: ObservableObject {
    @Published public private(set) var moments: [MomentsRepository.MomentItem] = []
    @Published public var composerDraft: String = ""
    @Published public private(set) var composing = false
    @Published public private(set) var error: String?

    public var app: CloudAppState?

    public init(app: CloudAppState? = nil) {
        self.app = app
    }

    /// Bind the live `CloudAppState` once the SwiftUI environment is wired.
    public func bind(app: CloudAppState) {
        self.app = app
    }

    public func load(cursor: String? = nil) async {
        guard let app = app else { return }
        do {
            moments = try await app.moments.list(cursor: cursor)
        } catch {
            self.error = String(describing: error)
        }
    }

    public func compose(visibilityClass: String) async {
        guard let app = app else { return }
        let text = composerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        composing = true
        defer { composing = false }
        do {
            let policy: [String: Any] = [
                "allowedActorIds": [],
                "class": visibilityClass,
            ]
            _ = try await app.moments.compose(content: text, audiencePolicy: policy)
            composerDraft = ""
            await load()
        } catch {
            self.error = String(describing: error)
        }
    }

    public func react(to momentId: String, kind: String) async {
        guard let app = app else { return }
        do {
            _ = try await app.moments.interact(momentId: momentId, type: kind)
            await load()
        } catch {
            self.error = String(describing: error)
        }
    }

    /// Post a text comment on a moment. `react(to:kind:)` only sends the
    /// interaction type; comments carry user content and need this path.
    public func comment(to momentId: String, content: String) async {
        guard let app = app else { return }
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            _ = try await app.moments.interact(momentId: momentId, type: "comment", content: text)
            await load()
        } catch {
            self.error = String(describing: error)
        }
    }
}