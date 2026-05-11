import Foundation

/// Stateless encode/decode for the wire protocol. All multi-byte fields are
/// big-endian.
///
/// TCP frame:    `[u16 len][u8 type][payload (len-1 bytes)]`
/// UDP datagram: `[u8 type][u32 seq][payload]`
enum PacketCodec {

    struct FrameRead: Equatable {
        let bytesConsumed: Int
        let message: ControlMessage
    }

    // MARK: - Outgoing (client → server)

    static func encodeHello(protoVer: UInt8, clientId: UInt32, wantsUdp: Bool) -> Data {
        // payload: protoVer(1) + clientId(4) + wantsUdp(1) = 6 bytes
        var d = Data(capacity: 2 + 1 + 6)
        d.appendUInt16BE(1 + 6)
        d.append(Protocol.MsgType.hello)
        d.append(protoVer)
        d.appendUInt32BE(clientId)
        d.append(wantsUdp ? 1 : 0)
        return d
    }

    static func encodeJoystick(x: Float, y: Float) -> Data {
        let ix = Int16(clamping: Int((x * Protocol.joystickScale).rounded()))
        let iy = Int16(clamping: Int((y * Protocol.joystickScale).rounded()))
        var d = Data(capacity: 2 + 1 + 4)
        d.appendUInt16BE(1 + 4)
        d.append(Protocol.MsgType.joystick)
        d.appendInt16BE(ix)
        d.appendInt16BE(iy)
        return d
    }

    static func encodeButton(buttonId: UInt8, down: Bool) -> Data {
        var d = Data(capacity: 2 + 1 + 2)
        d.appendUInt16BE(1 + 2)
        d.append(Protocol.MsgType.button)
        d.append(buttonId)
        d.append(down ? 1 : 0)
        return d
    }

    static func encodePing(seq: UInt32) -> Data {
        var d = Data(capacity: 2 + 1 + 4)
        d.appendUInt16BE(1 + 4)
        d.append(Protocol.MsgType.ping)
        d.appendUInt32BE(seq)
        return d
    }

    static func encodeLookDeltaTCP(seq: UInt32, dx: Int16, dy: Int16) -> Data {
        var d = Data(capacity: 2 + 1 + 8)
        d.appendUInt16BE(1 + 8)
        d.append(Protocol.MsgType.lookDelta)
        d.appendUInt32BE(seq)
        d.appendInt16BE(dx)
        d.appendInt16BE(dy)
        return d
    }

    static func encodeLookDeltaUDP(seq: UInt32, dx: Int16, dy: Int16) -> Data {
        // No TCP length prefix: the UDP datagram boundary defines the frame.
        var d = Data(capacity: 1 + 4 + 4)
        d.append(Protocol.MsgType.lookDelta)
        d.appendUInt32BE(seq)
        d.appendInt16BE(dx)
        d.appendInt16BE(dy)
        return d
    }

    static func encodeProbe() -> Data {
        var d = Data(capacity: 3)
        d.appendUInt16BE(1)
        d.append(Protocol.MsgType.probe)
        return d
    }

    // MARK: - Incoming (server → client) TCP framing

    /// Parse one frame starting at `buffer[start]`, with valid bytes up to but
    /// excluding `end`. Returns `nil` if the buffer doesn't yet contain a
    /// complete frame.
    static func tryReadFrame(from buffer: Data, start: Int, end: Int) -> FrameRead? {
        let available = end - start
        guard available >= 3 else { return nil }    // need u16 len + u8 type

        let len = (Int(buffer[start]) << 8) | Int(buffer[start + 1])
        guard len >= 1 else { return nil }
        guard available >= 2 + len else { return nil }

        let type = buffer[start + 2]
        let payloadStart = start + 3
        let payloadLen = len - 1

        let msg: ControlMessage
        switch type {
        case Protocol.MsgType.helloAck where payloadLen >= 3:
            let status = buffer[payloadStart]
            let udpPort = (UInt16(buffer[payloadStart + 1]) << 8) | UInt16(buffer[payloadStart + 2])
            msg = .helloAck(status: status, udpPort: udpPort)
        case Protocol.MsgType.stateChange where payloadLen >= 1:
            msg = .stateChange(mode: buffer[payloadStart])
        case Protocol.MsgType.pong where payloadLen >= 4:
            let seq = readUInt32BE(buffer, payloadStart)
            msg = .pong(seq: seq)
        case Protocol.MsgType.probeAck where payloadLen >= 1:
            msg = .probeAck(status: buffer[payloadStart])
        default:
            msg = .unknown(type: type, payloadLength: payloadLen)
        }
        return FrameRead(bytesConsumed: 2 + len, message: msg)
    }

    private static func readUInt32BE(_ buffer: Data, _ offset: Int) -> UInt32 {
        return (UInt32(buffer[offset]) << 24) |
               (UInt32(buffer[offset + 1]) << 16) |
               (UInt32(buffer[offset + 2]) << 8) |
                UInt32(buffer[offset + 3])
    }
}

// MARK: - Big-endian Data helpers

private extension Data {
    mutating func appendUInt16BE(_ v: UInt16) {
        append(UInt8(truncatingIfNeeded: v >> 8))
        append(UInt8(truncatingIfNeeded: v))
    }
    mutating func appendUInt32BE(_ v: UInt32) {
        append(UInt8(truncatingIfNeeded: v >> 24))
        append(UInt8(truncatingIfNeeded: v >> 16))
        append(UInt8(truncatingIfNeeded: v >> 8))
        append(UInt8(truncatingIfNeeded: v))
    }
    mutating func appendInt16BE(_ v: Int16) {
        let u = UInt16(bitPattern: v)
        append(UInt8(truncatingIfNeeded: u >> 8))
        append(UInt8(truncatingIfNeeded: u))
    }
}
