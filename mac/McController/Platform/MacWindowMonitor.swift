import Foundation
import AppKit
import ApplicationServices

/// macOS counterpart of `WindowStateMonitor.cs`. Polls the foreground
/// application + cursor visibility every 100 ms with 1-tick debounce
/// and emits `onModeChanged` when the derived `ControllerMode`
/// transitions. Also tracks the MC window's screen-coordinate client
/// rect so `MacCursorInjector` can clamp UI-mode cursor moves.
///
/// Foreground detection: matches `NSRunningApplication.bundleIdentifier`
/// / `localizedName` / executable name against MC-ish strings. Cursor
/// visibility uses `CGCursorIsVisible()` — a long-standing private API
/// used by ~every Mac game runtime, including Steam.
final class MacWindowMonitor: @unchecked Sendable {

    typealias ModeHandler = (Protocol.ControllerMode) -> Void

    private let pollInterval: TimeInterval
    private let queue = DispatchQueue(label: "mc.window.monitor", qos: .userInteractive)
    private var timer: DispatchSourceTimer?

    private var pendingMode: Protocol.ControllerMode?
    private var pendingTicks = 0

    private(set) var currentMode: Protocol.ControllerMode = .antiMistouch
    /// Screen rect of the MC window's content area in CG coordinates
    /// (origin top-left). Empty when MC isn't foreground.
    private(set) var currentClientRect: CGRect = .zero
    private(set) var currentPID: pid_t = 0

    var onModeChanged: ModeHandler?

    init(pollIntervalMs: Int = 100) {
        self.pollInterval = TimeInterval(pollIntervalMs) / 1000.0
    }

    func start() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .milliseconds(50),
                       repeating: pollInterval,
                       leeway: .milliseconds(20))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Polling

    private func tick() {
        let (isMc, pid) = detectForegroundMc()
        let reading: Protocol.ControllerMode
        if !isMc {
            reading = .antiMistouch
        } else if cursorIsVisible() {
            reading = .uiInteract
        } else {
            reading = .inGame
        }

        if reading == currentMode {
            pendingMode = nil
            pendingTicks = 0
        } else if reading == pendingMode {
            pendingTicks += 1
            if pendingTicks >= 1 {
                currentMode = reading
                currentPID = isMc ? pid : 0
                updateClientRect()
                onModeChanged?(reading)
                pendingMode = nil
                pendingTicks = 0
            }
        } else {
            pendingMode = reading
            pendingTicks = 0
        }

        // Keep the client rect fresh even if the mode didn't change —
        // the user may resize / move the MC window.
        if currentMode != .antiMistouch && isMc {
            updateClientRect()
        }
    }

    // MARK: - Foreground detection

    private func detectForegroundMc() -> (Bool, pid_t) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return (false, 0) }
        let bundle = (app.bundleIdentifier ?? "").lowercased()
        let name = (app.localizedName ?? "").lowercased()
        let exe = (app.executableURL?.lastPathComponent ?? "").lowercased()

        let matchers = [
            "minecraft", "mojang", "java",
        ]
        let any = matchers.contains { bundle.contains($0) || name.contains($0) || exe.contains($0) }
        return (any, app.processIdentifier)
    }

    // MARK: - Cursor visibility

    /// `CGCursorIsVisible()` is a private (unsupported) but rock-stable
    /// CG function. Has been around since 10.4 and is used by Steam,
    /// Unity, Unreal, GLFW, SDL, etc. It returns whether the system
    /// cursor is currently shown. When MC's GLFW captures input, it
    /// hides the cursor → returns false → we're InGame. When the user
    /// opens inventory, MC shows the cursor → returns true → UI mode.
    private func cursorIsVisible() -> Bool {
        return _CGCursorIsVisible()
    }

    // MARK: - Client rect

    private func updateClientRect() {
        guard currentPID > 0 else {
            currentClientRect = .zero
            return
        }
        let appElement = AXUIElementCreateApplication(currentPID)

        var focused: CFTypeRef?
        let focusedErr = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focused)
        let window: AXUIElement
        if focusedErr == .success, let f = focused {
            window = f as! AXUIElement
        } else {
            // Fall back to the main window.
            var main: CFTypeRef?
            let mainErr = AXUIElementCopyAttributeValue(
                appElement,
                kAXMainWindowAttribute as CFString,
                &main)
            guard mainErr == .success, let m = main else {
                currentClientRect = .zero
                return
            }
            window = m as! AXUIElement
        }

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &posRef)
        _ = AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)

        var pos = CGPoint.zero
        var size = CGSize.zero
        if let posVal = posRef {
            AXValueGetValue(posVal as! AXValue, .cgPoint, &pos)
        }
        if let sizeVal = sizeRef {
            AXValueGetValue(sizeVal as! AXValue, .cgSize, &size)
        }
        if size.width > 0 && size.height > 0 {
            currentClientRect = CGRect(origin: pos, size: size)
        } else {
            currentClientRect = .zero
        }
    }
}

/// Bridge to the long-lived private `CGCursorIsVisible()` CoreGraphics
/// function. The forwarder is wrapped so swapping it later (e.g., for
/// the eventually-public replacement Apple keeps not shipping) only
/// touches one site.
@_silgen_name("CGCursorIsVisible")
private func _CGCursorIsVisible() -> Bool
