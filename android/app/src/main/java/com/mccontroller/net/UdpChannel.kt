package com.mccontroller.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress
import java.util.concurrent.atomic.AtomicInteger

/**
 * Outbound-only UDP socket for the camera channel. Sequence numbers
 * are auto-incremented; the server uses them to drop reordered/duplicate
 * datagrams.
 */
class UdpChannel(host: String, port: Int) {
    private val target = InetSocketAddress(host, port)
    private val seqGen = AtomicInteger(0)
    private var socket: DatagramSocket? = null

    suspend fun open() = withContext(Dispatchers.IO) {
        socket = DatagramSocket()  // bind to ephemeral local port
    }

    suspend fun sendLookDelta(dx: Short, dy: Short) = withContext(Dispatchers.IO) {
        val s = socket ?: return@withContext
        val seq = seqGen.getAndIncrement()
        val packet = PacketCodec.encodeLookDeltaUdp(seq, dx, dy)
        try {
            s.send(DatagramPacket(packet, packet.size, target))
        } catch (_: Throwable) {
            // UDP send may fail silently on network issues; lookup level handles loss
        }
    }

    fun close() {
        try { socket?.close() } catch (_: Throwable) {}
        socket = null
    }
}
