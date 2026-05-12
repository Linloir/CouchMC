import SwiftUI

struct DeviceDiscoveryView: View {

    @EnvironmentObject private var host: ServerHost

    @StateObject private var adb: AdbDiscovery
    @State private var accessibilityGranted: Bool = AccessibilityPermission.isGranted
    // The "menu bar icon hidden" notice now lives on the Global
    // Settings page — conceptually it belongs with launch-at-login
    // and the rest of "how does this app sit in the menu bar"
    // preferences. Removed from this page to avoid duplication.

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
        }
        .onDisappear { adb.stop() }
        .onReceive(accessibilityTimer) { _ in
            refreshAccessibility()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibility()
        }
    }

    private func refreshAccessibility() {
        let now = AccessibilityPermission.isGranted
        if now != accessibilityGranted { accessibilityGranted = now }
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
