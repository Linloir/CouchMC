import Foundation

/// Wire protocol constants. Mirror of the PC server's Protocol.cs and the
/// Android client's Protocol.kt.
/// Authoritative spec: docs/protocol.md
enum Protocol {
    static let version: UInt8 = 1
    static let defaultPort: UInt16 = 34555
    static let discoveryPort: UInt16 = 34556

    /// All wire camera-delta values are tenths-of-pixel. The client multiplies
    /// its finger-pixel delta by this before encoding; the server divides.
    static let subpixelScale: CGFloat = 10

    /// Joystick fixed-point: actual_value × 10000 is sent as int16.
    static let joystickScale: Float = 10000

    enum MsgType {
        static let hello: UInt8       = 0x01
        static let helloAck: UInt8    = 0x02
        static let stateChange: UInt8 = 0x03
        static let joystick: UInt8    = 0x10
        static let lookDelta: UInt8   = 0x11   // both TCP and UDP carry this id
        static let button: UInt8      = 0x20
        static let ping: UInt8        = 0xF0
        static let pong: UInt8        = 0xF1
        static let probe: UInt8       = 0xFE
        static let probeAck: UInt8    = 0xFF
    }

    enum ProbeStatus: UInt8 {
        case alive  = 0x00
        case busy   = 0x01
        case incompatible = 0x02
    }

    enum HelloAckStatus: UInt8 {
        case ok               = 0
        case protocolMismatch = 1
        case serverBusy       = 2
    }

    /// PC binding IDs. Mirror of `Protocol.kt` and PC `ButtonId`.
    enum ButtonId: UInt8, CaseIterable {
        case mouseLeft  = 0x01
        case mouseRight = 0x02
        case jump       = 0x10
        case sneak      = 0x11
        case sprint     = 0x12
        case inventory  = 0x20
        case drop       = 0x21
        case swapHand   = 0x22
        case esc        = 0x30
        case hotbar1    = 0x40
        case hotbar2    = 0x41
        case hotbar3    = 0x42
        case hotbar4    = 0x43
        case hotbar5    = 0x44
        case hotbar6    = 0x45
        case hotbar7    = 0x46
        case hotbar8    = 0x47
        case hotbar9    = 0x48

        static func hotbar(_ slot: Int) -> ButtonId {
            precondition((0...8).contains(slot))
            return ButtonId(rawValue: UInt8(0x40 + slot))!
        }
    }
}
