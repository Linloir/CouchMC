import SwiftUI

struct DeviceDiscoveryView: View {

    @EnvironmentObject private var host: ServerHost

    @StateObject private var adb: AdbDiscovery
    @State private var accessibilityGranted: Bool = AccessibilityPermission.isGranted
    @State private var menuBarHiddenManager: String?

    /// Polls every 1 s in addition to the explicit refreshes below.
    /// AX trust changes don't fire any notification we can listen to,
    /// so polling is the fallback. The interval is fast enough that
    /// the user gets near-instant feedback after toggling the switch
    /// in System Settings, and cheap enough not to matter on idle
    /// power.
    private let accessibilityTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    init() {
        _adb = StateObject(wrappedValue: AdbDiscovery(reversePort: Protocol.defaultPort))
    }

    var body: some View {
        Form {
            // Only show the permission card when MC Controller is
            // NOT trusted. Once the user grants Accessibility, the
            // whole section disappears — there's no need to keep
            // telling them about a successfully-resolved state.
            if !accessibilityGranted {
                accessibilitySection
            }
            if let manager = menuBarHiddenManager {
                menuBarHiddenSection(manager: manager)
            }
            statusSection
            usbSection
            lanSection
            networkSection
        }
        .formStyle(.grouped)
        .navigationTitle(SidebarPage.discovery.title)
        .navigationSubtitle(SidebarPage.discovery.subtitle)
        .onAppear {
            adb.start()
            refreshAccessibility()
            refreshMenuBarStatus()
        }
        .onDisappear { adb.stop() }
        .onReceive(accessibilityTimer) { _ in
            refreshAccessibility()
            refreshMenuBarStatus()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibility()
            refreshMenuBarStatus()
        }
    }

    private func refreshAccessibility() {
        let now = AccessibilityPermission.isGranted
        if now != accessibilityGranted { accessibilityGranted = now }
    }

