import Foundation

struct UserProfile: Codable, Equatable {
    var nickName: String
    var avatarEmoji: String
    var signature: String

    static let defaultAvatars: [String] = [
        "😊", "🌟", "🎮", "🎨", "🌙", "🔥", "🎵", "🌸", "💪", "🦋", "🎯", "🦊",
    ]

    static let `default` = UserProfile(
        nickName: "You",
        avatarEmoji: "😊",
        signature: ""
    )
}
