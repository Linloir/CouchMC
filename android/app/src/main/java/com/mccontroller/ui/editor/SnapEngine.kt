package com.mccontroller.ui.editor

import android.graphics.RectF
import com.mccontroller.ui.view.EditorCanvas
import kotlin.math.abs

/**
 * Computes the position-snapped variant of a "proposed" widget rectangle
 * and the corresponding guide lines to draw.
 *
 * Two snap strategies, each independently toggleable:
 *
 *   * **Edge snap** — when one of the moving rect's six axes (left, right,
 *     centerX, top, bottom, centerY) comes within [thresholdPx] of the
 *     same axis on another widget, snap to align exactly. Drawn as a
 *     single long dashed line through all aligned widgets.
 *
 *   * **Spacing snap** — find every pair (a, b) of other widgets whose
 *     near-edge gap on the active axis equals the proposed gap between
 *     the moving widget and a third widget (within [thresholdPx]). When
 *     a match is found, snap the moving widget so the two gaps are
 *     exactly equal. Drawn as two short dashed segments — one spanning
 *     each matched gap — so the user sees "these distances are
 *     identical".
 *
 * Operates entirely in this view's local pixel space; the activity is
 * responsible for converting the snapped rect back into widget-spec
 * margins.
 *
 * Axis-locked: when the user nudges horizontally, only x-axis snaps
 * are considered; same for vertical. Cross-axis alignments don't make
 * sense during a single-axis drag.
 */
object SnapEngine {

    /**
     * Result of a snap pass.
     *
     * @property snappedDx delta along the active axis to add to the
     *           proposed rect to land on a snap point. Zero if nothing
     *           snapped.
     * @property guides guide lines to draw. Empty if nothing snapped.
     */
    data class Result(val snappedDx: Float, val guides: List<EditorCanvas.Guide>)

    /**
     * Run the snap pass.
     *
     * @param moving the rect of the widget being nudged, already shifted
     *               by the user's gesture but BEFORE snapping.
     * @param others rects of every other widget in the canvas (in the
     *               same pixel space as [moving]).
     * @param axis   which axis the user is nudging on.
     * @param edgeSnap toggle edge-snap.
     * @param spacingSnap toggle spacing-snap.
     * @param thresholdPx the pull-in distance for both kinds of snap.
     */
    fun compute(
        moving: RectF,
        others: List<RectF>,
        axis: EditorCanvas.NudgeAxis,
        edgeSnap: Boolean,
        spacingSnap: Boolean,
        thresholdPx: Float,
    ): Result {
        if (!edgeSnap && !spacingSnap) return Result(0f, emptyList())
        if (others.isEmpty()) return Result(0f, emptyList())

        val edge = if (edgeSnap) edgeSnap(moving, others, axis, thresholdPx) else null
        val spacing = if (spacingSnap) spacingSnap(moving, others, axis, thresholdPx) else null

        // Prefer whichever has a smaller required delta — edge tends to
        // win in practice but spacing's a stronger UX cue when both apply.
        val winner = when {
            edge != null && spacing != null ->
                if (abs(spacing.snappedDx) <= abs(edge.snappedDx)) spacing else edge
            edge != null -> edge
            spacing != null -> spacing
            else -> null
        } ?: return Result(0f, emptyList())
        return winner
    }

    // ===== Edge snap =====

