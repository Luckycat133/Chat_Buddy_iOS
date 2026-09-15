import Foundation
import SwiftUI
import os

/// Deep-link router per skill §"Push notifications and deep links":
///
/// ```text
/// chatbuddy://chats/{conversationId}
/// chatbuddy://requests/{requestId}
/// chatbuddy://groups/invitations/{invitationId}
/// chatbuddy://moments/{momentId}
/// ```
///
/// The router maintains a pending route that is consumed after the
/// initial sync completes and the matching surface is on-screen. This
/// avoids showing a flash of the chats list before the deep-link target.
@MainActor
public final class DeepLinkRouter: ObservableObject {
    public enum PendingRoute: Sendable, Equatable {
        case chat(conversationId: String)
        case friendRequest(requestId: String)
        case groupInvitation(invitationId: String)
        case moment(momentId: String)

        public var targetTab: CloudAppTab {
            switch self {
            case .chat:
                return .chats
            case .friendRequest:
                return .contacts
            case .groupInvitation:
                return .contacts
            case .moment:
                return .moments
            }
        }
    }

    @Published public var pending: PendingRoute?
    @Published public var selectedTab: CloudAppTab = .chats

    public init() {}

    /// Handle a URL or a push route.
    public func handle(url: URL) {
        guard let pending = PendingRoute(url: url) else { return }
        self.pending = pending
        self.selectedTab = pending.targetTab
    }

    public func handle(route: PushRoute) {
        switch route {
        case .chat(let id):
            pending = .chat(conversationId: id)
        case .friendRequest(let id):
            pending = .friendRequest(requestId: id)
        case .groupInvitation(let id):
            pending = .groupInvitation(invitationId: id)
        case .moment(let id):
            pending = .moment(momentId: id)
        case .proactiveMessage(let conversationId, _):
            pending = .chat(conversationId: conversationId)
        }
        if let p = pending {
            selectedTab = p.targetTab
        }
    }

    public func clear() {
        pending = nil
    }
}

/// Tab model for the cloud runtime (distinct from the legacy
/// `Navigation/AppTab.swift` enum used by `RootTabView`, whose cases are
/// dashboard/chats/moments/settings).
public enum CloudAppTab: String, Sendable, Hashable, Codable {
    case chats
    case contacts
    case moments
    case me

    /// Per skill §"Root navigation" — Chats is the default destination,
    /// not Dashboard.
    public static let defaultTab: CloudAppTab = .chats
}

extension DeepLinkRouter.PendingRoute {
    init?(url: URL) {
        guard url.scheme == "chatbuddy" else { return nil }
        let host = url.host ?? ""
        let path = url.path
        switch host {
        case "chats":
            let id = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !id.isEmpty else { return nil }
            self = .chat(conversationId: id)
        case "requests":
            let id = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !id.isEmpty else { return nil }
            self = .friendRequest(requestId: id)
        case "groups":
            // /invitations/{invitationId}
            let parts = path.split(separator: "/").map(String.init)
            guard parts.count >= 2, parts[0] == "invitations" else { return nil }
            self = .groupInvitation(invitationId: parts[1])
        case "moments":
            let id = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !id.isEmpty else { return nil }
            self = .moment(momentId: id)
        default:
            return nil
        }
    }
}