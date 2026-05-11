import Foundation

/// 3-state server-driven mode.
///
/// The PC server polls Minecraft's foreground state + cursor visibility every
/// 100ms and pushes a STATE_CHANGE whenever the derived mode changes. The
/// client renders different controllers per mode and resets all gesture FSMs
/// on transition.
enum ControllerMode: UInt8, Sendable, Equatable {
    case inGame        = 0  // full controller (joystick + buttons + hotbar)
    case uiInteract    = 1  // LookPad drives cursor, reduced button set
    case antiMistouch  = 2  // lock overlay; input blocked

    init(wireByte: UInt8) {
        self = ControllerMode(rawValue: wireByte) ?? .antiMistouch
    }
}
