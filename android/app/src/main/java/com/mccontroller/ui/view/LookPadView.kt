package com.mccontroller.ui.view

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import com.mccontroller.core.ControllerMode

/**
 * Touch surface for camera (in-game) / cursor (UI) control plus a
 * custom gesture FSM. Two distinct gesture trees per mode:
 *
 * **In-game** (priority: low-latency clicks + chained combat hold):
 * - Press + quick UP: primary tap fires *immediately* on UP.
 * - Press + slide: camera move only.
 * - Within ~280ms of the previous tap, second DOWN enters LMB-held mode
 *   (LMB DOWN on DOWN, LMB UP on UP). Camera deltas still fire during
 *   the hold. If the hold finished WITHOUT having slid, we chain back
 *   into the after-tap window so another DOWN can start another hold
 *   (rapid clicking pattern). If the hold DID slide, we end at IDLE so
 *   the very next press is a fresh first tap — fixes the "second press
 *   after slide-hold accidentally re-enters hold" bug.
 *
 * **UI** (priority: distinct LMB / RMB clicks + slide-while-held for
 * crafting / inventory work):
 * - Press + slide: cursor move only.
 * - Press + quick UP: single tap pending; fires LMB click after ~200ms
 *   *unless* a second DOWN arrives within that window.
 * - Second DOWN within window + slide: LMB hold during the slide.
 * - Second DOWN within window + quick UP: RMB click (= double tap).
 * - Within ~200ms of an RMB click, a third DOWN + slide: RMB hold.
 * - All other branches go back to IDLE.
 *
 * State resets on mode change so a mid-gesture flip can't strand the FSM.
 */
class LookPadView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {

    var onLookDelta: ((dx: Int, dy: Int) -> Unit)? = null

    /** Single tap → LMB click (both modes). */
    var onPrimaryTap: (() -> Unit)? = null
    /** UI-mode double tap → RMB click. */
    var onSecondaryTap: (() -> Unit)? = null

    /** LMB DOWN (in-game chain hold; UI "tap + re-press + slide"). */
    var onHoldStart: (() -> Unit)? = null
    /** LMB UP (matches onHoldStart). */
    var onHoldEnd: (() -> Unit)? = null

    /** RMB DOWN (UI "double-tap + re-press + slide"). */
    var onSecondaryHoldStart: (() -> Unit)? = null
    /** RMB UP (matches onSecondaryHoldStart). */
    var onSecondaryHoldEnd: (() -> Unit)? = null

    var mode: ControllerMode = ControllerMode.AntiMistouch
        set(value) {
            if (field != value) {
                field = value
                resetGestureState()
            }
        }

    /**
     * When false, in-game touches collapse to a pure camera-move gesture.
     * No tap-to-LMB, no chained hold. (Setting in the Settings page.)
     */
    var inGameQuickClicks: Boolean = true
        set(value) {
            if (field != value) {
                field = value
                if (mode == ControllerMode.InGame) resetGestureState()
            }
        }

    /**
     * When false, UI-mode touches drive only the cursor. No tap, no
     * double-tap, no slide-while-held. (Setting in the Settings page.)
     */
    var uiQuickClicks: Boolean = true
        set(value) {
            if (field != value) {
                field = value
                if (mode == ControllerMode.UiInteract) resetGestureState()
            }
        }

    /** Whether the tap/hold FSM is active for the current mode. */
    private fun quickClicksEnabledForMode(): Boolean = when (mode) {
        ControllerMode.InGame -> inGameQuickClicks
        ControllerMode.UiInteract -> uiQuickClicks
        else -> false
    }

    private enum class State {
        IDLE,
        PRIMED1,           // first DOWN; tap-or-drag candidate
        DRAG,               // first-press slide → camera/cursor move

        // In-game
        AFTER_TAP,          // first quick tap done; chain window open
        LMB_HELD_INGAME,    // chain DOWN happened, LMB held

        // UI mode
        SINGLE_PENDING,     // first quick tap up; LMB click queued (200ms)
        SECOND_PRIMED,      // second DOWN within window; will become RMB or LMB-hold
        LMB_HELD_UI,        // second press slid → LMB held
        DOUBLE_PENDING,     // RMB click fired; waiting for hold-chain
        THIRD_PRIMED,       // third DOWN within window
        RMB_HELD,           // third press slid → RMB held
    }

    private var state = State.IDLE
    private var primedX = 0f
    private var primedY = 0f

