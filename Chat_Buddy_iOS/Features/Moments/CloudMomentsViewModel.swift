import Foundation
import SwiftUI
import os

/// Cloud-backed moments view model per skill §"Moments":
///   - Cursor pagination (`load`, `loadMore`) with cache-first render.
///   - Real view events after meaningful display (debounced per moment).
///   - Optimistic reaction/comment rows reconciled against the server;
///     failures stay visible for retry.
///   - Compose with optional media (compressed + signed-URL upload with
///     progress) and audience selection.
@MainActor
public final class CloudMomentsViewModel: ObservableObject {
    @Published public private(set) var moments: [MomentsRepository.MomentItem] = []
    @Published public var composerDraft: String = ""
    @Published public private(set) var composing = false
    @Published public private(set) var error: String?
    @Published public private(set) var isLoadingMore = false
    @Published public private(set) var canLoadMore = true
    @Published public private(set) var uploadProgress: Double?
    @Published public private(set) var pendingInteractions: [MomentPendingInteraction] = []
    /// Audience for the next post. Values match the server policy class.
    @Published public var audienceClass: String = "familiar"
    @Published public private(set) var pendingMediaAssetIds: [String] = []

    public var app: CloudAppState?
    private var nextCursor: String?
    private var viewedMomentIds = Set<String>()
    private let logger = CloudLogger.cache

    public init(app: CloudAppState? = nil) {
        self.app = app
    }

    /// Bind the live `CloudAppState` once the SwiftUI environment is wired.
    public func bind(app: CloudAppState) {
        self.app = app
    }

    // MARK: Feed

    /// Cache-first load: render cached rows immediately, then refresh the
    /// first page from the network.
    public func load() async {
        guard let app = app else { return }
        moments = await app.moments.cachedFeed()
        do {
            let page = try await app.moments.list(cursor: nil)
            merge(page.items)
            nextCursor = page.nextCursor
            canLoadMore = page.nextCursor != nil
            error = nil
        } catch {
            // Cached rows remain visible; surface the refresh failure.
            self.error = String(describing: error)
        }
    }

    public func loadMore() async {
        guard let app, canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await app.moments.list(cursor: nextCursor)
            merge(page.items)
            nextCursor = page.nextCursor
            canLoadMore = page.nextCursor != nil
        } catch {
            logger.notice("moments loadMore failed: \(String(describing: error), privacy: .public)")
        }
    }

    private func merge(_ page: [MomentsRepository.MomentItem]) {
        let existing = Dictionary(uniqueKeysWithValues: moments.map { ($0.id, $0) })
        var merged = existing
        for item in page { merged[item.id] = item }
        moments = merged.values.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: View events (real, debounced per moment per session)

    public func reportVisible(_ momentId: String) async {
        guard !viewedMomentIds.contains(momentId) else { return }
        viewedMomentIds.insert(momentId)
        await app?.moments.markViewed(momentId: momentId)
    }

    // MARK: Optimistic reactions/comments

    public func react(to momentId: String, kind: String = "reaction") async {
        let localId = "pending-\(UUID().uuidString)"
        appendPending(MomentPendingInteraction(
            id: localId, momentId: momentId, type: kind, content: nil, state: .sending,
        ))
        do {
            _ = try await app?.moments.interact(momentId: momentId, type: kind)
            resolvePending(localId: localId)
            await load()
        } catch {
            markPendingFailed(localId: localId)
            self.error = String(describing: error)
        }
    }

    public func comment(to momentId: String, content: String) async {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let localId = "pending-\(UUID().uuidString)"
        appendPending(MomentPendingInteraction(
            id: localId, momentId: momentId, type: "comment", content: text, state: .sending,
        ))
        do {
            _ = try await app?.moments.interact(momentId: momentId, type: "comment", content: text)
            resolvePending(localId: localId)
            await load()
        } catch {
            markPendingFailed(localId: localId)
            self.error = String(describing: error)
        }
    }

    /// Retry a failed optimistic interaction.
    public func retryPending(_ pending: MomentPendingInteraction) async {
        if pending.type == "comment", let content = pending.content {
            await comment(to: pending.momentId, content: content)
        } else {
            await react(to: pending.momentId, kind: pending.type)
        }
        pendingInteractions.removeAll { $0.id == pending.id }
    }

    private func appendPending(_ pending: MomentPendingInteraction) {
        pendingInteractions.append(pending)
    }

    private func resolvePending(localId: String) {
        pendingInteractions.removeAll { $0.id == localId }
    }

    private func markPendingFailed(localId: String) {
        if let idx = pendingInteractions.firstIndex(where: { $0.id == localId }) {
            pendingInteractions[idx] = MomentPendingInteraction(
                id: pendingInteractions[idx].id,
                momentId: pendingInteractions[idx].momentId,
                type: pendingInteractions[idx].type,
                content: pendingInteractions[idx].content,
                state: .failed,
            )
        }
    }

    public func failedPending(for momentId: String) -> [MomentPendingInteraction] {
        pendingInteractions.filter { $0.momentId == momentId && $0.state == .failed }
    }

    // MARK: Compose

    public func compose() async {
        guard let app = app else { return }
        let text = composerDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        composing = true
        defer { composing = false }
        do {
            _ = try await app.moments.compose(
                content: text,
                audienceClass: audienceClass,
                mediaAssetIds: pendingMediaAssetIds,
            )
            composerDraft = ""
            pendingMediaAssetIds = []
            uploadProgress = nil
            error = nil
            await load()
        } catch {
            self.error = String(describing: error)
        }
    }

    /// Upload picked media and remember the resulting asset ids. Progress
    /// publishes 0...1 while running, nil when idle.
    public func attachMedia(_ data: Data) async {
        guard let app else { return }
        uploading = true
        uploadProgress = 0.0
        defer {
            uploading = false
        }
        do {
            let service = MediaUploadService(http: app.http)
            let result = try await service.upload(data) { [weak self] fraction in
                Task { @MainActor [weak self] in
                    self?.uploadProgress = fraction
                }
            }
            pendingMediaAssetIds.append(result.assetId)
            uploadProgress = nil
        } catch {
            uploadProgress = nil
            self.error = String(describing: error)
        }
    }

    private var uploading = false

    public var isUploading: Bool { uploading }
}
