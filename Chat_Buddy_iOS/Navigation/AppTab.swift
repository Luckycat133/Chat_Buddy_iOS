import SwiftUI

/// Legacy tab set. The legacy runtime is retained only for one-time
/// data import; per skill §"Root navigation" Chats is the default
/// destination and the Dashboard surface is removed entirely
/// (`CloudAppTab` is authoritative for the cloud runtime).
enum AppTab: String, CaseIterable, Identifiable {
    case chats
    case moments
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chats: return "nav_chats"
        case .moments: return "nav_moments"
        case .settings: return "nav_settings"
        }
    }

    var icon: String {
        switch self {
        case .chats: return "bubble.left.and.bubble.right.fill"
        case .moments: return "sparkles"
        case .settings: return "gearshape.fill"
        }
    }
}
