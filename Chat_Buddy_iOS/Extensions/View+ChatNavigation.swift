import SwiftUI

extension View {
    func chatInlineNavigationTitle() -> some View {
#if os(iOS)
        navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }
}

extension ToolbarItemPlacement {
    static var chatTopBarTrailing: ToolbarItemPlacement {
#if os(iOS)
        return .topBarTrailing
#else
        return .primaryAction
#endif
    }
}
