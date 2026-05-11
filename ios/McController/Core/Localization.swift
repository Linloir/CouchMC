import Foundation

/// Convenience: `L.key("home.title")` returns the localized string with
/// fallback to the key itself when missing. Keeps SwiftUI call sites short.
enum L {
    static func key(_ key: String) -> String {
        NSLocalizedString(key, comment: "")
    }
}
