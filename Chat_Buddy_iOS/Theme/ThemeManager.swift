import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum ThemeMode: String, CaseIterable, Codable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var localizedKey: String {
        switch self {
        case .system: return "theme_system"
        case .light: return "theme_light"
        case .dark: return "theme_dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

enum AnimationIntensity: String, CaseIterable, Codable {
    case none = "none"
    case subtle = "subtle"
    case standard = "standard"
    case intense = "intense"

    var localizedKey: String {
        switch self {
        case .none: return "anim_none"
        case .subtle: return "anim_subtle"
        case .standard: return "anim_standard"
        case .intense: return "anim_intense"
        }
    }

    var durationMultiplier: Double {
        switch self {
        case .none: return 0
        case .subtle: return 0.5
        case .standard: return 1.0
        case .intense: return 1.5
        }
    }

    var shouldAnimate: Bool {
        self != .none
    }
}

extension View {
    func themedAnimation(_ animation: Animation, intensity: AnimationIntensity) -> some View {
        if intensity.shouldAnimate {
            return AnyView(self.animation(animation))
        } else {
            return AnyView(self)
        }
    }
}

@Observable
final class ThemeManager {
    var mode: ThemeMode {
        didSet {
            UserDefaults.standard.set(mode.rawValue, forKey: UserDefaults.Keys.themeMode)
        }
    }

    var oledEnabled: Bool {
        didSet {
            UserDefaults.standard.set(oledEnabled, forKey: UserDefaults.Keys.oledEnabled)
        }
    }

    var animationIntensity: AnimationIntensity {
        didSet {
            UserDefaults.standard.set(animationIntensity.rawValue, forKey: UserDefaults.Keys.animationIntensity)
        }
    }

    var resolvedColorScheme: ColorScheme? {
        switch mode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    func isEffectivelyDark(_ colorScheme: ColorScheme = .light) -> Bool {
        switch mode {
        case .dark: return true
        case .light: return false
        case .system: return colorScheme == .dark
        }
    }

    func backgroundColor(_ colorScheme: ColorScheme = .light) -> Color {
        if oledEnabled && isEffectivelyDark(colorScheme) {
            return .black
        }
        #if canImport(UIKit)
        return Color(uiColor: .systemBackground)
        #else
        return Color(nsColor: .windowBackgroundColor)
        #endif
    }

    init() {
        let savedMode = UserDefaults.standard.string(forKey: UserDefaults.Keys.themeMode)
        self.mode = savedMode.flatMap { ThemeMode(rawValue: $0) } ?? .system

        self.oledEnabled = UserDefaults.standard.bool(forKey: UserDefaults.Keys.oledEnabled)

        let savedAnim = UserDefaults.standard.string(forKey: UserDefaults.Keys.animationIntensity)
        self.animationIntensity = savedAnim.flatMap { AnimationIntensity(rawValue: $0) } ?? .standard
    }

    func toggleMode() {
        switch mode {
        case .system: mode = .light
        case .light: mode = .dark
        case .dark: mode = .system
        }
    }
}
