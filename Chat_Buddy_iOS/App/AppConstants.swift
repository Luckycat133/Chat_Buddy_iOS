import Foundation

enum AppConstants {
    static let appName = "Chat Buddy"
    static let developer = "Jack"
    static let githubURL = "https://github.com/jackfranklin/chat-buddy"
    static let currentUserId = "user-me"

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    static var fullVersion: String {
        "\(appVersion) (\(buildNumber))"
    }
}
