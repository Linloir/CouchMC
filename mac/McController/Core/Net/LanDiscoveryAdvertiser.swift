import Foundation
import Network

/// LAN discovery advertiser. Implements both Channel A (UDP broadcast,
/// per `docs/discovery.md`) and Channel B (Bonjour / mDNS, service type
/// `_mccontroller._tcp.`). Mirrors `LanDiscoveryAdvertiser.cs`.
///
/// Channel A is the primary mechanism; Channel B is a nice-to-have for
/// router setups that drop unsolicited broadcasts but allow mDNS through.
final class LanDiscoveryAdvertiser: @unchecked Sendable {

    static let discoveryPort: UInt16 = 34556
    static let protocolVersion: UInt8 = 0x01
    static let msgAnnounce: UInt8 = 0x01
    private static let magic: [UInt8] = [0x4D, 0x43, 0x43, 0x54]  // "MCCT"

    struct AnnounceFlags: OptionSet {
        let rawValue: UInt8
        static let none         = AnnounceFlags([])
        static let mcForeground = AnnounceFlags(rawValue: 1 << 0)
        static let acceptsUdp   = AnnounceFlags(rawValue: 1 << 1)
        static let busy         = AnnounceFlags(rawValue: 1 << 2)
    }

    private let name: String
    private let tcpPortProvider: () -> Int
    private let flagsProvider: () -> AnnounceFlags

    private let queue = DispatchQueue(label: "mc.discovery.adv", qos: .background)
    private var timer: DispatchSourceTimer?
    private var burstPending = true
    private var burstWorkItem: DispatchWorkItem?

    init(name: String,
         tcpPortProvider: @escaping () -> Int,
         flagsProvider: @escaping () -> AnnounceFlags) {
        self.name = name
        self.tcpPortProvider = tcpPortProvider
        self.flagsProvider = flagsProvider
    }

    func start() {
        startUdpHeartbeat()
        // Channel B (Bonjour / mDNS) is intentionally disabled. The
        // service's `<host>.local.` SRV record resolves to *every*
        // address the host has, including IPv6 link-local
        // (`fe80::…`) entries. Some clients (notably Android's
        // NsdManager, and any iOS browser that tries the first
        // resolved address) pick the IPv6 link-local first and time
        // out — link-local IPv6 requires a scope ID that's not part
        // of the wire format. Channel A (UDP broadcast) carries an
        // unambiguous IPv4 source address and works reliably; the
        // discovery spec already designates Channel B as optional.
    }

    func stop() {
        timer?.cancel()
        timer = nil
        burstWorkItem?.cancel()
    }

    /// Schedule a 3-packet burst on the next heartbeat (or right away,
    /// if we're between heartbeats). Used when the user changes the
    /// listen port so phones re-learn within ~300 ms.
    func triggerBurst() {
        queue.async { [weak self] in self?.burstPending = true }
    }

    // MARK: - Channel A — UDP broadcast

    private func startUdpHeartbeat() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        // 1000 ± 100 ms jittered cadence per spec.
        timer.schedule(deadline: .now() + .milliseconds(50),
                       repeating: .milliseconds(1000),
                       leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    private func tick() {
        if burstPending {
            burstPending = false
            broadcast()
            queue.asyncAfter(deadline: .now() + .milliseconds(100)) { [weak self] in self?.broadcast() }
            queue.asyncAfter(deadline: .now() + .milliseconds(300)) { [weak self] in self?.broadcast() }
        } else {
            broadcast()
        }
    }

    private func broadcast() {
        let payload = encodePayload()
        // POSIX socket is the simplest path for IPv4 broadcast on a
        // fresh datagram per tick. NWConnection doesn't expose
        // SO_BROADCAST as a first-class option, and the alternative
        // (long-lived NWConnection) would have to be re-bound whenever
        // the interface list changes.
        sendBroadcastPosix(payload: payload)
    }

    private func sendBroadcastPosix(payload: Data) {
        // Compute every destination we want to hit: 255.255.255.255 +
        // each up interface's directed broadcast (192.168.x.255 etc.).
        let destinations = collectBroadcastIPv4s()
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }

        var yes: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))

        for addr in destinations {
            var sin = sockaddr_in()
            sin.sin_family = sa_family_t(AF_INET)
            sin.sin_port = UInt16(LanDiscoveryAdvertiser.discoveryPort).bigEndian
            sin.sin_addr.s_addr = addr  // already network byte order
            let size = socklen_t(MemoryLayout<sockaddr_in>.size)
            payload.withUnsafeBytes { (rawBuf: UnsafeRawBufferPointer) in
                guard let base = rawBuf.baseAddress else { return }
                withUnsafePointer(to: &sin) { sinPtr in
                    sinPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                        _ = sendto(fd, base, payload.count, 0, saPtr, size)
                    }
                }
            }
        }
    }

    /// Returns IPv4 addresses in network byte order: 255.255.255.255 +
    /// every up interface's directed broadcast.
    private func collectBroadcastIPv4s() -> [in_addr_t] {
        var result: [in_addr_t] = [in_addr_t(0xFFFFFFFF)]  // 255.255.255.255 in NBO
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return result }
        defer { freeifaddrs(ifap) }

        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = p {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            let supportsBroadcast = (flags & IFF_BROADCAST) != 0
            if let addrPtr = ptr.pointee.ifa_dstaddr,
               isUp, !isLoopback, supportsBroadcast,
               addrPtr.pointee.sa_family == AF_INET {
                addrPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sinPtr in
                    let s = sinPtr.pointee.sin_addr.s_addr
                    if s != 0 && !result.contains(s) {
                        result.append(s)
                    }
                }
            }
            p = ptr.pointee.ifa_next
        }
        return result
    }

    func encodePayload() -> Data {
        var nameBytes = Array(name.utf8)
        if nameBytes.count > 255 {
            // Truncate at a UTF-8 boundary so we don't emit a malformed
            // multi-byte sequence. Trim the trailing bytes until the
            // remaining prefix decodes cleanly.
            var trimmed = nameBytes.prefix(255).map { $0 }
            while !trimmed.isEmpty && String(data: Data(trimmed), encoding: .utf8) == nil {
                trimmed.removeLast()
            }
            nameBytes = trimmed
        }

        let port = UInt16(tcpPortProvider())
        let flags = flagsProvider().rawValue
        let nameLen = UInt16(nameBytes.count)

        var buf = Data(capacity: 11 + nameBytes.count)
        buf.append(contentsOf: Self.magic)
        buf.append(Self.protocolVersion)
        buf.append(Self.msgAnnounce)
        buf.append(flags)
        buf.appendBE(port)
        buf.appendBE(nameLen)
        buf.append(contentsOf: nameBytes)
        return buf
    }

}

private extension DispatchQueue {
    func asyncAfter(deadline: DispatchTime, _ block: @escaping () -> Void) {
        asyncAfter(deadline: deadline, execute: block)
    }
}
