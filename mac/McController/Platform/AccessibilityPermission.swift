import Foundation
import ApplicationServices
import AppKit

/// Accessibility permission helper. On macOS, posting synthetic
/// keyboard/mouse events via `CGEventPost(.cghidEventTap)` requires
/// the calling process to be in System Settings → Privacy & Security →
/// Accessibility. Without it, our events are silently dropped.
///
/// `AXIsProcessTrusted()` is the canonical check. Passing the
/// `kAXTrustedCheckOptionPrompt` option does both the check AND surfaces
/// the system prompt the first time; after the user grants permission
/// they may need to restart the app for the trust to take effect.
enum AccessibilityPermission {

    /// True if the process currently has Accessibility trust. Reads
    /// the current state without side-effects — no system dialog is
    /// shown. Safe to poll.
    static var isGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Explicitly request permission, surfacing the system prompt if
    /// the app isn't trusted yet. Only call from a user-driven action
    /// (e.g. tapping "Open System Settings" on the Discovery view).
    ///
    /// We *never* call this from `applicationDidFinishLaunching` or
    /// `View.task` — that path causes the dialog to reappear on every
    /// rebuild because dev binaries get a fresh cdhash each compile,
    /// which invalidates the trust grant in TCC's database. Showing
    /// the dialog only on user intent avoids that loop.
    @discardableResult
    static func requestPrompt() -> Bool {
        if isGranted { return true }
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as CFString
        let options: CFDictionary = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Open the Accessibility pane in System Settings. When the user
    /// rebuilds from source, TCC may keep an obsolete entry — they'll
    /// need to toggle the switch off + on, or remove and re-add the
    /// app, to re-issue trust for the new binary.
    static func openSystemSettings() {
        let urlStr = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Clears MC Controller's Accessibility entry from the user's
    /// TCC database. Useful when the OS shows the switch as ON in
    /// System Settings but `AXIsProcessTrusted()` still returns
    /// false — which happens after a rebuild, because TCC keys
    /// grants on the binary's *cdhash* (changes every compile under
    /// ad-hoc signing), not the bundle ID alone. After Reset, the
    /// app re-launches and macOS shows a fresh authorization
    /// prompt that records the current cdhash.
    ///
    /// `tccutil` operates on the *user* TCC db (no sudo needed).
    /// Side effect: the System Settings list will lose the
    /// McController row entirely until the user re-authorizes.
    static func resetTrust() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        task.arguments = ["reset", "Accessibility", "com.linloir.mccontroller"]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            NSLog("[AccessibilityPermission] tccutil reset failed: %@",
                  String(describing: error))
            return
        }
        // Open System Settings + activate so the user has an
        // obvious next step — re-authorize there, then relaunch
        // the app. We could relaunch programmatically, but on
        // ad-hoc builds the "relaunch" would inherit the same
        // PID environment and may not actually trigger a fresh
        // TCC prompt; leaving it as a manual step makes the
        // result predictable.
        openSystemSettings()
    }
}
