import SwiftUI

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

    var resolved: AppLanguage {
        guard self == .system else { return self }
        let preferred = Locale.preferredLanguages.first ?? "en"
        return preferred.hasPrefix("zh") ? .zh : .en
    }
}

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

    var resolvedAILanguage: String {
        aiLanguage == .auto ? resolvedLanguage.rawValue : aiLanguage.rawValue
    }

    var resolvedLanguage: AppLanguage {
        uiLanguage.resolved
    }

    private var bundle: Bundle = .main

    private var resolvedLangCode: String {
        switch resolvedLanguage {
        case .en: return "en"
        case .zh: return "zh-Hans"
        case .system: return "en"
        }
    }

    init() {
        let savedUI = UserDefaults.standard.string(forKey: UserDefaults.Keys.uiLanguage)
        self.uiLanguage = savedUI.flatMap { AppLanguage(rawValue: $0) } ?? .system

        let savedAI = UserDefaults.standard.string(forKey: UserDefaults.Keys.aiLanguage)
        self.aiLanguage = savedAI.flatMap { AILanguage(rawValue: $0) } ?? .auto

        updateBundle()
    }

    func t(_ key: String, params: [String: String]? = nil) -> String {
        var result = bundle.localizedString(forKey: key, value: nil, table: nil)

        if result == key {
            let mainString = Bundle.main.localizedString(forKey: key, value: nil, table: nil)
            if mainString != key {
                result = mainString
            } else {
                let readable = key
                    .replacingOccurrences(of: "_", with: " ")
                    .split(separator: " ")
                    .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                    .joined(separator: " ")
                result = readable
            }
        }

        if let params {
            for (k, v) in params {
                result = result.replacingOccurrences(of: "{\(k)}", with: v)
            }
        }

        return result
    }

    private func updateBundle() {
        let langCode = resolvedLangCode

        if let path = Bundle.main.path(forResource: langCode, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            bundle = langBundle
        } else {
            bundle = .main
        }
    }
}
