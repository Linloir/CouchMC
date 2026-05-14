import Foundation
import Combine

/// High-level connection lifecycle. Owns `HybridTransport`, the ping loop,
/// and the live state/mode/RTT observables.
@MainActor
final class ControllerSession: ObservableObject {

    enum State: Equatable {
        case idle
        case connecting
        case connected
        case disconnected
        case failed(reason: String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var mode: ControllerMode = .antiMistouch
    @Published private(set) var rttMs: Int? = nil

    /// `true` when the active "session" is the in-app simulator, NOT a
    /// real PC. Activated by connecting to a host marked `isDemo`
    /// (the `0.0.0.0:65537` magic combo from `AddHostSheet`). Demo mode:
    ///   - Skips the network stack entirely (no TCP/UDP).
    ///   - Lets the user cycle modes manually via the HUD button instead
    ///     of waiting for server-driven STATE_CHANGE.
    ///   - Captures button presses / joystick / look-delta in
    ///     `demoInputState` for the on-screen diagnostic HUD.
    @Published private(set) var isDemoMode: Bool = false

    /// Thread-safe demo-input collector. Populated from the nonisolated
    /// `send*` methods below when `isDemoMode` is true. The HUD polls
    /// this on a 30 Hz timer.
    nonisolated let demoInputState = DemoInputState()

    /// Lock-protected mirror of `isDemoMode` so the nonisolated send
    /// hot paths can branch without an actor hop. Set / cleared on the
    /// main actor whenever `isDemoMode` changes.
    private let demoFlag = LockedBool(false)

    private var transport: HybridTransport?
    private var pingTask: Task<Void, Never>?
    private var pingSentAt: [UInt32: Date] = [:]
    private var nextPingSeq: UInt32 = 0

    /// Thread-safe handle to the active transport's look-delta fast
    /// path. `sendLookDelta(...)` reads it from a non-main flush queue
    /// without going through the actor or main-thread, eliminating the
    /// burst-when-main-busy artifact described in `LookDeltaSender`.
    private let lookSenderHolder = LookSenderHolder()

    // MARK: - lifecycle

    /// Connect over WiFi. Returns once the HELLO_ACK is received or throws.
    func connect(host: String, port: UInt16) async {
        if case .connected = state { return }
        state = .connecting
        mode = .antiMistouch
        rttMs = nil

        let t = HybridTransport()
        self.transport = t

        do {
            try await t.connect(
                host: host,
                port: port,
                mode: .wifi,
                onMessage: { [weak self] msg in
                    Task { @MainActor in self?.handleControlMessage(msg) }
                },
                onModeChange: { [weak self] m in
                    Task { @MainActor in self?.mode = ControllerMode(wireByte: m) }
                },
                onClose: { [weak self] err in
                    Task { @MainActor in self?.handleClose(err) }
                }
            )
            // Publish the transport's nonisolated look-sender so the
            // hot path can skip the actor on every packet.
            lookSenderHolder.set(t.lookSender)
            state = .connected
            startPingLoop()
        } catch {
            state = .failed(reason: error.localizedDescription)
            await t.close()
            self.transport = nil
            lookSenderHolder.set(nil)
        }
    }

    func disconnect() async {
        pingTask?.cancel()
        pingTask = nil
        pingSentAt.removeAll()
        lookSenderHolder.set(nil)
        await transport?.close()
        transport = nil
        state = .disconnected
        mode = .antiMistouch
        rttMs = nil
        // Demo teardown
        if isDemoMode {
            isDemoMode = false
            demoFlag.set(false)
            demoInputState.reset()
        }
    }

    // MARK: - Demo mode (App Store reviewer simulator)

    /// Enter the in-app simulator. Triggered when the user (or App Store
    /// reviewer) selects a host marked `isDemo` from the home list.
    /// No network connection is opened.
    func connectDemo() {
        if case .connected = state, isDemoMode { return }
        demoInputState.reset()
        isDemoMode = true
        demoFlag.set(true)
        state = .connected
        mode = .antiMistouch
        rttMs = 0
    }

    /// Cycle / set the simulated mode in demo. No-op outside demo.
    func setDemoMode(_ newMode: ControllerMode) {
        guard isDemoMode else { return }
        mode = newMode
        // Mirror real-server semantics: locking releases all held buttons
        // (in real mode the server's state-change message triggers this
        // via the controller VC's `apply(mode:)` path; demo just clears
        // the captured state directly).
        if newMode == .antiMistouch {
            demoInputState.reset()
        }
    }

    // MARK: - outgoing
    //
    // These are deliberately nonisolated so non-main callers (e.g. the
    // LookAccumulator flush timer on a user-interactive queue) can send
    // without a main-actor hop on every packet. We hop to main only to
    // capture the transport reference, then hand off to the transport actor.

    nonisolated func sendButton(_ id: Protocol.ButtonId, down: Bool) {
        if demoFlag.get() {
            demoInputState.setButton(id: id.rawValue, down: down)
            // In demo we also mirror hotbar slot presses into a
            // dedicated field so the HUD can show "slot N" instead of
            // "button 0x4N" — the slot number is the more user-readable
            // representation.
            if id.rawValue >= Protocol.ButtonId.hotbar1.rawValue
                && id.rawValue <= Protocol.ButtonId.hotbar9.rawValue
                && down {
                demoInputState.setHotbarSlot(Int(id.rawValue - Protocol.ButtonId.hotbar1.rawValue))
            }
            return
        }
        let payload = PacketCodec.encodeButton(buttonId: id.rawValue, down: down)
        Task { await self.send(payload) }
    }

    nonisolated func sendJoystick(x: Float, y: Float) {
        if demoFlag.get() {
            demoInputState.setJoystick(x: x, y: y)
            return
        }
        let payload = PacketCodec.encodeJoystick(x: x, y: y)
        Task { await self.send(payload) }
    }

    /// Camera-delta hot path. Bypasses the MainActor + HybridTransport
    /// actor hops by going through the lock-protected `LookDeltaSender`
    /// directly. Safe to call from any thread (designed to be invoked
    /// from `LookAccumulator`'s flush queue at ~125 Hz).
    nonisolated func sendLookDelta(dx: Int16, dy: Int16) {
        if demoFlag.get() {
            demoInputState.addDelta(dx: dx, dy: dy)
            return
        }
        lookSenderHolder.get()?.send(dx: dx, dy: dy)
    }

    /// `true` when the camera-delta path is currently using UDP (lower
    /// overhead, lower latency); `false` when it has fallen back to
    /// TCP-framed packets (used when the server didn't advertise a UDP
    /// port or the UDP open failed). Surfaced in the HUD so users can
    /// diagnose laggy in-game look.
    nonisolated var isCameraUDP: Bool {
        lookSenderHolder.get()?.isUDPActive ?? false
    }

    @MainActor private func send(_ data: Data) async {
        await transport?.send(data)
    }

    // MARK: - incoming routing

    private func handleControlMessage(_ msg: ControlMessage) {
        switch msg {
        case .pong(let seq):
            if let sentAt = pingSentAt.removeValue(forKey: seq) {
                rttMs = Int(Date().timeIntervalSince(sentAt) * 1000)
            }
        case .stateChange(let m):
            mode = ControllerMode(wireByte: m)
        default:
            break
        }
    }

    private func handleClose(_ err: Error?) {
        pingTask?.cancel()
        pingTask = nil
        if let err {
            state = .failed(reason: err.localizedDescription)
        } else {
            state = .disconnected
        }
        mode = .antiMistouch
        rttMs = nil
        transport = nil
        lookSenderHolder.set(nil)
    }

    // MARK: - ping loop

    private func startPingLoop() {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { break }
                await self.sendPing()
            }
        }
    }

    private func sendPing() async {
        nextPingSeq = nextPingSeq &+ 1
        let seq = nextPingSeq
        pingSentAt[seq] = Date()
        // GC stale entries (>10s) so the map can't grow unbounded.
        let cutoff = Date().addingTimeInterval(-10)
        pingSentAt = pingSentAt.filter { $0.value >= cutoff }
        await transport?.send(PacketCodec.encodePing(seq: seq))
    }
}
