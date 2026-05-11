import Foundation
import CoreGraphics

/// macOS implementation of `InputInjector`. Posts CG events to
/// `kCGHIDEventTap` so MC (foreground) receives them as if they came
/// from a real keyboard/mouse. Requires Accessibility permission —
/// `AccessibilityPermission.ensurePromptIfNeeded()` should be called
/// at app startup so the user gets the one-time system prompt.
///
/// The event source is created once with `.hidSystemState` and reused
/// across calls — `nil` would work but a shared source is recommended
/// in CG docs for reducing per-event overhead.
final class CGEventInjector: InputInjector {

    private let source: CGEventSource?

    /// Optional override for "where is the cursor right now?". When
    /// the server is in UI-interact mode, `MacCursorInjector` has
    /// just warped the cursor via `CGWarpMouseCursorPosition`; the
    /// kernel's reply to `CGEvent(source:).location` lags by
    /// up to ~250 ms (the mouse-arrival filter), so reading from
    /// it would post the click at the pre-warp cell. The closure
    /// here returns the warp target instead, which is canonical.
    ///
    /// `nil` return means "I don't have a better answer, fall back
    /// to the system query" — that's the steady state in in-game
    /// mode, where MC owns the cursor and we never warp.
    private let cursorPositionOverride: () -> CGPoint?

    // Track held buttons so we know whether the next mouse-moved event
    // should be a drag (button-down) or a plain move. MC doesn't care
    // about this distinction, but if a player happens to be in UI mode
    // with LMB held over an item, dragging needs the .leftDragged event
    // type for the system cursor to surface a drag interaction.
    private var leftHeld = false
    private var rightHeld = false
    private var middleHeld = false

    init(cursorPositionOverride: @escaping () -> CGPoint? = { nil }) {
        self.source = CGEventSource(stateID: .hidSystemState)
        self.cursorPositionOverride = cursorPositionOverride
    }

    // MARK: - Mouse

    func mouseMoveRelative(dx: Int, dy: Int) {
        if dx == 0 && dy == 0 { return }
        // `kCGEventMouseMoved` carrying delta fields is the macOS
        // equivalent of `MOUSEEVENTF_MOVE` relative on Windows. The
        // `mouseCursorPosition` argument is required (CG won't post a
        // mouse event without one), but MC's GLFW capture reads from
        // the delta fields and ignores the absolute position field.
        let eventType: CGEventType
        if leftHeld { eventType = .leftMouseDragged }
        else if rightHeld { eventType = .rightMouseDragged }
        else if middleHeld { eventType = .otherMouseDragged }
        else { eventType = .mouseMoved }

        let here = currentCursorLocation()
        guard let evt = CGEvent(
            mouseEventSource: source,
            mouseType: eventType,
            mouseCursorPosition: here,
            mouseButton: middleHeld ? .center : (rightHeld ? .right : .left))
        else { return }
        evt.setIntegerValueField(.mouseEventDeltaX, value: Int64(dx))
        evt.setIntegerValueField(.mouseEventDeltaY, value: Int64(dy))
        evt.post(tap: .cghidEventTap)
    }

    func setMouseButton(_ button: MouseButton, down: Bool) {
        let here = currentCursorLocation()
        let (eventType, cgButton): (CGEventType, CGMouseButton)
        switch button {
        case .left:
            eventType = down ? .leftMouseDown : .leftMouseUp
            cgButton = .left
            leftHeld = down
        case .right:
            eventType = down ? .rightMouseDown : .rightMouseUp
            cgButton = .right
            rightHeld = down
        case .middle:
            eventType = down ? .otherMouseDown : .otherMouseUp
            cgButton = .center
            middleHeld = down
        }
        guard let evt = CGEvent(
            mouseEventSource: source,
            mouseType: eventType,
            mouseCursorPosition: here,
            mouseButton: cgButton) else { return }
        // Click count = 1 keeps it from registering as a double-click on
        // rapid press patterns; MC doesn't use double-click semantics
        // anyway. The HOLD-mode gesture in the phone client maps to
        // a single down/up bracket, never multi-click.
        evt.setIntegerValueField(.mouseEventClickState, value: 1)
        evt.post(tap: .cghidEventTap)
    }

    // MARK: - Keyboard

    func key(_ keyCode: UInt16, down: Bool) {
        guard let evt = CGEvent(
            keyboardEventSource: source,
            virtualKey: keyCode,
            keyDown: down) else { return }
        evt.post(tap: .cghidEventTap)
    }

    // MARK: - Helpers

    /// Best-available current cursor location, in screen-space CGPoint
    /// (top-left origin). Prefers the override (when UI-interact mode
    /// has just warped the cursor — see `cursorPositionOverride`
    /// comment); falls back to `CGEvent(source:).location` otherwise,
    /// which is what in-game mode wants (deltas; cursor field
    /// effectively ignored by MC's GLFW capture).
    private func currentCursorLocation() -> CGPoint {
        if let overridden = cursorPositionOverride() {
            return overridden
        }
        if let evt = CGEvent(source: nil) {
            return evt.location
        }
        return .zero
    }
}
