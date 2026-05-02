import Foundation

struct ChatPermissions: Codable, Equatable {
    var allowReactions: Bool
    var allowImages: Bool

    static let `default` = ChatPermissions(allowReactions: true, allowImages: false)
}
