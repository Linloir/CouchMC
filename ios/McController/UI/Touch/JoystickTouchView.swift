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
    private let sprintEngageFactor: CGFloat = 1.20
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

        let center = activeTouch != nil ? basePoint : CGPoint(x: bounds.midX, y: bounds.midY)
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
        // Sweep gradient: short bright arc centered around `angle`, fading to
        // transparent. We approximate it with a stroked arc at multiple alpha
        // steps — efficient and good enough visually.
        let steps = 18
        let halfSpread: CGFloat = .pi * 0.20  // arc spread either side of angle (~36°)
        let peakAlpha = min(intensity * 235 / 255, 1)
        ctx.setLineCap(.round)
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps)
            // Bell curve: max at center, fades to edges.
            let bell = sin(t * .pi)
            let a = peakAlpha * bell
            if a < 0.02 { continue }
            let startA = angle - halfSpread + 2 * halfSpread * t
            let endA = startA + 2 * halfSpread / CGFloat(steps)
            ctx.setStrokeColor(UIColor(white: 1, alpha: a).cgColor)
            ctx.setLineWidth(2.5)
            ctx.addArc(center: center, radius: baseRadius, startAngle: startA, endAngle: endA, clockwise: false)
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
        let factor = rawDist / baseRadius
        if !sprintEngaged && factor >= sprintEngageFactor {
            sprintEngaged = true
            onSprintExtensionChanged?(true)
        } else if sprintEngaged && factor <= sprintDisengageFactor {
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
