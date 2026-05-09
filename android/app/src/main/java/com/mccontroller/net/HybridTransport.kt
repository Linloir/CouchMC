package com.mccontroller.net

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.io.IOException
import java.util.concurrent.atomic.AtomicInteger

/**
 * Combines the TCP control channel with an optional UDP camera channel.
 *
 * On WiFi (server accepts UDP) — control packets go over TCP, look deltas
 * over UDP. On USB (client signals `wantsUdp=false`, or server doesn't
 * advertise a UDP port) — everything goes over TCP, with look deltas
 * carried as `LOOK_DELTA_TCP`.
 */
class HybridTransport {

    private val tcp = TcpChannel()
    private var udp: UdpChannel? = null
    private val tcpFallbackSeq = AtomicInteger(0)
    private val handshakeAck = CompletableDeferred<HelloAckMsg>()

    private val _incoming = MutableSharedFlow<ControlMessage>(
        replay = 0,
        extraBufferCapacity = 32,
    )
    val incoming: SharedFlow<ControlMessage> = _incoming.asSharedFlow()

    /**
     * Server-pushed mode (raw byte: 0=InGame, 1=UiInteract, 2=AntiMistouch).
     * Updated synchronously inside the read loop so it captures STATE_CHANGE
     * messages that arrive during the handshake — before any external
     * collector has a chance to subscribe.
     *
     * StateFlow always replays the current value to new subscribers, so
     * `ControllerSession.mode` will see the correct value on the very first
     * collect even if the message arrived earlier.
     */
    private val _serverMode = MutableStateFlow<Byte>(2)  // start in AntiMistouch
    val serverMode: StateFlow<Byte> = _serverMode.asStateFlow()

    val isUdpAvailable: Boolean get() = udp != null

    /**
     * Connects TCP, sends HELLO, awaits HELLO_ACK, opens UDP if accepted.
     * Throws on failure.
     */
    suspend fun connect(
        host: String,
        port: Int,
        isUsbMode: Boolean,
        scope: CoroutineScope,
    ) {
        tcp.connect(host, port)

        // Start the read loop in the caller's scope so cancellation propagates.
        // The read loop completes the handshake deferred, captures the latest
        // server mode into a StateFlow (so late subscribers still see it),
        // and forwards every message to the public flow.
        scope.launch(Dispatchers.IO) {
            tcp.runReadLoop(this) { msg ->
                when (msg) {
                    is HelloAckMsg -> {
                        if (!handshakeAck.isCompleted) handshakeAck.complete(msg)
                    }
                    is StateChangeMsg -> {
                        _serverMode.value = msg.mode
                    }
                    else -> { /* nothing eager; rest goes to the shared flow */ }
                }
                _incoming.tryEmit(msg)
            }
            // When the read loop returns, the connection is dead.
            close()
        }

        // Send HELLO.
        tcp.send(PacketCodec.encodeHello(
            protoVer = Protocol.VERSION,
            clientId = CLIENT_ID,
            wantsUdp = !isUsbMode,
        ))

        // Wait for HELLO_ACK with a timeout. CompletableDeferred avoids the
        // race window of subscribing to a SharedFlow after an emission.
        val ack = withTimeoutOrNull(HELLO_TIMEOUT_MS) { handshakeAck.await() }
            ?: throw IOException("HELLO_ACK timeout")

        if (ack.status != Protocol.HelloAckStatus.OK) {
            throw IOException("HELLO_ACK status=${ack.status} (expected OK=0)")
        }

        // Open UDP if the server advertised a port and the client wants it.
        if (!isUsbMode && ack.udpPort != 0) {
            udp = UdpChannel(host, ack.udpPort).apply { open() }
        }
    }

    suspend fun sendControl(packet: ByteArray) {
        tcp.send(packet)
    }

    suspend fun sendLookDelta(dx: Short, dy: Short) {
        val u = udp
        if (u != null) {
            u.sendLookDelta(dx, dy)
        } else {
            tcp.send(PacketCodec.encodeLookDeltaTcp(tcpFallbackSeq.getAndIncrement(), dx, dy))
        }
    }

    fun close() {
        tcp.close()
        udp?.close()
        udp = null
    }

    companion object {
        const val HELLO_TIMEOUT_MS = 3000L
        // Arbitrary 32-bit identifier; not currently used by server, but
        // reserved by the protocol. Fixed value is fine for single-client demo.
        const val CLIENT_ID = 0xCAFEBABE.toInt()
    }
}
