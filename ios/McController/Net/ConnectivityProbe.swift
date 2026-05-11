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
            let resumed = ManagedAtomic<Bool>(false)
            var buffer = Data()

            func finish(_ r: Result) {
                if resumed.exchange(true) == false {
                    conn.cancel()
                    cont.resume(returning: r)
                }
            }

            func scheduleReceive() {
                conn.receive(minimumIncompleteLength: 1, maximumLength: 64) { data, _, isComplete, error in
                    if let data, !data.isEmpty {
                        buffer.append(data)
                        if let frame = PacketCodec.tryReadFrame(from: buffer, start: 0, end: buffer.count) {
                            if case .probeAck(let status) = frame.message {
                                switch Protocol.ProbeStatus(rawValue: status) ?? .incompatible {
                                case .alive:        finish(.alive)
                                case .busy:         finish(.busy)
                                case .incompatible: finish(.incompatible)
                                }
                                return
                            }
                            // Some other unexpected first frame
                            finish(.failed(reason: "unexpected response"))
                            return
                        }
                    }
                    if let error {
                        finish(.failed(reason: error.localizedDescription))
                        return
                    }
                    if isComplete {
                        // Legacy server that doesn't speak PROBE — treat the
                        // successful TCP connect as "alive".
                        finish(.alive)
                        return
                    }
                    scheduleReceive()
                }
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.send(content: PacketCodec.encodeProbe(),
                              completion: .contentProcessed { _ in })
                    scheduleReceive()
                case .failed(let err):
                    finish(.failed(reason: err.localizedDescription))
                case .cancelled:
                    if resumed.load() == false {
                        finish(.failed(reason: "cancelled"))
                    }
                default:
                    break
                }
            }
            conn.start(queue: queue)

            // Hard timeout backstop.
            queue.asyncAfter(deadline: .now() + timeoutSeconds) {
                finish(.failed(reason: "timeout"))
            }
        }
    }
}
