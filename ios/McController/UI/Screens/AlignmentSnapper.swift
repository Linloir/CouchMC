import CoreGraphics

/// Pure function that computes "snap to nearby edges + equal-spacing" results
/// for a dragged widget given the frames of the other widgets on the canvas.
/// Used by the layout editor's pan handlers to provide PowerPoint-style
/// alignment guidance.
///
/// The solver works in canvas coordinates and is completely UI-free — the
/// caller (LayoutEditorViewController) is responsible for converting the
/// returned `snapDelta` into the widget's `WidgetSpec` adjustments and
/// rendering the `guides` via `AlignmentGuideOverlay`.
enum AlignmentSnapper {

    /// Which axis the snapper is allowed to nudge along. `.both` is used for
    /// free widget drag; `.horizontal` / `.vertical` are used when the
    /// editor's canvas-pan handler has axis-locked the precision drag.
    enum Axis: Equatable {
        case horizontal
        case vertical
        case both
    }

    /// A single overlay element to render. All coordinates are in the
    /// canvas's coordinate space.
    enum Guide: Equatable {
        /// Full-line dashed alignment indicator across a vertical line at
        /// `x`, spanning `yMin...yMax` (so the line just covers the widgets
        /// it relates).
        case verticalLine(x: CGFloat, yMin: CGFloat, yMax: CGFloat)
        case horizontalLine(y: CGFloat, xMin: CGFloat, xMax: CGFloat)
        /// Equal-spacing indicator on the horizontal axis: two thin arrows
        /// at `y`, segment 1 from `aStartX` to `aEndX`, segment 2 from
        /// `bStartX` to `bEndX`. Used for "this gap equals that gap".
        case spacingHorizontal(y: CGFloat, aStartX: CGFloat, aEndX: CGFloat, bStartX: CGFloat, bEndX: CGFloat)
        case spacingVertical(x: CGFloat, aStartY: CGFloat, aEndY: CGFloat, bStartY: CGFloat, bEndY: CGFloat)
    }

    struct Result: Equatable {
        let snapDelta: CGSize
        let guides: [Guide]
    }

    /// Compute snap.
    ///
    /// - Parameters:
    ///   - candidate: frame the dragged widget would have without snapping.
    ///   - others: frames of every other widget the user can snap against.
    ///   - axis: which dimensions the snap is allowed to touch.
    ///   - edgeEnabled: turn edge-to-edge / centre-to-centre snap on / off.
    ///   - spacingEnabled: turn equal-spacing snap on / off.
    ///   - tolerance: maximum delta (pt) for a snap to engage.
    /// - Returns: how much to nudge the candidate, plus a list of guides
    ///   to render while the snap is active.
    static func snap(
        candidate: CGRect,
        others: [CGRect],
        axis: Axis,
        edgeEnabled: Bool,
        spacingEnabled: Bool,
        tolerance: CGFloat = 6
    ) -> Result {
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        var guides: [Guide] = []

        // === EDGE SNAP ===========================================
        if edgeEnabled {
            if axis != .vertical {
                if let h = horizontalEdgeSnap(candidate: candidate, others: others, tolerance: tolerance) {
                    dx = h.delta
                    let shifted = candidate.offsetBy(dx: h.delta, dy: 0)
                    let yMin = min(shifted.minY, h.matched.map { $0.minY }.min() ?? shifted.minY)
                    let yMax = max(shifted.maxY, h.matched.map { $0.maxY }.max() ?? shifted.maxY)
                    guides.append(.verticalLine(x: h.lineX, yMin: yMin, yMax: yMax))
                }
            }
            if axis != .horizontal {
                if let v = verticalEdgeSnap(candidate: candidate, others: others, tolerance: tolerance) {
                    dy = v.delta
                    let shifted = candidate.offsetBy(dx: dx, dy: v.delta)
                    let xMin = min(shifted.minX, v.matched.map { $0.minX }.min() ?? shifted.minX)
                    let xMax = max(shifted.maxX, v.matched.map { $0.maxX }.max() ?? shifted.maxX)
                    guides.append(.horizontalLine(y: v.lineY, xMin: xMin, xMax: xMax))
                }
            }
        }

        // === SPACING SNAP ========================================
        if spacingEnabled {
            // Compute the *currently-displaced* candidate so edge-snap has
            // had a chance to claim its delta first; spacing snap only adds
            // on top in dimensions edge-snap left untouched.
            let post = candidate.offsetBy(dx: dx, dy: dy)
            if axis != .vertical && dx == 0 {
                if let s = horizontalSpacingSnap(candidate: post, others: others, tolerance: tolerance) {
                    dx += s.delta
                    guides.append(s.guide)
                }
            }
            if axis != .horizontal && dy == 0 {
                if let s = verticalSpacingSnap(candidate: post, others: others, tolerance: tolerance) {
                    dy += s.delta
                    guides.append(s.guide)
                }
            }
        }

        return Result(snapDelta: CGSize(width: dx, height: dy), guides: guides)
    }

    // MARK: - Edge snap (X)

    private struct EdgeSnapResult {
        let delta: CGFloat
        let lineX: CGFloat
        let matched: [CGRect]
    }

