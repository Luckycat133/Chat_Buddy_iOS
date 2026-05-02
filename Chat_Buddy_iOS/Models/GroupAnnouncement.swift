import Foundation

struct GroupAnnouncement: Codable, Equatable {
    var content: String
    var updatedAt: Date
    var createdBy: String

    init(content: String, updatedAt: Date = Date(), createdBy: String = AppConstants.currentUserId) {
        self.content = content
        self.updatedAt = updatedAt
        self.createdBy = createdBy
    }
}
