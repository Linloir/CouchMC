import Foundation

/// Abstraction over OS-level input injection. The production
/// implementation on macOS is `CGEventInjector` (CoreGraphics events);
/// tests can supply a fake recording variant. Mirrors `IInputInjector`
/// from the PC side.
protocol InputInjector: AnyObject {
    /// Post a relative mouse move (raw delta). On macOS in-game this
    /// becomes a `kCGEventMouseMoved` carrying the delta fields, which
    /// MC's GLFW capture consumes the same way it does on Windows
    /// `SendInput(MOUSEEVENTF_MOVE)`.
    func mouseMoveRelative(dx: Int, dy: Int)

    /// Press / release a mouse button.
    func setMouseButton(_ button: MouseButton, down: Bool)

    /// Press / release a key. `keyCode` is the *macOS virtual key code*
    /// (e.g. `kVK_ANSI_W = 13`) — NOT a Windows scancode.
    func key(_ keyCode: UInt16, down: Bool)
}

enum MouseButton {
    case left, right, middle
}
