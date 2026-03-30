import Foundation
import AudioToolbox

/// Notification service managing unread counts, sound, and DND settings.
/// Port of NotificationContext.jsx — adapted for iOS (no browser push).
@Observable
final class NotificationService {

    // MARK: - Settings

    struct Settings: Codable {
        var soundEnabled: Bool = true
        var doNotDisturb: Bool = false
        var soundVolume: Double = 0.5
    }

    var settings: Settings {
        didSet { saveSettings() }
    }

    // MARK: - Unread Counts

    private(set) var unreadCounts: [String: Int]

    // MARK: - Init

    init() {
        settings = StorageService.shared.get("notification.settings", default: Settings())
        unreadCounts = StorageService.shared.get("notification.unread", default: [:])
    }

    // MARK: - Sound

    func playNotificationSound() {
        guard settings.soundEnabled && !settings.doNotDisturb else { return }
        AudioServicesPlaySystemSound(1007) // Standard notification sound
    }

    // MARK: - Unread Management

    func incrementUnread(_ chatId: String) {
        unreadCounts[chatId, default: 0] += 1
        saveUnread()
    }

    func clearUnread(_ chatId: String) {
        unreadCounts[chatId] = 0
        saveUnread()
    }

    func markChatUnread(_ chatId: String) {
        if unreadCounts[chatId, default: 0] == 0 {
            unreadCounts[chatId] = 1
            saveUnread()
        }
    }

    func getUnreadCount(_ chatId: String) -> Int {
        unreadCounts[chatId, default: 0]
    }

    var totalUnread: Int {
        unreadCounts.values.reduce(0, +)
    }

    // MARK: - Settings Toggles

    func toggleSound() { settings.soundEnabled.toggle() }
    func toggleDoNotDisturb() { settings.doNotDisturb.toggle() }

    // MARK: - Notify

    func notify(chatId: String) {
        incrementUnread(chatId)
        playNotificationSound()
    }

    // MARK: - Persistence

    private func saveSettings() {
        StorageService.shared.set("notification.settings", value: settings)
    }

    private func saveUnread() {
        StorageService.shared.set("notification.unread", value: unreadCounts)
    }
}
