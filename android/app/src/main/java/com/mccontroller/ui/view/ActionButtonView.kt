package com.mccontroller.ui.view

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import com.mccontroller.R

/**
 * Generic round button with three input modes:
 *
 * - **HOLD**: emits `down=true` on press, `down=false` on release. Used for
 *   keys you want to press-and-hold (LMB, RMB, Jump).
 * - **TOGGLE**: emits a single edge transition per press — flips an
 *   internal latched state and reports it. Used for Sneak / Sprint.
 *   The PC sees the latched state as a long key hold/release.
 * - **TAP**: emits `down=true` on press and `down=false` on release —
 *   visually the same as HOLD but semantically a momentary tap.
 *   Used for Inventory, Swap, Esc.
 *
 * Visual: translucent dark backdrop, thin white ring, white label.
 * Pressed → brighter fill. Toggled-on → gold accent highlight.
 */
class ActionButtonView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {

    enum class Mode { HOLD, TOGGLE, TAP }

    var label: String = ""
        set(value) { field = value; invalidate() }
    var mode: Mode = Mode.HOLD

    var onStateChanged: ((down: Boolean) -> Unit)? = null

    /**
     * Fires while a HOLD-mode button is held and the finger drifts over it.
     * Delta is in tenths-of-pixel (matches LookPadView's wire scaling so the
     * caller can route directly into the look accumulator).
     * Caller is responsible for deciding whether to apply this — typically
     * only when the lookpad isn't already capturing camera with another
     * finger.
     */
    var onDragDelta: ((dx: Int, dy: Int) -> Unit)? = null

    private val density = resources.displayMetrics.density
    private fun dp(v: Float) = v * density

    private var pressed = false
    private var toggleState = false
    private var pointerId = MotionEvent.INVALID_POINTER_ID

    // For drag-while-held (HOLD mode only). Sub-pixel residual matches the
    // LookPadView pipeline so very slow micro-aim is preserved.
    private var dragLastX = 0f
    private var dragLastY = 0f
    private var dragResidualX = 0f
    private var dragResidualY = 0f

    private val backdropPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(60, 0, 0, 0)
        style = Paint.Style.FILL
    }
    private val pressedFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(80, 255, 255, 255)
        style = Paint.Style.FILL
    }
    private val toggleFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(70, 255, 200, 60)        // warm amber for "engaged"
        style = Paint.Style.FILL
    }
    private val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(140, 255, 255, 255)
        style = Paint.Style.STROKE
        strokeWidth = dp(1.5f)
    }
    private val toggleRingPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(220, 255, 200, 60)
        style = Paint.Style.STROKE
        strokeWidth = dp(2f)
    }
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(235, 255, 255, 255)
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }

    init {
        if (attrs != null) {
            val a = context.obtainStyledAttributes(attrs, R.styleable.ActionButtonView)
            label = a.getString(R.styleable.ActionButtonView_label) ?: ""
            mode = Mode.values()[a.getInt(R.styleable.ActionButtonView_buttonMode, 0)]
            a.recycle()
        }
        // Translucent shadow underneath via shadow layer requires software layer.
        setLayerType(LAYER_TYPE_SOFTWARE, null)
        backdropPaint.setShadowLayer(dp(2.5f), 0f, dp(1f), Color.argb(60, 0, 0, 0))
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        // Scale the label with the button so it doesn't look mismatched
        // across small (Esc/Inv) and large (Jump/LMB/RMB) button sizes.
        val r = minOf(w, h) / 2f
        labelPaint.textSize = r * 0.55f
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                if (pointerId == MotionEvent.INVALID_POINTER_ID) {
                    pointerId = e.getPointerId(e.actionIndex)
                    pressed = true
                    invalidate()
                    dragLastX = e.getX(e.actionIndex)
                    dragLastY = e.getY(e.actionIndex)
                    dragResidualX = 0f
                    dragResidualY = 0f
                    when (mode) {
                        Mode.HOLD -> onStateChanged?.invoke(true)
                        Mode.TOGGLE -> {
                            toggleState = !toggleState
                            onStateChanged?.invoke(toggleState)
                        }
                        Mode.TAP -> onStateChanged?.invoke(true)
                    }
                }
            }
            MotionEvent.ACTION_MOVE -> {
                if (mode == Mode.HOLD && pressed) {
                    val idx = e.findPointerIndex(pointerId)
                    if (idx >= 0) {
                        val curX = e.getX(idx)
                        val curY = e.getY(idx)
                        val rawDx = (curX - dragLastX) * SUBPIXEL_SCALE + dragResidualX
                        val rawDy = (curY - dragLastY) * SUBPIXEL_SCALE + dragResidualY
                        val ix = rawDx.toInt()
                        val iy = rawDy.toInt()
                        dragResidualX = rawDx - ix
                        dragResidualY = rawDy - iy
                        dragLastX = curX
                        dragLastY = curY
                        if (ix != 0 || iy != 0) onDragDelta?.invoke(ix, iy)
                    }
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_CANCEL -> {
                if (e.getPointerId(e.actionIndex) == pointerId) {
                    pointerId = MotionEvent.INVALID_POINTER_ID
                    pressed = false
                    invalidate()
                    when (mode) {
                        Mode.HOLD -> onStateChanged?.invoke(false)
                        Mode.TOGGLE -> {} // edge already emitted on DOWN
                        Mode.TAP -> onStateChanged?.invoke(false)
                    }
                }
            }
        }
        return true
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val cx = width / 2f
        val cy = height / 2f
        val r = minOf(width, height) / 2f - dp(3f)

        // Backdrop fill
        canvas.drawCircle(cx, cy, r, backdropPaint)

        // State-dependent fill overlay
        val toggledOn = mode == Mode.TOGGLE && toggleState
        if (toggledOn) canvas.drawCircle(cx, cy, r, toggleFillPaint)
        if (pressed) canvas.drawCircle(cx, cy, r, pressedFillPaint)

        // Ring
        canvas.drawCircle(cx, cy, r, if (toggledOn) toggleRingPaint else ringPaint)

        // Label (vertically centered: y baseline = cy - (ascent+descent)/2)
        val baseline = cy - (labelPaint.ascent() + labelPaint.descent()) / 2
        canvas.drawText(label, cx, baseline, labelPaint)
    }

    companion object {
        // Same factor LookPadView uses; keeps wire deltas consistent across
        // both touch surfaces.
        private const val SUBPIXEL_SCALE = 10f
    }

    /** Programmatically reset toggle state without firing events. */
    fun resetToggle() {
        if (toggleState) {
            toggleState = false
            invalidate()
        }
    }

    /**
     * Override the visual toggle state from outside (no event fired).
     * Used so that the Sprint button can light up when sprint is engaged
     * via the joystick-extension gesture, not just by pressing the button.
     */
    fun setToggleState(state: Boolean) {
        if (toggleState != state) {
            toggleState = state
            invalidate()
        }
    }
}
