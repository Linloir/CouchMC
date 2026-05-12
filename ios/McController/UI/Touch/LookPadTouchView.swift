import UIKit

/// Full-screen camera / cursor surface with a hand-rolled gesture FSM.
///
/// In-game mode (camera + LMB chain-hold):
///   IDLE → DOWN → PRIMED1
///     ├─ slop crossed → DRAG (emit deltas)
///     └─ quick UP → onPrimaryTap(); → AFTER_TAP (280 ms chain window)
///         ├─ DOWN within window → LMB_HELD_INGAME (emit deltas + LMB held)
///         │   └─ UP: if slid → IDLE else → AFTER_TAP (chain again)
///         └─ timeout → IDLE
///
/// UI mode (cursor + tap-confirm + slide-press variants):
///   IDLE → DOWN → PRIMED1
///     ├─ slop crossed → DRAG (cursor only)
///     └─ quick UP → SINGLE_PENDING (200 ms confirm window)
///         ├─ DOWN within window → SECOND_PRIMED
///         │   ├─ slop → LMB_HELD_UI (cursor + LMB held)
///         │   └─ UP: if slid → IDLE else → onSecondaryTap(); DOUBLE_PENDING
///         │       └─ DOWN within window → THIRD_PRIMED
///         │           ├─ slop → RMB_HELD_UI (cursor + RMB held)
///         │           └─ UP: → IDLE
///         └─ timeout → onPrimaryTap(); IDLE
///
/// Mode change resets the FSM and releases any held button.
final class LookPadTouchView: UIView, EditableWidgetView {

    // EditableWidgetView
    let widgetID: String = "lookpad"
    var isEditing: Bool = false {
        didSet {
            isUserInteractionEnabled = !isEditing
            if isEditing { resetGestureState(releaseHeld: true) }
        }
    }
    var isSelectedInEditor: Bool = false

    // MARK: - Public callbacks
    var onLookDelta: ((Int, Int) -> Void)?              // sub-pixel (×10) deltas
    var onPrimaryTap: (() -> Void)?                     // LMB click (both modes)
    var onSecondaryTap: (() -> Void)?                   // RMB click (UI only)
    var onHoldStart: (() -> Void)?                      // LMB down
    var onHoldEnd: (() -> Void)?                        // LMB up
    var onSecondaryHoldStart: (() -> Void)?             // RMB down
    var onSecondaryHoldEnd: (() -> Void)?               // RMB up

    // MARK: - Mode + tunables
    var mode: ControllerMode = .antiMistouch {
        didSet { if oldValue != mode { resetGestureState(releaseHeld: true) } }
    }
    var inGameQuickClicks: Bool = true
    var uiQuickClicks: Bool = true
    /// Multiplier on emitted look deltas. iOS coalesces fewer micro-touch
    /// samples than Android in practice, so the raw signal feels slow; we
    /// scale up by this factor when sending. Set from `SettingsStore`.
    var cameraSensitivity: Double = 1.5

    private let touchSlop: CGFloat = 8                  // points; matches Android scaledTouchSlop on hidpi
    private let inGameChainWindowMs: Int = 280
    private let uiDoubleTapWindowMs: Int = 200
    private let subpixelScale: CGFloat = Protocol.subpixelScale

    // MARK: - FSM state

    private enum FSM {
        case idle
        case primed1                   // first touch, deciding tap-vs-drag
        case drag                      // camera-only (in-game) or cursor-only (UI)
        case afterTap                  // in-game chain window
        case lmbHeldInGame             // chain-pressed second touch
        case singlePending             // UI: scheduled 200 ms LMB confirm
        case secondPrimed              // UI: second tap-down within window
        case lmbHeldUI                 // UI: slide-press LMB
        case doublePending             // UI: after RMB tap, waiting for third press
        case thirdPrimed
        case rmbHeldUI
    }

