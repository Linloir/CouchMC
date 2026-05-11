import Foundation

/// Decoded form of a TCP control packet. Mirrors `Messages.cs` on the PC side.
enum ControlMessage: Equatable {
    case hello(protoVer: UInt8, clientId: UInt32, wantsUdp: Bool)
    case joystick(x: Float, y: Float)
    case lookDeltaTcp(seq: UInt32, dx: Int16, dy: Int16)
    case button(id: UInt8, down: Bool)
    case ping(seq: UInt32)
    case probe
    case probeAck(status: UInt8)
    case unknown(type: UInt8, payloadLength: Int)
}

/// UDP camera datagram carried on its own (non-TCP) channel.
struct LookDeltaUdpMsg: Equatable {
    let seq: UInt32
    let dx: Int16
    let dy: Int16
}
