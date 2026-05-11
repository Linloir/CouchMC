import Foundation

/// Wire protocol constants, mirrored from `docs/protocol.md`. Both the
/// Android and PC implementations must agree on these — see
/// `pc/McController.Core/Net/Protocol.cs` for the Windows source of truth.
enum Protocol {
    static let version: UInt8 = 1
    static let defaultPort: Int = 34555

    enum MsgType {
        static let hello: UInt8         = 0x01
        static let helloAck: UInt8      = 0x02
        static let stateChange: UInt8   = 0x03
        static let joystick: UInt8      = 0x10
        static let lookDeltaTcp: UInt8  = 0x11
        static let lookDeltaUdp: UInt8  = 0x11
        static let button: UInt8        = 0x20
        static let ping: UInt8          = 0xF0
        static let pong: UInt8          = 0xF1
        static let probe: UInt8         = 0xFE
        static let probeAck: UInt8      = 0xFF
    }

    enum HelloAckStatus {
        static let ok: UInt8               = 0
        static let protocolMismatch: UInt8 = 1
        static let serverBusy: UInt8       = 2
    }

    enum ProbeAckStatus {
        static let alive: UInt8                = 0
        static let busy: UInt8                 = 1
        static let protocolIncompatible: UInt8 = 2
    }

    /// Operating mode driven by PC-side window/cursor state. Sent to the
    /// client via STATE_CHANGE so the phone UI can reshape itself.
    enum ControllerMode: UInt8 {
        case inGame       = 0  // MC focused + cursor captured by GLFW
        case uiInteract   = 1  // MC focused + cursor visible (inventory/menu)
        case antiMistouch = 2  // MC not in foreground
    }

    enum ButtonId {
        static let mouseLeft: UInt8  = 0x01
        static let mouseRight: UInt8 = 0x02
        static let jump: UInt8       = 0x10
        static let sneak: UInt8      = 0x11
        static let sprint: UInt8     = 0x12
        static let inventory: UInt8  = 0x20
        static let drop: UInt8       = 0x21
        static let swapHand: UInt8   = 0x22
        static let esc: UInt8        = 0x30
        static let hotbar1: UInt8    = 0x40
        static let hotbar2: UInt8    = 0x41
        static let hotbar3: UInt8    = 0x42
        static let hotbar4: UInt8    = 0x43
        static let hotbar5: UInt8    = 0x44
        static let hotbar6: UInt8    = 0x45
        static let hotbar7: UInt8    = 0x46
        static let hotbar8: UInt8    = 0x47
        static let hotbar9: UInt8    = 0x48
    }
}
