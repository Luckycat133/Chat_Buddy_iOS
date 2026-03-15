import SwiftUI
import UIKit

/// Observable store for the Moments social feed.
/// Persists a single `MomentsData` blob at `chat-buddy:moments`.
@Observable final class MomentsStore {
    private(set) var posts: [MomentPost] = []
    var lastAIPostTime: [String: Double] = [:]
    var draftText: String = ""
    var draftLocation: String? = nil
    var lastStoryEventDate: String? = nil

    private static let storageKey = "moments"
    private static let momentsFolderName = "moments"

    // MARK: - Init

    init() {
        let data: MomentsData = StorageService.shared.get(Self.storageKey, default: .empty)
        posts = data.posts
        lastAIPostTime = data.lastAIPostTime
        draftText = data.draftText ?? ""
        draftLocation = data.draftLocation
        lastStoryEventDate = data.lastStoryEventDate
    }

    // MARK: - CRUD

    /// Creates a new post. Saves image data to disk and returns the new post ID.
    @discardableResult
    func createPost(
        content: String,
        imageData: [Data],
        location: String?,
        authorId: String = "user-me"
    ) -> String {
        let paths = imageData.compactMap { Self.saveImage($0) }
        let post = MomentPost(authorId: authorId, content: content, imagePaths: paths, location: location)
        posts.insert(post, at: 0)
        save()
        return post.id
    }

    func deletePost(id: String) {
        if let idx = posts.firstIndex(where: { $0.id == id }) {
            let post = posts[idx]
            post.imagePaths.forEach { Self.deleteImage($0) }
            posts.remove(at: idx)
            save()
        }
    }

    func toggleLike(postId: String, userId: String = "user-me") {
        guard let idx = posts.firstIndex(where: { $0.id == postId }) else { return }
        if let likeIdx = posts[idx].likes.firstIndex(of: userId) {
            posts[idx].likes.remove(at: likeIdx)
        } else {
            posts[idx].likes.append(userId)
        }
        save()
    }

    func addReaction(postId: String, emoji: String, userId: String = "user-me") {
        guard let idx = posts.firstIndex(where: { $0.id == postId }) else { return }
        var emojiUsers = posts[idx].reactions[emoji] ?? []
        if let uIdx = emojiUsers.firstIndex(of: userId) {
            emojiUsers.remove(at: uIdx)
        } else {
            emojiUsers.append(userId)
        }
        if emojiUsers.isEmpty {
            posts[idx].reactions.removeValue(forKey: emoji)
        } else {
            posts[idx].reactions[emoji] = emojiUsers
        }
        save()
    }

    @discardableResult
    func addComment(
        postId: String,
        content: String,
        authorId: String,
        replyTo: MomentComment.ReplyReference? = nil
    ) -> String {
        guard let idx = posts.firstIndex(where: { $0.id == postId }) else { return "" }
        let comment = MomentComment(authorId: authorId, content: content, replyTo: replyTo)
        posts[idx].comments.append(comment)
        save()
        return comment.id
    }

    func deleteComment(postId: String, commentId: String) {
        guard let pIdx = posts.firstIndex(where: { $0.id == postId }) else { return }
        posts[pIdx].comments.removeAll { $0.id == commentId }
        save()
    }

    func saveDraft(text: String, location: String?) {
        draftText = text
        draftLocation = location
        save()
    }

    func clearDraft() {
        draftText = ""
        draftLocation = nil
        save()
    }

    func recordAIPost(personaId: String) {
        lastAIPostTime[personaId] = Date().timeIntervalSince1970
        save()
    }

    func recordStoryEvent(date: String) {
        lastStoryEventDate = date
        save()
    }

    /// Adds a post with a custom createdAt (e.g. for seeding historical posts).
    /// Inserts and keeps array sorted newest-first.
    func addHistoricalPost(_ post: MomentPost) {
        posts.append(post)
        posts.sort { $0.createdAt > $1.createdAt }
        save()
    }

    // MARK: - Image Helpers

    static func momentsDirectory() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent(momentsFolderName)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func imageURL(for filename: String) -> URL {
        Self.momentsDirectory().appendingPathComponent(filename)
    }

    /// Compresses `data` to max 600px JPEG and saves to disk. Returns the filename.
    static func saveImage(_ data: Data) -> String? {
        guard let image = UIImage(data: data) else { return nil }
        let resized = resizeImage(image, maxDimension: 600)
        guard let jpeg = resized.jpegData(compressionQuality: 0.7) else { return nil }
        let filename = "\(UUID().uuidString).jpg"
        let url = momentsDirectory().appendingPathComponent(filename)
        do {
            try jpeg.write(to: url)
            return filename
        } catch {
            print("[MomentsStore] Failed to save image: \(error)")
            return nil
        }
    }

    static func deleteImage(_ filename: String) {
        let url = momentsDirectory().appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Persistence

    private func save() {
        let data = MomentsData(
            posts: posts,
            lastAIPostTime: lastAIPostTime,
            draftText: draftText.isEmpty ? nil : draftText,
            draftLocation: draftLocation,
            lastStoryEventDate: lastStoryEventDate
        )
        StorageService.shared.set(Self.storageKey, value: data)
    }

    // MARK: - Private

    private static func resizeImage(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
