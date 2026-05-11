import UIKit

/// Round action button. Three behavior modes (HOLD / TOGGLE / TAP) and a
/// CG-drawn visual that mirrors the Android `ActionButtonView` exactly:
///   - Backdrop: rgba(30,30,35, 95/255) glass disc.
///   - Ring: white at 70/255 alpha, 1.5pt — barely-visible.
///   - Toggle accent: warm amber 255,200,60 (fill 70/255, ring 220/255).
///   - Tap flash: bright white overlay fading out over 380ms.
///   - Icon: SF Symbol (or label fallback), tinted white at 225/255.
///
/// When `isEditing == true`, normal touch handling is disabled — the parent
/// editor canvas takes over via attached gesture recognizers.
final class ActionButtonTouchView: UIView, EditableWidgetView {

    enum Behavior { case hold, toggle, tap }

    // MARK: - Public callbacks
    var onStateChanged: ((Bool) -> Void)?
    var onDragDelta: ((Int, Int) -> Void)?       // hold-mode camera deltas

    // MARK: - Configuration
    var behavior: Behavior = .hold
    var hapticsEnabled: Bool = true
    /// Custom vector icon ported from the Android drawables. Preferred over
    /// `iconSystemName`/`labelText` when non-nil.
    var widgetIcon: WidgetIcon? { didSet { setNeedsDisplay() } }
    var iconSystemName: String? { didSet { setNeedsDisplay() } }
    var labelText: String? { didSet { setNeedsDisplay() } }

    // MARK: - EditableWidgetView
    let widgetID: String
    /// In edit mode the widget keeps `isUserInteractionEnabled = true` so the
    /// editor's UIPanGestureRecognizer + UITapGestureRecognizer attached to
    /// this view still receive touches. The view's own `touchesBegan/Moved/…`
    /// early-return on `isEditing` so no live button behavior runs.
    var isEditing: Bool = false {
        didSet { setNeedsDisplay() }
    }
    var isSelectedInEditor: Bool = false {
        didSet { setNeedsDisplay() }
    }

    // MARK: - Toggle state
    private(set) var toggleEngaged: Bool = false {
        didSet { setNeedsDisplay() }
    }

    // MARK: - Touch / drag
    private var activeTouch: UITouch?
    private var lastDragLocation: CGPoint = .zero
    private var residualX: CGFloat = 0
    private var residualY: CGFloat = 0
    private let subpixelScale: CGFloat = Protocol.subpixelScale

    // MARK: - Flash animation
    private var flashIntensity: CGFloat = 0
    private var flashDisplayLink: CADisplayLink?
    private var flashStartTime: CFTimeInterval = 0
    private var flashStartIntensity: CGFloat = 0
    private let flashFadeMs: CGFloat = 380

