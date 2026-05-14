import Foundation
import os.log

final class SensitiveDataHandler {
    private static let logger = Logger(subsystem: "com.chatbuddy", category: "Security")

    static func sanitizeForLogging(_ input: String, sensitivePatterns: [String] = ["api_key", "apiKey", "token", "secret", "password", "auth"]) -> String {
        var sanitized = input

        for pattern in sensitivePatterns {
            let regex = try? NSRegularExpression(
                pattern: "(\(pattern)\"\\s*:\\s*\"?)([^\",}\\s]+)",
                options: .caseInsensitive
            )

            sanitized = regex?.stringByReplacingMatches(
                in: sanitized,
                options: [],
                range: NSRange(sanitized.startIndex..., in: sanitized),
                withTemplate: "$1[REDACTED]"
            ) ?? sanitized
        }

        if sanitized != input {
            logger.info("Sensitive data detected and redacted in logs")
        }

        return sanitized
    }

    static func secureCleanup(_ string: inout String?) {
        guard var value = string else { return }
        let count = value.count
        for i in 0..<count {
            let index = value.index(value.startIndex, offsetBy: i)
            value.replaceSubrange(index...index, with: "\0")
        }
        value.removeAll()
        string = nil
    }

    static func secureCleanup(_ data: inout Data?) {
        guard var value = data else { return }
        value.withUnsafeMutableBytes { bytes in
            if let baseAddress = bytes.baseAddress {
                memset(baseAddress, 0, bytes.count)
            }
        }
        value.removeAll()
        data = nil
    }

    static func securelyWipeArray(_ array: inout [UInt8]?) {
        guard var value = array else { return }
        for i in 0..<value.count {
            value[i] = 0
        }
        value.removeAll()
        array = nil
    }
}

extension String {
    func redactedForLogging() -> String {
        return SensitiveDataHandler.sanitizeForLogging(self)
    }
}
