package com.mccontroller.ui.view

import android.content.Context
import android.graphics.BlurMaskFilter
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import android.view.animation.AccelerateInterpolator
import android.view.animation.DecelerateInterpolator
import kotlin.math.sqrt

/**
 * Dynamic (floating) virtual joystick, inspired by PUBG Mobile / Honor of Kings.
 *
 * Behavior:
 * - The view is the "activation zone". Tap anywhere inside it; the base
 *   appears at the touch point (clamped so the full base remains visible).
 * - The knob tracks the active pointer, clamped to `baseRadius` from base.
 * - On release, the knob snaps to base and the whole stack fades out.
 *
 * Visual stack (drawn order):
 * - Soft outer glow (BlurMaskFilter)
 * - Translucent dark backdrop (subtle "glass")
 * - Thin white ring
 * - Knob with drop shadow (lit-from-above), inner highlight (specular),
 *   and a hairline dark edge for definition.
 *
 * Output: normalized `[-1, 1]`, **Y flipped** (UP = positive = forward in MC).
 * Throttled to ≤60Hz; bypasses throttle on release to ensure (0, 0) is sent.
 */
class JoystickView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {

    var onPositionChanged: ((x: Float, y: Float) -> Unit)? = null

    /**
     * Fires when the user pushes the stick past the rim (engage) or returns
     * back inside the inner threshold (disengage). Independent of the
     * Sprint toggle button — caller OR-combines the two.
     */
    var onSprintExtensionChanged: ((engaged: Boolean) -> Unit)? = null

    private val density = resources.displayMetrics.density
    private fun dp(v: Float) = v * density

    private val knobRadius = dp(24f)
    private val baseRadius = dp(72f)

