package com.mccontroller.ui

import android.os.Bundle
import android.view.KeyEvent
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
import com.mccontroller.core.AppSettings
import com.mccontroller.core.ControllerSession
import com.mccontroller.core.HostStore
import com.mccontroller.core.LayoutApplier
import com.mccontroller.core.LayoutProfile
import com.mccontroller.core.ProfileStore
import com.mccontroller.core.SettingsStore
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
    private lateinit var activeProfile: LayoutProfile

    /**
     * Joystick state goes through a CONFLATED channel so that bursts of
     * touch updates collapse to "the latest" — keeping the IO sender from
     * piling up coroutines while preserving final-position correctness.
     */
    private val joystickChannel = Channel<Pair<Float, Float>>(Channel.CONFLATED)

    /**
     * Hotbar slot selection goes through a CONFLATED channel + single
     * sender coroutine so a fast swipe (e.g. 5→1 in one motion) can't
     * out-of-order multiple hotbar key events — the consumer always sends
     * the latest target slot and the PC ends up on the right slot.
     */
    private val hotbarSelectChannel = Channel<Int>(Channel.CONFLATED)

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

        // Apply the user's saved layout profile (or factory default on first run).
        val store = ProfileStore(this)
        val (profiles, activeName) = store.loadAll()
        activeProfile = profiles.firstOrNull { it.name == activeName } ?: profiles.first()
        applyProfileLayout()

        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, binding.root).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }

        val ip = intent.getStringExtra(EXTRA_IP) ?: ""
        val port = intent.getIntExtra(EXTRA_PORT, Protocol.DEFAULT_PORT)
        val usbMode = intent.getBooleanExtra(EXTRA_USB_MODE, false)
        val savedHostId = intent.getStringExtra(EXTRA_SAVED_HOST_ID)

        // HUD + layer-visibility + lookpad mode: re-render on state, RTT,
        // or mode change. Also bumps the saved-host "last connected" stamp
        // the first time we reach Connected this session, so the home list
        // sorts recents to the top next time.
        var markedConnected = false
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                combine(session.state, session.rttMs, session.mode) { s, r, m -> Triple(s, r, m) }
                    .collect { (state, rtt, mode) ->
                        updateHud(state, rtt, mode)
                        updateLayerVisibility(mode)
                        binding.lookPad.mode = mode
                        if (!markedConnected &&
                            state is ConnectionState.Connected &&
                            savedHostId != null
                        ) {
                            markedConnected = true
                            HostStore.get(applicationContext).markConnected(savedHostId)
                        }
                    }
            }
        }

        // App settings — hotbar swipe mode, gesture toggles, volume key
        // bindings. Re-applied whenever the user changes them in Settings.
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                SettingsStore.get(applicationContext).settings.collect { applyAppSettings(it) }
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
        // Tap / double-tap gestures on the look pad.
        binding.lookPad.onPrimaryTap = {
            lifecycleScope.launch {
                session.sendButton(Protocol.ButtonId.MOUSE_LEFT, true)
                kotlinx.coroutines.delay(50)
                session.sendButton(Protocol.ButtonId.MOUSE_LEFT, false)
            }
        }
        binding.lookPad.onSecondaryTap = {
            lifecycleScope.launch {
                session.sendButton(Protocol.ButtonId.MOUSE_RIGHT, true)
                kotlinx.coroutines.delay(50)
                session.sendButton(Protocol.ButtonId.MOUSE_RIGHT, false)
            }
        }
        binding.lookPad.onHoldStart = {
            lifecycleScope.launch { session.sendButton(Protocol.ButtonId.MOUSE_LEFT, true) }
        }
        binding.lookPad.onHoldEnd = {
            lifecycleScope.launch { session.sendButton(Protocol.ButtonId.MOUSE_LEFT, false) }
        }
        binding.lookPad.onSecondaryHoldStart = {
            lifecycleScope.launch { session.sendButton(Protocol.ButtonId.MOUSE_RIGHT, true) }
        }
        binding.lookPad.onSecondaryHoldEnd = {
            lifecycleScope.launch { session.sendButton(Protocol.ButtonId.MOUSE_RIGHT, false) }
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
        hotbarSelectChannel.close()
        session.disconnect()
        super.onDestroy()
    }

    // ===== Volume key intercept =====
    //
    // VOL_UP/DOWN map to mouse LMB/RMB so the user can use phone hardware
    // keys for fast attack/use without taking a finger off the look pad.
    // Returning true consumes the event and prevents the system from
    // changing media volume.

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (!isVolumeKey(keyCode)) return super.onKeyDown(keyCode, event)
        if (event != null && event.repeatCount > 0) return true   // first DOWN already sent
        bindingForVolumeKey(keyCode)?.let { id ->
            lifecycleScope.launch { session.sendButton(id.toByte(), true) }
        }
        return true   // consume even if unbound — don't change media volume
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (!isVolumeKey(keyCode)) return super.onKeyUp(keyCode, event)
        bindingForVolumeKey(keyCode)?.let { id ->
            lifecycleScope.launch { session.sendButton(id.toByte(), false) }
        }
        return true
    }

    private fun isVolumeKey(keyCode: Int): Boolean =
        keyCode == KeyEvent.KEYCODE_VOLUME_UP || keyCode == KeyEvent.KEYCODE_VOLUME_DOWN

    /** Resolves the current binding for a volume key. Null means unbound. */
    private fun bindingForVolumeKey(keyCode: Int): Int? {
        val s = SettingsStore.get(applicationContext).current
        return when (keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP -> s.volumeUpBinding
            KeyEvent.KEYCODE_VOLUME_DOWN -> s.volumeDownBinding
            else -> null
        }
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

        // Drag-while-held on LMB/RMB also nudges the camera, but only when
        // the lookpad isn't already capturing camera with another finger.
        // Without that guard, the lookpad's deltas double up.
        val dragRouting: (Int, Int) -> Unit = { dx, dy ->
            if (!binding.lookPad.isDragging) {
                lookAccumulator.add(dx, dy)
            }
        }
        binding.btnLmb.onDragDelta = dragRouting
        binding.btnRmb.onDragDelta = dragRouting
    }

    private fun updateSprint() {
        val newEffective = sprintFromToggle || sprintFromJoystick
        if (newEffective != sprintEffective) {
            sprintEffective = newEffective
            lifecycleScope.launch {
                session.sendButton(Protocol.ButtonId.SPRINT, newEffective)
            }
        }
        // Keep the Sprint button's visual in sync with the effective state so
        // it lights up whether sprint was triggered by tap or by joystick.
        binding.btnSprint.setToggleState(newEffective)
    }

    private fun wireHotbar() {
        binding.hotbar.onSelect = { slot ->
            hotbarSelectChannel.trySend(slot)
        }
        binding.hotbar.onDrop = { _ ->
            lifecycleScope.launch {
                session.sendButton(Protocol.ButtonId.DROP, true)
                session.sendButton(Protocol.ButtonId.DROP, false)
            }
        }
        // Single consumer: serializes sends, and on fast swipes the
        // CONFLATED channel collapses intermediate slots to the latest.
        lifecycleScope.launch {
            for (slot in hotbarSelectChannel) {
                val buttonId = (Protocol.ButtonId.HOTBAR_1.toInt() + slot).toByte()
                session.sendButton(buttonId, true)
                session.sendButton(buttonId, false)
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
            binding.btnSneak,
            binding.btnLmb, binding.btnRmb, binding.btnJump, binding.btnSprint,
            binding.btnSwap, binding.btnInv, binding.btnEsc,
            binding.hotbar,
        )
    }

    private val uiModeWidgets: List<View> by lazy {
        listOf(
            binding.btnUiLmb, binding.btnUiRmb,
            binding.btnUiQ, binding.btnUiShift, binding.btnUiEsc,
        )
    }

    private fun inGameWidgetMap(): Map<String, View> = mapOf(
        "joystick" to binding.joystick,
        "btn_sneak" to binding.btnSneak,
        "btn_sprint" to binding.btnSprint,
        "btn_lmb" to binding.btnLmb,
        "btn_rmb" to binding.btnRmb,
        "btn_jump" to binding.btnJump,
        "btn_swap" to binding.btnSwap,
        "btn_inv" to binding.btnInv,
        "btn_esc" to binding.btnEsc,
        "hotbar" to binding.hotbar,
    )

    private fun uiModeWidgetMap(): Map<String, View> = mapOf(
        "btn_ui_lmb" to binding.btnUiLmb,
        "btn_ui_rmb" to binding.btnUiRmb,
        "btn_ui_q" to binding.btnUiQ,
        "btn_ui_shift" to binding.btnUiShift,
        "btn_ui_esc" to binding.btnUiEsc,
    )

    private fun applyProfileLayout() {
        LayoutApplier.applyAll(inGameWidgetMap(), activeProfile.inGame)
        LayoutApplier.applyAll(uiModeWidgetMap(), activeProfile.uiMode)
        // hotbarSwipeMode + L/R margin overrides + gesture toggles come from
        // AppSettings now — see applyAppSettings() collector.
    }

    /**
     * Pushes the latest [AppSettings] values into the widgets that read
     * them: hotbar swipe mode, lookpad quick-click toggles. Edge offsets
     * are applied through a separate margin override; volume bindings
     * are read on demand in [bindingForVolumeKey].
     */
    private fun applyAppSettings(s: AppSettings) {
        binding.hotbar.swipeMode = s.hotbarSwipeMode
        binding.hotbar.relativeStepDp = s.hotbarRelativeStepDp
        binding.lookPad.inGameQuickClicks = s.inGameQuickClicks
        binding.lookPad.uiQuickClicks = s.uiQuickClicks
        binding.joystick.quickSprintEnabled = s.quickSprintEnabled
        binding.joystick.sprintEngageFactor = s.sprintEngageFactor
    }

    private fun updateLayerVisibility(mode: ControllerMode) {
        val showInGame = mode == ControllerMode.InGame
        val showUiMode = mode == ControllerMode.UiInteract
        val showLock = mode == ControllerMode.AntiMistouch

        inGameWidgets.forEach {
            it.visibility = if (showInGame) View.VISIBLE else View.GONE
        }
        uiModeWidgets.forEach {
            it.visibility = if (showUiMode) View.VISIBLE else View.GONE
        }
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

    companion object {
        /** Target IP. Required. */
        const val EXTRA_IP = "ip"
        /** Target TCP port. Defaults to 34555 if absent. */
        const val EXTRA_PORT = "port"
        /** True if connecting via adb-reverse on 127.0.0.1 (no UDP). */
        const val EXTRA_USB_MODE = "usbMode"
        /**
         * Optional [com.mccontroller.core.SavedHost.id]. When present and
         * the connection succeeds, [com.mccontroller.core.HostStore.markConnected]
         * is called so this host bubbles to the top of the home list next time.
         */
        const val EXTRA_SAVED_HOST_ID = "savedHostId"
    }
}
