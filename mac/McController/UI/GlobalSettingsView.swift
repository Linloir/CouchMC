import SwiftUI
import AppKit
import CoreGraphics

struct GlobalSettingsView: View {

    @EnvironmentObject private var appearance: AppearancePreferences
    @State private var startupEnabled: Bool = StartupRegistration.isEnabled

    /// Set when our `NSStatusItem` is currently hidden by a third-party
    /// menu-bar-manager app (Hidden Bar, Bartender, etc.). The card
    /// only renders when this is non-nil — there's no point telling
    /// the user about a state that's currently fine.
    ///
    /// Lives here, not on the Devices page, because conceptually it's
    /// a "this is how the app sits in the menu bar" preference, in the
    /// same neighbourhood as "launch at login".
    @State private var menuBarHiddenManager: String?

    /// 2-second polling: detecting menu-bar-manager presence has no
    /// notification API we can subscribe to, and the user might toggle
    /// CouchMC's visibility in the manager's own UI without ever
    /// touching our window. 2s is fast enough for "I just clicked
    /// Show in Bartender" feedback and cheap enough to ignore on idle.
    private let menuBarTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            generalSection
            if let manager = menuBarHiddenManager {
                menuBarHiddenSection(manager: manager)
            }
            appearanceSection
        }
        .formStyle(.grouped)
        .navigationTitle(SidebarPage.global.title)
        .navigationSubtitle(SidebarPage.global.subtitle)
        .onAppear { refreshMenuBarStatus() }
        .onReceive(menuBarTimer) { _ in refreshMenuBarStatus() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            // Manager toggles tend to coincide with the user switching
            // back to our window. Catch the change immediately on
            // focus instead of waiting for the 2 s tick.
            refreshMenuBarStatus()
        }
    }

    @ViewBuilder private var generalSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { startupEnabled },
                set: { newValue in
                    if StartupRegistration.setEnabled(newValue) {
                        startupEnabled = newValue
                    }
                })) {
                Text(L.get("global.startup.header", fallback: "Launch at login"))
                Text(L.get("global.startup.desc",
                           fallback: "Run quietly in the background after sign-in"))
            }
        } header: {
            Text(L.get("global.section.general", fallback: "General"))
        }
    }

    @ViewBuilder private var appearanceSection: some View {
        let supported = appearance.systemSupportsLiquidGlass
        Section {
            Toggle(isOn: Binding(
                get: { supported && appearance.liquidGlassMode == .on },
                set: { newValue in
                    appearance.liquidGlassMode = newValue ? .on : .off
                })) {
                Text(L.get("global.liquidGlass.header",
                           fallback: "Liquid Glass design"))
                Text(L.get("global.liquidGlass.desc",
                           fallback: "macOS 26 glass material; older systems fall back to standard translucency"))
            }
            .disabled(!supported)
        } header: {
            Text(L.get("global.section.appearance", fallback: "Appearance"))
        } footer: {
            if !supported {
                Text(L.get("global.liquidGlass.unsupported",
                           fallback: "Current macOS doesn't support Liquid Glass (requires macOS 26 Tahoe or later)."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Menu bar hidden notice

    @ViewBuilder private func menuBarHiddenSection(manager: String) -> some View {
        Section {
            // Title-on-top, description-below — same shape as the
            // System-Settings rows already in this Form. No "Restore"
            // affordance: the only reliable way to un-hide a managed
            // status item is via the manager's own UI; trying to do
            // it ourselves by restarting ControlCenter has left
            // Sequoia in a broken state in earlier revisions.
            VStack(alignment: .leading, spacing: 2) {
                Text(L.get("discovery.menubar.hiddenTitle",
                           fallback: "Menu bar icon hidden"))
                Text(String(format: L.get(
                        "discovery.menubar.hiddenDesc",
                        fallback: "%@ is hiding CouchMC's menu bar icon. Reveal it by clicking the manager's overflow chevron, or open the manager's preferences and move CouchMC into the always-visible group."),
                            manager))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
            Text(L.get("discovery.menubar.section", fallback: "Menu bar"))
        }
    }

    /// Detect whether our `NSStatusItem`'s window is currently
    /// offscreen / behind a manager. Mirrors the same approach
    /// `DeviceDiscoveryView` was using before — query
    /// `CGWindowListCopyWindowInfo` for windows owned by our PID at
    /// `kCGStatusWindowLevel` (25), and decide "hidden" when the
    /// matching window is either flagged offscreen or has a negative
    /// X (Hidden Bar parks its overflow group at e.g. X = -1000).
    private func refreshMenuBarStatus() {
        let myPID = Int(getpid())
        let info = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID)
                    as? [[String: Any]]) ?? []
        var hidden = false
        for w in info {
            guard (w[kCGWindowOwnerPID as String] as? Int) == myPID else { continue }
            guard (w[kCGWindowLayer as String] as? Int) == 25 else { continue }
            let onScreen = w[kCGWindowIsOnscreen as String] as? Bool ?? false
            var offscreenX = false
            if let bounds = w[kCGWindowBounds as String] as? [String: Any],
               let x = bounds["X"] as? Double, x < 0 {
                offscreenX = true
            }
            if !onScreen || offscreenX {
                hidden = true
            }
            break
        }
        if hidden {
            menuBarHiddenManager = detectMenuBarManager()
        } else {
            menuBarHiddenManager = nil
        }
    }

    /// Return the friendly name of whichever menu-bar-manager app is
    /// currently running, so the warning card can name it ("Hidden
    /// Bar is hiding CouchMC's menu bar icon"). Falls back to a
    /// generic name when none of the known bundle IDs match — better
    /// to surface a slightly vague hint than a confusingly empty one.
    private func detectMenuBarManager() -> String {
        let knownManagers: [(bundleIDs: [String], name: String)] = [
            (["com.dwarvesv.minimalbar"], "Hidden Bar"),
            (["com.surteesstudios.Bartender",
              "com.surteesstudios.Bartender-Beta",
              "com.surteesstudios.Bartender4"], "Bartender"),
            (["com.bjango.istatmenus",
              "com.bjango.istatmenus6",
              "com.bjango.istatmenus.status"], "iStat Menus"),
            (["com.matthewpalmer.Vanilla"], "Vanilla"),
        ]
        let running = NSWorkspace.shared.runningApplications
            .compactMap(\.bundleIdentifier)
        for (ids, name) in knownManagers {
            if ids.contains(where: { running.contains($0) }) {
                return name
            }
        }
        return L.get("discovery.menubar.unknownManager", fallback: "Menu bar manager")
    }
}
