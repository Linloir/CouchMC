import Foundation
import Network
import os.lock

/// Outbound-only UDP channel for high-frequency camera deltas.
///
/// We don't listen on UDP — the PC server learns our (IP, port) from the
/// first datagram and remembers it for the rest of the session.
final class UDPChannel: @unchecked Sendable {

    private let queue: DispatchQueue
    private var connection: NWConnection?
    private var sequence: UInt32 = 0
    private var seqLock = os_unfair_lock()

    init(queue: DispatchQueue = DispatchQueue(label: "mcc.udp", qos: .userInteractive)) {
        self.queue = queue
    }

    /// Open a UDP "connection" (in Network framework's sense — really just a
    /// bound outbound socket).
    func open(host: String, port: UInt16) async throws {
        let params = NWParameters.udp
        params.serviceClass = .interactiveVideo
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let conn = NWConnection(to: endpoint, using: params)
        self.connection = conn

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let resumed = ManagedAtomic<Bool>(false)
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumed.exchange(true) == false { cont.resume() }
                case .failed(let err):
                    if resumed.exchange(true) == false { cont.resume(throwing: err) }
                case .cancelled:
                    if resumed.exchange(true) == false { cont.resume(throwing: CancellationError()) }
                default:
                    break
                }
            }
            conn.start(queue: queue)
        }
    }

    /// Auto-incrementing seq + send. Thread-safe.
    func sendLookDelta(dx: Int16, dy: Int16) {
        os_unfair_lock_lock(&seqLock)
        let seq = sequence
        sequence = sequence &+ 1
        os_unfair_lock_unlock(&seqLock)
        let payload = PacketCodec.encodeLookDeltaUDP(seq: seq, dx: dx, dy: dy)
        connection?.send(content: payload, completion: .contentProcessed { _ in })
    }

    func close() {
        connection?.cancel()
        connection = nil
    }
}
