import Foundation

/// Stateless encode/decode for the wire protocol. All multi-byte fields
/// are big-endian. Mirrors `PacketCodec.cs` on the PC side.
///
/// TCP frame layout: `[u16 len BE][u8 type][payload (len-1 B)]`.
/// UDP datagram layout: `[u8 type][u32 seq BE][payload]`.
enum PacketCodec {

    // MARK: - TCP frame writers (server → client)

    static func encodeHelloAck(status: UInt8, udpPort: UInt16) -> Data {
        var d = Data(capacity: 6)
        d.appendBE(UInt16(1 + 3))
        d.append(Protocol.MsgType.helloAck)
        d.append(status)
        d.appendBE(udpPort)
        return d
    }

    static func encodePong(seq: UInt32) -> Data {
        var d = Data(capacity: 7)
        d.appendBE(UInt16(1 + 4))
        d.append(Protocol.MsgType.pong)
        d.appendBE(seq)
        return d
    }

    static func encodeStateChange(_ mode: Protocol.ControllerMode) -> Data {
        var d = Data(capacity: 4)
        d.appendBE(UInt16(1 + 1))
        d.append(Protocol.MsgType.stateChange)
        d.append(mode.rawValue)
        return d
    }

    static func encodeProbe() -> Data {
        Data([0x00, 0x01, Protocol.MsgType.probe])
    }

    static func encodeProbeAck(status: UInt8) -> Data {
        Data([0x00, 0x02, Protocol.MsgType.probeAck, status])
    }

    // MARK: - TCP frame writers (mostly for tests / parity with the C# side)

    static func encodeHello(protoVer: UInt8, clientId: UInt32, wantsUdp: Bool) -> Data {
        var d = Data(capacity: 9)
        d.appendBE(UInt16(1 + 6))
        d.append(Protocol.MsgType.hello)
        d.append(protoVer)
        d.appendBE(clientId)
        d.append(wantsUdp ? 1 : 0)
        return d
    }

    static func encodeJoystick(x: Float, y: Float) -> Data {
        let ix = Int16(clamping: Int((x * 10000).rounded()))
        let iy = Int16(clamping: Int((y * 10000).rounded()))
        var d = Data(capacity: 7)
        d.appendBE(UInt16(1 + 4))
        d.append(Protocol.MsgType.joystick)
        d.appendBE(ix)
        d.appendBE(iy)
        return d
    }

    static func encodeButton(id: UInt8, down: Bool) -> Data {
        var d = Data(capacity: 5)
        d.appendBE(UInt16(1 + 2))
        d.append(Protocol.MsgType.button)
        d.append(id)
        d.append(down ? 1 : 0)
        return d
    }

    static func encodePing(seq: UInt32) -> Data {
        var d = Data(capacity: 7)
        d.appendBE(UInt16(1 + 4))
        d.append(Protocol.MsgType.ping)
        d.appendBE(seq)
        return d
    }

    static func encodeLookDeltaUdp(seq: UInt32, dx: Int16, dy: Int16) -> Data {
        var d = Data(capacity: 9)
        d.append(Protocol.MsgType.lookDeltaUdp)
        d.appendBE(seq)
        d.appendBE(dx)
        d.appendBE(dy)
        return d
    }

    static func encodeLookDeltaTcp(seq: UInt32, dx: Int16, dy: Int16) -> Data {
        var d = Data(capacity: 11)
        d.appendBE(UInt16(1 + 8))
        d.append(Protocol.MsgType.lookDeltaTcp)
        d.appendBE(seq)
        d.appendBE(dx)
        d.appendBE(dy)
        return d
    }

    // MARK: - TCP framing (incoming)

    /// Try to parse one frame from the start of `buffer`. Returns `nil` if
    /// the buffer doesn't yet contain a full frame. Otherwise returns
    /// `(consumed, message)`.
    static func tryReadFrame(_ buffer: Data) -> (consumed: Int, message: ControlMessage)? {
        if buffer.count < 3 { return nil }
        let len = buffer.readUInt16BE(at: 0)
        if len < 1 { return nil }
        let total = 2 + Int(len)
        if buffer.count < total { return nil }
        let type = buffer[buffer.startIndex + 2]
        let payload = buffer.subdata(
            in: (buffer.startIndex + 3)..<(buffer.startIndex + total))
        let msg = decodeTcpPayload(type: type, payload: payload)
        return (total, msg)
    }

    private static func decodeTcpPayload(type: UInt8, payload p: Data) -> ControlMessage {
        switch type {
        case Protocol.MsgType.hello where p.count >= 6:
            return .hello(
                protoVer: p[p.startIndex],
                clientId: p.readUInt32BE(at: 1),
                wantsUdp: p[p.startIndex + 5] != 0)
        case Protocol.MsgType.joystick where p.count >= 4:
            return .joystick(
                x: Float(p.readInt16BE(at: 0)) / 10000.0,
                y: Float(p.readInt16BE(at: 2)) / 10000.0)
        case Protocol.MsgType.lookDeltaTcp where p.count >= 8:
            return .lookDeltaTcp(
                seq: p.readUInt32BE(at: 0),
                dx: p.readInt16BE(at: 4),
                dy: p.readInt16BE(at: 6))
        case Protocol.MsgType.button where p.count >= 2:
            return .button(id: p[p.startIndex], down: p[p.startIndex + 1] != 0)
        case Protocol.MsgType.ping where p.count >= 4:
            return .ping(seq: p.readUInt32BE(at: 0))
        case Protocol.MsgType.probe:
            return .probe
        case Protocol.MsgType.probeAck where p.count >= 1:
            return .probeAck(status: p[p.startIndex])
        default:
            return .unknown(type: type, payloadLength: p.count)
        }
    }

    // MARK: - UDP datagram (incoming)

    static func tryParseUdp(_ datagram: Data) -> LookDeltaUdpMsg? {
        if datagram.count < 9 { return nil }
        let type = datagram[datagram.startIndex]
        if type != Protocol.MsgType.lookDeltaUdp { return nil }
        return LookDeltaUdpMsg(
            seq: datagram.readUInt32BE(at: 1),
            dx: datagram.readInt16BE(at: 5),
            dy: datagram.readInt16BE(at: 7))
    }
}

// MARK: - Big-endian helpers on Data

extension Data {
    mutating func appendBE(_ v: UInt16) {
        append(UInt8(v >> 8))
        append(UInt8(v & 0xFF))
    }

    mutating func appendBE(_ v: Int16) {
        appendBE(UInt16(bitPattern: v))
    }

    mutating func appendBE(_ v: UInt32) {
        append(UInt8((v >> 24) & 0xFF))
        append(UInt8((v >> 16) & 0xFF))
        append(UInt8((v >> 8) & 0xFF))
        append(UInt8(v & 0xFF))
    }

    func readUInt16BE(at relativeOffset: Int) -> UInt16 {
        let i = startIndex + relativeOffset
        return (UInt16(self[i]) << 8) | UInt16(self[i + 1])
    }

    func readInt16BE(at relativeOffset: Int) -> Int16 {
        Int16(bitPattern: readUInt16BE(at: relativeOffset))
    }

    func readUInt32BE(at relativeOffset: Int) -> UInt32 {
        let i = startIndex + relativeOffset
        return (UInt32(self[i]) << 24)
            | (UInt32(self[i + 1]) << 16)
            | (UInt32(self[i + 2]) << 8)
            | UInt32(self[i + 3])
    }
}
