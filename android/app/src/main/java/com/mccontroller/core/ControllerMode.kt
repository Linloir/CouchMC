package com.mccontroller.core

/**
 * Mode pushed by the PC server based on detected MC window/cursor state.
 * Drives which Android UI layer is visible.
 */
enum class ControllerMode(val byteValue: Byte) {
    /** MC focused + GLFW cursor captured. Full controller (joystick + buttons). */
    InGame(0),

    /** MC focused but cursor visible. LookPad drives cursor; reduced button set. */
    UiInteract(1),

    /** MC not in foreground. Lock screen overlay; reject most input. */
    AntiMistouch(2);

    companion object {
        fun fromByte(b: Byte): ControllerMode = when (b.toInt()) {
            0 -> InGame
            1 -> UiInteract
            else -> AntiMistouch  // 2 or unknown → safe default
        }
    }
}
