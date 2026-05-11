import Foundation
import Network

/// Single-client TCP listener. Mirrors `TcpServer.cs` semantics:
///   - First frame on every accepted connection is peeked; PROBE replies
///     immediately and closes silently (does NOT fire connect/disconnect
///     events).
///   - HELLO is accepted only if no session is active — otherwise a
///     HELLO_ACK with status=ServerBusy is sent and the socket closed.
///   - The accept loop keeps running while a real session is held, so
///     probes are answered promptly even during an active connection.
///
/// Built on `Network.framework` — `NWListener` for accepts,
/// `NWConnection` per peer.
final class TcpServer: @unchecked Sendable {

    private let stats: ConnectionStats
    private let queue = DispatchQueue(label: "mc.tcp.server", qos: .userInteractive)

    private var listener: NWListener?
    private var currentSession: Session?
    private let sessionLock = NSLock()

    /// Fires on the read-loop thread for every decoded control message
    /// belonging to the active session (HELLO + everything after).
    var onPacket: ((ControlMessage) -> Void)?
    var onClientConnected: ((String) -> Void)?
    var onClientDisconnected: (() -> Void)?

    init(stats: ConnectionStats) {
        self.stats = stats
    }

    func start(port: Int) throws {
        guard listener == nil else { return }
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.connectionTimeout = 5
        let params = NWParameters(tls: nil, tcp: tcp)
        params.allowLocalEndpointReuse = true
        params.includePeerToPeer = false
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw NSError(domain: "TcpServer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Invalid port \(port)"])
        }
        let listener = try NWListener(using: params, on: nwPort)
        listener.newConnectionHandler = { [weak self] conn in
            self?.handleNewConnection(conn)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        closeCurrentSession()
    }

    /// Send a frame to the active session, if any. No-op otherwise.
    func send(_ frame: Data) {
        sessionLock.lock()
        let session = currentSession
        sessionLock.unlock()
        session?.connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    // MARK: - Internals

    private func handleNewConnection(_ conn: NWConnection) {
        conn.start(queue: queue)
        let context = ConnectionContext(connection: conn)
        readFirstFrame(context: context)
    }

    /// Read until we have one full frame, then dispatch. Bounded by a 5s
    /// hard timeout so a half-open peer can't tie up resources forever.
    private func readFirstFrame(context: ConnectionContext) {
        context.timeout = queue.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            self?.closeQuietly(context: context)
        }
        receive(context: context, expectingFirstFrame: true)
    }

    private func receive(context: ConnectionContext, expectingFirstFrame: Bool) {
        context.connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                context.buffer.append(data)
                self.drain(context: context, expectingFirstFrame: expectingFirstFrame)
            }
            if isComplete || error != nil {
                self.handleClose(context: context)
                return
            }
            if context.connection.state != .cancelled && context.alive {
                self.receive(context: context,
                             expectingFirstFrame: expectingFirstFrame && context.firstFrameStillPending)
            }
        }
    }

    private func drain(context: ConnectionContext, expectingFirstFrame: Bool) {
        while true {
            guard let (consumed, msg) = PacketCodec.tryReadFrame(context.buffer) else { break }
            context.buffer.removeSubrange(0..<consumed)

            if context.firstFrameStillPending {
                context.firstFrameStillPending = false
                cancelTimeout(context: context)
                switch msg {
                case .probe:
                    handleProbe(context: context)
                    return
                case .hello:
                    let became = promoteToSession(context: context, helloMessage: msg)
                    if !became { return }
                default:
                    // Spec violation — close.
                    closeQuietly(context: context)
                    return
                }
            } else {
                onPacket?(msg)
            }
        }
    }

    private func cancelTimeout(context: ConnectionContext) {
        context.timeout?.cancel()
        context.timeout = nil
    }

    private func handleProbe(context: ConnectionContext) {
        // ALIVE if no real session right now, BUSY otherwise. Probes are
        // intentionally invisible to UI connection counters.
        sessionLock.lock()
        let busy = currentSession != nil
        sessionLock.unlock()
        let status: UInt8 = busy ? Protocol.ProbeAckStatus.busy : Protocol.ProbeAckStatus.alive
        let ack = PacketCodec.encodeProbeAck(status: status)
        context.connection.send(content: ack, completion: .contentProcessed { [weak self] _ in
            self?.closeQuietly(context: context)
        })
    }

    /// Returns true if we became the active session (caller should keep
    /// reading on the same connection); false means we sent NACK and
    /// closed.
    private func promoteToSession(context: ConnectionContext, helloMessage: ControlMessage) -> Bool {
        sessionLock.lock()
        let busy = currentSession != nil
        if !busy {
            currentSession = Session(connection: context.connection,
                                     peerDescription: context.peerDescription)
        }
        sessionLock.unlock()

        if busy {
            let nack = PacketCodec.encodeHelloAck(status: Protocol.HelloAckStatus.serverBusy, udpPort: 0)
            context.connection.send(content: nack, completion: .contentProcessed { [weak self] _ in
                self?.closeQuietly(context: context)
            })
            return false
        }

        stats.connected = true
        stats.clientEndpoint = context.peerDescription
        onClientConnected?(context.peerDescription)
        // The HELLO we already consumed still needs to reach subscribers
        // so they can emit HELLO_ACK + initial STATE_CHANGE.
        onPacket?(helloMessage)
        return true
    }

    private func handleClose(context: ConnectionContext) {
        cancelTimeout(context: context)
        if !context.alive { return }
        context.alive = false

        var wasActive = false
        sessionLock.lock()
        if let s = currentSession, s.connection === context.connection {
            currentSession = nil
            wasActive = true
        }
        sessionLock.unlock()

        context.connection.cancel()
        if wasActive {
            onClientDisconnected?()
        }
    }

    private func closeQuietly(context: ConnectionContext) {
        cancelTimeout(context: context)
        context.alive = false
        context.connection.cancel()
    }

    private func closeCurrentSession() {
        sessionLock.lock()
        let s = currentSession
        currentSession = nil
        sessionLock.unlock()
        s?.connection.cancel()
    }

    // MARK: - Helper types

    /// Per-accept context: holds the read buffer, alive flag, and a
    /// first-frame timeout. The connection itself owns its own lifecycle
    /// — we just attach state.
    private final class ConnectionContext {
        let connection: NWConnection
        var buffer = Data()
        var firstFrameStillPending = true
        var timeout: DispatchWorkItem?
        var alive = true

        var peerDescription: String {
            switch connection.endpoint {
            case .hostPort(let host, let port):
                return "\(host):\(port.rawValue)"
            default:
                return "\(connection.endpoint)"
            }
        }

        init(connection: NWConnection) { self.connection = connection }
    }

    private final class Session {
        let connection: NWConnection
        let peerDescription: String
        init(connection: NWConnection, peerDescription: String) {
            self.connection = connection
            self.peerDescription = peerDescription
        }
    }
}

private extension DispatchQueue {
    func asyncAfter(deadline: DispatchTime, _ block: @escaping () -> Void) -> DispatchWorkItem {
        let item = DispatchWorkItem(block: block)
        asyncAfter(deadline: deadline, execute: item)
        return item
    }
}
