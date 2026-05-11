import Foundation
import CoreGraphics

/// Drives the system cursor for UI-mode interactions (inventory /
/// menu navigation) by posting synthetic `mouseMoved` CGEvents at
/// the target position. Clamps the new position to MC's window rect
/// from `MacWindowMonitor` so the cursor can't drift outside the
/// game window.
///
/// **Why posted events, not `CGWarpMouseCursorPosition`**:
/// `CGWarpMouseCursorPosition` moves the cursor sprite but emits
/// *no input event* — the foreground app (MC's GLFW / NSWindow)
/// has no way to learn the cursor moved. The user observed exactly
/// this: "看屏幕上鼠标确实动了，但游戏好像不知道一样" — clicks kept
/// registering at the pre-move cell because MC's internal cursor
/// cache hadn't been told to update.
///
/// A posted `kCGEventMouseMoved` at `.cghidEventTap` does both jobs:
///   1. **Moves the cursor sprite** (Quartz interprets the event's
///      `mouseCursorPosition` field as an explicit placement).
///   2. **Delivers a real input event** that propagates through
///      WindowServer to MC's NSWindow, so GLFW's cursor cache
///      stays current.
final class MacCursorInjector {

    private let monitor: MacWindowMonitor
    private let source: CGEventSource?

    /// The point we most recently moved the cursor to. Read by
    /// `CGEventInjector` when posting click events in UI-interact
    /// mode as a backstop against the kernel's ~250 ms mouse-arrival
    /// filter: even though our posted `mouseMoved` event *should*
    /// update `CGEvent.location` immediately, a stale read would
    /// still send the click to the pre-move cell.
    ///
    /// `nil` until the first move; the injector falls back to
    /// querying the system in that case (in-game mode never moves
    /// the cursor absolutely, so `nil` is the steady state there).
    private(set) var lastWarpedPosition: CGPoint?
    private let positionLock = NSLock()

    init(monitor: MacWindowMonitor) {
        self.monitor = monitor
        self.source = CGEventSource(stateID: .hidSystemState)
    }

    func applyDelta(dx: Int, dy: Int) {
        let here = lastWarpedPosition ?? currentCursorLocation() ?? .zero
        var newX = here.x + CGFloat(dx)
        var newY = here.y + CGFloat(dy)

        let rect = monitor.currentClientRect
        if rect.width > 0 && rect.height > 0 {
            newX = max(rect.minX, min(newX, rect.maxX - 1))
            newY = max(rect.minY, min(newY, rect.maxY - 1))
        }

        let target = CGPoint(x: newX, y: newY)

        // Post a real mouseMoved event at the target. This both moves
        // the cursor sprite AND notifies MC. See the class-level
        // comment for the full reasoning.
        if let evt = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: target,
            mouseButton: .left) {
            evt.post(tap: .cghidEventTap)
        }

        positionLock.lock()
        lastWarpedPosition = target
        positionLock.unlock()
    }

    /// Discard the cached warp position. Called when the controller
    /// flips out of `uiInteract` mode — in `inGame` mode MC owns the
    /// cursor and we should fall back to live system queries; in
    /// `antiMistouch` the connection is essentially idle. The next
    /// UI-mode warp will repopulate the cache.
    func clearCachedPosition() {
        positionLock.lock()
        lastWarpedPosition = nil
        positionLock.unlock()
    }

    private func currentCursorLocation() -> CGPoint? {
        // Cheapest way to ask "where is the cursor right now?": create
        // a hostlessly-sourced CGEvent and read its `location`. Equivalent
        // to `NSEvent.mouseLocation` but works without an active runloop
        // and doesn't require AppKit on the call site.
        if let evt = CGEvent(source: nil) {
            return evt.location
        }
        return nil
    }
}
