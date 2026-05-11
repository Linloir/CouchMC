import UIKit

/// 9-slot inventory bar. CG-drawn to match Android's `HotbarView` exactly:
///   - Slot backdrop: rgba(0,0,0, 80/255), 6pt corner.
///   - Ring unselected: white 110/255 alpha, 1pt.
///   - Ring selected: white 235/255 alpha, 2pt.
///   - Pressed fill: white 60/255 alpha.
///   - Dropping fill: rgba(255,100,100, 90/255) — red tint while long-pressing.
///   - Slot label: "1".."9" white 220/255 alpha, bold, font size ≈ height × 0.45.
final class HotbarTouchView: UIView, EditableWidgetView {

    var onSelect: ((Int) -> Void)?
    var onDrop: ((Int) -> Void)?
    var swipeMode: HotbarSwipeMode = .precise
    var hapticsEnabled: Bool = true

    // MARK: - EditableWidgetView
    let widgetID: String = "hotbar"
    /// `isUserInteractionEnabled` stays `true` in edit mode so the editor's
    /// gesture recognisers attached to this view fire. The view's own touch
    /// handlers early-return on `isEditing`.
    var isEditing: Bool = false {
        didSet {
            if isEditing { stopDropPulses(); cancelLongPress() }
            setNeedsDisplay()
        }
    }
    var isSelectedInEditor: Bool = false { didSet { setNeedsDisplay() } }

    private(set) var selectedSlot: Int = -1 {
        didSet { if selectedSlot != oldValue { setNeedsDisplay() } }
    }
    private var pressedSlot: Int = -1 {
        didSet { if pressedSlot != oldValue { setNeedsDisplay() } }
    }
    private var hasSwiped: Bool = false
    private var isDropping: Bool = false {
        didSet { if isDropping != oldValue { setNeedsDisplay() } }
    }

    private let slotCount: Int = 9
    private let slotStep: CGFloat = 32
    private let longPressMs: Int = 400
    private let dropPeriodMs: Int = 200

    private var activeTouch: UITouch?
    private var relAccumX: CGFloat = 0
    private var relLastX: CGFloat = 0