    private var state: FSM = .idle
    private var activeTouch: UITouch?
    private var primedLocation: CGPoint = .zero
    private var lastLocation: CGPoint = .zero
    private var residualX: CGFloat = 0
    private var residualY: CGFloat = 0
    private var slidDuringHold: Bool = false
    private var chainTimer: DispatchWorkItem?

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
        isMultipleTouchEnabled = false  // FSM is single-finger; siblings handle their own touches
        isExclusiveTouch = false
    }

    // MARK: - Hit test
    // Make the look pad transparent to widgets ON TOP of it (visually below it,
    // but in z-order they're siblings). Containers should put the LookPad
    // first, so iOS hitTest naturally prefers later siblings.

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard mode != .antiMistouch else { return }
        if activeTouch != nil { return }
        guard let t = touches.first else { return }
        activeTouch = t
        let p = t.location(in: self)
        primedLocation = p
        lastLocation = p
        residualX = 0
        residualY = 0
        slidDuringHold = false

        switch state {
        case .idle:
            state = .primed1
        case .afterTap:
            cancelChainTimer()
            // Re-press during in-game chain window: enter held state immediately.
            state = .lmbHeldInGame
            onHoldStart?()
        case .singlePending:
            cancelChainTimer()
            state = .secondPrimed
        case .doublePending:
            cancelChainTimer()
            state = .thirdPrimed
        default:
            state = .primed1
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        // Use coalesced touches for >60 Hz sampling.
        let samples = event?.coalescedTouches(for: t) ?? [t]
        for s in samples { processMoveTo(s.location(in: self)) }
    }

    private func processMoveTo(_ p: CGPoint) {
        let dxf = p.x - lastLocation.x
        let dyf = p.y - lastLocation.y
        lastLocation = p

        switch state {
        case .primed1:
            // Decide tap-or-drag based on cumulative distance from primedLocation.
            let traveled = hypot(p.x - primedLocation.x, p.y - primedLocation.y)
            if traveled > touchSlop {
                state = .drag
                emitDelta(dxf, dyf)
            }
        case .drag:
            emitDelta(dxf, dyf)
        case .secondPrimed:
            let traveled = hypot(p.x - primedLocation.x, p.y - primedLocation.y)
            if traveled > touchSlop {
                state = .lmbHeldUI
                onHoldStart?()
                slidDuringHold = true
                emitDelta(dxf, dyf)
            }
        case .thirdPrimed:
            let traveled = hypot(p.x - primedLocation.x, p.y - primedLocation.y)
            if traveled > touchSlop {
                state = .rmbHeldUI
                onSecondaryHoldStart?()
                slidDuringHold = true
                emitDelta(dxf, dyf)
            }
        case .lmbHeldInGame, .lmbHeldUI, .rmbHeldUI:
            slidDuringHold = true
            emitDelta(dxf, dyf)
        default:
            break
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        activeTouch = nil
        let quickClicksEnabled = (mode == .inGame) ? inGameQuickClicks : uiQuickClicks

        switch state {
        case .primed1:
            if quickClicksEnabled {
                if mode == .inGame {
                    onPrimaryTap?()
                    enterAfterTap()
                } else {
                    // UI mode: wait 200 ms to confirm single-tap (might be double).
                    state = .singlePending
                    scheduleTimer(ms: uiDoubleTapWindowMs) { [weak self] in
                        guard let self else { return }
                        if self.state == .singlePending {
                            self.onPrimaryTap?()
                            self.state = .idle
                        }
                    }
                }
            } else {
                state = .idle
            }
        case .drag:
            state = .idle
        case .secondPrimed:
            // Quick second tap → RMB click; then wait for third press.
            if mode == .uiInteract {
                onSecondaryTap?()
                state = .doublePending
                scheduleTimer(ms: uiDoubleTapWindowMs) { [weak self] in
                    guard let self else { return }
                    if self.state == .doublePending {
                        self.state = .idle
                    }
                }
            } else {
                state = .idle
            }
        case .thirdPrimed:
            // Quick third tap with no slide → nothing extra; return to idle.
            state = .idle
        case .lmbHeldInGame:
            onHoldEnd?()
            if slidDuringHold {
                state = .idle
            } else {
                // No slide during chain — reopen the chain window for rapid fire.
                enterAfterTap()
            }
        case .lmbHeldUI:
            onHoldEnd?()
            state = .idle
        case .rmbHeldUI:
            onSecondaryHoldEnd?()
            state = .idle
        default:
            state = .idle
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = activeTouch, touches.contains(t) else { return }
        activeTouch = nil
        // On cancel we don't fire taps, but we MUST release any held buttons.
        releaseHeldFor(state: state)
        state = .idle
        cancelChainTimer()
    }

    // MARK: - Helpers

    private func enterAfterTap() {
        state = .afterTap
        scheduleTimer(ms: inGameChainWindowMs) { [weak self] in
            guard let self else { return }
            if self.state == .afterTap {
                self.state = .idle
            }
        }
    }

    private func emitDelta(_ dx: CGFloat, _ dy: CGFloat) {
        // Accumulate sub-pixel and emit only the integer portion. Apply the
        // user-tunable camera sensitivity multiplier on top of the protocol's
        // ×10 sub-pixel scale (tenths-of-pixel wire deltas).
        let sens = CGFloat(cameraSensitivity)
        let sx = dx * subpixelScale * sens + residualX
        let sy = dy * subpixelScale * sens + residualY
        let ix = Int(sx)
        let iy = Int(sy)
        residualX = sx - CGFloat(ix)
        residualY = sy - CGFloat(iy)
        if ix != 0 || iy != 0 {
            onLookDelta?(ix, iy)
        }
    }

    private func resetGestureState(releaseHeld: Bool) {
        if releaseHeld { releaseHeldFor(state: state) }
        state = .idle
        activeTouch = nil
        residualX = 0
        residualY = 0
        slidDuringHold = false
        cancelChainTimer()
    }

    private func releaseHeldFor(state: FSM) {
        switch state {
        case .lmbHeldInGame, .lmbHeldUI:
            onHoldEnd?()
        case .rmbHeldUI:
            onSecondaryHoldEnd?()
        default:
            break
        }
    }

    private func scheduleTimer(ms: Int, _ block: @escaping () -> Void) {
        cancelChainTimer()
        let work = DispatchWorkItem(block: block)
        chainTimer = work
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(ms), execute: work)
    }

    private func cancelChainTimer() {
        chainTimer?.cancel()
        chainTimer = nil
    }
}
