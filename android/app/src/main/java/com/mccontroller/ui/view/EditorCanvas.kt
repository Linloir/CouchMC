package com.mccontroller.ui.view

import android.content.Context
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.ViewConfiguration
import android.widget.FrameLayout

/**
 * Editor canvas that intercepts multi-touch so pinch-resize works
 * regardless of where the user's fingers land — single-finger touches
 * still pass through to children for tap-to-select / drag-to-move.
 *
 * The canvas also detects "tap on empty area" (single-pointer DOWN→UP
 * with no child consuming and no significant movement) and reports it
 * via [Callback.onTapEmpty], used by the editor to deselect.
 */
class EditorCanvas @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : FrameLayout(context, attrs) {

    interface Callback {
        fun onPinch(scaleFactor: Float)
        fun onTapEmpty()
    }

    var callback: Callback? = null

    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private var inPinch = false

    private val scaleDetector = ScaleGestureDetector(
        context,
        object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScaleBegin(d: ScaleGestureDetector): Boolean {
                inPinch = true
                return true
            }

            override fun onScale(d: ScaleGestureDetector): Boolean {
                callback?.onPinch(d.scaleFactor)
                return true
            }

            override fun onScaleEnd(d: ScaleGestureDetector) {
                inPinch = false
            }
        },
    )

    private var downX = 0f
    private var downY = 0f
    private var movedDuringTap = false

    override fun onInterceptTouchEvent(ev: MotionEvent): Boolean {
        // Once a 2nd pointer lands, the canvas claims the gesture so the
        // child receiving the 1st pointer gets ACTION_CANCEL and we run
        // ScaleGestureDetector cleanly.
        if (ev.actionMasked == MotionEvent.ACTION_POINTER_DOWN && ev.pointerCount >= 2) {
            return true
        }
        return super.onInterceptTouchEvent(ev)
    }

    override fun onTouchEvent(ev: MotionEvent): Boolean {
        scaleDetector.onTouchEvent(ev)
        when (ev.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                downX = ev.x
                downY = ev.y
                movedDuringTap = false
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = ev.x - downX
                val dy = ev.y - downY
                if (dx * dx + dy * dy > touchSlop * touchSlop) movedDuringTap = true
            }
            MotionEvent.ACTION_UP -> {
                if (!inPinch && !movedDuringTap) callback?.onTapEmpty()
            }
        }
        return true
    }
}