    private var longPressTimer: DispatchWorkItem?
    private var dropTimer: DispatchSourceTimer?
    private lazy var haptic = UIImpactFeedbackGenerator(style: .soft)

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
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
        guard bounds.width > 0, bounds.height > 0 else { return }
        let slotW = bounds.width / CGFloat(slotCount)
        let pad: CGFloat = 2
        let corner: CGFloat = 6
        let labelFont = UIFont.boldSystemFont(ofSize: bounds.height * 0.45)
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: UIColor(white: 1, alpha: 220/255),
        ]

        for i in 0..<slotCount {
            let left = CGFloat(i) * slotW + pad
            let right = CGFloat(i + 1) * slotW - pad
            let r = CGRect(x: left, y: pad, width: right - left, height: bounds.height - 2 * pad)
            let path = UIBezierPath(roundedRect: r, cornerRadius: corner).cgPath

            // Backdrop
            ctx.setFillColor(UIColor(white: 0, alpha: 80/255).cgColor)
            ctx.addPath(path)
            ctx.fillPath()

            // Pressed / dropping fill
            if i == pressedSlot && isDropping {
                ctx.setFillColor(UIColor(red: 255/255, green: 100/255, blue: 100/255, alpha: 90/255).cgColor)
                ctx.addPath(path)
                ctx.fillPath()
            } else if i == pressedSlot {
                ctx.setFillColor(UIColor(white: 1, alpha: 60/255).cgColor)
                ctx.addPath(path)
                ctx.fillPath()
            }

            // Ring (selected = bright + thick)
            if i == selectedSlot {
                ctx.setStrokeColor(UIColor(white: 1, alpha: 235/255).cgColor)
                ctx.setLineWidth(2)
            } else {
                ctx.setStrokeColor(UIColor(white: 1, alpha: 110/255).cgColor)
                ctx.setLineWidth(1)
            }
            ctx.addPath(path)
            ctx.strokePath()

            // Label "1".."9"
            let s = "\(i + 1)" as NSString
            let size = s.size(withAttributes: labelAttrs)
            let cx = (left + right) / 2
            let cy = bounds.midY
            s.draw(at: CGPoint(x: cx - size.width / 2, y: cy - size.height / 2),
                   withAttributes: labelAttrs)
        }

        // Editor selection ring
        if isEditing && isSelectedInEditor {
            ctx.setStrokeColor(UIColor(red: 0xE8/255, green: 0xC5/255, blue: 0x47/255, alpha: 1).cgColor)
            ctx.setLineWidth(2.5)
            let outerRect = bounds.insetBy(dx: 1.5, dy: 1.5)
            let outer = UIBezierPath(roundedRect: outerRect, cornerRadius: 8)
            ctx.addPath(outer.cgPath)
            ctx.strokePath()
        }
    }

    // MARK: - Touch

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isEditing, activeTouch == nil, let t = touches.first else { return }
        activeTouch = t
        let p = t.location(in: self)
        let slot = slotAt(x: p.x)
        guard slot >= 0 else { return }

        pressedSlot = slot
        hasSwiped = false
        relAccumX = 0
        relLastX = p.x

        switch swipeMode {
        case .precise:
            selectImmediate(slot)
        case .relative:
            break  // defer commit until UP or long-press fires
        }
        scheduleLongPress()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isEditing, let t = activeTouch, touches.contains(t) else { return }
        let samples = event?.coalescedTouches(for: t) ?? [t]
        for s in samples {
            let p = s.location(in: self)
            switch swipeMode {
            case .precise:
                let slot = slotAt(x: p.x)
                if slot >= 0 && slot != pressedSlot {
                    hasSwiped = true
                    cancelLongPress()
                    pressedSlot = slot
                    selectImmediate(slot)
                }
            case .relative:
                relAccumX += p.x - relLastX
                relLastX = p.x
                var stepped = false
                while relAccumX >= slotStep {
                    selectedSlot = (selectedSlot + 1 + slotCount) % slotCount
                    onSelect?(selectedSlot)
                    relAccumX -= slotStep
                    stepped = true
                }
                while relAccumX <= -slotStep {
                    selectedSlot = (selectedSlot - 1 + slotCount) % slotCount
                    onSelect?(selectedSlot)
                    relAccumX += slotStep
                    stepped = true
                }
                if stepped {
                    hasSwiped = true
                    cancelLongPress()
                    pressedSlot = selectedSlot
                    if hapticsEnabled { haptic.impactOccurred(intensity: 0.3) }
                }
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isEditing, let t = activeTouch, touches.contains(t) else { return }
        activeTouch = nil
        let isTap = !hasSwiped && !isDropping
        if isTap, pressedSlot >= 0, swipeMode == .relative {
            selectImmediate(pressedSlot)
        }
        pressedSlot = -1
        hasSwiped = false
        isDropping = false
        cancelLongPress()
        stopDropPulses()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard !isEditing, let t = activeTouch, touches.contains(t) else { return }
        activeTouch = nil
        pressedSlot = -1
        hasSwiped = false
        isDropping = false
        cancelLongPress()
        stopDropPulses()
    }

    // MARK: - Helpers

    private func slotAt(x: CGFloat) -> Int {
        guard bounds.width > 0 else { return -1 }
        let slotW = bounds.width / CGFloat(slotCount)
        return max(0, min(slotCount - 1, Int(x / slotW)))
    }

    private func selectImmediate(_ slot: Int) {
        guard slot != selectedSlot else { return }
        selectedSlot = slot
        if hapticsEnabled { haptic.impactOccurred(intensity: 0.3) }
        onSelect?(slot)
    }

    private func scheduleLongPress() {
        cancelLongPress()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.hasSwiped, self.activeTouch != nil else { return }
            self.startDropPulses()
        }
        longPressTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(longPressMs), execute: work)
    }

    private func cancelLongPress() {
        longPressTimer?.cancel()
        longPressTimer = nil
    }

    private func startDropPulses() {
        // Relative mode defers selection on DOWN — first tick commits it.
        if selectedSlot != pressedSlot {
            selectImmediate(pressedSlot)
        }
        isDropping = true
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: .milliseconds(dropPeriodMs))
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            self.onDrop?(self.selectedSlot)
        }
        timer.resume()
        dropTimer = timer
    }

    private func stopDropPulses() {
        dropTimer?.cancel()
        dropTimer = nil
    }

    /// External hint (e.g., on connect).
    func setSelectedSlot(_ slot: Int) {
        selectedSlot = max(0, min(slotCount - 1, slot))
    }
}
