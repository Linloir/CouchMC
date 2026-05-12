import UIKit

/// Dynamic floating joystick.
///
/// At rest the view is fully transparent (alpha = 0). On touch DOWN we set
/// the base position to the finger (clamped so knob + base stay onscreen),
/// fade in over 120ms, and draw a soft radial halo + the knob disc. Off-
/// centre deflection adds a rim "sweep" arc oriented toward the knob.
///
/// Sprint engagement triggers when the finger travels >120 % of the base
/// radius — i.e. past the visible rim. Hysteresis (engage 1.2, disengage
/// 1.0) prevents jitter.
///
/// In edit mode the view stays drawable but doesn't process touches; the
/// editor canvas treats it as a passive bounds.
final class JoystickTouchView: UIView, EditableWidgetView {

    // MARK: - Callbacks
    var onPositionChanged: ((Float, Float) -> Void)?
    var onSprintExtensionChanged: ((Bool) -> Void)?

    // MARK: - EditableWidgetView
    let widgetID: String = "joystick"
    /// Matches Android: the joystick is rendered in the editor but has no
    /// visible indicator (it's invisible at rest) and isn't interactive — its
    /// activation zone is fixed in v3 and not editable. The editor skips
    /// attaching gesture recognisers to this view.
    var isEditing: Bool = false {
        didSet { setNeedsDisplay() }
    }
    var isSelectedInEditor: Bool = false { didSet { setNeedsDisplay() } }

    // MARK: - Tunables
    private let knobRadius: CGFloat = 22
    private let baseRadius: CGFloat = 70
    private let fadeInMs: CGFloat = 120
    private let fadeOutMs: CGFloat = 180

    /// Joystick-extension sprint config — driven externally by
    /// `ControllerHostingController` from `SettingsStore`. Defaults
    /// match `AppSettings.sprintEngageFactor` so the in-game widget
    /// seeded from code (before the settings push reaches it) lines
    /// up with the persisted default.
    var sprintFromJoystickEnabled: Bool = true
    var sprintEngageFactor: CGFloat = 1.5
    /// Disengage hysteresis is fixed below engage (avoids jitter at the
    /// boundary). 1.00 means "back inside the rim".
    private let sprintDisengageFactor: CGFloat = 1.00

    private let emitThreshold: Float = 0.02
    private let maxIntervalSec: TimeInterval = 0.05

    // MARK: - State
    private var activeTouch: UITouch?
    private var basePoint: CGPoint = .zero
    private var knobOffset: CGSize = .zero
    private var sprintEngaged: Bool = false
    private var alphaProgress: CGFloat = 0  // 0..1; 0 = transparent
    private var alphaAnimator: CADisplayLink?
    private var alphaAnimStart: CFTimeInterval = 0
    private var alphaAnimFrom: CGFloat = 0
    private var alphaAnimTo: CGFloat = 0
    private var alphaAnimDurationMs: CGFloat = 120

