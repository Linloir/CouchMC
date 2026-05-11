import Foundation

/// Display formatting for host addresses.
///
/// Two concerns this fixes:
///   1. SwiftUI's `Text("\(port)")` picks the `LocalizedStringKey` overload,
///      which formats UInt16 with thousands separators ("60,809" in en-US).
///      We must build the string as a plain `String` and pass it via
///      `Text(verbatim:)` to get "60809".
///   2. IPv6 addresses must be wrapped in brackets so the trailing `:port`
///      doesn't read as another colon-separated hextet. RFC 3986 §3.2.2.
enum HostFormat {

    /// "192.168.1.10:34555"   or   "[fe80::1]:34555"
    static func endpoint(ip: String, port: UInt16) -> String {
        "\(formatAddress(ip)):\(port)"
    }

    /// "192.168.1.10"   or   "[fe80::1]"
    static func formatAddress(_ ip: String) -> String {
        isIPv6(ip) ? "[\(ip)]" : ip
    }

    private static func isIPv6(_ ip: String) -> Bool {
        // A naive but reliable check: IPv4 dotted-quad never contains ":",
        // IPv6 always does. Hostnames may contain ":" only when already
        // bracketed — we treat those as a no-op below.
        guard ip.contains(":") else { return false }
        guard !(ip.hasPrefix("[") && ip.contains("]")) else { return false }
        return true
    }
}
