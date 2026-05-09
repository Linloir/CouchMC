package com.mccontroller.ui

import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import android.view.View
import com.mccontroller.core.ConnectionMode
import com.mccontroller.core.ConnectionState
import com.mccontroller.core.ControllerMode
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

    // Sprint key state is the OR of two sources: the Sprint toggle button
    // and pushing the joystick past its rim. Either being true keeps SPRINT
    // held down; both must release for SPRINT to lift.
    private var sprintFromToggle = false
    private var sprintFromJoystick = false
    private var sprintEffective = false

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

        // HUD + layer-visibility: re-render on state, RTT, or mode change.
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                combine(session.state, session.rttMs, session.mode) { s, r, m -> Triple(s, r, m) }
                    .collect { (state, rtt, mode) ->
                        updateHud(state, rtt, mode)
                        updateLayerVisibility(mode)
                    }
            }
        }

        // Joystick wiring: view → CONFLATED channel → single-coroutine sender.
        binding.joystick.onPositionChanged = { x, y ->
            joystickChannel.trySend(x to y)
        }
        binding.joystick.onSprintExtensionChanged = { engaged ->
            sprintFromJoystick = engaged
            updateSprint()
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
        wireUiModeButtons()

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
        bind(binding.btnJump, Protocol.ButtonId.JUMP)
        bind(binding.btnLmb, Protocol.ButtonId.MOUSE_LEFT)
        bind(binding.btnRmb, Protocol.ButtonId.MOUSE_RIGHT)
        bind(binding.btnEsc, Protocol.ButtonId.ESC)
        bind(binding.btnInv, Protocol.ButtonId.INVENTORY)
        bind(binding.btnSwap, Protocol.ButtonId.SWAP_HAND)

        // Sprint button feeds into the OR-combined sprint state.
        binding.btnSprint.onStateChanged = { down ->
            sprintFromToggle = down
            updateSprint()
        }
    }

    private fun updateSprint() {
        val newEffective = sprintFromToggle || sprintFromJoystick
        if (newEffective != sprintEffective) {
            sprintEffective = newEffective
            lifecycleScope.launch {
                session.sendButton(Protocol.ButtonId.SPRINT, newEffective)
            }
        }
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

    private fun wireUiModeButtons() {
        fun bind(btn: ActionButtonView, buttonId: Byte) {
            btn.onStateChanged = { down ->
                lifecycleScope.launch { session.sendButton(buttonId, down) }
            }
        }
        bind(binding.btnUiLmb, Protocol.ButtonId.MOUSE_LEFT)
        bind(binding.btnUiRmb, Protocol.ButtonId.MOUSE_RIGHT)
        bind(binding.btnUiEsc, Protocol.ButtonId.ESC)
        bind(binding.btnUiQ, Protocol.ButtonId.DROP)
        bind(binding.btnUiShift, Protocol.ButtonId.SNEAK)  // Shift = SNEAK keycode
    }

    private val inGameWidgets: List<View> by lazy {
        listOf(
            binding.joystick,
            binding.rowSneakSprint,
            binding.btnLmb, binding.btnRmb, binding.btnJump,
            binding.rowTopButtons,
            binding.hotbar,
        )
    }

    private fun updateLayerVisibility(mode: ControllerMode) {
        val showInGame = mode == ControllerMode.InGame
        val showUiMode = mode == ControllerMode.UiInteract
        val showLock = mode == ControllerMode.AntiMistouch

        inGameWidgets.forEach {
            it.visibility = if (showInGame) View.VISIBLE else View.GONE
        }
        binding.columnUiButtons.visibility = if (showUiMode) View.VISIBLE else View.GONE
        binding.lockLayer.visibility = if (showLock) View.VISIBLE else View.GONE
    }

    private fun updateHud(state: ConnectionState, rtt: Int?, mode: ControllerMode) {
        val rttStr = rtt?.let { "${it}ms" } ?: "—"
        binding.txtHud.text = when (state) {
            is ConnectionState.Idle -> "Idle"
            is ConnectionState.Connecting -> "● Connecting…"
            is ConnectionState.Connected -> {
                val transport = if (state.mode == ConnectionMode.Wifi) "WiFi" else "USB"
                val modeLabel = when (mode) {
                    ControllerMode.InGame -> "in-game"
                    ControllerMode.UiInteract -> "UI"
                    ControllerMode.AntiMistouch -> "locked"
                }
                "● $transport · $modeLabel · $rttStr"
            }
            is ConnectionState.Failed -> "● Failed: ${state.reason}"
            is ConnectionState.Disconnected -> "● Disconnected"
        }
    }
}
