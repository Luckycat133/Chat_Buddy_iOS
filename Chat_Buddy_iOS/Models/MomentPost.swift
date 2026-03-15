import Foundation

// MARK: - MomentComment

struct MomentComment: Identifiable, Codable {
    var id: String
    var authorId: String       // "user-me" or persona id
    var content: String
    var createdAt: Date

    /// Non-nil when this comment is a threaded reply
    var replyTo: ReplyReference?

    struct ReplyReference: Codable {
        var commentId: String
        var authorId: String
        var authorName: String
    }

    init(authorId: String, content: String, replyTo: ReplyReference? = nil) {
        self.id = UUID().uuidString
        self.authorId = authorId
        self.content = content
        self.createdAt = Date()
        self.replyTo = replyTo
    }
}

// MARK: - MomentPost

struct MomentPost: Identifiable, Codable {
    var id: String
    var authorId: String           // "user-me" or persona id
    var content: String
    var imagePaths: [String]       // filenames in Documents/moments/
    var location: String?
    var createdAt: Date

    /// Array of userId strings who liked this post
    var likes: [String]

    /// emoji → [userId] mapping for reactions
    var reactions: [String: [String]]

    var comments: [MomentComment]

    init(
        authorId: String,
        content: String,
        imagePaths: [String] = [],
        location: String? = nil
    ) {
        self.id = UUID().uuidString
        self.authorId = authorId
        self.content = content
        self.imagePaths = imagePaths
        self.location = location
        self.createdAt = Date()
        self.likes = []
        self.reactions = [:]
        self.comments = []
    }
}

// MARK: - MomentsData (top-level persisted blob)

struct MomentsData: Codable {
    var posts: [MomentPost]
    /// personaId → unix timestamp of last AI post
    var lastAIPostTime: [String: Double]
    var draftText: String?
    var draftLocation: String?
    /// "YYYY-MM-DD" of the last day story events were generated
    var lastStoryEventDate: String?

    static var empty: MomentsData {
        MomentsData(posts: [], lastAIPostTime: [:], draftText: nil, draftLocation: nil, lastStoryEventDate: nil)
    }
}
