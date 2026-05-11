import Foundation
import Network
import Combine

/// LAN discovery of running PC servers.
///
/// Implements both channels from `docs/discovery.md`:
///   - Channel A: UDP broadcast on port 34556, payload `MCCT v1 ...`
///   - Channel B: Bonjour `_mccontroller._tcp.` via `NWBrowser`
///
/// Results are merged by `(ip, tcpPort)`. Entries are evicted after 5s of
/// silence. Channel A entries win the merge because they carry the live
/// `mc`/`busy`/`udp` flags fresher than mDNS TXT records.
final class DiscoveryClient: ObservableObject, @unchecked Sendable {

    struct DiscoveredHost: Identifiable, Hashable, Sendable {
        let ip: String
        let tcpPort: UInt16
        let name: String
        let mcInForeground: Bool
        let acceptsUDP: Bool
        let busy: Bool
        var lastSeenAt: Date
        let source: Source

        var id: String { "\(ip):\(tcpPort)" }

        enum Source: Sendable { case udpBroadcast, bonjour }
    }

    @Published private(set) var hosts: [String: DiscoveredHost] = [:]

    private var udpListener: NWListener?
    private let udpQueue = DispatchQueue(label: "mcc.discovery.udp", qos: .utility)

    private var bonjourBrowser: NWBrowser?

    private var gcTimer: DispatchSourceTimer?
    private let staleAfter: TimeInterval = 5.0

    @MainActor
    func start() {
        startUDP()
        startBonjour()
        startGC()
    }

    @MainActor
    func stop() {
        udpListener?.cancel()
        udpListener = nil
        bonjourBrowser?.cancel()
        bonjourBrowser = nil
        gcTimer?.cancel()
        gcTimer = nil
        hosts.removeAll()
    }

    // MARK: - Channel A: UDP broadcast listener
    //
    // NWListener with NWParameters.udp accepts UDP datagrams. Each remote peer
    // shows up as a fresh NWConnection in `newConnectionHandler`. We receive
    // one message per connection, parse it, then cancel.

    private func startUDP() {
        do {
            let params = NWParameters.udp
            params.allowLocalEndpointReuse = true
            params.allowFastOpen = true
            let listener = try NWListener(
                using: params,
                on: NWEndpoint.Port(rawValue: Protocol.discoveryPort)!
            )
            listener.newConnectionHandler = { [weak self] conn in
                guard let self else { conn.cancel(); return }
                conn.start(queue: self.udpQueue)
                self.receiveDatagram(on: conn)
            }
            listener.start(queue: udpQueue)
            self.udpListener = listener
        } catch {
            // Non-fatal — Bonjour can still discover.
        }
    }

    private nonisolated func receiveDatagram(on conn: NWConnection) {
        conn.receiveMessage { [weak self] data, _, _, _ in
            if let data, case let .hostPort(host, _) = conn.endpoint {
                let ip = DiscoveryClient.hostString(host)
                self?.parseUDPAnnounce(data, fromIP: ip)
            }
            conn.cancel()
        }
    }

    private nonisolated func parseUDPAnnounce(_ data: Data, fromIP ip: String) {
        guard data.count >= 11 else { return }
        guard data[0] == 0x4D, data[1] == 0x43, data[2] == 0x43, data[3] == 0x54 else { return }
        guard data[4] == 0x01, data[5] == 0x01 else { return }
        let flags   = data[6]
        let tcpPort = (UInt16(data[7]) << 8) | UInt16(data[8])
        let nameLen = (Int(data[9]) << 8) | Int(data[10])
        guard data.count >= 11 + nameLen else { return }
        let name = String(data: data.subdata(in: 11..<(11 + nameLen)), encoding: .utf8) ?? ""

        let host = DiscoveredHost(
            ip: ip,
            tcpPort: tcpPort,
            name: name,
            mcInForeground: (flags & 0x01) != 0,
            acceptsUDP:     (flags & 0x02) != 0,
            busy:           (flags & 0x04) != 0,
            lastSeenAt: Date(),
            source: .udpBroadcast
        )
        DispatchQueue.main.async { [weak self] in
            self?.hosts[host.id] = host
        }
    }

    // MARK: - Channel B: Bonjour browser

    private func startBonjour() {
        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
            type: "_mccontroller._tcp.",
            domain: nil
        )
        let params = NWParameters()
        params.includePeerToPeer = false
        let browser = NWBrowser(for: descriptor, using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.handleBonjourResults(results)
        }
        browser.start(queue: .main)
        self.bonjourBrowser = browser
    }

    private nonisolated func handleBonjourResults(_ results: Set<NWBrowser.Result>) {
        for r in results {
            guard case let .service(name, _, _, _) = r.endpoint else { continue }
            var txt: [String: String] = [:]
            if case let .bonjour(record) = r.metadata {
                for key in ["v", "mc", "udp", "busy"] {
                    switch record.getEntry(for: key) {
                    case .some(.string(let s)):
                        txt[key] = s
                    case .some(.data(let d)):
                        txt[key] = String(data: d, encoding: .utf8)
                    default:
                        break
                    }
                }
            }
            resolveBonjour(name: name, txt: txt)
        }
    }

    private nonisolated func resolveBonjour(name: String, txt: [String: String]) {
        let endpoint = NWEndpoint.service(
            name: name,
            type: "_mccontroller._tcp.",
            domain: "local.",
            interface: nil
        )
        let conn = NWConnection(to: endpoint, using: .tcp)
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let remote = conn.currentPath?.remoteEndpoint,
                   case let .hostPort(host, port) = remote {
                    let ip = DiscoveryClient.hostString(host)
                    let discovered = DiscoveredHost(
                        ip: ip,
                        tcpPort: port.rawValue,
                        name: name,
                        mcInForeground: txt["mc"] == "1",
                        acceptsUDP:     txt["udp"] == "1",
                        busy:           txt["busy"] == "1",
                        lastSeenAt: Date(),
                        source: .bonjour
                    )
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        if self.hosts[discovered.id]?.source == .udpBroadcast {
                            self.hosts[discovered.id]?.lastSeenAt = Date()
                        } else {
                            self.hosts[discovered.id] = discovered
                        }
                    }
                }
                conn.cancel()
            case .failed:
                conn.cancel()
            default:
                break
            }
        }
        conn.start(queue: .global(qos: .utility))
    }

    // MARK: - GC

    private func startGC() {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 1.0, repeating: 1.0)
        timer.setEventHandler { [weak self] in
            self?.collectStale()
        }
        timer.resume()
        self.gcTimer = timer
    }

    private func collectStale() {
        let cutoff = Date().addingTimeInterval(-staleAfter)
        hosts = hosts.filter { _, host in host.lastSeenAt >= cutoff }
    }

    // MARK: - helpers

    private nonisolated static func hostString(_ host: NWEndpoint.Host) -> String {
        switch host {
        case .ipv4(let addr):
            let s = addr.debugDescription
            return s.split(separator: "%").first.map(String.init) ?? s
        case .ipv6(let addr):
            let s = addr.debugDescription
            return s.split(separator: "%").first.map(String.init) ?? s
        case .name(let n, _):
            return n
        @unknown default:
            return "\(host)"
        }
    }
}
