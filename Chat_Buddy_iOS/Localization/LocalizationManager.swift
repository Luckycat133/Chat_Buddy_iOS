import SwiftUI

/// Supported UI languages
enum AppLanguage: String, CaseIterable, Codable {
    case system = "system"
    case en = "en"
    case zh = "zh-Hans"

    var displayName: String {
        switch self {
        case .system: return "System"
        case .en: return "English"
        case .zh: return "简体中文"
        }
    }

    /// Resolve system language to a concrete language
    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("zh") ? .zh : .en
    }
}

/// AI response language
enum AILanguage: String, CaseIterable, Codable {
    case auto = "auto"
    case en = "en"
    case zh = "zh"

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .en: return "English"
        case .zh: return "中文"
        }
    }
}

/// Runtime localization manager with in-app language switching.
@Observable
final class LocalizationManager {
    var uiLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(uiLanguage.rawValue, forKey: UserDefaults.Keys.uiLanguage)
            updateBundle()
        }
    }

    var aiLanguage: AILanguage {
        didSet {
            UserDefaults.standard.set(aiLanguage.rawValue, forKey: UserDefaults.Keys.aiLanguage)
        }
    }

    /// The resolved language code for AI responses
    var resolvedAILanguage: String {
        aiLanguage == .auto ? resolvedLanguage.rawValue : aiLanguage.rawValue
    }

    /// The effective language after resolving "system"
    var resolvedLanguage: AppLanguage {
        uiLanguage.resolved
    }

    private var bundle: Bundle = .main

    init() {
        let savedUI = UserDefaults.standard.string(forKey: UserDefaults.Keys.uiLanguage)
        self.uiLanguage = savedUI.flatMap { AppLanguage(rawValue: $0) } ?? .system

        let savedAI = UserDefaults.standard.string(forKey: UserDefaults.Keys.aiLanguage)
        self.aiLanguage = savedAI.flatMap { AILanguage(rawValue: $0) } ?? .auto

        updateBundle()
    }

    /// Translate a key with optional parameter interpolation.
    /// Usage: t("greeting_hello", params: ["name": "Luna"])
    func t(_ key: String, params: [String: String]? = nil) -> String {
        let langCode: String
        switch resolvedLanguage {
        case .en: langCode = "en"
        case .zh: langCode = "zh-Hans"
        case .system: langCode = "en"
        }

        // Try to find the localized string from the appropriate bundle
        var result: String
        if let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            result = langBundle.localizedString(forKey: key, value: nil, table: nil)
        } else {
            result = NSLocalizedString(key, bundle: bundle, comment: "")
        }

        // If the key was not found (returned as-is), use it as the fallback
        if result == key {
            result = key
        }

        // Parameter interpolation: replace {param} with values
        if let params {
            for (k, v) in params {
                result = result.replacingOccurrences(of: "{\(k)}", with: v)
            }
        }

        return result
    }

    private func updateBundle() {
        let langCode: String
        switch resolvedLanguage {
        case .en: langCode = "en"
        case .zh: langCode = "zh-Hans"
        case .system: langCode = "en"
        }

        if let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            bundle = langBundle
        } else {
            bundle = .main
        }
    }
}