    private var pointerId = MotionEvent.INVALID_POINTER_ID
    private var lastX = 0f
    private var lastY = 0f

    val isDragging: Boolean
        get() = pointerId != MotionEvent.INVALID_POINTER_ID

    private var residualX = 0f
    private var residualY = 0f

    /**
     * Did the finger move >touchSlop from the press anchor during the
     * current hold? Tracked separately from `state` because we need to
     * decide on UP whether to chain (no slide) or terminate (slid).
     */
    private var slidDuringHold = false

    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop.toFloat()
    private val handler = Handler(Looper.getMainLooper())

    private val singleTapDelayRunnable = Runnable {
        if (state == State.SINGLE_PENDING) {
            onPrimaryTap?.invoke()
            state = State.IDLE
        }
    }

    private val afterTapTimeoutRunnable = Runnable {
        if (state == State.AFTER_TAP) state = State.IDLE
    }

    private val doublePendingTimeoutRunnable = Runnable {
        if (state == State.DOUBLE_PENDING) state = State.IDLE
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                if (pointerId == MotionEvent.INVALID_POINTER_ID) {
                    pointerId = e.getPointerId(e.actionIndex)
                    lastX = e.getX(e.actionIndex)
                    lastY = e.getY(e.actionIndex)
                    residualX = 0f
                    residualY = 0f
                    handleDown(lastX, lastY)
                }
            }
            MotionEvent.ACTION_MOVE -> {
                val idx = e.findPointerIndex(pointerId)
                if (idx < 0) return true
                for (h in 0 until e.historySize) {
                    handleMove(e.getHistoricalX(idx, h), e.getHistoricalY(idx, h))
                }
                handleMove(e.getX(idx), e.getY(idx))
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_CANCEL -> {
                if (e.getPointerId(e.actionIndex) == pointerId) {
                    pointerId = MotionEvent.INVALID_POINTER_ID
                    handleUp()
                }
            }
        }
        return true
    }

    private fun handleDown(x: Float, y: Float) {
        primedX = x
        primedY = y
        slidDuringHold = false
        // Quick clicks disabled → bypass the tap/hold FSM. PRIMED1 with
        // slop-then-DRAG is the only path forward, so only camera /
        // cursor deltas can fire.
        if (!quickClicksEnabledForMode()) {
            state = State.PRIMED1
            return
        }
        when (state) {
            State.IDLE -> {
                state = State.PRIMED1
            }
            State.AFTER_TAP -> {
                handler.removeCallbacks(afterTapTimeoutRunnable)
                if (mode == ControllerMode.InGame) {
                    state = State.LMB_HELD_INGAME
                    onHoldStart?.invoke()
                } else {
                    state = State.PRIMED1
                }
            }
            State.SINGLE_PENDING -> {
                handler.removeCallbacks(singleTapDelayRunnable)
                state = State.SECOND_PRIMED
            }
            State.DOUBLE_PENDING -> {
                handler.removeCallbacks(doublePendingTimeoutRunnable)
                state = State.THIRD_PRIMED
            }
            else -> {
                state = State.PRIMED1
            }
        }
    }

    private fun handleMove(curX: Float, curY: Float) {
        when (state) {
            State.PRIMED1 -> {
                if (movedPastSlop(curX, curY)) {
                    state = State.DRAG
                    resetDeltaTrackingTo(curX, curY)
                }
            }
            State.SECOND_PRIMED -> {
                if (movedPastSlop(curX, curY)) {
                    // Slide during second press → LMB held + cursor move.
                    state = State.LMB_HELD_UI
                    slidDuringHold = true   // remember it slid
                    resetDeltaTrackingTo(curX, curY)
                    onHoldStart?.invoke()
                }
            }
            State.THIRD_PRIMED -> {
                if (movedPastSlop(curX, curY)) {
                    // Slide during third press → RMB held + cursor move.
                    state = State.RMB_HELD
                    slidDuringHold = true
                    resetDeltaTrackingTo(curX, curY)
                    onSecondaryHoldStart?.invoke()
                }
            }
            State.LMB_HELD_INGAME, State.LMB_HELD_UI, State.RMB_HELD -> {
                emitDelta(curX, curY)
                if (!slidDuringHold && movedPastSlop(curX, curY)) {
                    slidDuringHold = true
                }
            }
            State.DRAG -> {
                emitDelta(curX, curY)
            }
            else -> { /* IDLE / SINGLE_PENDING / AFTER_TAP / DOUBLE_PENDING: no finger down */ }
        }
    }

    private fun handleUp() {
        when (state) {
            State.PRIMED1 -> {
                if (!quickClicksEnabledForMode()) {
                    // Quick clicks off → no tap event, return to IDLE.
                    state = State.IDLE
                } else if (mode == ControllerMode.InGame) {
                    onPrimaryTap?.invoke()
                    state = State.AFTER_TAP
                    handler.postDelayed(afterTapTimeoutRunnable, IN_GAME_CHAIN_WINDOW_MS)
                } else if (mode == ControllerMode.UiInteract) {
                    // Defer LMB click — could still become double-tap or
                    // "tap + re-press" gesture.
                    state = State.SINGLE_PENDING
                    handler.postDelayed(singleTapDelayRunnable, UI_DOUBLE_TAP_WINDOW_MS)
                } else {
                    state = State.IDLE
                }
            }
            State.LMB_HELD_INGAME -> {
                onHoldEnd?.invoke()
                if (slidDuringHold) {
                    // Slide-and-hold completed deliberately — end gesture.
                    // The next press is a fresh first tap (camera-only on slide).
                    state = State.IDLE
                } else {
                    // No slide → looked like a "double-click" pattern; chain
                    // back to AFTER_TAP so spam clicking keeps firing.
                    state = State.AFTER_TAP
                    handler.postDelayed(afterTapTimeoutRunnable, IN_GAME_CHAIN_WINDOW_MS)
                }
            }
            State.SECOND_PRIMED -> {
                // Quick second UP, no slide → double tap = RMB click.
                onSecondaryTap?.invoke()
                state = State.DOUBLE_PENDING
                handler.postDelayed(doublePendingTimeoutRunnable, UI_DOUBLE_TAP_WINDOW_MS)
            }
            State.LMB_HELD_UI -> {
                onHoldEnd?.invoke()
                state = State.IDLE
            }
            State.THIRD_PRIMED -> {
                // Quick third UP without slide — unspecified by user. End.
                state = State.IDLE
            }
            State.RMB_HELD -> {
                onSecondaryHoldEnd?.invoke()
                state = State.IDLE
            }
            State.DRAG -> state = State.IDLE
            else -> state = State.IDLE
        }
    }

    private fun emitDelta(curX: Float, curY: Float) {
        val rawDx = (curX - lastX) * SUBPIXEL_SCALE
        val rawDy = (curY - lastY) * SUBPIXEL_SCALE
        lastX = curX
        lastY = curY

        if (state != State.DRAG &&
            state != State.LMB_HELD_INGAME &&
            state != State.LMB_HELD_UI &&
            state != State.RMB_HELD
        ) {
            residualX = 0f
            residualY = 0f
            return
        }

        val totalX = rawDx + residualX
        val totalY = rawDy + residualY
        val ix = totalX.toInt()
        val iy = totalY.toInt()
        residualX = totalX - ix
        residualY = totalY - iy

        if (ix != 0 || iy != 0) {
            onLookDelta?.invoke(ix, iy)
        }
    }

    private fun movedPastSlop(curX: Float, curY: Float): Boolean {
        val dx = curX - primedX
        val dy = curY - primedY
        return dx * dx + dy * dy > touchSlop * touchSlop
    }

    private fun resetDeltaTrackingTo(curX: Float, curY: Float) {
        lastX = curX
        lastY = curY
        residualX = 0f
        residualY = 0f
    }

    private fun resetGestureState() {
        handler.removeCallbacks(singleTapDelayRunnable)
        handler.removeCallbacks(afterTapTimeoutRunnable)
        handler.removeCallbacks(doublePendingTimeoutRunnable)
        // If we're in any held state, fire the corresponding UP so PC
        // doesn't end up stuck with a held mouse button.
        when (state) {
            State.LMB_HELD_INGAME, State.LMB_HELD_UI -> onHoldEnd?.invoke()
            State.RMB_HELD -> onSecondaryHoldEnd?.invoke()
            else -> {}
        }
        state = State.IDLE
    }

    companion object {
        const val SUBPIXEL_SCALE = 10f
        private const val IN_GAME_CHAIN_WINDOW_MS = 280L
        private const val UI_DOUBLE_TAP_WINDOW_MS = 200L
    }
}
