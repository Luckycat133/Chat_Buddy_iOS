import Foundation
import os

/// Runtime configuration for the Chat Buddy iOS cloud client.
///
/// Per `chat-buddy-ios-demo-development` skill §"Current-repository corrections":
///   - iOS is a cloud client; it must not become a second implementation of
///     character intelligence.
///   - do not persist full chat or memory arrays in UserDefaults.
///   - do not run background Moments generation independently from cloud.
///   - do not maintain provider profiles in the TestFlight primary flow.
public struct AppEnvironment: Sendable, Equatable {
    public let apiBaseURL: URL
    public let realtimeURL: URL
    public let bundleIdentifier: String
    public let buildNumber: String
    public let enableDiagnostics: Bool
    public let apnsEnvironment: APNSEnvironment

    public init(
        apiBaseURL: URL,
        realtimeURL: URL,
        bundleIdentifier: String,
        buildNumber: String,
        enableDiagnostics: Bool,
        apnsEnvironment: APNSEnvironment,
    ) {
        self.apiBaseURL = apiBaseURL
        self.realtimeURL = realtimeURL
        self.bundleIdentifier = bundleIdentifier
        self.buildNumber = buildNumber
        self.enableDiagnostics = enableDiagnostics
        self.apnsEnvironment = apnsEnvironment
    }

    public static let development = AppEnvironment(
        apiBaseURL: URL(string: "http://localhost:8080")!,
        realtimeURL: URL(string: "ws://localhost:8080/v1/realtime")!,
        bundleIdentifier: "com.chatbuddy.ios.dev",
        buildNumber: "0.0.1",
        enableDiagnostics: true,
        apnsEnvironment: .sandbox,
    )

    public static let testFlight = AppEnvironment(
        apiBaseURL: URL(string: "https://api.chatbuddy.app")!,
        realtimeURL: URL(string: "wss://api.chatbuddy.app/v1/realtime")!,
        bundleIdentifier: "com.chatbuddy.ios",
        buildNumber: "1.0.0",
        enableDiagnostics: false,
        apnsEnvironment: .production,
    )

    /// Resolve the runtime environment from Info.plist or compile-time defaults.
    public static func resolve(bundle: Bundle = .main) -> AppEnvironment {
        let dict = bundle.infoDictionary ?? [:]
        let envOverride = (dict["CBEnvironment"] as? String)?.lowercased()
        if envOverride == "testflight" || envOverride == "production" {
            return .testFlight
        }
        if let urlString = dict["CBAPIBaseURL"] as? String,
           let url = URL(string: urlString) {
            let realtime = URL(
                string: (dict["CBRealtimeURL"] as? String) ?? url.replacingScheme(with: "wss").absoluteString,
            ) ?? url.replacingScheme(with: "wss")
            return AppEnvironment(
                apiBaseURL: url,
                realtimeURL: realtime,
                bundleIdentifier: bundle.bundleIdentifier ?? "com.chatbuddy.ios",
                buildNumber: (dict["CFBundleVersion"] as? String) ?? "0.0.0",
                enableDiagnostics: (envOverride == "development"),
                apnsEnvironment: (envOverride == "testflight") ? .production : .sandbox,
            )
        }
        return .development
    }
}

public enum APNSEnvironment: String, Sendable {
    case sandbox
    case production
}

extension URL {
    /// Replace the scheme (https → wss, http → ws) while preserving host/path.
    fileprivate func replacingScheme(with newScheme: String) -> URL {
        guard let comps = URLComponents(url: self, resolvingAgainstBaseURL: false) else {
            return self
        }
        var updated = comps
        switch comps.scheme?.lowercased() {
        case "https":
            updated.scheme = "wss"
        case "http":
            updated.scheme = "ws"
        default:
            updated.scheme = newScheme
        }
        return updated.url ?? self
    }
}

/// Shared logger subsystem for the cloud client.
public enum CloudLogger {
    public static let subsystem = "com.chatbuddy.ios.cloud"

    public static let auth = Logger(subsystem: subsystem, category: "auth")
    public static let realtime = Logger(subsystem: subsystem, category: "realtime")
    public static let sync = Logger(subsystem: subsystem, category: "sync")
    public static let outbox = Logger(subsystem: subsystem, category: "outbox")
    public static let push = Logger(subsystem: subsystem, category: "push")
    public static let cache = Logger(subsystem: subsystem, category: "cache")
    public static let capability = Logger(subsystem: subsystem, category: "capability")
}