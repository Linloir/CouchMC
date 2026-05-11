package com.mccontroller.ui.view

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RadialGradient
import android.graphics.Shader
import android.graphics.SweepGradient
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import android.view.animation.AccelerateInterpolator
import android.view.animation.DecelerateInterpolator
import kotlin.math.atan2
import kotlin.math.sqrt

/**
 * Dynamic (floating) virtual joystick, inspired by PUBG Mobile / Honor of Kings.
 *
 * Visual (Phase 4 redesign):
 *   - **At rest the only thing visible is the glowing knob.** No
 *     backdrop disc, no fully-drawn outline. RadialGradient creates the
 *     glow without needing BlurMaskFilter (and the software layer it
 *     would force).
 *   - **When the knob leaves the centre the rim "lights up" as an arc**
 *     pointing in the direction the knob is pushing. A SweepGradient is
 *     rotated to align its bright peak with the knob's angle; the arc
 *     fades out toward its two ends. The further the knob is pushed,
 *     the brighter the arc — interpolated linearly with knob distance.
 *
 * Behaviour: same as before — tap anywhere in the activation zone, the
 * base appears under the touch (clamped so the full base stays visible),
 * the knob tracks the finger to `baseRadius`, snaps back on release.
 *
 * Output: normalised `[-1, 1]`, Y flipped (UP = positive = forward in MC).
 */
class JoystickView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {

    var onPositionChanged: ((x: Float, y: Float) -> Unit)? = null

    var onSprintExtensionChanged: ((engaged: Boolean) -> Unit)? = null

    private val density = resources.displayMetrics.density
    private fun dp(v: Float) = v * density

    private val knobRadius = dp(22f)
    private val baseRadius = dp(70f)
    private val haloRadius = knobRadius * 2.6f

    // ---- Paints ----
    // Knob solid body — nearly opaque white. Slight inset from the halo
    // so the halo's bright centre overlaps the knob edge cleanly.
    private val knobPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(245, 255, 255, 255)
        style = Paint.Style.FILL
    }

    // Halo paint — shader is re-created each frame (knob moves, intensity changes).
    private val haloPaint = Paint(Paint.ANTI_ALIAS_FLAG)

    // Rim arc paint — shader is re-created each frame; rotation matrix
    // applied via setLocalMatrix to align the gradient with knob angle.
    private val rimPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        style = Paint.Style.STROKE
        strokeWidth = dp(2.5f)
    }
    private val rimMatrix = Matrix()

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

    private fun setBasePosition(tx: Float, ty: Float) {
        // Keep the rim + knob (not the halo — clipping a transparent
        // gradient is invisible) inside view bounds. Earlier this also
        // accounted for haloRadius, which over-clamped the activation
        // zone enough that touches anywhere outside the centre band
        // produced the same base position — joystick stopped feeling
        // dynamic. Halo extending past the edge is fine.
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
        if (alpha == 0f) return

        val dx = knobX - baseX
        val dy = knobY - baseY
        val dist = sqrt(dx * dx + dy * dy)
        val intensity = if (dist > 0f) (dist / baseRadius).coerceIn(0f, 1f) else 0f

        // ---- Rim arc (only when knob is off-centre) ----
        if (intensity > 0.02f) {
            // Brightest at peak; tapered to transparent at the arc's edges.
            // Stops constrained to ~40% of the sweep so the lit region is a
            // distinct arc, not a soft full-circle wash.
            val brightAlpha = (intensity * 235f).toInt().coerceIn(0, 255)
            val brightColor = Color.argb(brightAlpha, 255, 255, 255)
            val transparent = Color.argb(0, 255, 255, 255)
            val gradient = SweepGradient(
                baseX, baseY,
                intArrayOf(transparent, transparent, brightColor, transparent, transparent),
                floatArrayOf(0f, 0.30f, 0.50f, 0.70f, 1f),
            )
            // SweepGradient starts at angle 0 (positive X, screen-right). To
            // centre the bright zone at the knob angle we rotate so that the
            // gradient's 0.5 mark (= 180° from start in default orientation)
            // lands on the knob's atan2 angle.
            val angleDeg = Math.toDegrees(atan2(dy.toDouble(), dx.toDouble())).toFloat()
            rimMatrix.setRotate(angleDeg - 180f, baseX, baseY)
            gradient.setLocalMatrix(rimMatrix)
            rimPaint.shader = gradient
            canvas.drawCircle(baseX, baseY, baseRadius, rimPaint)
        }

        // ---- Knob glow halo ----
        val haloGradient = RadialGradient(
            knobX, knobY, haloRadius,
            intArrayOf(
                Color.argb(140, 255, 255, 255),    // bright translucent centre
                Color.argb(55, 255, 255, 255),     // mid taper
                Color.argb(0, 255, 255, 255),      // transparent rim
            ),
            floatArrayOf(0f, 0.45f, 1f),
            Shader.TileMode.CLAMP,
        )
        haloPaint.shader = haloGradient
        canvas.drawCircle(knobX, knobY, haloRadius, haloPaint)

        // ---- Knob solid body ----
        canvas.drawCircle(knobX, knobY, knobRadius, knobPaint)
    }

    companion object {
        private const val THRESHOLD_DELTA = 0.05f
        private const val MAX_INTERVAL_MS = 16L
        private const val FADE_IN_MS = 120L
        private const val FADE_OUT_MS = 180L
        // Push past 1.2× the rim engages sprint; pull back inside 1.2×
        // disengages — symmetric, no hysteresis band, per user request.
        private const val SPRINT_ENGAGE_FACTOR = 1.2f
        private const val SPRINT_DISENGAGE_FACTOR = 1.2f
    }
}
