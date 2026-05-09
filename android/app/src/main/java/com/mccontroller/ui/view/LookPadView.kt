package com.mccontroller.ui.view

import android.content.Context
import android.util.AttributeSet
import android.view.GestureDetector
import android.view.MotionEvent
import android.view.View
import com.mccontroller.core.ControllerMode

/**
 * Touch surface for camera control. Reads finger movement deltas (with
 * historical sampling so fast swipes don't lose precision) and forwards
 * them to a callback. The accumulator/sender lives outside this view.
 *
 * Multi-touch behavior: only tracks the first pointer to land in this view.
 * Additional pointers are ignored until the primary lifts.
 */
class LookPadView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {

    var onLookDelta: ((dx: Int, dy: Int) -> Unit)? = null

    /**
     * Controller mode set by ControllerActivity. The gesture handler routes
     * differently per mode:
     * - InGame: single tap = primary tap (LMB click); double-tap-and-hold
     *   fires hold start on second DOWN and hold end on second UP.
     * - UiInteract: single tap = primary; double tap = secondary (RMB click).
     * - AntiMistouch: callbacks not invoked (this view is hidden anyway).
     */
    var mode: ControllerMode = ControllerMode.AntiMistouch

    /** Single-finger quick tap (no slide). LMB click in both gameplay modes. */
    var onPrimaryTap: (() -> Unit)? = null
    /** Quick double-tap. UI mode only — RMB click. */
    var onSecondaryTap: (() -> Unit)? = null
    /** Double-tap-and-hold start (in-game only) — LMB pressed and held. */
    var onHoldStart: (() -> Unit)? = null
    /** Double-tap-and-hold end (in-game only) — LMB released. */
    var onHoldEnd: (() -> Unit)? = null

    private var pointerId = MotionEvent.INVALID_POINTER_ID
    private var lastX = 0f
    private var lastY = 0f

    /**
     * True while the user is actively dragging the lookpad. Used by
     * ControllerActivity to suppress "L/R drag-on-button" camera input
     * when the lookpad already owns camera control via another finger.
     */
    val isDragging: Boolean
        get() = pointerId != MotionEvent.INVALID_POINTER_ID

    // Sub-pixel residual: fractional deltas that didn't quite cross 1px get
    // carried into the next emit. Without this, slow finger drift truncates
    // to zero and fine aiming / cursor micro-movement feels unresponsive.
    private var residualX = 0f
    private var residualY = 0f

    private val gestureDetector: GestureDetector = GestureDetector(
        context,
        object : GestureDetector.SimpleOnGestureListener() {
            override fun onSingleTapConfirmed(e: MotionEvent): Boolean {
                if (mode != ControllerMode.AntiMistouch) onPrimaryTap?.invoke()
                return true
            }

            override fun onDoubleTap(e: MotionEvent): Boolean {
                // UI-mode shortcut: a clean double-tap fires RMB. In-game,
                // we instead use onDoubleTapEvent below to track DOWN/UP of
                // the second tap as the LMB hold window.
                if (mode == ControllerMode.UiInteract) onSecondaryTap?.invoke()
                return true
            }

            override fun onDoubleTapEvent(e: MotionEvent): Boolean {
                if (mode != ControllerMode.InGame) return true
                when (e.actionMasked) {
                    MotionEvent.ACTION_DOWN -> onHoldStart?.invoke()
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> onHoldEnd?.invoke()
                }
                return true
            }
        },
    )

    override fun onTouchEvent(e: MotionEvent): Boolean {
        // Forward to gesture detector first so tap/double-tap can fire
        // alongside our delta tracking. Both can run for the same gesture.
        gestureDetector.onTouchEvent(e)

        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                if (pointerId == MotionEvent.INVALID_POINTER_ID) {
                    pointerId = e.getPointerId(e.actionIndex)
                    lastX = e.getX(e.actionIndex)
                    lastY = e.getY(e.actionIndex)
                    // Reset residual so a stale fraction from a previous
                    // gesture doesn't bleed into this one.
                    residualX = 0f
                    residualY = 0f
                }
            }
            MotionEvent.ACTION_MOVE -> {
                val idx = e.findPointerIndex(pointerId)
                if (idx < 0) return true

                // The touch sampler may have captured several intermediate
                // points since the last frame; replay them so a fast swipe
                // doesn't collapse into one big delta.
                for (h in 0 until e.historySize) {
                    val hx = e.getHistoricalX(idx, h)
                    val hy = e.getHistoricalY(idx, h)
                    emitDelta(hx, hy)
                }
                emitDelta(e.getX(idx), e.getY(idx))
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_CANCEL -> {
                if (e.getPointerId(e.actionIndex) == pointerId) {
                    pointerId = MotionEvent.INVALID_POINTER_ID
                }
            }
        }
        return true
    }

    private fun emitDelta(curX: Float, curY: Float) {
        // Multiply by SUBPIXEL_SCALE so wire deltas are in tenths-of-pixel.
        // Combined with residual carryover, this gives 10x finer micro-aim
        // resolution: a 0.3px finger move produces wire delta 3 (= 0.3 px),
        // which the PC scales by sensitivity *and* divides by 10 to recover
        // the actual pixel value before injecting.
        val rawDx = (curX - lastX) * SUBPIXEL_SCALE
        val rawDy = (curY - lastY) * SUBPIXEL_SCALE
        lastX = curX
        lastY = curY

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

    companion object {
        /** Wire deltas are scaled by this factor; PC divides by it. */
        const val SUBPIXEL_SCALE = 10f
    }
}
