import Foundation
import Network

/// Single TCP control connection. Uses Apple's `NWConnection` so we get
/// `noDelay`, the right QoS queue, and zero-copy framing automatically.
///
/// Threading model:
///   - All `NWConnection` callbacks run on the supplied queue (default:
///     `.userInteractive`). The owner (HybridTransport) MUST be safe to
///     invoke from that queue.
///   - `send(_:)` is thread-safe — it hands off to Network framework's
///     internal queue.
final class TCPChannel: @unchecked Sendable {

    typealias MessageHandler = @Sendable (ControlMessage) -> Void
    typealias DisconnectHandler = @Sendable (Error?) -> Void

    private let queue: DispatchQueue
    private var connection: NWConnection?

    /// Sliding buffer for partial frame reassembly.
    private var buffer = Data()

    init(queue: DispatchQueue = DispatchQueue(label: "mcc.tcp", qos: .userInteractive)) {
        self.queue = queue
    }

    /// Open the TCP connection. Returns once the socket is ready or throws on
    /// failure / timeout.
    func connect(host: String, port: UInt16, timeoutSeconds: TimeInterval = 3.0) async throws {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        tcpOptions.connectionTimeout = Int(timeoutSeconds)
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 30

        let params = NWParameters(tls: nil, tcp: tcpOptions)
        params.serviceClass = .interactiveVideo  // lowest-latency QoS

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
                    if resumed.exchange(true) == false {
                        cont.resume()
                    }
                case .failed(let err):
                    if resumed.exchange(true) == false {
                        cont.resume(throwing: err)
                    }
                case .cancelled:
                    if resumed.exchange(true) == false {
                        cont.resume(throwing: CancellationError())
                    }
                default:
                    break
                }
            }
            conn.start(queue: queue)

            // Manual timeout — NWConnection's `connectionTimeout` triggers a
            // .failed transition, but it's coarse; we layer our own.
            queue.asyncAfter(deadline: .now() + timeoutSeconds + 0.5) {
                if resumed.exchange(true) == false {
                    conn.cancel()
                    cont.resume(throwing: NetError.connectTimeout)
                }
            }
        }
    }

    /// Begin the receive loop. Caller supplies handlers for each decoded
    /// message and for the eventual disconnect.
    func startReading(onMessage: @escaping MessageHandler,
                      onClose: @escaping DisconnectHandler) {
        guard let conn = connection else { return }
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let err):
                onClose(err)
                self?.connection = nil
            case .cancelled:
                onClose(nil)
                self?.connection = nil
            default:
                break
            }
        }
        scheduleReceive(conn, onMessage: onMessage)
    }

    private func scheduleReceive(_ conn: NWConnection, onMessage: @escaping MessageHandler) {
        // Network framework requires a minimum byte count >= 1; we ask for
        // anything up to 4 KiB per chunk.
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.drainFrames(onMessage: onMessage)
            }
            if error != nil {
                conn.cancel()
                return
            }
            if isComplete {
                conn.cancel()
                return
            }
            self.scheduleReceive(conn, onMessage: onMessage)
        }
    }

    private func drainFrames(onMessage: MessageHandler) {
        var cursor = 0
        while cursor < buffer.count {
            guard let frame = PacketCodec.tryReadFrame(from: buffer, start: cursor, end: buffer.count) else {
                break
            }
            onMessage(frame.message)
            cursor += frame.bytesConsumed
        }
        if cursor > 0 {
            // Drop consumed bytes; Data CoW means this is cheap when buffer
            // is small (which it always is here).
            buffer.removeSubrange(0..<cursor)
        }
    }

    /// Send raw bytes. Thread-safe.
    func send(_ data: Data) {
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    /// Send and await ack of delivery to the kernel buffer. Use sparingly —
    /// only when we genuinely need to wait (e.g. HELLO during handshake).
    func sendAwaitable(_ data: Data) async throws {
        guard let conn = connection else { throw NetError.notConnected }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            conn.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) }
                else { cont.resume() }
            })
        }
    }

    func close() {
        connection?.cancel()
        connection = nil
        buffer.removeAll(keepingCapacity: false)
    }
}

enum NetError: Error, LocalizedError {
    case notConnected
    case connectTimeout
    case handshakeTimeout
    case handshakeRejected(reason: String)
    case probeTimeout
    case malformed

    var errorDescription: String? {
        switch self {
        case .notConnected:                return "Not connected"
        case .connectTimeout:              return "Connect timeout"
        case .handshakeTimeout:            return "Handshake timeout"
        case .handshakeRejected(let r):    return "Server refused: \(r)"
        case .probeTimeout:                return "Probe timeout"
        case .malformed:                   return "Malformed frame"
        }
    }
}

/// Tiny atomic flag — avoids importing swift-atomics for one bool.
final class ManagedAtomic<Value: Equatable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    init(_ value: Value) { self.value = value }
    func exchange(_ new: Value) -> Value {
        lock.lock(); defer { lock.unlock() }
        let old = value
        value = new
        return old
    }
    func load() -> Value {
        lock.lock(); defer { lock.unlock() }
        return value
    }
    func store(_ new: Value) {
        lock.lock(); defer { lock.unlock() }
        value = new
    }
}
