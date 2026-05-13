import Foundation
import Network

/// Session-less reachability check. Sends a single PROBE frame, expects one
/// PROBE_ACK, then closes — the server side does NOT register this as a
/// "client connected" event.
enum ConnectivityProbe {

    enum Result: Equatable {
        case alive
        case busy
        case incompatible
        case failed(reason: String)
    }

    static func probe(host: String, port: UInt16, timeoutSeconds: TimeInterval = 1.5) async -> Result {
        let queue = DispatchQueue(label: "mcc.probe", qos: .userInitiated)

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        tcpOptions.connectionTimeout = Int(timeoutSeconds)
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let conn = NWConnection(to: endpoint, using: params)

        return await withCheckedContinuation { (cont: CheckedContinuation<Result, Never>) in
            // All state lives on `ProbeSession`, which is `@unchecked
            // Sendable`. NWConnection callbacks (state-update + receive
            // + the asyncAfter backstop) all run on the single serial
            // `mcc.probe` queue, so the buffer + finish() guard need no
            // locks — the queue serialises access. Wrapping in a class
            // (rather than capturing a `var buffer` and local funcs in
            // `@Sendable` closures) is what silences Swift 6 strict-
            // concurrency warnings without changing behaviour.
            let session = ProbeSession(conn: conn, cont: cont)

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.send(content: PacketCodec.encodeProbe(),
                              completion: .contentProcessed { _ in })
                    session.scheduleReceive()
                case .failed(let err):
                    session.finish(.failed(reason: err.localizedDescription))
                case .cancelled:
                    if session.isResumed == false {
                        session.finish(.failed(reason: "cancelled"))
                    }
                default:
                    break
                }
            }
            conn.start(queue: queue)

            // Hard timeout backstop.
            queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                session.finish(.failed(reason: "timeout"))
            }
        }
    }
}

/// State holder for one in-flight probe. All mutation happens on the
/// single `mcc.probe` serial DispatchQueue created by `ConnectivityProbe`,
/// so the type is `@unchecked Sendable` (no locks required) — Swift 6's
/// concurrency checker can't see the queue-serialised access pattern, so
/// we have to assert it.
private final class ProbeSession: @unchecked Sendable {
    private let conn: NWConnection
    private let cont: CheckedContinuation<ConnectivityProbe.Result, Never>
    private let resumed = ManagedAtomic<Bool>(false)
    private var buffer = Data()

    init(conn: NWConnection, cont: CheckedContinuation<ConnectivityProbe.Result, Never>) {
        self.conn = conn
        self.cont = cont
    }

    var isResumed: Bool { resumed.load() }

    func finish(_ r: ConnectivityProbe.Result) {
        if resumed.exchange(true) == false {
            conn.cancel()
            cont.resume(returning: r)
        }
    }

    func scheduleReceive() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                if let frame = PacketCodec.tryReadFrame(from: self.buffer, start: 0, end: self.buffer.count) {
                    if case .probeAck(let status) = frame.message {
                        switch Protocol.ProbeStatus(rawValue: status) ?? .incompatible {
                        case .alive:        self.finish(.alive)
                        case .busy:         self.finish(.busy)
                        case .incompatible: self.finish(.incompatible)
                        }
                        return
                    }
                    // Some other unexpected first frame
                    self.finish(.failed(reason: "unexpected response"))
                    return
                }
            }
            if let error {
                self.finish(.failed(reason: error.localizedDescription))
                return
            }
            if isComplete {
                // Legacy server that doesn't speak PROBE — treat the
                // successful TCP connect as "alive".
                self.finish(.alive)
                return
            }
            self.scheduleReceive()
        }
    }
}