    /**
     * For each of the moving rect's six axes, find the closest matching
     * axis on any other widget. If within threshold, snap. The guide
     * line spans all widgets whose chosen axis matches the snapped value.
     */
    private fun edgeSnap(
        moving: RectF,
        others: List<RectF>,
        axis: EditorCanvas.NudgeAxis,
        threshold: Float,
    ): Result? {
        // Active-axis edges only — left/right/centerX for horizontal
        // nudges; top/bottom/centerY for vertical. Cross-axis snaps
        // would create surprising "drift" perpendicular to user intent.
        val movingEdges: List<Pair<EdgeKind, Float>> = when (axis) {
            EditorCanvas.NudgeAxis.Horizontal -> listOf(
                EdgeKind.Left to moving.left,
                EdgeKind.Right to moving.right,
                EdgeKind.CenterX to moving.centerX(),
            )
            EditorCanvas.NudgeAxis.Vertical -> listOf(
                EdgeKind.Top to moving.top,
                EdgeKind.Bottom to moving.bottom,
                EdgeKind.CenterY to moving.centerY(),
            )
        }

        var best: Snapshot? = null
        for ((kind, movingValue) in movingEdges) {
            for (other in others) {
                // Compare against the same KIND of edge AND the symmetric
                // kinds. e.g. moving.left can align to other.left OR
                // other.right (same vertical line). Same for top/bottom.
                val candidates = when (kind) {
                    EdgeKind.Left -> listOf(EdgeKind.Left to other.left, EdgeKind.Right to other.right)
                    EdgeKind.Right -> listOf(EdgeKind.Left to other.left, EdgeKind.Right to other.right)
                    EdgeKind.CenterX -> listOf(EdgeKind.CenterX to other.centerX())
                    EdgeKind.Top -> listOf(EdgeKind.Top to other.top, EdgeKind.Bottom to other.bottom)
                    EdgeKind.Bottom -> listOf(EdgeKind.Top to other.top, EdgeKind.Bottom to other.bottom)
                    EdgeKind.CenterY -> listOf(EdgeKind.CenterY to other.centerY())
                }
                for ((_, otherValue) in candidates) {
                    val dist = movingValue - otherValue
                    if (abs(dist) <= threshold) {
                        if (best == null || abs(dist) < abs(best.delta)) {
                            best = Snapshot(kind, otherValue, dist)
                        }
                    }
                }
            }
        }

        val snap = best ?: return null
        val snappedDx = -snap.delta  // move moving rect by -delta to align

        // Build guides for ALL other widgets that share this axis line
        // exactly (so a 3-widget alignment gets the line going through
        // all three).
        val aligned = mutableListOf<RectF>()
        for (other in others) {
            val touches = when (snap.kind) {
                EdgeKind.Left, EdgeKind.Right ->
                    abs(other.left - snap.snappedValue) < 0.5f ||
                    abs(other.right - snap.snappedValue) < 0.5f
                EdgeKind.CenterX ->
                    abs(other.centerX() - snap.snappedValue) < 0.5f
                EdgeKind.Top, EdgeKind.Bottom ->
                    abs(other.top - snap.snappedValue) < 0.5f ||
                    abs(other.bottom - snap.snappedValue) < 0.5f
                EdgeKind.CenterY ->
                    abs(other.centerY() - snap.snappedValue) < 0.5f
            }
            if (touches) aligned.add(other)
        }

        val snappedMoving = RectF(moving).apply { offset(if (snap.kind.isVerticalLine()) snappedDx else 0f,
            if (!snap.kind.isVerticalLine()) snappedDx else 0f) }
        val rectsForGuide = aligned + snappedMoving

        val guide = if (snap.kind.isVerticalLine()) {
            EditorCanvas.Guide(
                orientation = EditorCanvas.GuideOrientation.Vertical,
                mainCoord = snap.snappedValue,
                span = rectsForGuide.fold(Float.POSITIVE_INFINITY to Float.NEGATIVE_INFINITY) { acc, r ->
                    minOf(acc.first, r.top) to maxOf(acc.second, r.bottom)
                },
            )
        } else {
            EditorCanvas.Guide(
                orientation = EditorCanvas.GuideOrientation.Horizontal,
                mainCoord = snap.snappedValue,
                span = rectsForGuide.fold(Float.POSITIVE_INFINITY to Float.NEGATIVE_INFINITY) { acc, r ->
                    minOf(acc.first, r.left) to maxOf(acc.second, r.right)
                },
            )
        }

        return Result(snappedDx, listOf(guide))
    }

    // ===== Spacing snap =====

