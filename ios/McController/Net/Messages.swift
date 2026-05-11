import Foundation

/// Server-to-client messages decoded from the TCP control channel.
enum ControlMessage: Sendable, Equatable {
    case helloAck(status: UInt8, udpPort: UInt16)
    case stateChange(mode: UInt8)
    case pong(seq: UInt32)
    case probeAck(status: UInt8)
    case unknown(type: UInt8, payloadLength: Int)
}
