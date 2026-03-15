import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case dashboard
    case chats
    case moments
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "nav_dashboard"
        case .chats: return "nav_chats"
        case .moments: return "nav_moments"
        case .settings: return "nav_settings"
        }
    }

    var icon: String {
        switch self {
        case .dashboard: return "square.grid.2x2.fill"
        case .chats: return "bubble.left.and.bubble.right.fill"
        case .moments: return "sparkles"
        case .settings: return "gearshape.fill"
        }
    }
}