    /**
     * Look for "M is between two existing widgets with equal gaps" or
     * "M-X gap matches Y-Z gap". When found, snap so the moving widget's
     * key gap exactly matches the reference gap.
     *
     * Only considers the active axis: vertical nudges compare vertical
     * (y) gaps, horizontal nudges compare horizontal (x) gaps.
     */
    private fun spacingSnap(
        moving: RectF,
        others: List<RectF>,
        axis: EditorCanvas.NudgeAxis,
        threshold: Float,
    ): Result? {
        // Project everyone onto the active axis as (lowEdge, highEdge).
        val isVertical = axis == EditorCanvas.NudgeAxis.Vertical
        val (mLow, mHigh) = if (isVertical) moving.top to moving.bottom
                            else moving.left to moving.right
        val othersProj = others.map {
            if (isVertical) it.top to it.bottom else it.left to it.right
        }

        // Existing pair gaps (signed, but we only care about magnitude
        // for the reference). gap = next.low - prev.high when widgets
        // don't overlap. We consider each unordered pair once.
        val pairGaps = mutableListOf<PairGap>()
        for (i in othersProj.indices) for (j in (i + 1) until othersProj.size) {
            val (la, ha) = othersProj[i]
            val (lb, hb) = othersProj[j]
            // Distance between the two rectangles on this axis (0 = touching/overlapping)
            val gap = if (la >= hb) la - hb else if (lb >= ha) lb - ha else 0f
            if (gap > 0f) pairGaps.add(PairGap(i, j, gap))
        }
        if (pairGaps.isEmpty()) return null

        // For each other widget X, compute the gap M-X on the active
        // axis. If |M-X gap - some reference pair's gap| <= threshold,
        // candidate snap exists: shift M so its M-X gap == reference gap.
        var best: SpacingCandidate? = null
        for ((idx, proj) in othersProj.withIndex()) {
            val (xLow, xHigh) = proj
            // Two cases: M is below X (mLow > xHigh) → gap = mLow - xHigh;
            // M is above X (mHigh < xLow) → gap = xLow - mHigh.
            val (gap, side) = when {
                mLow >= xHigh -> (mLow - xHigh) to SpacingSide.After
                mHigh <= xLow -> (xLow - mHigh) to SpacingSide.Before
                else -> continue   // overlapping, no clean gap
            }
            for (pair in pairGaps) {
                if (pair.a == idx || pair.b == idx) continue  // would be a degenerate match
                val diff = gap - pair.gap
                if (abs(diff) <= threshold) {
                    val deltaSign = if (side == SpacingSide.After) -1f else 1f
                    val snappedDx = deltaSign * diff
                    if (best == null || abs(snappedDx) < abs(best.delta)) {
                        best = SpacingCandidate(
                            anchorIdx = idx,
                            referencePair = pair,
                            side = side,
                            delta = snappedDx,
                        )
                    }
                }
            }
        }

        val s = best ?: return null

        // Build two short dashed segments at the same x (horizontal nudge
        // → segments are vertical; vertical nudge → horizontal) showing
        // the two equal gaps. Draw them at the midline of the bounding
        // box of the four rects involved.
        val anchor = others[s.anchorIdx]
        val pairA = others[s.referencePair.a]
        val pairB = others[s.referencePair.b]
        val movingSnapped = RectF(moving).apply {
            if (isVertical) offset(0f, s.delta) else offset(s.delta, 0f)
        }
        val all = listOf(anchor, pairA, pairB, movingSnapped)

        val guides = if (isVertical) {
            // Two vertical-gap markers — draw HORIZONTAL dashed segments
            // at the midpoint between the two gap pairs, spanning the
            // x-overlap of each pair.
            val gap1 = gapSegmentVertical(movingSnapped, anchor)
            val gap2 = gapSegmentVertical(pairA, pairB)
            val midX = all.map { it.centerX() }.average().toFloat()
            buildList {
                if (gap1 != null) add(EditorCanvas.Guide(
                    EditorCanvas.GuideOrientation.Vertical,
                    midX,
                    gap1,
                ))
                if (gap2 != null) add(EditorCanvas.Guide(
                    EditorCanvas.GuideOrientation.Vertical,
                    midX,
                    gap2,
                ))
            }
        } else {
            val gap1 = gapSegmentHorizontal(movingSnapped, anchor)
            val gap2 = gapSegmentHorizontal(pairA, pairB)
            val midY = all.map { it.centerY() }.average().toFloat()
            buildList {
                if (gap1 != null) add(EditorCanvas.Guide(
                    EditorCanvas.GuideOrientation.Horizontal,
                    midY,
                    gap1,
                ))
                if (gap2 != null) add(EditorCanvas.Guide(
                    EditorCanvas.GuideOrientation.Horizontal,
                    midY,
                    gap2,
                ))
            }
        }

        return Result(s.delta, guides)
    }

    private fun gapSegmentVertical(a: RectF, b: RectF): Pair<Float, Float>? {
        val (low, high) = when {
            a.bottom <= b.top -> a.bottom to b.top
            b.bottom <= a.top -> b.bottom to a.top
            else -> return null
        }
        return low to high
    }

    private fun gapSegmentHorizontal(a: RectF, b: RectF): Pair<Float, Float>? {
        val (low, high) = when {
            a.right <= b.left -> a.right to b.left
            b.right <= a.left -> b.right to a.left
            else -> return null
        }
        return low to high
    }

    // ===== internals =====

    private enum class EdgeKind { Left, Right, CenterX, Top, Bottom, CenterY }

    private fun EdgeKind.isVerticalLine() = this == EdgeKind.Left ||
        this == EdgeKind.Right || this == EdgeKind.CenterX

    private data class Snapshot(val kind: EdgeKind, val snappedValue: Float, val delta: Float)

    private enum class SpacingSide { Before, After }

    private data class PairGap(val a: Int, val b: Int, val gap: Float)

    private data class SpacingCandidate(
        val anchorIdx: Int,
        val referencePair: PairGap,
        val side: SpacingSide,
        val delta: Float,
    )
}
