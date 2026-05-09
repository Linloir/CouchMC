package com.mccontroller.core

import android.view.Gravity
import android.view.View
import android.widget.FrameLayout

/**
 * Applies a [WidgetSpec] (and global L/R offsets) to a View's
 * `FrameLayout.LayoutParams`. Used by both ControllerActivity (load profile
 * on startup) and LayoutEditorActivity (live-update during edit).
 *
 * All coordinates are in `dp`; the applier converts to px using the View's
 * resources density.
 */
object LayoutApplier {

    fun apply(view: View, spec: WidgetSpec, mode: ModeLayout) {
        val density = view.resources.displayMetrics.density
        val lp = (view.layoutParams as? FrameLayout.LayoutParams)
            ?: FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.WRAP_CONTENT,
                FrameLayout.LayoutParams.WRAP_CONTENT,
            )

        lp.gravity = anchorToGravity(spec.anchor)
        lp.width = if (spec.widthDp > 0) (spec.widthDp * density).toInt()
                   else FrameLayout.LayoutParams.WRAP_CONTENT
        lp.height = if (spec.heightDp > 0) (spec.heightDp * density).toInt()
                    else FrameLayout.LayoutParams.WRAP_CONTENT

        // Horizontal margin: which side depends on anchor + add per-mode offset.
        val edgeOffset = when (spec.anchor) {
            Anchor.BottomStart, Anchor.CenterStart, Anchor.TopStart -> mode.leftOffsetDp
            Anchor.BottomEnd, Anchor.CenterEnd, Anchor.TopEnd -> mode.rightOffsetDp
        }
        val horizPx = ((spec.edgeMarginDp + edgeOffset) * density).toInt().coerceAtLeast(0)
        when (spec.anchor) {
            Anchor.BottomStart, Anchor.CenterStart, Anchor.TopStart -> {
                lp.marginStart = horizPx
                lp.marginEnd = 0
            }
            Anchor.BottomEnd, Anchor.CenterEnd, Anchor.TopEnd -> {
                lp.marginEnd = horizPx
                lp.marginStart = 0
            }
        }

        // Vertical margin: top vs bottom anchors. Center anchors use bottomMargin
        // as a "below center" offset so users can shift the column up/down.
        val vertPx = (spec.verticalMarginDp * density).toInt()
        when (spec.anchor) {
            Anchor.TopStart, Anchor.TopEnd -> {
                lp.topMargin = vertPx
                lp.bottomMargin = 0
            }
            Anchor.BottomStart, Anchor.BottomEnd -> {
                lp.topMargin = 0
                lp.bottomMargin = vertPx
            }
            Anchor.CenterStart, Anchor.CenterEnd -> {
                lp.topMargin = 0
                lp.bottomMargin = vertPx
            }
        }

        view.layoutParams = lp
    }

    fun applyAll(views: Map<String, View>, mode: ModeLayout) {
        for ((id, view) in views) {
            val spec = mode.widgets[id] ?: continue
            apply(view, spec, mode)
        }
    }

    private fun anchorToGravity(anchor: Anchor): Int = when (anchor) {
        Anchor.TopStart -> Gravity.TOP or Gravity.START
        Anchor.TopEnd -> Gravity.TOP or Gravity.END
        Anchor.CenterStart -> Gravity.CENTER_VERTICAL or Gravity.START
        Anchor.CenterEnd -> Gravity.CENTER_VERTICAL or Gravity.END
        Anchor.BottomStart -> Gravity.BOTTOM or Gravity.START
        Anchor.BottomEnd -> Gravity.BOTTOM or Gravity.END
    }
}
