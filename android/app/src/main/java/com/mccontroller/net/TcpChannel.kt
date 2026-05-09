package com.mccontroller.net

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.isActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Single TCP connection with a length-prefixed framing read loop.
 * `runReadLoop` blocks until the socket closes; emit each parsed message
 * via the supplied callback.
 */
class TcpChannel {
    private var socket: Socket? = null
    private val sendMutex = Mutex()

    @Throws(IOException::class)
    suspend fun connect(host: String, port: Int) = withContext(Dispatchers.IO) {
        val s = Socket().apply {
            tcpNoDelay = true
            connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)
        }
        socket = s
    }

    suspend fun send(packet: ByteArray) = withContext(Dispatchers.IO) {
        sendMutex.withLock {
            try {
                socket?.getOutputStream()?.let { out ->
                    out.write(packet)
                    out.flush()
                }
            } catch (e: IOException) {
                // socket dying; let read loop clean up
            }
        }
    }

    /**
     * Block reading from the socket until it closes or `scope` is cancelled.
     * Each parsed [ControlMessage] is delivered to [onMessage].
     */
    suspend fun runReadLoop(scope: CoroutineScope, onMessage: (ControlMessage) -> Unit) =
        withContext(Dispatchers.IO) {
            val sock = socket ?: return@withContext
            val buffer = ByteArray(4096)
            var filled = 0
            try {
                val input = sock.getInputStream()
                while (scope.isActive) {
                    val read = input.read(buffer, filled, buffer.size - filled)
                    if (read <= 0) break
                    filled += read

                    var consumed = 0
                    while (consumed < filled) {
                        val res = PacketCodec.tryReadFrame(buffer, consumed, filled) ?: break
                        consumed += res.frameLen
                        onMessage(res.msg)
                    }
                    if (consumed > 0) {
                        System.arraycopy(buffer, consumed, buffer, 0, filled - consumed)
                        filled -= consumed
                    }
                    if (filled == buffer.size) break  // protocol violation
                }
            } catch (e: IOException) {
                // socket closed or read failure — caller will observe via close
            }
        }

    fun close() {
        try { socket?.close() } catch (_: Throwable) {}
        socket = null
    }

    val isConnected: Boolean
        get() {
            val s = socket
            return s != null && s.isConnected && !s.isClosed
        }

    companion object {
        const val CONNECT_TIMEOUT_MS = 3000
    }
}
