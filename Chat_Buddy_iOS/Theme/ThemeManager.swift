import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Theme mode matching web's system/light/dark
enum ThemeMode: String, CaseIterable, Codable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

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

/// Animation intensity levels matching web's anim-none/subtle/standard/intense
enum AnimationIntensity: String, CaseIterable, Codable {
    case none = "none"
    case subtle = "subtle"
    case standard = "standard"
    case intense = "intense"

    var displayName: String {
        switch self {
        case .none: return "Off"
        case .subtle: return "Subtle"
        case .standard: return "Standard"
        case .intense: return "Intense"
        }
    }

    var localizedKey: String {
        switch self {
        case .none: return "anim_none"
        case .subtle: return "anim_subtle"
        case .standard: return "anim_standard"
        case .intense: return "anim_intense"
        }
    }

    /// Duration multiplier for animations
    var durationMultiplier: Double {
        switch self {
        case .none: return 0
        case .subtle: return 0.5
        case .standard: return 1.0
        case .intense: return 1.5
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

    /// Resolved color scheme for SwiftUI .preferredColorScheme()
    var resolvedColorScheme: ColorScheme? {
        switch mode {
        case .system: return nil // follow system
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Whether the effective appearance is dark
    var isDarkMode: Bool {
        switch mode {
        case .dark: return true
        case .light: return false
        case .system:
            // Cannot determine system appearance in @Observable without environment
            // Will be resolved in view layer
            return false
        }
    }

    /// Background color considering OLED mode
    var backgroundColor: Color {
        if oledEnabled && isDarkMode {
            return .black
        }
#if canImport(UIKit)
        return Color(uiColor: .systemBackground)
#elseif canImport(AppKit)
        return Color(nsColor: .windowBackgroundColor)
#else
        return Color(.background)
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
