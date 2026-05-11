package com.mccontroller.net

/**
 * Wire protocol constants. Mirror of the PC server's Protocol.cs.
 * Authoritative spec: docs/protocol.md
 */
object Protocol {
    const val VERSION: Byte = 1
    const val DEFAULT_PORT = 34555

    object MsgType {
        const val HELLO: Byte = 0x01
        const val HELLO_ACK: Byte = 0x02
        const val STATE_CHANGE: Byte = 0x03   // S->C: mode 0/1/2
        const val JOYSTICK: Byte = 0x10
        const val LOOK_DELTA_TCP: Byte = 0x11
        const val LOOK_DELTA_UDP: Byte = 0x11
        const val BUTTON: Byte = 0x20
        const val PING: Byte = 0xF0.toByte()
        const val PONG: Byte = 0xF1.toByte()
        const val PROBE: Byte = 0xFE.toByte()       // C->S, session-less reachability check
        const val PROBE_ACK: Byte = 0xFF.toByte()   // S->C, response to PROBE
    }

    object ProbeStatus {
        const val ALIVE: Byte = 0x00
        const val BUSY: Byte = 0x01
        const val PROTOCOL_INCOMPATIBLE: Byte = 0x02
    }

    object HelloAckStatus {
        const val OK: Byte = 0
        const val PROTOCOL_MISMATCH: Byte = 1
        const val SERVER_BUSY: Byte = 2
    }

    object ButtonId {
        const val MOUSE_LEFT: Byte = 0x01
        const val MOUSE_RIGHT: Byte = 0x02
        const val JUMP: Byte = 0x10
        const val SNEAK: Byte = 0x11
        const val SPRINT: Byte = 0x12
        const val INVENTORY: Byte = 0x20
        const val DROP: Byte = 0x21
        const val SWAP_HAND: Byte = 0x22
        const val ESC: Byte = 0x30
        const val HOTBAR_1: Byte = 0x40
        const val HOTBAR_2: Byte = 0x41
        const val HOTBAR_3: Byte = 0x42
        const val HOTBAR_4: Byte = 0x43
        const val HOTBAR_5: Byte = 0x44
        const val HOTBAR_6: Byte = 0x45
        const val HOTBAR_7: Byte = 0x46
        const val HOTBAR_8: Byte = 0x47
        const val HOTBAR_9: Byte = 0x48
    }
}
