import Foundation
import ServiceManagement

/// Toggles "launch at login" via `SMAppService.mainApp`. Mirrors the
/// HKCU\…\Run registry toggle on the Windows side, but uses Apple's
/// modern API (replaces the deprecated `SMLoginItemSetEnabled` from
/// macOS 13+).
///
/// Requires no entitlement and no helper. The system creates a
/// background launchd job pointing at our bundle that fires after the
/// user logs in. Disabling removes it.
enum StartupRegistration {

    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard #available(macOS 13.0, *) else { return false }
        let service = SMAppService.mainApp
        do {
            if enabled {
                if service.status != .enabled {
                    try service.register()
                }
            } else {
                if service.status != .notRegistered {
                    try service.unregister()
                }
            }
            return true
        } catch {
            NSLog("[Startup] toggle failed: %@", String(describing: error))
            return false
        }
    }
}
