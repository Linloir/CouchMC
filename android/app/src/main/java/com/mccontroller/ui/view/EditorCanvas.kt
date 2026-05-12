package com.mccontroller.ui.view

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.ViewConfiguration
import android.widget.FrameLayout
import kotlin.math.abs

/**
 * Editor canvas that intercepts multi-touch so pinch-resize works
 * regardless of where the user's fingers land — single-finger touches
 * still pass through to children for tap-to-select / drag-to-move.
 *
 * Three single-finger empty-area gestures are reported back via [Callback]:
 *
 *   - **Tap** (DOWN → UP, no movement): [Callback.onTapEmpty] — deselect
 *   - **Drag** (DOWN → MOVE past slop → UP): [Callback.onNudgeStart] /
 *     [Callback.onNudgeDelta] / [Callback.onNudgeEnd] — fine-grained
 *     position adjust of the currently-selected widget. The dominant axis
 *     (horizontal vs. vertical) is locked at first slop-crossing and the
 *     emitted delta is *scaled down* via [NUDGE_DIVISOR] so the user
 *     gets a 1 px nudge for every several pixels of finger travel.
 *
 * Snap-alignment guide lines (set by the activity via [setGuides]) are
 * drawn on top of children in [dispatchDraw].
 */
class EditorCanvas @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : FrameLayout(context, attrs) {

    enum class NudgeAxis { Horizontal, Vertical }

    /** Direction of a snap guide. Decides what we paint. */
    enum class GuideOrientation { Vertical, Horizontal }

    /**
     * A single dashed alignment guide line. Coordinates are in this view's
     * local pixel space.
     *
     * - For [GuideOrientation.Vertical] the line is drawn at x=[mainCoord]
     *   from y=[span.first] to y=[span.second].
     * - For [GuideOrientation.Horizontal] the line is at y=[mainCoord]
     *   between x=[span.first] and x=[span.second].
     */
    data class Guide(
        val orientation: GuideOrientation,
        val mainCoord: Float,
        val span: Pair<Float, Float>,
    )

    interface Callback {
        fun onPinch(scaleFactor: Float)
        fun onTapEmpty()

        /** Selection drag begins (first slop crossing on an empty-area touch). */
        fun onNudgeStart()
        /** Delta-since-start in the locked axis. */
        fun onNudgeDelta(axis: NudgeAxis, deltaPx: Float)
        /** Drag ends (UP / CANCEL). */
        fun onNudgeEnd()
    }

    var callback: Callback? = null

    private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
    private var inPinch = false

    private val scaleDetector = ScaleGestureDetector(
        context,
        object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
            override fun onScaleBegin(d: ScaleGestureDetector): Boolean {
                inPinch = true
                if (nudgeAxis != null) {
                    callback?.onNudgeEnd()
                    nudgeAxis = null
                }
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

    // Single-finger tracking
    private var downX = 0f
    private var downY = 0f
    private var lastEmittedTotalX = 0f
    private var lastEmittedTotalY = 0f
    private var movedDuringTap = false
    private var nudgeAxis: NudgeAxis? = null

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
                lastEmittedTotalX = 0f
                lastEmittedTotalY = 0f
                movedDuringTap = false
                nudgeAxis = null
            }
            MotionEvent.ACTION_MOVE -> {
                if (inPinch) return true
                val dx = ev.x - downX
                val dy = ev.y - downY
                if (nudgeAxis == null) {
                    if (dx * dx + dy * dy <= touchSlop * touchSlop) return true
                    movedDuringTap = true
                    nudgeAxis = if (abs(dx) >= abs(dy)) NudgeAxis.Horizontal else NudgeAxis.Vertical
                    callback?.onNudgeStart()
                }
                val axis = nudgeAxis ?: return true
                // Emit the FULL delta from down (not deltas-since-last-move),
                // so the activity can do its own snap math against a stable
                // anchor each step. Skip if it didn't change for this axis.
                when (axis) {
                    NudgeAxis.Horizontal -> if (dx != lastEmittedTotalX) {
                        lastEmittedTotalX = dx
                        callback?.onNudgeDelta(axis, dx)
                    }
                    NudgeAxis.Vertical -> if (dy != lastEmittedTotalY) {
                        lastEmittedTotalY = dy
                        callback?.onNudgeDelta(axis, dy)
                    }
                }
            }
            MotionEvent.ACTION_UP -> {
                if (nudgeAxis != null) {
                    callback?.onNudgeEnd()
                    nudgeAxis = null
                } else if (!inPinch && !movedDuringTap) {
                    callback?.onTapEmpty()
                }
            }
            MotionEvent.ACTION_CANCEL -> {
                if (nudgeAxis != null) {
                    callback?.onNudgeEnd()
                    nudgeAxis = null
                }
            }
        }
        return true
    }

    // ===== Snap guide drawing =====

    private var guides: List<Guide> = emptyList()

    private val guidePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(180, 200, 200, 200)
        strokeWidth = resources.displayMetrics.density * 1.2f
        style = Paint.Style.STROKE
        pathEffect = DashPathEffect(
            floatArrayOf(
                resources.displayMetrics.density * 6f,
                resources.displayMetrics.density * 4f,
            ),
            0f,
        )
    }

    /** Replace the guide overlay. Pass an empty list to clear. */
    fun setGuides(g: List<Guide>) {
        // Quick equality short-circuit avoids invalidate() spam during
        // a hot nudge — only redraw when the set actually changes.
        if (g === guides) return
        if (g.size == guides.size && g.zip(guides).all { (a, b) -> a == b }) return
        guides = g
        invalidate()
    }

    override fun dispatchDraw(canvas: Canvas) {
        super.dispatchDraw(canvas)
        if (guides.isEmpty()) return
        for (g in guides) {
            when (g.orientation) {
                GuideOrientation.Vertical -> canvas.drawLine(
                    g.mainCoord, g.span.first, g.mainCoord, g.span.second, guidePaint,
                )
                GuideOrientation.Horizontal -> canvas.drawLine(
                    g.span.first, g.mainCoord, g.span.second, g.mainCoord, guidePaint,
                )
            }
        }
    }

    companion object {
        /**
         * Finger-travel : widget-movement ratio for empty-area nudge. The
         * user wants "滑动距离远大于按钮移动速度" — a slow / fine adjust.
         * 8 px of swipe → 1 px of widget move.
         */
        const val NUDGE_DIVISOR = 8f
    }
}