    /// Detects whether our `NSStatusItem` is currently invisible.
    /// Catches both flavors of hiding a menu-bar manager applies:
    ///   - **`kCGWindowIsOnscreen = false`** — `NSStatusItem.isVisible`
    ///     was toggled off (Hidden Bar's "always hide" group does this,
    ///     and the flag persists even after Hidden Bar quits).
    ///   - **`bounds.x < 0`** — the status item's window was moved
    ///     off-screen via the Accessibility API (Bartender's older
    ///     technique).
    private func refreshMenuBarStatus() {
        let myPID = Int(ProcessInfo.processInfo.processIdentifier)
        let info = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID)
                    as? [[String: Any]]) ?? []
        var hidden = false
        for w in info {
            guard (w[kCGWindowOwnerPID as String] as? Int) == myPID else { continue }
            // NSStatusWindowLevel == 25 (Carbon kCGStatusWindowLevel).
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

    /// Detect known menu-bar-manager apps that hide newly-added
    /// `NSStatusItem`s by default. Returns the user-visible product
    /// name we can name in the warning card so the user knows where
    /// to look.
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

    @ViewBuilder private func menuBarHiddenSection(manager: String) -> some View {
        Section {
            // No "Restore" button. The previous revision called into
            // `AppDelegate.forceStatusItemVisible()` which restarted
            // ControlCenter via `launchctl kickstart -k` — that's
            // observed to occasionally leave the system menu bar in
            // a broken state on Sequoia. An app must not restart
            // system-owned launchd services. We just inform the user
            // and let them take action in the manager's own UI.
            titleDesc(
                title: L.get("discovery.menubar.hiddenTitle",
                             fallback: "Menu bar icon hidden"),
                description: String(
                    format: L.get(
                        "discovery.menubar.hiddenDesc",
                        fallback: "%@ is hiding MC Controller's menu bar icon. Reveal it by clicking the manager's overflow chevron, or open the manager's preferences and move MC Controller into the always-visible group."),
                    manager))
                .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
            sectionHeader(L.get("discovery.menubar.section", fallback: "Menu bar"))
        }
    }

    // MARK: - Sections

    @ViewBuilder private var accessibilitySection: some View {
        Section {
            LabeledContent {
                HStack(spacing: 8) {
                    // Two-button row: the primary path is "Open
                    // System Settings" so the user can flip the
                    // switch; the secondary "Reset" calls
                    // `tccutil reset Accessibility` which clears the
                    // stale TCC entry and lets the next launch
                    // trigger a fresh authorization prompt — the
                    // reliable fix when System Settings shows the
                    // switch as ON but `AXIsProcessTrusted()` still
                    // returns false (typical after a rebuild, since
                    // TCC keys grants on the binary's cdhash).
                    Button(L.get("discovery.permission.reset",
                                 fallback: "Reset")) {
                        AccessibilityPermission.resetTrust()
                    }
                    Button(L.get("discovery.permission.open",
                                 fallback: "Open System Settings")) {
                        AccessibilityPermission.openSystemSettings()
                    }
                    .buttonStyle(.borderedProminent)
                }
            } label: {
                titleDesc(
                    title: L.get("discovery.permission.header", fallback: "Accessibility"),
                    description: L.get("discovery.permission.descStale",
                                       fallback: "If you've enabled the switch in System Settings but still see this, click Reset — rebuilds invalidate the previous grant and Reset clears the stale TCC entry so the next launch re-prompts cleanly."))
            }
        } header: {
            sectionHeader(L.get("discovery.permission.section", fallback: "Permission"))
        }
    }

    @ViewBuilder private var statusSection: some View {
        Section {
            LabeledContent {
                Text(host.isClientConnected
                     ? L.get("discovery.pill.connected", fallback: "Connected")
                     : L.get("discovery.pill.disconnected", fallback: "Idle"))
                    .foregroundStyle(host.isClientConnected ? .green : .secondary)
            } label: {
                Text(L.get("discovery.status.header", fallback: "Current connection"))
            }
            if let ep = host.lastClientEndpoint, host.isClientConnected {
                LabeledContent(L.get("discovery.status.endpoint", fallback: "Endpoint"),
                               value: ep)
            }
            LabeledContent(L.get("discovery.status.port", fallback: "Listening port"),
                           value: "TCP/UDP \(host.config.port)")
        } header: {
            sectionHeader(L.get("discovery.status.section", fallback: "Status"))
        }
    }

    @ViewBuilder private var usbSection: some View {
        Section {
            if adb.devices.isEmpty {
                titleDesc(
                    title: L.get("discovery.usb.emptyTitle",
                                 fallback: "No USB device detected"),
                    description: L.get("discovery.usb.emptyDesc",
                                       fallback: "Plug in a phone with USB debugging enabled"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(adb.devices) { device in
                    LabeledContent {
                        if device.hasControllerApp {
                            Text(L.get("discovery.usb.appInstalled",
                                       fallback: "App installed"))
                                .font(.caption)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.green.opacity(0.18), in: Capsule())
                        }
                    } label: {
                        titleDesc(title: device.model, description: device.subtitle)
                    }
                }
            }
        } header: {
            sectionHeader(L.get("discovery.usb.section", fallback: "USB"))
        } footer: {
            // The auto-`adb reverse` mechanism is fully implicit —
            // the user doesn't need to know about it. Only the
            // bundled-adb-missing error stays, because that one
            // is actionable.
            if !adb.adbAvailable {
                Text(L.get("discovery.usb.adbMissing",
                           fallback: "Bundled adb missing — run scripts/fetch-adb.sh"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var lanSection: some View {
        Section {
            // Same empty-state pattern as the USB section: a single
            // title-on-top / description-below row inside the
            // grouped container. We don't actually maintain a list of
            // LAN-discovered *clients* (the server only advertises),
            // so this card is the steady-state — it's "we're waiting,
            // here's how to find us".
            titleDesc(
                title: L.get("discovery.lan.emptyTitle",
                             fallback: "No LAN device connected yet"),
                description: L.get("discovery.lan.emptyDesc",
                                   fallback: "We're broadcasting on the local network; the phone's connect screen will list this Mac."))
                .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
            sectionHeader(L.get("discovery.lan.section", fallback: "LAN"))
        }
    }

    @ViewBuilder private var networkSection: some View {
        Section {
            ForEach(host.localIPv4s, id: \.self) { ip in
                Text(ip)
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } header: {
            sectionHeader(L.get("discovery.net.section", fallback: "This computer"))
        } footer: {
            Text(L.get("discovery.net.desc",
                       fallback: "Type any of these into the phone (WiFi mode)"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Helpers

    /// Title-on-top, description-below pattern. Matches the LabeledContent
    /// label style native System Settings uses for items that need a
    /// secondary explanation under the main label.
    @ViewBuilder
    private func titleDesc(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Section header — small bold gray text. Apple's grouped Form
    /// style on macOS renders Section headers in a consistent
    /// caption-sized font; explicit styling here keeps the rendering
    /// stable across Tahoe / earlier.
    @ViewBuilder
    private func sectionHeader(_ text: String) -> some View {
        Text(text)
    }
}
