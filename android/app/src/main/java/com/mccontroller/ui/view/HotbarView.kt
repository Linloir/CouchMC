package com.mccontroller.ui.view

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Handler
import android.os.Looper
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View

/**
 * Nine-slot hotbar mimicking PC Minecraft's bottom inventory strip.
 *
 * - **Tap a slot** → fires [onSelect] with the slot index (0..8).
 * - **Long-press (≥ 400ms)** → fires [onSelect] then [onDrop] periodically
 *   every 200ms while the finger remains down.
 *
 * The slot select edge is what tells the PC server to press the
 * corresponding 1..9 key; the periodic drop sends Q. Together this
 * mimics the mobile MC "long-press to drop the held item" gesture.
 */
class HotbarView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {

    var onSelect: ((slot: Int) -> Unit)? = null
    var onDrop: ((slot: Int) -> Unit)? = null

    private val density = resources.displayMetrics.density
    private fun dp(v: Float) = v * density

    private val slotCount = 9

    private var selectedSlot = -1
    private var pressedSlot = -1
    private var pointerId = MotionEvent.INVALID_POINTER_ID

    /**
     * Sticky flag: once the finger has crossed to a different slot during
     * this gesture, drop is disabled for the remainder of the gesture.
     * Reset to false on each fresh ACTION_DOWN.
     */
    private var hasSwiped = false

    private val handler = Handler(Looper.getMainLooper())
    private var dropPending: Runnable? = null

    private val backdropPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(80, 0, 0, 0)
        style = Paint.Style.FILL
    }
    private val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(110, 255, 255, 255)
        style = Paint.Style.STROKE
        strokeWidth = dp(1f)
    }
    private val selectedRingPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(235, 255, 255, 255)
        style = Paint.Style.STROKE
        strokeWidth = dp(2f)
    }
    private val pressedFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(60, 255, 255, 255)
        style = Paint.Style.FILL
    }
    private val droppingFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(90, 255, 100, 100)        // red tint when in drop mode
        style = Paint.Style.FILL
    }
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(220, 255, 255, 255)
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }

    private var isDropping = false

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val slotH = h.toFloat()
        labelPaint.textSize = slotH * 0.45f
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                if (pointerId == MotionEvent.INVALID_POINTER_ID) {
                    val slot = slotAt(e.getX(e.actionIndex))
                    if (slot >= 0) {
                        pointerId = e.getPointerId(e.actionIndex)
                        pressedSlot = slot
                        selectedSlot = slot
                        hasSwiped = false  // fresh gesture
                        onSelect?.invoke(slot)
                        scheduleLongPress()
                        invalidate()
                    }
                }
            }
            MotionEvent.ACTION_MOVE -> {
                // If the finger crosses to another slot we treat it as a swipe.
                // First swipe disables drop for this gesture (sticky); any
                // pending or in-progress drop is also cancelled here.
                val idx = e.findPointerIndex(pointerId)
                if (idx >= 0) {
                    val slot = slotAt(e.getX(idx))
                    if (slot >= 0 && slot != pressedSlot) {
                        hasSwiped = true
                        cancelDropTimer()
                        pressedSlot = slot
                        selectedSlot = slot
                        onSelect?.invoke(slot)
                        invalidate()
                        // Intentionally do NOT reschedule long-press: the
                        // user is swiping, not pressing-and-holding.
                    }
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_CANCEL -> {
                if (e.getPointerId(e.actionIndex) == pointerId) {
                    pointerId = MotionEvent.INVALID_POINTER_ID
                    pressedSlot = -1
                    hasSwiped = false
                    isDropping = false
                    cancelDropTimer()
                    invalidate()
                }
            }
        }
        return true
    }

    private fun slotAt(x: Float): Int {
        if (width == 0) return -1
        val slotW = width.toFloat() / slotCount
        val s = (x / slotW).toInt()
        // Clamp out-of-bounds touches to the nearest extreme slot. This way
        // a fast swipe that overshoots past slot 0 or slot 8 still ends on
        // the intended extreme rather than getting stuck on the last slot
        // the finger crossed while still inside the hotbar.
        return s.coerceIn(0, slotCount - 1)
    }

    private fun scheduleLongPress() {
        cancelDropTimer()
        val r = object : Runnable {
            override fun run() {
                if (pressedSlot < 0) return
                if (!isDropping) {
                    isDropping = true
                    invalidate()
                }
                onDrop?.invoke(pressedSlot)
                handler.postDelayed(this, DROP_PERIOD_MS)
            }
        }
        dropPending = r
        handler.postDelayed(r, LONG_PRESS_MS)
    }

    private fun cancelDropTimer() {
        dropPending?.let { handler.removeCallbacks(it) }
        dropPending = null
        if (isDropping) {
            isDropping = false
            invalidate()
        }
    }

    override fun onDetachedFromWindow() {
        cancelDropTimer()
        super.onDetachedFromWindow()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (width == 0 || height == 0) return

        val slotW = width.toFloat() / slotCount
        val pad = dp(2f)
        val corner = dp(6f)

        for (i in 0 until slotCount) {
            val left = i * slotW + pad
            val right = (i + 1) * slotW - pad
            val rect = RectF(left, pad, right, height - pad)

            canvas.drawRoundRect(rect, corner, corner, backdropPaint)

            if (i == pressedSlot && isDropping) {
                canvas.drawRoundRect(rect, corner, corner, droppingFillPaint)
            } else if (i == pressedSlot) {
                canvas.drawRoundRect(rect, corner, corner, pressedFillPaint)
            }

            val ring = if (i == selectedSlot) selectedRingPaint else ringPaint
            canvas.drawRoundRect(rect, corner, corner, ring)

            val centerX = (left + right) / 2f
            val baseline = height / 2f - (labelPaint.ascent() + labelPaint.descent()) / 2
            canvas.drawText((i + 1).toString(), centerX, baseline, labelPaint)
        }
    }

    /** External hint: pretend slot N is selected (e.g., on connect). */
    fun setSelectedSlot(slot: Int) {
        selectedSlot = slot.coerceIn(0, slotCount - 1)
        invalidate()
    }

    companion object {
        private const val LONG_PRESS_MS = 400L
        private const val DROP_PERIOD_MS = 200L
    }
}
