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
 * Touch surface for camera control. Reads finger movement deltas (with
 * historical sampling so fast swipes don't lose precision) and forwards
 * them to a callback. Also drives custom tap / double-tap gestures with
 * mode-aware semantics.
 *
 * **In-game mode** (low-latency, optimized for spam clicking + combat):
 * - Down → quick UP (no slide): primary tap fires *immediately* on UP.
 *   No double-tap waiting penalty.
 * - Down → slide before UP (fresh sequence): camera move only, no click.
 * - Within ~280ms of the previous tap → second DOWN enters "held" mode:
 *   LMB held from DOWN to UP. Camera deltas during the hold still fire.
 *   Whether the held tap is quick or long doesn't matter — LMB cycles
 *   DOWN+UP either way. Releasing chains back into the after-tap window
 *   so a third tap can start another held block.
 *
 * **UI mode** (cursor + buttons):
 * - Down → quick UP: pending primary tap, fires after a short delay
 *   (~200ms — shorter than Android's default 300ms).
 * - Within ~200ms, second DOWN: pending primary cancelled; UP fires
 *   secondary tap (RMB click) instead.
 * - Slide on either tap cancels the click and switches to camera move.
 *
 * Multi-touch policy: only tracks the first pointer.
 */
class LookPadView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {

    var onLookDelta: ((dx: Int, dy: Int) -> Unit)? = null

    /** Called on a quick first tap (no slide). LMB click in both modes. */
    var onPrimaryTap: (() -> Unit)? = null
    /** UI-mode quick double-tap. RMB click. */
    var onSecondaryTap: (() -> Unit)? = null
    /** In-game double-tap entering held mode — LMB pressed and held. */
    var onHoldStart: (() -> Unit)? = null
    /** In-game held-mode finger lift — LMB released. */
    var onHoldEnd: (() -> Unit)? = null

    /**
     * Mode is set externally; gesture FSM resets on change so a mid-gesture
     * mode flip can't leave state inconsistent.
     */
    var mode: ControllerMode = ControllerMode.AntiMistouch
        set(value) {
            if (field != value) {
                field = value
                resetGestureState()
            }
        }

    private enum class State {
        IDLE,
        PRIMED1,        // first finger down, may become tap or drag
        DRAG,            // first-tap movement → camera move only
        AFTER_TAP,       // in-game: first tap fired, chain window open
        LMB_HELD,        // in-game: chained tap currently down, LMB held
        SINGLE_DELAY,    // ui-mode: first tap up, waiting briefly for double
        DOUBLE_PRIMED,   // ui-mode: second tap candidate
    }

    private var state = State.IDLE
    private var primedX = 0f
    private var primedY = 0f

    private var pointerId = MotionEvent.INVALID_POINTER_ID
    private var lastX = 0f
    private var lastY = 0f

    val isDragging: Boolean
        get() = pointerId != MotionEvent.INVALID_POINTER_ID

    // Sub-pixel residual for slow micro-aim.
    private var residualX = 0f
    private var residualY = 0f

    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop.toFloat()
    private val handler = Handler(Looper.getMainLooper())

    private val singleTapDelayRunnable = Runnable {
        if (state == State.SINGLE_DELAY) {
            onPrimaryTap?.invoke()
            state = State.IDLE
        }
    }

    private val afterTapTimeoutRunnable = Runnable {
        if (state == State.AFTER_TAP) state = State.IDLE
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
        when (state) {
            State.IDLE -> {
                state = State.PRIMED1
            }
            State.AFTER_TAP -> {
                handler.removeCallbacks(afterTapTimeoutRunnable)
                if (mode == ControllerMode.InGame) {
                    state = State.LMB_HELD
                    onHoldStart?.invoke()
                } else {
                    state = State.PRIMED1
                }
            }
            State.SINGLE_DELAY -> {
                handler.removeCallbacks(singleTapDelayRunnable)
                state = State.DOUBLE_PRIMED
            }
            else -> {
                // Defensive: stray DOWN; reset.
                state = State.PRIMED1
            }
        }
    }

    private fun handleMove(curX: Float, curY: Float) {
        when (state) {
            State.PRIMED1, State.DOUBLE_PRIMED -> {
                val dx = curX - primedX
                val dy = curY - primedY
                if (dx * dx + dy * dy > touchSlop * touchSlop) {
                    // Movement past slop → it's a drag, not a tap.
                    state = State.DRAG
                    lastX = curX
                    lastY = curY
                    residualX = 0f
                    residualY = 0f
                }
            }
            State.DRAG, State.LMB_HELD -> {
                emitDelta(curX, curY)
            }
            else -> { /* AFTER_TAP / SINGLE_DELAY: no finger down; ignore */ }
        }
    }

    private fun handleUp() {
        when (state) {
            State.PRIMED1 -> {
                if (mode == ControllerMode.InGame) {
                    onPrimaryTap?.invoke()
                    state = State.AFTER_TAP
                    handler.postDelayed(afterTapTimeoutRunnable, IN_GAME_CHAIN_WINDOW_MS)
                } else if (mode == ControllerMode.UiInteract) {
                    // Defer LMB until we know if a second tap follows.
                    state = State.SINGLE_DELAY
                    handler.postDelayed(singleTapDelayRunnable, UI_DOUBLE_TAP_WINDOW_MS)
                } else {
                    state = State.IDLE
                }
            }
            State.LMB_HELD -> {
                onHoldEnd?.invoke()
                state = State.AFTER_TAP
                handler.postDelayed(afterTapTimeoutRunnable, IN_GAME_CHAIN_WINDOW_MS)
            }
            State.DOUBLE_PRIMED -> {
                onSecondaryTap?.invoke()
                state = State.IDLE
            }
            State.DRAG -> {
                state = State.IDLE
            }
            else -> {
                state = State.IDLE
            }
        }
    }

    private fun emitDelta(curX: Float, curY: Float) {
        val rawDx = (curX - lastX) * SUBPIXEL_SCALE
        val rawDy = (curY - lastY) * SUBPIXEL_SCALE
        lastX = curX
        lastY = curY

        if (state != State.DRAG && state != State.LMB_HELD) {
            // Not in a "fire camera deltas" state; just keep position fresh.
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

    private fun resetGestureState() {
        handler.removeCallbacks(singleTapDelayRunnable)
        handler.removeCallbacks(afterTapTimeoutRunnable)
        if (state == State.LMB_HELD) {
            onHoldEnd?.invoke()
        }
        state = State.IDLE
    }

    companion object {
        const val SUBPIXEL_SCALE = 10f

        // In-game: window after a tap during which a second DOWN starts
        // LMB-held mode. Tuned shorter than Android's default 300ms so the
        // chain doesn't feel laggy.
        private const val IN_GAME_CHAIN_WINDOW_MS = 280L

        // UI mode: how long we wait after a quick tap to see if a double
        // tap follows. Shorter than the system default so the cursor click
        // feels responsive.
        private const val UI_DOUBLE_TAP_WINDOW_MS = 200L
    }
}
