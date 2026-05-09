package com.mccontroller.core

import com.mccontroller.net.HybridTransport
import com.mccontroller.net.PacketCodec
import com.mccontroller.net.PongMsg
import com.mccontroller.net.StateChangeMsg
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentHashMap

sealed class ConnectionState {
    data object Idle : ConnectionState()
    data object Connecting : ConnectionState()
    data class Connected(val mode: ConnectionMode) : ConnectionState()
    data class Failed(val reason: String) : ConnectionState()
    data object Disconnected : ConnectionState()
}

enum class ConnectionMode { Wifi, Usb }

/**
 * High-level session lifecycle: handshake, ping/pong RTT measurement,
 * coroutine ownership. Owns the [HybridTransport] and a private scope
 * that the caller cancels via [disconnect].
 */
class ControllerSession {

    private val _state = MutableStateFlow<ConnectionState>(ConnectionState.Idle)
    val state: StateFlow<ConnectionState> = _state.asStateFlow()

    private val _rttMs = MutableStateFlow<Int?>(null)
    val rttMs: StateFlow<Int?> = _rttMs.asStateFlow()

    /**
     * Current controller mode pushed by the PC server. Defaults to
     * AntiMistouch so the lock screen shows immediately at startup,
     * giving way only when the first STATE_CHANGE arrives.
     */
    private val _mode = MutableStateFlow(ControllerMode.AntiMistouch)
    val mode: StateFlow<ControllerMode> = _mode.asStateFlow()

    private var transport: HybridTransport? = null
    private var sessionScope: CoroutineScope? = null
    private var pingJob: Job? = null
    private var dispatchJob: Job? = null

    suspend fun connect(host: String, port: Int, isUsbMode: Boolean) {
        if (_state.value is ConnectionState.Connected || _state.value is ConnectionState.Connecting) return
        _state.value = ConnectionState.Connecting

        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        sessionScope = scope

        try {
            val t = HybridTransport()
            t.connect(host, port, isUsbMode, scope)
            transport = t
            _state.value = ConnectionState.Connected(
                if (isUsbMode) ConnectionMode.Usb else ConnectionMode.Wifi
            )
            startPingLoop(scope)
        } catch (e: Exception) {
            scope.cancel()
            sessionScope = null
            transport?.close()
            transport = null
            _state.value = ConnectionState.Failed(e.message ?: e::class.simpleName ?: "unknown")
        }
    }

    fun disconnect() {
        pingJob?.cancel()
        dispatchJob?.cancel()
        sessionScope?.cancel()
        transport?.close()
        transport = null
        sessionScope = null
        pingJob = null
        dispatchJob = null
        if (_state.value !is ConnectionState.Failed) {
            _state.value = ConnectionState.Disconnected
        }
        _rttMs.value = null
        _mode.value = ControllerMode.AntiMistouch
    }

    suspend fun sendButton(buttonId: Byte, down: Boolean) {
        transport?.sendControl(PacketCodec.encodeButton(buttonId, down))
    }

    suspend fun sendJoystick(x: Float, y: Float) {
        transport?.sendControl(PacketCodec.encodeJoystick(x, y))
    }

    suspend fun sendLookDelta(dx: Short, dy: Short) {
        transport?.sendLookDelta(dx, dy)
    }

    private fun startPingLoop(scope: CoroutineScope) {
        val pendingPings = ConcurrentHashMap<Int, Long>()

        dispatchJob = scope.launch {
            transport?.incoming?.collect { msg ->
                if (msg is PongMsg) {
                    pendingPings.remove(msg.seq)?.let { sentAt ->
                        _rttMs.value = (System.currentTimeMillis() - sentAt).toInt()
                    }
                }
                // StateChangeMsg is captured eagerly by HybridTransport into
                // its serverMode StateFlow; mirrored by the launch below so
                // a STATE_CHANGE that arrived during handshake (before any
                // collector subscribed to `incoming`) is still picked up.
            }
        }

        scope.launch {
            transport?.serverMode?.collect { byte ->
                _mode.value = ControllerMode.fromByte(byte)
            }
        }

        pingJob = scope.launch {
            var seq = 0
            val staleCutoffMs = 10_000L
            while (isActive) {
                pendingPings[seq] = System.currentTimeMillis()
                try {
                    transport?.sendControl(PacketCodec.encodePing(seq))
                } catch (_: Exception) {
                    // socket dying; read-loop completion will trigger disconnect
                }
                seq++
                val cutoff = System.currentTimeMillis() - staleCutoffMs
                pendingPings.entries.removeAll { it.value < cutoff }
                delay(1000)
            }
        }
    }
}
