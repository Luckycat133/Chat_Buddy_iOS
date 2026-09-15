import Foundation
import UserNotifications
import os
#if canImport(UIKit)
import UIKit
#endif

/// APNs registration and silent push handling per skill §"Push
/// notifications and deep links".
///
///   - Register APNs token after permission.
///   - Push payload includes opaque route data, not hidden AI content.
///   - Quiet hours and per-character mute are enforced server-side;
///     the client only mirrors presentation.
public final class PushNotificationService: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = PushNotificationService()

    private let logger = CloudLogger.push
    private var routeHandler: ((PushRoute) -> Void)?

    private override init() { super.init() }

    /// Request permission and register for APNs. Call from the onboarding
    /// flow only after the user is signed in (so we can register the
    /// token against the correct account).
    public func bootstrap(routeHandler: @escaping (PushRoute) -> Void) async {
        self.routeHandler = routeHandler
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            logger.notice("push authorization failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Persist the APNs device token to the server's `/v1/devices` so
    /// the cloud runtime can route pushes to this account.
    public func registerDeviceToken(_ token: Data, accountId: String, http: HTTPClient) async {
        let hex = token.map { String(format: "%02x", $0) }.joined()
        struct Body: Codable {
            let platform: String
            let pushToken: String
            let appVersion: String
            let notificationPermission: String
        }
        struct Response: Codable, Sendable { let id: String }
        let body = Body(
            platform: "ios",
            pushToken: hex,
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0",
            notificationPermission: "granted",
        )
        do {
            _ = try await http.send(
                APIEndpoint(path: "/v1/devices"),
                method: "POST",
                body: body,
                as: Response.self,
            )
        } catch {
            logger.notice("device token registration failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// UNUserNotificationCenterDelegate: foreground presentation.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void,
    ) {
        completionHandler([.banner, .sound])
    }

    /// UNUserNotificationCenterDelegate: user tapped a notification.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void,
    ) {
        let info = response.notification.request.content.userInfo
        if let route = PushRoute(info: info) {
            routeHandler?(route)
        }
        completionHandler()
    }
}

public enum PushRoute: Sendable, Equatable {
    case chat(conversationId: String)
    case friendRequest(requestId: String)
    case groupInvitation(invitationId: String)
    case moment(momentId: String)
    case proactiveMessage(conversationId: String, messageId: String)

    public init?(info: [AnyHashable: Any]) {
        guard let kind = info["route"] as? String else { return nil }
        switch kind {
        case "chat":
            guard let id = info["conversationId"] as? String else { return nil }
            self = .chat(conversationId: id)
        case "friend_request":
            guard let id = info["requestId"] as? String else { return nil }
            self = .friendRequest(requestId: id)
        case "group_invitation":
            guard let id = info["invitationId"] as? String else { return nil }
            self = .groupInvitation(invitationId: id)
        case "moment":
            guard let id = info["momentId"] as? String else { return nil }
            self = .moment(momentId: id)
        case "proactive":
            guard let conv = info["conversationId"] as? String,
                  let msg = info["messageId"] as? String else { return nil }
            self = .proactiveMessage(conversationId: conv, messageId: msg)
        default:
            return nil
        }
    }
}
