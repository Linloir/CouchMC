import Foundation
import os.lock

/// Nonisolated, lock-protected fast path for camera-delta packets.
///
/// Why this exists: the look-delta hot path runs at ~125 Hz from the
/// `LookAccumulator` flush timer. Routing every packet through
/// `ControllerSession.sendLookDelta` -> `Task { await @MainActor ... }`
/// -> `await HybridTransport.actor` -> `udp.send(...)` involves two
/// actor hops per packet. When the main thread is busy (the user is
/// dragging on the LookPad / Joystick and UIKit is processing
/// touchesMoved at 120 Hz), the MainActor hop stalls and the Tasks
/// queue up — then drain in a burst once main is free, producing the
/// "camera freezes for a beat then jumps a long way" stutter that
/// Android (which sends from the touch thread directly with no
/// hops) doesn't suffer.
///
/// This class lets the look-delta path skip every actor:
///   - `udp` is set once after the HELLO_ACK by `HybridTransport`.
///   - `lookSeqTCP` is the TCP-fallback sequence counter, used only
///     when UDP is unavailable.
///   - Both are protected by `os_unfair_lock`, which has lower overhead
///     than NSLock or actor isolation and is safe across threads.
///
/// Other transport paths (HELLO, button presses, joystick state, ping)
/// stay on the actor — they're low-frequency, so the actor's serial
/// guarantees are worth more than the MainActor-hop savings.
final class LookDeltaSender: @unchecked Sendable {

    private let tcp: TCPChannel
    private var udpRef: UDPChannel?
    private var udpLock = os_unfair_lock()
    private var lookSeqTCP: UInt32 = 0
    private var seqLock = os_unfair_lock()

    /// True iff the last `setUDP` was called with a non-nil channel. Read
    /// from the HUD code path on a non-main queue, so we use the same
    /// `udpLock` to keep the view consistent. The caller doesn't get a
    /// strong UDP reference (we don't want to leak the channel beyond its
    /// session), just whether the fast path is currently UDP or TCP.
    var isUDPActive: Bool {
        os_unfair_lock_lock(&udpLock)
        defer { os_unfair_lock_unlock(&udpLock) }
        return udpRef != nil
    }

    init(tcp: TCPChannel) {
        self.tcp = tcp
    }

    /// Called by `HybridTransport` after UDP is established (or when it
    /// closes / falls back). Pass `nil` to clear.
    func setUDP(_ udp: UDPChannel?) {
        os_unfair_lock_lock(&udpLock)
        udpRef = udp
        os_unfair_lock_unlock(&udpLock)
    }

    /// The hot path. Safe to call from any thread; specifically intended
    /// to be called directly from `LookAccumulator`'s flush timer queue
    /// (`mcc.look.flush`, userInteractive QoS) without any actor hops.
    func send(dx: Int16, dy: Int16) {
        os_unfair_lock_lock(&udpLock)
        let udp = udpRef
        os_unfair_lock_unlock(&udpLock)

        if let udp {
            udp.sendLookDelta(dx: dx, dy: dy)
            return
        }

        // TCP fallback: wire-frame `LOOK_DELTA_TCP`. Sequence counter
        // is per-session, not per-channel, so we keep it here rather
        // than on TCPChannel.
        os_unfair_lock_lock(&seqLock)
        lookSeqTCP = lookSeqTCP &+ 1
        let seq = lookSeqTCP
        os_unfair_lock_unlock(&seqLock)
        tcp.send(PacketCodec.encodeLookDeltaTCP(seq: seq, dx: dx, dy: dy))
    }
}

/// Thread-safe holder for the active session's `LookDeltaSender`. Lets a
/// `@MainActor` class (`ControllerSession`) hand off / clear the sender on
/// connect / disconnect from main, while a non-main flush thread reads it
/// without an actor hop on every packet.
final class LookSenderHolder: @unchecked Sendable {
    private var sender: LookDeltaSender?
    private var lock = os_unfair_lock()

    func set(_ s: LookDeltaSender?) {
        os_unfair_lock_lock(&lock)
        sender = s
        os_unfair_lock_unlock(&lock)
    }

    func get() -> LookDeltaSender? {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return sender
    }
}
