package com.mccontroller.ui.view

import android.content.Context
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View

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

    private var pointerId = MotionEvent.INVALID_POINTER_ID
    private var lastX = 0f
    private var lastY = 0f

    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                if (pointerId == MotionEvent.INVALID_POINTER_ID) {
                    pointerId = e.getPointerId(e.actionIndex)
                    lastX = e.getX(e.actionIndex)
                    lastY = e.getY(e.actionIndex)
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
        val dx = curX - lastX
        val dy = curY - lastY
        lastX = curX
        lastY = curY
        if (dx != 0f || dy != 0f) {
            onLookDelta?.invoke(dx.toInt(), dy.toInt())
        }
    }
}
