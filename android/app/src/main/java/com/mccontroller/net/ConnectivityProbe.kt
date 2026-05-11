package com.mccontroller.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import java.net.InetSocketAddress
import java.net.Socket

/**
 * Lightweight reachability check: open a TCP socket, close it, return a
 * verdict. The home screen uses this to satisfy the user's "only enter
 * the controller after the connection actually works" requirement.
 *
 * This is intentionally NOT a full HELLO/HELLO_ACK round-trip — that's
 * what [com.mccontroller.core.ControllerSession] does once the user has
 * landed on the controller screen. The probe just answers "is there
 * something listening on that ip:port within `timeoutMs`?".
 *
 * Result types let the UI distinguish "no route" from "refused" from
 * "timeout" if it wants to show a helpful error string.
 */
object ConnectivityProbe {

    sealed class Result {
        object Ok : Result()
        data class Failed(val reason: String) : Result()
    }

    suspend fun probe(ip: String, port: Int, timeoutMs: Long = 3000): Result =
        withContext(Dispatchers.IO) {
            try {
                withTimeout(timeoutMs) {
                    Socket().use { s ->
                        s.connect(InetSocketAddress(ip, port), timeoutMs.toInt())
                    }
                }
                Result.Ok
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
}
