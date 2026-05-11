package com.mccontroller.ui.view

import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffColorFilter
import android.graphics.Typeface
import android.graphics.drawable.Drawable
import android.util.AttributeSet
import android.view.MotionEvent
import android.view.View
import android.view.animation.DecelerateInterpolator
import androidx.core.content.ContextCompat
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
 * Visual (Phase 4 polish):
 *   - Soft translucent backdrop + barely-visible white ring — backdrop
 *     and ring brought close together in apparent opacity so the button
 *     reads as a calm glass disc, not a screaming border.
 *   - Centre icon (vector drawable, white @ ~88% alpha) replaces the
 *     old text labels which the user found too busy. Icons tinted on
 *     draw so the same drawable can be used at any size.
 *   - On press: a quick bright-white flash overlay snaps in (≈0ms),
 *     then fades out over ~380ms after release — like a light bulb
 *     dimming. The toggled-on amber accent remains for sneak/sprint.
 */
class ActionButtonView @JvmOverloads constructor(
    context: Context,
    attrs: AttributeSet? = null,
) : View(context, attrs) {

    enum class Mode { HOLD, TOGGLE, TAP }

    /** Fallback text shown when [icon] is null. Kept for the hotbar / legacy uses. */
    var label: String = ""
        set(value) { field = value; invalidate() }

    /** Vector icon shown in the centre. Overrides [label] when non-null. */
    var icon: Drawable? = null
        set(value) {
            field = value?.mutate()
            invalidate()
        }

    var mode: Mode = Mode.HOLD

    var onStateChanged: ((down: Boolean) -> Unit)? = null

    /**
     * Fires while a HOLD-mode button is held and the finger drifts over it.
     * Delta is in tenths-of-pixel (matches LookPadView's wire scaling so the
     * caller can route directly into the look accumulator).
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

    // ---- Paints ----

    /**
     * Backdrop: a softly-darkened glass disc. Slightly more opaque than
     * the old design so it doesn't wash out over bright MC scenes.
     */
    private val backdropPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(95, 30, 30, 35)
        style = Paint.Style.FILL
    }

    /**
     * Ring: a barely-visible white outline. Toned way down from the old
     * design — only there to soften the edge between the backdrop and
     * whatever's behind the controller.
     */
    private val ringPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(70, 255, 255, 255)
        style = Paint.Style.STROKE
        strokeWidth = dp(1.5f)
    }

    /** Tap flash overlay — instant bright-white that fades out post-release. */
    private val flashPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(255, 255, 255, 255)
        style = Paint.Style.FILL
    }

    /** Toggle-on accent (sneak / sprint engaged) — warm amber overlay. */
    private val toggleFillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(70, 255, 200, 60)
        style = Paint.Style.FILL
    }
    private val toggleRingPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(220, 255, 200, 60)
        style = Paint.Style.STROKE
        strokeWidth = dp(2f)
    }

    /** Plain text label paint, only used when no [icon] is set. */
    private val labelPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.argb(225, 255, 255, 255)
        textAlign = Paint.Align.CENTER
        typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
    }

    // ---- Flash animation ----

    private var flashIntensity = 0f   // 0..1
    private val flashFadeAnimator: ValueAnimator =
        ValueAnimator.ofFloat(1f, 0f).apply {
            duration = FLASH_FADE_MS
            interpolator = DecelerateInterpolator(1.6f)
            addUpdateListener {
                flashIntensity = it.animatedValue as Float
                invalidate()
            }
        }

    init {
        if (attrs != null) {
            val a = context.obtainStyledAttributes(attrs, R.styleable.ActionButtonView)
            label = a.getString(R.styleable.ActionButtonView_label) ?: ""
            mode = Mode.values()[a.getInt(R.styleable.ActionButtonView_buttonMode, 0)]
            val iconResId = a.getResourceId(R.styleable.ActionButtonView_icon, 0)
            if (iconResId != 0) {
                icon = ContextCompat.getDrawable(context, iconResId)
            }
            a.recycle()
        }
        // Tint the icon white at the consumer-facing alpha. PorterDuff SRC_IN
        // replaces the icon's intrinsic fill colour with this — keeps the
        // drawable monochrome regardless of how it was authored.
        icon?.colorFilter = PorterDuffColorFilter(
            Color.argb(225, 255, 255, 255),
            PorterDuff.Mode.SRC_IN,
        )
    }

    override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
        super.onSizeChanged(w, h, oldw, oldh)
        val r = minOf(w, h) / 2f
        labelPaint.textSize = r * 0.55f
    }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                if (pointerId == MotionEvent.INVALID_POINTER_ID) {
                    pointerId = e.getPointerId(e.actionIndex)
                    pressed = true
                    onPressed()
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
                    onReleased()
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

    private fun onPressed() {
        // Instant flash at full intensity. Stays at 1 until the user releases.
        flashFadeAnimator.cancel()
        flashIntensity = 1f
        invalidate()
    }

    private fun onReleased() {
        // Bulb-dimming fade out.
        flashFadeAnimator.cancel()
        flashFadeAnimator.setFloatValues(flashIntensity, 0f)
        flashFadeAnimator.duration = (FLASH_FADE_MS * flashIntensity).toLong()
            .coerceAtLeast(120L)
        flashFadeAnimator.start()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        val cx = width / 2f
        val cy = height / 2f
        val r = minOf(width, height) / 2f - dp(3f)

        // Backdrop
        canvas.drawCircle(cx, cy, r, backdropPaint)

        // Toggle-on accent (sneak/sprint engaged)
        val toggledOn = mode == Mode.TOGGLE && toggleState
        if (toggledOn) canvas.drawCircle(cx, cy, r, toggleFillPaint)

        // Tap flash overlay (clips to disc via drawCircle)
        if (flashIntensity > 0.005f) {
            flashPaint.alpha = (flashIntensity * 170f).toInt().coerceIn(0, 255)
            canvas.drawCircle(cx, cy, r, flashPaint)
        }

        // Ring (toggled = amber, otherwise soft white)
        canvas.drawCircle(cx, cy, r, if (toggledOn) toggleRingPaint else ringPaint)

        // Foreground: icon if present, else fallback label
        val ic = icon
        if (ic != null) {
            val iconExtent = (r * 0.95f).toInt()
            val iconLeft = (cx - iconExtent / 2).toInt()
            val iconTop = (cy - iconExtent / 2).toInt()
            ic.setBounds(iconLeft, iconTop, iconLeft + iconExtent, iconTop + iconExtent)
            ic.draw(canvas)
        } else if (label.isNotEmpty()) {
            val baseline = cy - (labelPaint.ascent() + labelPaint.descent()) / 2
            canvas.drawText(label, cx, baseline, labelPaint)
        }
    }

    companion object {
        // Same factor LookPadView uses; keeps wire deltas consistent across
        // both touch surfaces.
        private const val SUBPIXEL_SCALE = 10f

        /** Maximum length of the press-release fade-out animation. */
        private const val FLASH_FADE_MS = 380L
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
