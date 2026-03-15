import Foundation

extension String {
    /// Replace {key} placeholders with values from a dictionary
    func interpolating(_ params: [String: String]) -> String {
        var result = self
        for (key, value) in params {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }
}