    private val baseGlowPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(40, 255, 255, 255)         // ~16% white
        style = Paint.Style.STROKE
        strokeWidth = dp(4f)
        maskFilter = BlurMaskFilter(dp(2.5f), BlurMaskFilter.Blur.NORMAL)
    }
    private val baseFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(28, 0, 0, 0)               // ~11% black "glass"
        style = Paint.Style.FILL
    }
    private val baseStrokePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(125, 255, 255, 255)        // ~49% white ring
        style = Paint.Style.STROKE
        strokeWidth = dp(1.5f)
    }
    private val knobFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(235, 255, 255, 255)        // 92% white solid
        style = Paint.Style.FILL
        // Drop shadow: 4dp blur, 1.5dp downward offset, ~31% black.
        setShadowLayer(dp(4f), 0f, dp(1.5f), Color.argb(80, 0, 0, 0))
    }
    private val knobHighlightPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(80, 255, 255, 255)         // soft white highlight
        style = Paint.Style.FILL
        maskFilter = BlurMaskFilter(dp(3f), BlurMaskFilter.Blur.NORMAL)
    }
    private val knobEdgePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(45, 0, 0, 0)               // hairline dark edge
        style = Paint.Style.STROKE
        strokeWidth = dp(0.7f)
    }

    private var baseX = 0f
    private var baseY = 0f
    private var knobX = 0f
    private var knobY = 0f
    private var pointerId = MotionEvent.INVALID_POINTER_ID

    private var lastSentX = 0f
    private var lastSentY = 0f
    private var lastSentTime = 0L

    private var sprintEngaged = false

    init {
        // Shadow + BlurMaskFilter need software rendering on most API levels.
        setLayerType(LAYER_TYPE_SOFTWARE, null)
        alpha = 0f  // hidden until first touch
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                if (pointerId == MotionEvent.INVALID_POINTER_ID) {
                    pointerId = e.getPointerId(e.actionIndex)
                    val tx = e.getX(e.actionIndex)
                    val ty = e.getY(e.actionIndex)
                    setBasePosition(tx, ty)
                    knobX = baseX
                    knobY = baseY
                    invalidate()
                    fadeIn()
                }
            }
            MotionEvent.ACTION_MOVE -> {
                val idx = e.findPointerIndex(pointerId)
                if (idx >= 0) updateKnob(e.getX(idx), e.getY(idx))
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_CANCEL -> {
                if (e.getPointerId(e.actionIndex) == pointerId) {
                    pointerId = MotionEvent.INVALID_POINTER_ID
                    knobX = baseX  // snap knob to base before fade-out
                    knobY = baseY
                    invalidate()
                    onPositionChanged?.invoke(0f, 0f)
                    lastSentX = 0f
                    lastSentY = 0f
                    lastSentTime = System.currentTimeMillis()
                    if (sprintEngaged) {
                        sprintEngaged = false
                        onSprintExtensionChanged?.invoke(false)
                    }
                    fadeOut()
                }
            }
        }
        return true
    }

    /**
     * Clamp `(tx, ty)` so the knob at maximum excursion (base + baseRadius +
     * knobRadius) plus the glow halo stays inside view bounds — no clipping.
     */
    private fun setBasePosition(tx: Float, ty: Float) {
        val safeMargin = baseRadius + knobRadius + dp(4f)
        baseX = tx.coerceIn(safeMargin, width - safeMargin)
        baseY = ty.coerceIn(safeMargin, height - safeMargin)
    }

    private fun updateKnob(touchX: Float, touchY: Float) {
        val dx = touchX - baseX
        val dy = touchY - baseY
        val dist = sqrt(dx * dx + dy * dy)

        if (dist > baseRadius) {
            knobX = baseX + dx / dist * baseRadius
            knobY = baseY + dy / dist * baseRadius
        } else {
            knobX = touchX
            knobY = touchY
        }
        invalidate()

        // Sprint-on-extend: hysteresis between two thresholds so it doesn't
        // chatter when the finger sits near the rim.
        val engageDist = baseRadius * SPRINT_ENGAGE_FACTOR
        val disengageDist = baseRadius * SPRINT_DISENGAGE_FACTOR
        val newEngaged = if (sprintEngaged) dist > disengageDist else dist > engageDist
        if (newEngaged != sprintEngaged) {
            sprintEngaged = newEngaged
            onSprintExtensionChanged?.invoke(newEngaged)
        }

        val normX = (knobX - baseX) / baseRadius
        val normY = -(knobY - baseY) / baseRadius   // flip: UP = positive
        emitIfChanged(normX, normY)
    }

    private fun emitIfChanged(x: Float, y: Float) {
        val now = System.currentTimeMillis()
        val dx = x - lastSentX
        val dy = y - lastSentY
        val change = sqrt(dx * dx + dy * dy)

        if (change > THRESHOLD_DELTA || (now - lastSentTime) > MAX_INTERVAL_MS) {
            onPositionChanged?.invoke(x, y)
            lastSentX = x
            lastSentY = y
            lastSentTime = now
        }
    }

    private fun fadeIn() {
        animate().cancel()
        animate()
            .alpha(1f)
            .setDuration(FADE_IN_MS)
            .setInterpolator(DecelerateInterpolator())
            .start()
    }

    private fun fadeOut() {
        animate().cancel()
        animate()
            .alpha(0f)
            .setDuration(FADE_OUT_MS)
            .setInterpolator(AccelerateInterpolator())
            .start()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        if (alpha == 0f) return  // skip work when fully hidden

        // Base layer
        canvas.drawCircle(baseX, baseY, baseRadius, baseGlowPaint)
        canvas.drawCircle(baseX, baseY, baseRadius, baseFillPaint)
        canvas.drawCircle(baseX, baseY, baseRadius, baseStrokePaint)

        // Knob layer
        canvas.drawCircle(knobX, knobY, knobRadius, knobFillPaint)
        // Specular highlight: small soft circle at upper-left of knob.
        canvas.drawCircle(
            knobX - knobRadius * 0.32f,
            knobY - knobRadius * 0.42f,
            knobRadius * 0.45f,
            knobHighlightPaint,
        )
        canvas.drawCircle(knobX, knobY, knobRadius, knobEdgePaint)
    }

    companion object {
        private const val THRESHOLD_DELTA = 0.05f
        private const val MAX_INTERVAL_MS = 16L
        private const val FADE_IN_MS = 120L
        private const val FADE_OUT_MS = 180L
        // Symmetric sprint trigger: same radius for engage and disengage
        // (per user request). Push past 1.2x the rim engages, pull back
        // inside 1.2x disengages. No hysteresis band.
        private const val SPRINT_ENGAGE_FACTOR = 1.2f
        private const val SPRINT_DISENGAGE_FACTOR = 1.2f
    }
}
