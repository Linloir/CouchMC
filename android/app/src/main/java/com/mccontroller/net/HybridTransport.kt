package com.mccontroller.net

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.asSharedFlow
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
        // The read loop both completes the handshake deferred and forwards
        // every message to the public flow.
        scope.launch(Dispatchers.IO) {
            tcp.runReadLoop(this) { msg ->
                if (msg is HelloAckMsg && !handshakeAck.isCompleted) {
                    handshakeAck.complete(msg)
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
