import Foundation
import Network

/// UDP listener for the camera channel. Discards out-of-order/duplicate
/// packets via the `seq` field. Captures the client's UDP endpoint from
/// the first valid packet (no separate handshake). Mirrors `UdpServer.cs`.
///
/// Implementation note: NWListener-with-UDP gives us one `NWConnection`
/// per (client-endpoint × server-endpoint) pair. We don't need per-
/// connection state — we just funnel every received datagram through the
/// shared `seq` tracker. Sessions are intentionally short — datagrams
/// don't keep the connection alive between rapid bursts, so we re-read
/// each connection as it materializes.
final class UdpServer: @unchecked Sendable {

    private let stats: ConnectionStats
    private let queue = DispatchQueue(label: "mc.udp.server", qos: .userInteractive)

    private var listener: NWListener?
    private let seqLock = NSLock()
    private var lastSeq: UInt32 = 0
    private var hasSeenSeq = false
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    var onLookDelta: ((Int16, Int16) -> Void)?

    init(stats: ConnectionStats) {
        self.stats = stats
    }

    func start(port: Int) throws {
        guard listener == nil else { return }
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw NSError(domain: "UdpServer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid port \(port)"])
        }
        let listener = try NWListener(using: params, on: nwPort)
        listener.newConnectionHandler = { [weak self] conn in
            self?.attach(connection: conn)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        for (_, c) in connections { c.cancel() }
        connections.removeAll()
        resetSequence()
    }

    func resetSequence() {
        seqLock.withLock {
            lastSeq = 0
            hasSeenSeq = false
        }
    }

    // MARK: - Internals

    private func attach(connection conn: NWConnection) {
        let id = ObjectIdentifier(conn)
        connections[id] = conn
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .cancelled, .failed:
                self?.connections.removeValue(forKey: id)
            default:
                break
            }
        }
        conn.start(queue: queue)
        receive(on: conn)
    }

    private func receive(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.handle(datagram: data)
            }
            if error == nil {
                self.receive(on: conn)
            }
        }
    }

    private func handle(datagram: Data) {
        guard let msg = PacketCodec.tryParseUdp(datagram) else { return }
        let accept: Bool = seqLock.withLock {
            if hasSeenSeq && msg.seq <= lastSeq { return false }
            lastSeq = msg.seq
            hasSeenSeq = true
            return true
        }
        if !accept {
            stats.incrementUdpDropped()
            return
        }
        onLookDelta?(msg.dx, msg.dy)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }
        return body()
    }
}