    private static func horizontalEdgeSnap(
        candidate: CGRect,
        others: [CGRect],
        tolerance: CGFloat
    ) -> EdgeSnapResult? {
        let selX: [CGFloat] = [candidate.minX, candidate.midX, candidate.maxX]
        // Track the best (smallest absolute) delta found and which target value it snaps to.
        var bestDelta: CGFloat?
        var bestTarget: CGFloat?
        for sel in selX {
            for o in others {
                for target in [o.minX, o.midX, o.maxX] {
                    let delta = target - sel
                    if abs(delta) <= tolerance {
                        if bestDelta == nil || abs(delta) < abs(bestDelta!) {
                            bestDelta = delta
                            bestTarget = target
                        }
                    }
                }
            }
        }
        guard let delta = bestDelta, let target = bestTarget else { return nil }
        // Find every other-widget whose vertical edge sits at `target` so
        // the dashed guide line spans all of them.
        let matched = others.filter { o in
            abs(o.minX - target) < 0.5 || abs(o.midX - target) < 0.5 || abs(o.maxX - target) < 0.5
        }
        return EdgeSnapResult(delta: delta, lineX: target, matched: matched)
    }

    private static func verticalEdgeSnap(
        candidate: CGRect,
        others: [CGRect],
        tolerance: CGFloat
    ) -> (delta: CGFloat, lineY: CGFloat, matched: [CGRect])? {
        let selY: [CGFloat] = [candidate.minY, candidate.midY, candidate.maxY]
        var bestDelta: CGFloat?
        var bestTarget: CGFloat?
        for sel in selY {
            for o in others {
                for target in [o.minY, o.midY, o.maxY] {
                    let delta = target - sel
                    if abs(delta) <= tolerance {
                        if bestDelta == nil || abs(delta) < abs(bestDelta!) {
                            bestDelta = delta
                            bestTarget = target
                        }
                    }
                }
            }
        }
        guard let delta = bestDelta, let target = bestTarget else { return nil }
        let matched = others.filter { o in
            abs(o.minY - target) < 0.5 || abs(o.midY - target) < 0.5 || abs(o.maxY - target) < 0.5
        }
        return (delta, target, matched)
    }

    // MARK: - Spacing snap
    //
    // "Equal-spacing" snap = when the dragged widget is positioned such that
    // its gap from one other widget equals the gap between two other widgets
    // along the same axis. We only check the two "mirror" cases (S left of a
    // pair, or S right of a pair); the "S sits between" case is rare in
    // practice for game-controller layouts and adds noise.

    private struct SpacingSnap {
        let delta: CGFloat
        let guide: Guide
    }

    private static func horizontalSpacingSnap(
        candidate: CGRect,
        others: [CGRect],
        tolerance: CGFloat
    ) -> SpacingSnap? {
        var best: (delta: CGFloat, guide: Guide)?
        for w1 in others {
            for w2 in others {
                guard w1 != w2 else { continue }
                // Want w1 left of w2 (non-overlapping)
                guard w1.maxX <= w2.minX else { continue }
                let gap = w2.minX - w1.maxX
                guard gap > 0 else { continue }
                let y = (max(w1.minY, w2.minY) + min(w1.maxY, w2.maxY)) / 2

                // Case: candidate is to the right of w2 → snap S so its
                // minX = w2.maxX + gap.
                let targetMinXRight = w2.maxX + gap
                let dRight = targetMinXRight - candidate.minX
                if abs(dRight) < tolerance &&
                   (best == nil || abs(dRight) < abs(best!.delta)) {
                    let snappedX = candidate.minX + dRight
                    let guide = Guide.spacingHorizontal(
                        y: y,
                        aStartX: w1.maxX, aEndX: w2.minX,
                        bStartX: w2.maxX, bEndX: snappedX
                    )
                    best = (dRight, guide)
                }

                // Case: candidate is to the left of w1 → snap so S.maxX = w1.minX - gap.
                let targetMaxXLeft = w1.minX - gap
                let dLeft = targetMaxXLeft - candidate.maxX
                if abs(dLeft) < tolerance &&
                   (best == nil || abs(dLeft) < abs(best!.delta)) {
                    let snappedMaxX = candidate.maxX + dLeft
                    let guide = Guide.spacingHorizontal(
                        y: y,
                        aStartX: snappedMaxX, aEndX: w1.minX,
                        bStartX: w1.maxX, bEndX: w2.minX
                    )
                    best = (dLeft, guide)
                }
            }
        }
        guard let b = best else { return nil }
        return SpacingSnap(delta: b.delta, guide: b.guide)
    }

    private static func verticalSpacingSnap(
        candidate: CGRect,
        others: [CGRect],
        tolerance: CGFloat
    ) -> SpacingSnap? {
        var best: (delta: CGFloat, guide: Guide)?
        for w1 in others {
            for w2 in others {
                guard w1 != w2 else { continue }
                guard w1.maxY <= w2.minY else { continue }
                let gap = w2.minY - w1.maxY
                guard gap > 0 else { continue }
                let x = (max(w1.minX, w2.minX) + min(w1.maxX, w2.maxX)) / 2

                let targetMinYBelow = w2.maxY + gap
                let dBelow = targetMinYBelow - candidate.minY
                if abs(dBelow) < tolerance &&
                   (best == nil || abs(dBelow) < abs(best!.delta)) {
                    let snappedY = candidate.minY + dBelow
                    let guide = Guide.spacingVertical(
                        x: x,
                        aStartY: w1.maxY, aEndY: w2.minY,
                        bStartY: w2.maxY, bEndY: snappedY
                    )
                    best = (dBelow, guide)
                }

                let targetMaxYAbove = w1.minY - gap
                let dAbove = targetMaxYAbove - candidate.maxY
                if abs(dAbove) < tolerance &&
                   (best == nil || abs(dAbove) < abs(best!.delta)) {
                    let snappedMaxY = candidate.maxY + dAbove
                    let guide = Guide.spacingVertical(
                        x: x,
                        aStartY: snappedMaxY, aEndY: w1.minY,
                        bStartY: w1.maxY, bEndY: w2.minY
                    )
                    best = (dAbove, guide)
                }
            }
        }
        guard let b = best else { return nil }
        return SpacingSnap(delta: b.delta, guide: b.guide)
    }
}
