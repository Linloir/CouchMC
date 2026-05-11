import Foundation

/// Owns the TCP control channel + optional UDP camera channel.
///
/// Performs the HELLO/HELLO_ACK handshake on connect, then forwards control
/// messages to `onMessage` and routes look deltas to UDP (if available) or to
/// TCP fallback.
actor HybridTransport {

    enum Mode { case wifi, usb }

    private let tcp = TCPChannel()
    private var udp: UDPChannel?

    /// Server-reported mode (0/1/2). Updated eagerly by the read loop so the
    /// initial STATE_CHANGE that arrives during handshake is not missed.
    private(set) var serverMode: UInt8 = 2  // start in AntiMistouch

    private var lookSeqTCP: UInt32 = 0

    private var onMessage: (@Sendable (ControlMessage) -> Void)?
    private var onClose: (@Sendable (Error?) -> Void)?
    private var onMode: (@Sendable (UInt8) -> Void)?

    /// Connect, send HELLO, await HELLO_ACK. WiFi mode opens UDP if the server
    /// advertised a port; USB mode never opens UDP.
    func connect(
        host: String,
        port: UInt16,
        mode: Mode,
        clientId: UInt32 = UInt32.random(in: 1...UInt32.max - 1),
        handshakeTimeout: TimeInterval = 3.0,
        onMessage: @escaping @Sendable (ControlMessage) -> Void,
        onModeChange: @escaping @Sendable (UInt8) -> Void,
        onClose: @escaping @Sendable (Error?) -> Void
    ) async throws {
        self.onMessage = onMessage
        self.onMode = onModeChange
        self.onClose = onClose

        try await tcp.connect(host: host, port: port)

        // The read loop is owned by NWConnection's queue. We forward everything
        // through here so this actor can safely capture STATE_CHANGE.
        let handler: TCPChannel.MessageHandler = { [weak self] msg in
            guard let self else { return }
            Task { await self.handleIncoming(msg) }
        }
        let closer: TCPChannel.DisconnectHandler = { [weak self] err in
            guard let self else { return }
            Task { await self.handleClose(err) }
        }
        tcp.startReading(onMessage: handler, onClose: closer)

        // Send HELLO and wait for HELLO_ACK.
        //
        // CRITICAL: the continuation that listens for HELLO_ACK must be
        // installed on `pendingHelloAck` **before** HELLO leaves the wire.
        // Otherwise the receive callback can deliver HELLO_ACK before
        // `awaitNextHelloAck`'s task has had a chance to enter the actor and
        // register its continuation — the response then falls through to
        // `onMessage?(...)` and the handshake silently times out after 3s.
        // (Android's coroutine ordering happens to be more deterministic so
        // this never bit them; on iOS task scheduling can run the sender
        // first.)
        let wantsUdp = (mode == .wifi)
        let hello = PacketCodec.encodeHello(protoVer: Protocol.version,
                                            clientId: clientId,
                                            wantsUdp: wantsUdp)

        let ack: ControlMessage = try await withCheckedThrowingContinuation {
            (cont: CheckedContinuation<ControlMessage, Error>) in
            // We're synchronously on the actor here — set the continuation
            // first, then dispatch HELLO send + timeout fallback as a
            // detached task.
            self.pendingHelloAck = cont
            Task { [weak self] in
                guard let self else { return }
                do {
                    try await self.tcp.sendAwaitable(hello)
                } catch {
                    await self.failPendingHelloAck(with: error)
                    return
                }
                try? await Task.sleep(
                    nanoseconds: UInt64(handshakeTimeout * 1_000_000_000)
                )
                await self.failPendingHelloAck(with: NetError.handshakeTimeout)
            }
        }

        guard case .helloAck(let status, let udpPort) = ack else {
            throw NetError.malformed
        }
        switch Protocol.HelloAckStatus(rawValue: status) ?? .protocolMismatch {
        case .ok:
            break
        case .protocolMismatch:
            throw NetError.handshakeRejected(reason: "protocol version mismatch")
        case .serverBusy:
            throw NetError.handshakeRejected(reason: "server busy")
        }

        // Open UDP if requested and offered.
        if wantsUdp && udpPort != 0 {
            let u = UDPChannel()
            do {
                try await u.open(host: host, port: udpPort)
                self.udp = u
            } catch {
                // UDP optional — fall back to TCP camera deltas silently.
                self.udp = nil
            }
        }
    }

    // MARK: - Outgoing convenience

    func send(_ data: Data) {
        tcp.send(data)
    }

    /// Camera delta. Goes via UDP when available, TCP framing otherwise.
    func sendLookDelta(dx: Int16, dy: Int16) {
        if let udp {
            udp.sendLookDelta(dx: dx, dy: dy)
        } else {
            lookSeqTCP = lookSeqTCP &+ 1
            tcp.send(PacketCodec.encodeLookDeltaTCP(seq: lookSeqTCP, dx: dx, dy: dy))
        }
    }

    func close() {
        udp?.close()
        udp = nil
        tcp.close()
    }

    // MARK: - HELLO_ACK awaiting

    private var pendingHelloAck: CheckedContinuation<ControlMessage, Error>?

    /// Resume the pending HELLO_ACK continuation with an error (timeout, send
    /// failure, etc.). Idempotent — a no-op if the continuation has already
    /// been fulfilled by an incoming HELLO_ACK.
    private func failPendingHelloAck(with error: Error) {
        guard let cont = pendingHelloAck else { return }
        pendingHelloAck = nil
        cont.resume(throwing: error)
    }

    private func handleIncoming(_ msg: ControlMessage) {
        // Capture STATE_CHANGE eagerly.
        if case .stateChange(let mode) = msg {
            serverMode = mode
            onMode?(mode)
        }
        // Complete the handshake if we're waiting on HELLO_ACK.
        if case .helloAck = msg, let cont = pendingHelloAck {
            pendingHelloAck = nil
            cont.resume(returning: msg)
            return
        }
        onMessage?(msg)
    }

    private func handleClose(_ err: Error?) {
        if let cont = pendingHelloAck {
            pendingHelloAck = nil
            cont.resume(throwing: err ?? NetError.notConnected)
        }
        onClose?(err)
    }
}
