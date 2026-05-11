import Foundation
import AppKit
import Combine

/// Owns the server-side lifecycle: TCP / UDP listeners, input injector,
/// joystick/look/button routing, window-state polling. Exposes the live
/// objects so SwiftUI views can observe them directly.
///
/// Lifetime is bound to the app process — created at `McControllerApp`
/// startup, disposed on real quit. UI views keep references and mutate
/// the config directly; the input thread picks changes up on the next
/// packet (config fields are plain mutable POCO, atomic float reads).
@MainActor
final class ServerHost: ObservableObject {

    // `nonisolated` lets the network read loops touch these without
    // hopping back to the main actor for every packet. They're either
    // thread-safe internally (ConnectionStats, TcpServer, UdpServer) or
    // POCO with non-tearing atomic-sized fields (ServerConfig — Int /
    // Float scalars + class references). The orchestrator's lifecycle
    // operations (`start`/`stop`) remain main-actor-isolated.
    nonisolated let configURL: URL
    nonisolated let config: ServerConfig
    nonisolated let stats: ConnectionStats
    nonisolated let windowMonitor: MacWindowMonitor
    nonisolated let curve: CameraCurve
    nonisolated let mapper: JoystickToWasdMapper
    nonisolated let router: ButtonRouter
    nonisolated let injector: InputInjector
    nonisolated let cursorInjector: MacCursorInjector
    nonisolated let tcp: TcpServer
    nonisolated let udp: UdpServer
    nonisolated let discoveryAdvertiser: LanDiscoveryAdvertiser

    /// Published so the discovery view can re-render the "connected" pill.
    @Published private(set) var isClientConnected: Bool = false
    @Published private(set) var lastClientEndpoint: String?
    @Published private(set) var currentMode: Protocol.ControllerMode = .antiMistouch
    @Published private(set) var startError: Error?
    @Published private(set) var localIPv4s: [String] = []

    /// Shared mutable busy flag the LAN advertiser's flags closure reads
    /// on every heartbeat. Updated from `tcp.onClientConnected` /
    /// `onClientDisconnected`. Lives on a thread-safe holder so the
    /// advertiser's background queue and the @MainActor connect/disconnect
    /// callbacks can both touch it safely.
    private var busy: ClientConnectedFlag!

    /// Debounced save: the Settings view raises `requestSave()` on each
    /// slider tick; we flush 500 ms later.
    private var saveDebounceTimer: Timer?

    init(configURL: URL? = nil) {
        let url = configURL ?? ConfigStore.defaultConfigURL()
        self.configURL = url
        self.config = ConfigStore.loadOrDefault(at: url)
        self.stats = ConnectionStats()
        self.windowMonitor = MacWindowMonitor()
        // Create `cursorInjector` first so we can hand its
        // `lastWarpedPosition` to `injector` as a closure. After a
        // `CGWarpMouseCursorPosition` call (which UI-interact mode
        // does on every look-delta), the system's `CGEvent.location`
        // read lags by ~250 ms, so the injector would otherwise
        // post clicks at the pre-warp cell. The override returns
        // the warp target instead — see CGEventInjector for the
        // full reasoning.
        let cursorInj = MacCursorInjector(monitor: windowMonitor)
        self.cursorInjector = cursorInj
        self.injector = CGEventInjector(cursorPositionOverride: { [weak cursorInj] in
            cursorInj?.lastWarpedPosition
        })
        self.curve = CameraCurve(config: config)
        self.mapper = JoystickToWasdMapper(injector: injector, config: config)
        self.router = ButtonRouter(injector: injector, config: config)
        self.tcp = TcpServer(stats: stats)
        self.udp = UdpServer(stats: stats)
        self.localIPv4s = Self.collectLocalIPv4s()

        let hostName = Host.current().localizedName ?? Host.current().name ?? "Mac"

        // Capture references the discovery closures need without capturing
        // `self` — at this point `self` is still being initialized
        // (`discoveryAdvertiser` is the property being assigned right
        // now), so a `[weak self]` capture would fail compile-time.
        let configRef = self.config
        let monitorRef = self.windowMonitor
        let busyFlag = ClientConnectedFlag()
        self.busy = busyFlag

        self.discoveryAdvertiser = LanDiscoveryAdvertiser(
            name: hostName,
            tcpPortProvider: { configRef.port },
            flagsProvider: {
                var f: LanDiscoveryAdvertiser.AnnounceFlags = .none
                if monitorRef.currentMode != .antiMistouch {
                    f.insert(.mcForeground)
                }
                f.insert(.acceptsUdp)
                if busyFlag.value { f.insert(.busy) }
                return f
            })

        // Wire callbacks. `OnPacket` may fire on the TCP read queue, but
        // all `@Published` updates must marshal to MainActor — we hop
        // via `Task { @MainActor in ... }` at the boundary.
        tcp.onPacket = { [weak self] msg in self?.handlePacket(msg) }
        tcp.onClientConnected = { [weak self] ep in
            busyFlag.value = true
            Task { @MainActor in
                guard let self else { return }
                self.stats.mode = self.stats.mode ?? "TCP"
                self.lastClientEndpoint = ep
                self.isClientConnected = true
            }
        }
        tcp.onClientDisconnected = { [weak self] in
            busyFlag.value = false
            Task { @MainActor in
                guard let self else { return }
                self.mapper.releaseAll()
                self.router.releaseAll()
                self.stats.onDisconnect()
                self.udp.resetSequence()
                self.isClientConnected = false
                self.lastClientEndpoint = nil
            }
        }
        udp.onLookDelta = { [weak self] dx, dy in self?.handleLookDelta(dx: dx, dy: dy) }
        windowMonitor.onModeChanged = { [weak self] newMode in
            guard let self else { return }
            self.tcp.send(PacketCodec.encodeStateChange(newMode))
            // Drop the cached warp target whenever we leave UI mode.
            // In-game mode hands cursor control to MC's GLFW capture
            // (and never warps), and antiMistouch is idle — in both
            // cases a stale cached position would steer subsequent
            // clicks to nowhere useful.
            if newMode != .uiInteract {
                self.cursorInjector.clearCachedPosition()
            }
            if newMode == .antiMistouch {
                Task { @MainActor in
                    self.mapper.releaseAll()
                    self.router.releaseAll()
                }
            }
            Task { @MainActor in self.currentMode = newMode }
        }
    }

