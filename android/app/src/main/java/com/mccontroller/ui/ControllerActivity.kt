package com.mccontroller.ui

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.mccontroller.core.ConnectionMode
import com.mccontroller.core.ConnectionState
import com.mccontroller.core.ControllerSession
import com.mccontroller.databinding.ActivityControllerBinding
import com.mccontroller.net.Protocol
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

/**
 * Main controller surface (landscape, fullscreen, immersive). Owns a
 * [ControllerSession] for its lifetime; HUD reflects connection + RTT.
 *
 * Step 4 puts only a placeholder body; joystick / look pad / buttons are
 * added in Steps 5–7.
 */
class ControllerActivity : AppCompatActivity() {

    private lateinit var binding: ActivityControllerBinding
    private val session = ControllerSession()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityControllerBinding.inflate(layoutInflater)
        setContentView(binding.root)

        // Immersive fullscreen: hide system bars, allow swipe-from-edge to peek.
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, binding.root).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }

        val ip = intent.getStringExtra(ConnectActivity.EXTRA_IP) ?: ""
        val port = intent.getIntExtra(ConnectActivity.EXTRA_PORT, Protocol.DEFAULT_PORT)
        val usbMode = intent.getBooleanExtra(ConnectActivity.EXTRA_USB_MODE, false)

        // HUD: re-render whenever state or RTT changes.
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                combine(session.state, session.rttMs) { state, rtt -> state to rtt }
                    .collect { (state, rtt) -> updateHud(state, rtt) }
            }
        }

        // Kick off the connection.
        lifecycleScope.launch {
            session.connect(ip, port, usbMode)
        }
    }

    override fun onDestroy() {
        session.disconnect()
        super.onDestroy()
    }

    private fun updateHud(state: ConnectionState, rtt: Int?) {
        val rttStr = rtt?.let { "${it}ms" } ?: "—"
        binding.txtHud.text = when (state) {
            is ConnectionState.Idle -> "Idle"
            is ConnectionState.Connecting -> "● Connecting…"
            is ConnectionState.Connected -> {
                val mode = if (state.mode == ConnectionMode.Wifi) "WiFi (TCP+UDP)" else "USB (TCP)"
                "● Connected   $mode   RTT: $rttStr"
            }
            is ConnectionState.Failed -> "● Failed: ${state.reason}"
            is ConnectionState.Disconnected -> "● Disconnected"
        }
    }
}
