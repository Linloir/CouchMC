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
import com.mccontroller.input.LookAccumulator
import com.mccontroller.net.Protocol
import com.mccontroller.ui.view.ActionButtonView
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch

/**
 * Main controller surface (landscape, fullscreen, immersive). Owns a
 * [ControllerSession] for its lifetime; HUD reflects connection + RTT.
 *
 * Step 5: joystick wired up. Look pad / buttons / hotbar in Steps 6–7.
 */
class ControllerActivity : AppCompatActivity() {

    private lateinit var binding: ActivityControllerBinding
    private val session = ControllerSession()
    private val lookAccumulator = LookAccumulator(session)

    /**
     * Joystick state goes through a CONFLATED channel so that bursts of
     * touch updates collapse to "the latest" — keeping the IO sender from
     * piling up coroutines while preserving final-position correctness.
     */
    private val joystickChannel = Channel<Pair<Float, Float>>(Channel.CONFLATED)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityControllerBinding.inflate(layoutInflater)
        setContentView(binding.root)

        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, binding.root).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }

        val ip = intent.getStringExtra(ConnectActivity.EXTRA_IP) ?: ""
        val port = intent.getIntExtra(ConnectActivity.EXTRA_PORT, Protocol.DEFAULT_PORT)
        val usbMode = intent.getBooleanExtra(ConnectActivity.EXTRA_USB_MODE, false)

        // HUD: re-render on state or RTT change.
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                combine(session.state, session.rttMs) { state, rtt -> state to rtt }
                    .collect { (state, rtt) -> updateHud(state, rtt) }
            }
        }

        // Joystick wiring: view → CONFLATED channel → single-coroutine sender.
        binding.joystick.onPositionChanged = { x, y ->
            joystickChannel.trySend(x to y)
        }
        lifecycleScope.launch {
            for ((x, y) in joystickChannel) {
                session.sendJoystick(x, y)
            }
        }

        // Look pad wiring: view → atomic accumulator → 8ms flush coroutine.
        binding.lookPad.onLookDelta = { dx, dy ->
            lookAccumulator.add(dx, dy)
        }
        lookAccumulator.start(lifecycleScope)

        wireButtons()
        wireHotbar()

        lifecycleScope.launch {
            session.connect(ip, port, usbMode)
        }
    }

    override fun onPause() {
        super.onPause()
        // Safety: if the activity is backgrounded with the joystick held,
        // make sure WASD doesn't stay pressed on the PC.
        joystickChannel.trySend(0f to 0f)
    }

    override fun onDestroy() {
        lookAccumulator.stop()
        joystickChannel.close()
        session.disconnect()
        super.onDestroy()
    }

    private fun wireButtons() {
        fun bind(btn: ActionButtonView, buttonId: Byte) {
            btn.onStateChanged = { down ->
                lifecycleScope.launch { session.sendButton(buttonId, down) }
            }
        }
        bind(binding.btnSneak, Protocol.ButtonId.SNEAK)
        bind(binding.btnSprint, Protocol.ButtonId.SPRINT)
        bind(binding.btnJump, Protocol.ButtonId.JUMP)
        bind(binding.btnLmb, Protocol.ButtonId.MOUSE_LEFT)
        bind(binding.btnRmb, Protocol.ButtonId.MOUSE_RIGHT)
        bind(binding.btnEsc, Protocol.ButtonId.ESC)
        bind(binding.btnInv, Protocol.ButtonId.INVENTORY)
        bind(binding.btnSwap, Protocol.ButtonId.SWAP_HAND)
    }

    private fun wireHotbar() {
        binding.hotbar.onSelect = { slot ->
            val buttonId = (Protocol.ButtonId.HOTBAR_1.toInt() + slot).toByte()
            lifecycleScope.launch {
                session.sendButton(buttonId, true)
                session.sendButton(buttonId, false)
            }
        }
        binding.hotbar.onDrop = { _ ->
            lifecycleScope.launch {
                session.sendButton(Protocol.ButtonId.DROP, true)
                session.sendButton(Protocol.ButtonId.DROP, false)
            }
        }
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