    // MARK: - Haptics
    private lazy var haptic = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Init
    init(widgetID: String) {
        self.widgetID = widgetID
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = false
        isExclusiveTouch = false
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Drawing
    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let cx = bounds.midX
        let cy = bounds.midY
        let r = min(bounds.width, bounds.height) / 2 - 3
        let center = CGPoint(x: cx, y: cy)

        // Backdrop
        ctx.setFillColor(UIColor(red: 30/255, green: 30/255, blue: 35/255, alpha: 95/255).cgColor)
        ctx.addArc(center: center, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        ctx.fillPath()

        // Toggle accent fill
        if behavior == .toggle && toggleEngaged {
            ctx.setFillColor(UIColor(red: 255/255, green: 200/255, blue: 60/255, alpha: 70/255).cgColor)
            ctx.addArc(center: center, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            ctx.fillPath()
        }

        // Tap flash
        if flashIntensity > 0.005 {
            let a = min(max(flashIntensity * 170 / 255, 0), 1)
            ctx.setFillColor(UIColor(white: 1, alpha: a).cgColor)
            ctx.addArc(center: center, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            ctx.fillPath()
        }

        // Ring (or amber if toggled)
        let toggledOn = behavior == .toggle && toggleEngaged
        if toggledOn {
            ctx.setStrokeColor(UIColor(red: 255/255, green: 200/255, blue: 60/255, alpha: 220/255).cgColor)
            ctx.setLineWidth(2)
        } else {
            ctx.setStrokeColor(UIColor(white: 1, alpha: 70/255).cgColor)
            ctx.setLineWidth(1.5)
        }
        ctx.addArc(center: center, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        ctx.strokePath()

        // Icon or label centered. Custom WidgetIcon wins over SF Symbol over
        // text fallback.
        let iconAlpha: CGFloat = 225 / 255
        let tintColor = UIColor(white: 1, alpha: iconAlpha)
        let extent = r * 0.95
        let iconRect = CGRect(x: cx - extent / 2, y: cy - extent / 2,
                              width: extent, height: extent)
        if let icon = widgetIcon {
            icon.draw(in: iconRect, color: tintColor, ctx: ctx)
        } else if let name = iconSystemName,
                  let img = UIImage(systemName: name,
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: r * 0.95, weight: .semibold)) {
            let tinted = img.withTintColor(tintColor, renderingMode: .alwaysOriginal)
            tinted.draw(in: iconRect)
        } else if let text = labelText, !text.isEmpty {
            let font = UIFont.systemFont(ofSize: r * 0.55, weight: .bold)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: tintColor,
            ]
            let ns = text as NSString
            let size = ns.size(withAttributes: attrs)
            ns.draw(at: CGPoint(x: cx - size.width / 2, y: cy - size.height / 2),
                    withAttributes: attrs)
        }

        // Editor selection ring (gold) — drawn outside the button.
        if isEditing && isSelectedInEditor {
            ctx.setStrokeColor(UIColor(red: 0xE8/255, green: 0xC5/255, blue: 0x47/255, alpha: 1).cgColor)
            ctx.setLineWidth(2.5)
            let rectInset: CGFloat = 1.5
            let outer = bounds.insetBy(dx: rectInset, dy: rectInset)
            let path = UIBezierPath(roundedRect: outer, cornerRadius: 8)
            ctx.addPath(path.cgPath)
            ctx.strokePath()
        }
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isEditing, activeTouch == nil, let t = touches.first else { return }
        activeTouch = t
        lastDragLocation = t.location(in: self)
        residualX = 0
        residualY = 0

        startFlash()
        if hapticsEnabled { haptic.impactOccurred(intensity: 0.55) }

        switch behavior {
        case .hold:
            onStateChanged?(true)
        case .toggle:
            toggleEngaged.toggle()
            onStateChanged?(toggleEngaged)
        case .tap:
            onStateChanged?(true)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isEditing, behavior == .hold else { return }
        guard let t = activeTouch, touches.contains(t) else { return }
        let samples = event?.coalescedTouches(for: t) ?? [t]
        for s in samples {
            let p = s.location(in: self)
            let dx = p.x - lastDragLocation.x
            let dy = p.y - lastDragLocation.y
            lastDragLocation = p
            emitDrag(dx: dx, dy: dy)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isEditing, let t = activeTouch, touches.contains(t) else { return }
        activeTouch = nil
        endFlash()
        switch behavior {
        case .hold:
            onStateChanged?(false)
        case .toggle:
            break  // already fired on DOWN
        case .tap:
            onStateChanged?(false)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isEditing, let t = activeTouch, touches.contains(t) else { return }
        activeTouch = nil
        endFlash()
        if behavior == .hold {
            onStateChanged?(false)
        }
    }

    private func emitDrag(dx: CGFloat, dy: CGFloat) {
        let sx = dx * subpixelScale + residualX
        let sy = dy * subpixelScale + residualY
        let ix = Int(sx)
        let iy = Int(sy)
        residualX = sx - CGFloat(ix)
        residualY = sy - CGFloat(iy)
        if ix != 0 || iy != 0 { onDragDelta?(ix, iy) }
    }

    // MARK: - Flash animation

    private func startFlash() {
        flashDisplayLink?.invalidate()
        flashDisplayLink = nil
        flashIntensity = 1
        setNeedsDisplay()
    }

    private func endFlash() {
        flashStartTime = CACurrentMediaTime()
        flashStartIntensity = flashIntensity
        let link = CADisplayLink(target: self, selector: #selector(stepFlash))
        link.add(to: .main, forMode: .common)
        flashDisplayLink = link
    }

    @objc private func stepFlash() {
        let elapsed = (CACurrentMediaTime() - flashStartTime) * 1000  // ms
        let duration = max(120, flashFadeMs * flashStartIntensity)
        let t = min(elapsed / duration, 1)
        // DecelerateInterpolator(1.6) ≈ 1 - (1-t)^(2*1.6) but simpler ease-out below:
        let eased = 1 - pow(1 - t, 1.6 * 2)
        flashIntensity = max(0, flashStartIntensity * (1 - eased))
        setNeedsDisplay()
        if t >= 1 {
            flashIntensity = 0
            flashDisplayLink?.invalidate()
            flashDisplayLink = nil
            setNeedsDisplay()
        }
    }

    // MARK: - External hooks

    /// External callers (e.g. mode-change reset, joystick-driven sprint) can
    /// override the visual toggle state without firing events.
    func setToggleState(_ engaged: Bool) {
        if toggleEngaged != engaged {
            toggleEngaged = engaged
        }
    }

    /// Force-release a toggle button (also fires the off event).
    func forceToggleOff() {
        guard toggleEngaged else { return }
        toggleEngaged = false
        onStateChanged?(false)
    }
}

/// Common interface for widgets that can be edited in the layout editor.
protocol EditableWidgetView: UIView {
    var widgetID: String { get }
    var isEditing: Bool { get set }
    var isSelectedInEditor: Bool { get set }
}