    private var lastSentX: Float = 0
    private var lastSentY: Float = 0
    private var lastSentAt: TimeInterval = 0

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame); commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder); commonInit()
    }
    private func commonInit() {
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = false
        isExclusiveTouch = false
    }

    // MARK: - Drawing

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        // The joystick is invisible at rest in both live and edit mode
        // (matches Android — the editor doesn't draw the activation zone).
        guard alphaProgress > 0.005 else { return }

        // Use the last touch's base position even during the post-release
        // fade-out. The knob itself snaps back to that base centre on release
        // (`knobOffset = .zero` in `finishTouch`), but the base must stay put
        // — falling back to `bounds.midX/midY` made the whole joystick teleport
        // to the view centre before fading, which looks like the joystick ran
        // away from the finger. `alphaProgress > 0` already guards against
        // drawing before there's been any touch.
        let center = basePoint
        let knobCenter = CGPoint(x: center.x + knobOffset.width, y: center.y + knobOffset.height)
        let a = alphaProgress

        // Halo — RadialGradient stops 0:rgba(255,255,255,140/255), 0.45: 55/255, 1: 0
        let haloRadius = knobRadius * 2.6
        let colors = [
            UIColor(white: 1, alpha: (140 / 255) * a).cgColor,
            UIColor(white: 1, alpha: (55  / 255) * a).cgColor,
            UIColor(white: 1, alpha: 0).cgColor,
        ] as CFArray
        let locations: [CGFloat] = [0, 0.45, 1]
        if let cs = CGColorSpace(name: CGColorSpace.sRGB),
           let grad = CGGradient(colorsSpace: cs, colors: colors, locations: locations) {
            ctx.saveGState()
            ctx.drawRadialGradient(
                grad,
                startCenter: knobCenter, startRadius: 0,
                endCenter: knobCenter, endRadius: haloRadius,
                options: []
            )
            ctx.restoreGState()
        }

        // Rim sweep — only when knob is meaningfully off-center.
        let distance = hypot(knobOffset.width, knobOffset.height)
        let intensity = min(distance / baseRadius, 1)
        if intensity > 0.02 {
            let angle = atan2(knobOffset.height, knobOffset.width)
            drawRimSweep(ctx: ctx, center: center, angle: angle, intensity: intensity * a)
        }

        // Knob disc
        ctx.setFillColor(UIColor(white: 1, alpha: (245 / 255) * a).cgColor)
        ctx.addArc(center: knobCenter, radius: knobRadius, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        ctx.fillPath()
    }

    private func drawRimSweep(ctx: CGContext, center: CGPoint, angle: CGFloat, intensity: CGFloat) {
        // Approximate a sweep gradient with densely-packed overlapping arcs.
        // The previous 18-step implementation with round caps + butted
        // boundaries showed a visible "dashed" pattern because adjacent
        // strokes had perceptibly different alpha values and their rounded
        // ends made the seams blob up. The fix:
        //   - 64 steps (~3.5× density) so per-segment alpha deltas are
        //     below the perceptible threshold;
        //   - butt caps so segment ends are flush rather than rounded blobs;
        //   - 1.8× overlap so each segment slightly extends into its
        //     neighbour, smoothing out any residual seam;
        //   - cos² falloff (instead of sin) so the alpha curve is gentler
        //     at the tails and there's no abrupt edge between "lit" and
        //     "dark" sides.
        let steps = 64
        let halfSpread: CGFloat = .pi * 0.22         // ~40° either side
        let peakAlpha = min(intensity * 235 / 255, 1)
        let segmentArc = 2 * halfSpread / CGFloat(steps)
        let overlap: CGFloat = 1.8
        ctx.setLineCap(.butt)
        ctx.setLineWidth(2.5)
        for i in 0..<steps {
            let t = (CGFloat(i) + 0.5) / CGFloat(steps)   // segment centre 0..1
            let phase = (t - 0.5) * .pi
            let bell = cos(phase) * cos(phase)             // smooth cos² bell
            let a = peakAlpha * bell
            if a < 0.005 { continue }
            let mid = angle - halfSpread + 2 * halfSpread * t
            let half = segmentArc * overlap / 2
            ctx.setStrokeColor(UIColor(white: 1, alpha: a).cgColor)
            ctx.addArc(center: center, radius: baseRadius,
                       startAngle: mid - half, endAngle: mid + half, clockwise: false)
            ctx.strokePath()
        }
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isEditing, activeTouch == nil, let t = touches.first else { return }
        activeTouch = t

        var pt = t.location(in: self)
        // Clamp the base so knob + rim stays onscreen.
        let pad = baseRadius + 6
        pt.x = min(max(pt.x, pad), bounds.width - pad)
        pt.y = min(max(pt.y, pad), bounds.height - pad)
        basePoint = pt
        knobOffset = .zero
        sprintEngaged = false

        animateAlpha(to: 1, durationMs: fadeInMs)
        setNeedsDisplay()
        emit(0, 0, force: true)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isEditing, let t = activeTouch, touches.contains(t) else { return }
        let samples = event?.coalescedTouches(for: t) ?? [t]
        guard let last = samples.last else { return }
        let p = last.location(in: self)

        let rawDx = p.x - basePoint.x
        let rawDy = p.y - basePoint.y
        let rawDist = hypot(rawDx, rawDy)
        let scale = rawDist > baseRadius ? baseRadius / rawDist : 1
        knobOffset = CGSize(width: rawDx * scale, height: rawDy * scale)

        // Sprint hysteresis based on RAW finger distance vs base radius.
        // Skipped entirely when the user has disabled joystick-triggered
        // sprint in Settings (only the manual button counts then).
        if sprintFromJoystickEnabled {
            let factor = rawDist / baseRadius
            if !sprintEngaged && factor >= sprintEngageFactor {
                sprintEngaged = true
                onSprintExtensionChanged?(true)
            } else if sprintEngaged && factor <= sprintDisengageFactor {
                sprintEngaged = false
                onSprintExtensionChanged?(false)
            }
        } else if sprintEngaged {
            // Toggle was just turned off mid-press — release.
            sprintEngaged = false
            onSprintExtensionChanged?(false)
        }

        let nx = Float(knobOffset.width / baseRadius)
        let ny = Float(-knobOffset.height / baseRadius)  // flip Y: forward = positive
        emit(nx, ny, force: false)
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isEditing, let t = activeTouch, touches.contains(t) else { return }
        finishTouch()
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isEditing, let t = activeTouch, touches.contains(t) else { return }
        finishTouch()
    }
    private func finishTouch() {
        activeTouch = nil
        knobOffset = .zero
        if sprintEngaged {
            sprintEngaged = false
            onSprintExtensionChanged?(false)
        }
        animateAlpha(to: 0, durationMs: fadeOutMs)
        emit(0, 0, force: true)
        setNeedsDisplay()
    }

    // MARK: - Emit throttle

    private func emit(_ x: Float, _ y: Float, force: Bool) {
        let now = CACurrentMediaTime()
        let dx = abs(x - lastSentX)
        let dy = abs(y - lastSentY)
        let elapsed = now - lastSentAt
        if force || dx >= emitThreshold || dy >= emitThreshold || elapsed >= maxIntervalSec {
            lastSentX = x
            lastSentY = y
            lastSentAt = now
            onPositionChanged?(x, y)
        }
    }

    // MARK: - Alpha animation

    private func animateAlpha(to target: CGFloat, durationMs: CGFloat) {
        alphaAnimator?.invalidate()
        alphaAnimFrom = alphaProgress
        alphaAnimTo = target
        alphaAnimStart = CACurrentMediaTime()
        alphaAnimDurationMs = durationMs
        let link = CADisplayLink(target: self, selector: #selector(stepAlpha))
        link.add(to: .main, forMode: .common)
        alphaAnimator = link
    }

    @objc private func stepAlpha() {
        let elapsed = (CACurrentMediaTime() - alphaAnimStart) * 1000
        var t = min(elapsed / alphaAnimDurationMs, 1)
        // DecelerateInterpolator (fade-in) vs AccelerateInterpolator (fade-out)
        if alphaAnimTo > alphaAnimFrom {
            t = 1 - (1 - t) * (1 - t)          // ease-out (decelerate)
        } else {
            t = t * t                           // ease-in (accelerate)
        }
        alphaProgress = alphaAnimFrom + (alphaAnimTo - alphaAnimFrom) * t
        setNeedsDisplay()
        if elapsed >= alphaAnimDurationMs {
            alphaProgress = alphaAnimTo
            alphaAnimator?.invalidate()
            alphaAnimator = nil
            setNeedsDisplay()
        }
    }
}
