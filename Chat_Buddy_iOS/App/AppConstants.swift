import Foundation

enum AppConstants {
    static let appName = "Chat Buddy"
    static let appVersion = "0.1.0"
    static let buildNumber = "1"
    static let developer = "Jack"
    static let githubURL = "https://github.com/jackfranklin/chat-buddy"

    static var fullVersion: String {
        "\(appVersion) (\(buildNumber))"
    }
}
