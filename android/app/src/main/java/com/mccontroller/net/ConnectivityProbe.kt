package com.mccontroller.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Session-less reachability check using the PROBE / PROBE_ACK message
 * pair (see docs/protocol.md § "PROBE / PROBE_ACK").
 *
 * Earlier we just opened a TCP socket and closed it. That made the
 * server flicker its "client connected" indicator on every reachability
 * tick because it couldn't tell a probe from a real client that gave
 * up before sending HELLO. The new probe:
 *
 *   1. Open TCP socket to ip:port.
 *   2. Send PROBE frame (3 bytes: `00 01 FE`).
 *   3. Read PROBE_ACK frame (4 bytes: `00 02 FF <status>`).
 *   4. Close.
 *
 * The server is expected to handle PROBE without firing the
 * "client connected" callback chain — the whole point is to be invisible.
 *
 * The home-screen card uses this both for first-tap connect verification
 * AND for the periodic 3-second USB-loopback alive check.
 */
object ConnectivityProbe {

    sealed class Result {
        /** Server answered PROBE_ACK with status=ALIVE — ready to accept HELLO. */
        object Ok : Result()
        /** Server is alive but already has a client. Still counts as reachable for UI. */
        object Busy : Result()
        /** Could not connect, server didn't respond, or protocol error. */
        data class Failed(val reason: String) : Result()
    }

    suspend fun probe(ip: String, port: Int, timeoutMs: Long = 3000): Result =
        withContext(Dispatchers.IO) {
            try {
                withTimeout(timeoutMs) {
                    Socket().use { s ->
                        s.connect(InetSocketAddress(ip, port), timeoutMs.toInt())
                        s.soTimeout = (timeoutMs.coerceAtLeast(400) / 2).toInt()

                        // Send PROBE frame: [u16 len = 1][u8 type = 0xFE]
                        try {
                            val out = s.getOutputStream()
                            out.write(byteArrayOf(0, 1, Protocol.MsgType.PROBE))
                            out.flush()
                        } catch (_: Exception) {
                            // Couldn't even write — server was open enough to
                            // accept but closed immediately. Still treat as
                            // "reachable" for the UI; failed-to-connect would
                            // have thrown earlier from connect().
                            return@withTimeout Result.Ok
                        }

                        // Try to read PROBE_ACK. Any deviation (EOF, timeout,
                        // unknown type, bad length) is treated as a *legacy*
                        // server that doesn't speak PROBE yet — TCP was open,
                        // so the host is reachable; we just can't get a
                        // busy/alive distinction. Result.Ok.
                        val input = s.getInputStream()
                        val header = ByteArray(2)
                        if (input.readFully(header) < 2) return@withTimeout Result.Ok
                        val len = ((header[0].toInt() and 0xff) shl 8) or (header[1].toInt() and 0xff)
                        if (len < 1 || len > 16) return@withTimeout Result.Ok

                        val payload = ByteArray(len)
                        if (input.readFully(payload) < len) return@withTimeout Result.Ok
                        if (payload[0] != Protocol.MsgType.PROBE_ACK) return@withTimeout Result.Ok

                        val status = if (len >= 2) payload[1] else Protocol.ProbeStatus.ALIVE
                        when (status) {
                            Protocol.ProbeStatus.ALIVE -> Result.Ok
                            Protocol.ProbeStatus.BUSY -> Result.Busy
                            Protocol.ProbeStatus.PROTOCOL_INCOMPATIBLE ->
                                Result.Failed("incompatible protocol version")
                            else -> Result.Ok   // unknown status: trust reachability
                        }
                    }
                }
            } catch (_: TimeoutCancellationException) {
                Result.Failed("timeout")
            } catch (e: java.net.ConnectException) {
                Result.Failed(e.message ?: "refused")
            } catch (e: java.net.SocketTimeoutException) {
                Result.Failed("timeout")
            } catch (e: Exception) {
                Result.Failed(e.message ?: e.javaClass.simpleName)
            }
        }

    /** Reads `dst.size` bytes from the stream, blocking. Returns count read; < size on EOF. */
    private fun java.io.InputStream.readFully(dst: ByteArray): Int {
        var read = 0
        while (read < dst.size) {
            val n = read(dst, read, dst.size - read)
            if (n < 0) return read
            read += n
        }
        return read
    }
}