    func start() {
        do {
            try tcp.start(port: config.port)
            try udp.start(port: config.port)
            windowMonitor.start()
            discoveryAdvertiser.start()
            startError = nil
        } catch {
            startError = error
        }
    }

    func stop() {
        mapper.releaseAll()
        router.releaseAll()
        discoveryAdvertiser.stop()
        windowMonitor.stop()
        tcp.stop()
        udp.stop()
    }

    /// Called by Settings view when the user moves a tuning slider.
    /// Debounces by 500 ms — the same window the WinUI version uses.
    func requestSave() {
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self else { return }
            do { try ConfigStore.save(self.config, to: self.configURL) }
            catch { NSLog("[ServerHost] save failed: %@", String(describing: error)) }
        }
    }

    /// Save immediately, bypassing the debounce. Called on profile-list
    /// mutations where the user has clearly committed the change.
    func saveNow() {
        saveDebounceTimer?.invalidate()
        saveDebounceTimer = nil
        do { try ConfigStore.save(config, to: configURL) }
        catch { NSLog("[ServerHost] save failed: %@", String(describing: error)) }
    }

    func onActiveProfileChanged() {
        curve.reset()
        mapper.releaseAll()
        router.releaseAll()
    }

    /// Rebind to a new TCP/UDP port. Stops the old listeners, restarts
    /// on the new port, and fires a discovery burst so phones still on
    /// the old advertisement learn the new port within ~300 ms.
    func rebind(toPort newPort: Int) {
        guard newPort >= 1 && newPort <= 65535, newPort != config.port else { return }
        config.port = newPort
        tcp.stop()
        udp.stop()
        do {
            try tcp.start(port: newPort)
            try udp.start(port: newPort)
            discoveryAdvertiser.triggerBurst()
            startError = nil
        } catch {
            startError = error
        }
        saveNow()
    }

    // MARK: - Packet handling (wire-side dispatch)

    private static let wireSubpixelScale: Float = 10

    private func handlePacket(_ msg: ControlMessage) {
        switch msg {
        case .hello(let protoVer, _, let wantsUdp):
            let status: UInt8 = protoVer == Protocol.version
                ? Protocol.HelloAckStatus.ok
                : Protocol.HelloAckStatus.protocolMismatch
            let udpPort: UInt16 = wantsUdp ? UInt16(config.port) : 0
            tcp.send(PacketCodec.encodeHelloAck(status: status, udpPort: udpPort))
            Task { @MainActor in
                self.stats.mode = wantsUdp ? "WiFi (TCP+UDP)" : "USB (TCP only)"
                self.udp.resetSequence()
                self.curve.reset()
                self.mapper.releaseAll()
                self.router.releaseAll()
                self.tcp.send(PacketCodec.encodeStateChange(self.windowMonitor.currentMode))
            }

        case .joystick(let x, let y):
            mapper.update(x: x, y: y)
            stats.incrementJoystick()

        case .lookDeltaTcp(_, let dx, let dy):
            handleLookDelta(dx: dx, dy: dy)

        case .button(let id, let down):
            router.handle(buttonId: id, down: down)
            stats.incrementButton()

        case .ping(let seq):
            tcp.send(PacketCodec.encodePong(seq: seq))

        case .probe, .probeAck, .unknown:
            break
        }
    }

    private func handleLookDelta(dx: Int16, dy: Int16) {
        let fdx = Float(dx) / Self.wireSubpixelScale
        let fdy = Float(dy) / Self.wireSubpixelScale
        let (sdx, sdy) = curve.apply(rawDx: fdx, rawDy: fdy)
        if sdx == 0 && sdy == 0 { return }

        switch windowMonitor.currentMode {
        case .inGame:
            injector.mouseMoveRelative(dx: sdx, dy: sdy)
        case .uiInteract:
            cursorInjector.applyDelta(dx: sdx, dy: sdy)
        case .antiMistouch:
            break
        }
        stats.incrementLook()
    }

    // MARK: - Local IPv4 enumeration

    private static func collectLocalIPv4s() -> [String] {
        var addresses: [String] = []
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return addresses }
        defer { freeifaddrs(ifap) }

        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = p {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & IFF_UP) != 0
            let isLoopback = (flags & IFF_LOOPBACK) != 0
            if let addrPtr = ptr.pointee.ifa_addr,
               isUp, !isLoopback,
               addrPtr.pointee.sa_family == AF_INET {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let len = socklen_t(MemoryLayout<sockaddr_in>.size)
                if getnameinfo(addrPtr, len,
                               &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    let ifaceName = String(cString: ptr.pointee.ifa_name)
                    let ip = String(cString: host)
                    addresses.append("\(ifaceName): \(ip)")
                }
            }
            p = ptr.pointee.ifa_next
        }
        return addresses
    }
}

/// Tiny thread-safe boolean used by the LAN advertiser's flag closure
/// to read the connected-state from background queues without crossing
/// MainActor isolation.
final class ClientConnectedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _value }
        set { lock.lock(); _value = newValue; lock.unlock() }
    }
}
