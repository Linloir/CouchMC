import AppKit

/// AppKit bridge for lifecycle behaviors SwiftUI doesn't model:
///
/// 1. **Menu bar item** — built manually with `NSStatusItem` instead
///    of SwiftUI's `MenuBarExtra` because we want the AppKit-classic
///    split where **left-click toggles the main window and right-click
///    opens a context menu**. SwiftUI's `MenuBarExtra` only supports
///    "click → open menu" or "click → open popover".
///
/// 2. **Hide-on-close** — the red close button is intercepted so the
///    window goes away (`orderOut`) without destroying the scene or
///    quitting the process. The server keeps running in the
///    background; the user reopens via the menu bar icon.
///
/// 3. **Don't quit when last window closes** — paired with #2.
///
/// 4. **Click-outside-to-defocus** — clicking anywhere that isn't a
///    text input clears the first responder so the active `TextField`
///    stops grabbing keyboard input. Matches macOS Settings / Mail.
///
/// ## Status item lifecycle (read this before refactoring!)
///
/// **Minimal + read-only**:
///
/// - **Launch**: `installStatusItem()` runs once. No retry, no
///   auto-heal. macOS picks a position; if it lands behind the
///   MBP notch (typical when the app is launched from a
///   DerivedData / build path), the user installs to
///   `/Applications` via `scripts/install.sh` to give the bundle
///   a canonical location — that fixes the placement.
/// - **`applicationDidBecomeActive`**: explicitly does NOTHING for
///   the status item. An earlier revision auto-recreated the item
///   here on every activation; combined with a delayed check in
///   `applicationDidFinishLaunching`, the two paths interleaved
///   and produced phantom duplicate `NSStatusItem` windows in
///   `CGWindowList` (one at x≈729 behind the notch, another at
///   x=-847 off-screen). One source of truth.
/// - **No "Restore" / self-heal button**: an earlier revision
///   exposed `forceStatusItemVisible()` that issued
///   `launchctl kickstart -k com.apple.controlcenter` to rebuild
///   the menu bar. **Removed permanently.** That was observed to
///   leave ControlCenter in `state = not running` on Sequoia (the
///   whole system menu bar disappeared); in one case the entire
///   Finder + Dock + WindowServer chain became unstable until a
///   full reboot. **An app must never restart system-owned
///   launchd services.** If a third-party menu bar manager
///   (Hidden Bar / Bartender) is hiding the icon, we surface a
///   read-only explanation in the Discovery view and tell the
///   user to act in that manager's UI.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    private(set) var statusItem: NSStatusItem?
    private var clickOutsideMonitor: Any?

    // MARK: - NSApplicationDelegate

    func applicationDidFinishLaunching(_ notification: Notification) {
        installStatusItem()
        installClickOutsideToDefocus()
        // Window-delegate wiring waits for the next runloop tick so
        // SwiftUI's WindowGroup has time to materialize the NSWindow.
        DispatchQueue.main.async { [weak self] in self?.configureMainWindow() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // No-op (see class-level comment).
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false  // hide-to-bar semantics
    }

    /// Triggered when the user clicks the Dock icon (or `open`s the
    /// bundle while it's already running). Re-show the main window
    /// if it's hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppEnvironment.shared.host.stop()
    }

    // MARK: - Status item

    private func installStatusItem() {
        // `.variableLength` is the canonical choice for text+image
        // items. We briefly tried `.squareLength` to dodge MBP-14
        // notch placement issues — empirically that produced *two*
        // status item windows at x=274 / x=1850, both invisible.
        // Sticking with variableLength.
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let image = NSImage(named: "MenuBarIcon") {
            image.isTemplate = true  // adapts to dark/light menu bar
            item.button?.image = image
        }
        if let button = item.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = L.get("app.tooltip", fallback: "CouchMC")
        }
        statusItem = item
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            toggleMainWindow()
            return
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            presentContextMenu()
        } else {
            toggleMainWindow()
        }
    }

    private func presentContextMenu() {
        guard let button = statusItem?.button else { return }
        let menu = NSMenu()

        let openItem = NSMenuItem(
            title: L.get("tray.open", fallback: "Open Panel"),
            action: #selector(menuOpenMainWindow),
            keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: L.get("tray.exit", fallback: "Quit Service"),
            action: #selector(menuQuit),
            keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        // `NSMenu.popUp(positioning:at:in:)` displays the menu and
        // dispatches the chosen item's action synchronously — no
        // race with `statusItem.menu = nil`. The previous revision
        // toggled `statusItem.menu` around a `performClick(nil)`
        // call, which sometimes returned before the menu was
        // dismissed and clobbered the action target before macOS
        // could fire it. Using `popUp` directly is the documented
        // pattern for ad-hoc context menus from a status item.
        let origin = NSPoint(x: 0, y: button.bounds.maxY + 4)
        menu.popUp(positioning: nil, at: origin, in: button)
    }

    // Note: an earlier revision of this file exposed a
    // `forceStatusItemVisible()` method that would `launchctl
    // kickstart -k` the system menu-bar daemon (`ControlCenter`
    // on Sequoia, `SystemUIServer` on older). It was wired to a
    // "Restore Icon" button in the Discovery view as an escape
    // hatch when our status item ended up off-screen.
    //
    // **It has been deliberately removed.** An app must NEVER
    // restart system-owned launchd services. The risk:
    //
    //   • On Sequoia 15.x, `launchctl stop / kickstart -k` on
    //     `com.apple.controlcenter` was observed to leave the
    //     service in `state = not running` — launchd did not
    //     auto-respawn it. The entire system menu bar (clock,
    //     Wi-Fi, Bluetooth, battery, Control Center button)
    //     disappeared until the user manually `launchctl kickstart`'d
    //     the service, and in one observed case the whole Finder
    //     + Dock + WindowServer chain became unstable until a
    //     full reboot.
    //   • Even when it works, killing ControlCenter / Dock
    //     briefly flashes every other status icon across the
    //     menu bar, which is a hostile UX for fixing *our* one
    //     icon's placement.
    //
    // The right answer to "status item placed off-screen because
    // a third-party menu-bar manager hid it" is **out-of-process**:
    // tell the user to open that manager's preferences and
    // whitelist McController, or quit it. We never reach into
    // launchctl from the app.

    // MARK: - Click-outside-to-defocus

    private func installClickOutsideToDefocus() {
        clickOutsideMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) {
            [weak self] event in
            self?.handleLeftMouseDown(event)
            return event
        }
    }

    private func handleLeftMouseDown(_ event: NSEvent) {
        guard let window = event.window else { return }
        let location = event.locationInWindow
        guard let hitView = window.contentView?.hitTest(location) else { return }
        if isTextInput(hitView) { return }
        // Defer so the click is dispatched to its target view first;
        // clearing the first responder synchronously here would race
        // with SwiftUI's own focus bookkeeping.
        DispatchQueue.main.async {
            window.makeFirstResponder(nil)
        }
    }

    /// Walk up the view hierarchy looking for an editable text input.
    /// Covers AppKit's `NSTextView` / `NSTextField` and SwiftUI's
    /// private text-field hosting views (class names contain
    /// `TextField` / `TextView`).
    private func isTextInput(_ view: NSView) -> Bool {
        var current: NSView? = view
        while let v = current {
            if v is NSTextView || v is NSTextField {
                return true
            }
            let name = NSStringFromClass(type(of: v))
            if name.contains("TextField") || name.contains("TextView") {
                return true
            }
            current = v.superview
        }
        return false
    }

    // MARK: - Window plumbing

    /// Attach this delegate to every SwiftUI-spawned NSWindow so we
    /// can intercept close. Idempotent — safe to re-run.
    private func configureMainWindow() {
        for window in NSApp.windows where window.canBecomeMain {
            window.isReleasedWhenClosed = false
            if window.delegate !== self { window.delegate = self }
            stripSidebarToggle(from: window)
        }
    }

    /// Remove the `NavigationSplitView`'s sidebar-toggle item from the
    /// window's `NSToolbar`. SwiftUI's documented
    /// `.toolbar(removing: .sidebarToggle)` modifier is silently
    /// ignored on macOS 14 / 15 for `NavigationSplitView` —
    /// the item shows up regardless. The only reliable workaround is
    /// to reach down to AppKit and strip it directly.
    ///
    /// Defensive characteristics:
    ///   - **Pattern-matched on identifier**, not a hardcoded string
    ///     (SwiftUI's private identifiers shift between macOS
    ///     versions). Anything containing "toggleSidebar" /
    ///     "SidebarToggle" gets stripped.
    ///   - **Re-applied lazily**: SwiftUI re-populates the toolbar
    ///     across some scene-update paths, so we call this from
    ///     every window-delegate notification that might follow a
    ///     toolbar rebuild (`windowDidBecomeKey`, `windowDidUpdate`).
    private func stripSidebarToggle(from window: NSWindow) {
        guard let toolbar = window.toolbar else { return }
        for (idx, item) in toolbar.items.enumerated().reversed() {
            let id = item.itemIdentifier.rawValue
            if id.localizedCaseInsensitiveContains("toggleSidebar")
                || id.localizedCaseInsensitiveContains("sidebarToggle") {
                toolbar.removeItem(at: idx)
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    /// SwiftUI re-populates the window's toolbar across various scene
    /// update events; calling `stripSidebarToggle` here keeps it
    /// removed even after SwiftUI tries to put it back.
    func windowDidBecomeKey(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            stripSidebarToggle(from: window)
        }
    }

    func windowDidUpdate(_ notification: Notification) {
        if let window = notification.object as? NSWindow {
            stripSidebarToggle(from: window)
        }
    }

    private func toggleMainWindow() {
        if let window = mainWindow() {
            // Hide only when the window is **fully present in the
            // foreground** — visible, not miniaturized, and the
            // current key window of an active app. Any other state
            // (behind another app, hidden, minimized) means the
            // user clicked the status item to *recover* the window,
            // not to dismiss it.
            let shouldHide = window.isVisible
                && !window.isMiniaturized
                && NSApp.isActive
                && window.isKeyWindow
            if shouldHide {
                window.orderOut(nil)
            } else {
                showMainWindow(window: window)
            }
        } else {
            showMainWindow()
        }
    }

    /// Bring the main window to the foreground, surfacing it from
    /// any of: hidden behind another app, ordered-out (red-X
    /// close → our `windowShouldClose` hid it), or miniaturized
    /// (yellow button → in the Dock). If SwiftUI destroyed the
    /// window entirely (observed in some macOS 14/15 builds
    /// despite `isReleasedWhenClosed = false`), trigger a reopen
    /// via `NSWorkspace.shared.open(bundleURL)` so the
    /// `WindowGroup` rebuilds the scene.
    private func showMainWindow(window: NSWindow? = nil) {
        NSApp.activate(ignoringOtherApps: true)
        guard let target = window ?? mainWindow() else {
            // No NSWindow we can revive. Asking the system to
            // "open" our bundle URL routes through
            // `applicationShouldHandleReopen` (which returns true)
            // and SwiftUI's `WindowGroup` recreates the scene.
            NSWorkspace.shared.open(Bundle.main.bundleURL)
            return
        }
        // `makeKeyAndOrderFront(_:)` alone does NOT deminiaturize.
        // A minimized window stays in the Dock as a thumbnail
        // even after the call returns. Surface it explicitly.
        if target.isMiniaturized {
            target.deminiaturize(nil)
        }
        // Re-attach the window delegate idempotently — newly-
        // recreated SwiftUI windows lose it, which would let the
        // next red-X close destroy the scene instead of hiding.
        if target.delegate !== self {
            target.isReleasedWhenClosed = false
            target.delegate = self
        }
        target.makeKeyAndOrderFront(nil)
    }

    private func mainWindow() -> NSWindow? {
        NSApp.windows.first { $0.canBecomeMain && $0.identifier?.rawValue == "main" }
            ?? NSApp.windows.first { $0.canBecomeMain }
    }

    // MARK: - Menu actions

    @objc private func menuOpenMainWindow() { showMainWindow() }

    @objc private func menuQuit() { NSApp.terminate(nil) }
}
