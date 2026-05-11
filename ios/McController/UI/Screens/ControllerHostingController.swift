import UIKit
import Combine

/// Landscape-locked, full-screen controller surface. Owns:
///   - LookPad (background) → camera/cursor + tap/hold gestures
///   - Joystick → WASD-equivalent movement
///   - 7 action buttons (in-game) / 5 buttons (UI mode)
///   - Hotbar
///   - LookAccumulator (8 ms flush → UDP/TCP camera deltas)
///   - HUD (mode indicator + RTT, top-center, monospace, mirrors Android)
///   - Anti-mistouch overlay
final class ControllerHostingController: UIViewController {

    private let session: ControllerSession
    private let settings: SettingsStore
    private let profileStore: ProfileStoreObservable
    private let hostStore: HostStore
    private let host: SavedHost
    private let onDismiss: () -> Void

    private let stage = UIView()

    // Touch widgets
    private var lookPad: LookPadTouchView!
    private var joystick: JoystickTouchView!
    private var hotbar: HotbarTouchView!
    private var inGameButtons: [String: ActionButtonTouchView] = [:]
    private var uiButtons: [String: ActionButtonTouchView] = [:]

    // Anti-mistouch overlay
    private let lockOverlay = UIView()
    private let lockLabel = UILabel()

    // HUD
    private let hud = UILabel()
    private let backButton = UIButton(type: .system)

    // LookAccumulator
    private var lookAccumulator: LookAccumulator!

    // Sprint OR-logic
    private var sprintFromToggle: Bool = false
    private var sprintFromJoystick: Bool = false
    private var sprintEffective: Bool = false

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(session: ControllerSession,
         settings: SettingsStore,
         profileStore: ProfileStoreObservable,
         hostStore: HostStore,
         host: SavedHost,
         onDismiss: @escaping () -> Void) {
        self.session = session
        self.settings = settings
        self.profileStore = profileStore
        self.hostStore = hostStore
        self.host = host
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.06, alpha: 1) // dark background, matches Android bg_dark ≈ #0F0F10
        UIApplication.shared.isIdleTimerDisabled = true

        stage.frame = view.bounds
        stage.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(stage)

        buildWidgets()
        layoutLockOverlay()
        layoutHUD()

        lookAccumulator = LookAccumulator { [weak self] dx, dy in
            self?.session.sendLookDelta(dx: dx, dy: dy)
        }
        lookAccumulator.start()

        session.$mode.sink { [weak self] mode in
            self?.apply(mode: mode)
        }.store(in: &cancellables)

        session.$rttMs.combineLatest(session.$state).sink { [weak self] rtt, state in
            self?.updateHUD(rtt: rtt, state: state)
        }.store(in: &cancellables)

        session.$state.sink { [weak self] state in
            self?.handleSessionState(state)
        }.store(in: &cancellables)

        Task {
            await session.connect(host: host.ip, port: host.port)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.hostStore.markConnected(id: self.host.id)
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        lookAccumulator?.stop()
        Task { await session.disconnect() }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    // No `supportedInterfaceOrientations` override — the AppDelegate is the
    // single source of truth, switched dynamically by `OrientationHelper`.
    // Hardcoding `.landscape` here would block `requestGeometryUpdate(.portrait)`
    // on exit (iOS intersects the VC's mask with the AppDelegate's).

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        applyLayout()
        lockOverlay.frame = view.bounds
        lockLabel.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
    }

    // MARK: - Build

    private func buildWidgets() {
        // LookPad first → siblings (added after) naturally hit-test on top.
        lookPad = LookPadTouchView(frame: stage.bounds)
        lookPad.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        lookPad.onLookDelta = { [weak self] dx, dy in
            self?.lookAccumulator.add(dx: dx, dy: dy)
        }
        lookPad.onPrimaryTap = { [weak self] in self?.tap(.mouseLeft) }
        lookPad.onSecondaryTap = { [weak self] in self?.tap(.mouseRight) }
        lookPad.onHoldStart = { [weak self] in self?.session.sendButton(.mouseLeft, down: true) }
        lookPad.onHoldEnd = { [weak self] in self?.session.sendButton(.mouseLeft, down: false) }
        lookPad.onSecondaryHoldStart = { [weak self] in self?.session.sendButton(.mouseRight, down: true) }
        lookPad.onSecondaryHoldEnd = { [weak self] in self?.session.sendButton(.mouseRight, down: false) }
        lookPad.inGameQuickClicks = settings.settings.inGameQuickClicks
        lookPad.uiQuickClicks = settings.settings.uiQuickClicks
        stage.addSubview(lookPad)

        // Joystick
        joystick = JoystickTouchView()
        joystick.onPositionChanged = { [weak self] x, y in
            self?.session.sendJoystick(x: x, y: y)
        }
        joystick.onSprintExtensionChanged = { [weak self] engaged in
            self?.sprintFromJoystick = engaged
            self?.inGameButtons["btn_sprint"]?.setToggleState((self?.sprintFromToggle ?? false) || engaged)
            self?.recomputeSprint()
        }
        stage.addSubview(joystick)

        // Hotbar
        hotbar = HotbarTouchView()
        hotbar.swipeMode = profileStore.activeProfile.hotbarSwipeMode
        hotbar.hapticsEnabled = settings.settings.haptics
        hotbar.onSelect = { [weak self] slot in
            guard let self else { return }
            let id = Protocol.ButtonId.hotbar(slot)
            self.session.sendButton(id, down: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) {
                self.session.sendButton(id, down: false)
            }
        }
        hotbar.onDrop = { [weak self] _ in
            self?.session.sendButton(.drop, down: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(30)) {
                self?.session.sendButton(.drop, down: false)
            }
        }
        stage.addSubview(hotbar)

        // In-game buttons — icons ported from the Android vector drawables.
        addInGameButton(id: "btn_lmb",    icon: .mouseLeft,  behavior: .hold,   button: .mouseLeft)
        addInGameButton(id: "btn_rmb",    icon: .mouseRight, behavior: .hold,   button: .mouseRight)
        addInGameButton(id: "btn_jump",   icon: .jump,       behavior: .hold,   button: .jump)
        addInGameButton(id: "btn_sneak",  icon: .sneak,      behavior: .toggle, button: .sneak)
        addInGameButton(id: "btn_sprint", icon: .sprint,     behavior: .toggle, button: nil) {
            [weak self] engaged in
            self?.sprintFromToggle = engaged
            self?.recomputeSprint()
        }
        addInGameButton(id: "btn_inv",    icon: .inventory,  behavior: .tap,    button: .inventory)
        addInGameButton(id: "btn_swap",   icon: .swap,       behavior: .tap,    button: .swapHand)
        addInGameButton(id: "btn_esc",    icon: .esc,        behavior: .tap,    button: .esc)

        // UI mode buttons
        addUIButton(id: "btn_ui_lmb",   icon: .mouseLeft,  behavior: .hold, button: .mouseLeft)
        addUIButton(id: "btn_ui_rmb",   icon: .mouseRight, behavior: .hold, button: .mouseRight)
        addUIButton(id: "btn_ui_q",     icon: .drop,       behavior: .tap,  button: .drop)
        addUIButton(id: "btn_ui_shift", icon: .shift,      behavior: .hold, button: .sneak)
        addUIButton(id: "btn_ui_esc",   icon: .esc,        behavior: .tap,  button: .esc)
    }

    private func addInGameButton(id: String,
                                  icon: WidgetIcon,
                                  behavior: ActionButtonTouchView.Behavior,
                                  button: Protocol.ButtonId?,
                                  override: ((Bool) -> Void)? = nil) {
        let v = ActionButtonTouchView(widgetID: id)
        v.behavior = behavior
        v.widgetIcon = icon
        v.hapticsEnabled = settings.settings.haptics
        v.onStateChanged = { [weak self] engaged in
            if let override { override(engaged); return }
            guard let button else { return }
            self?.session.sendButton(button, down: engaged)
        }
        v.onDragDelta = { [weak self] dx, dy in
            self?.lookAccumulator.add(dx: dx, dy: dy)
        }
        stage.addSubview(v)
        inGameButtons[id] = v
    }

    private func addUIButton(id: String,
                              icon: WidgetIcon,
                              behavior: ActionButtonTouchView.Behavior,
                              button: Protocol.ButtonId) {
        let v = ActionButtonTouchView(widgetID: id)
        v.behavior = behavior
        v.widgetIcon = icon
        v.hapticsEnabled = settings.settings.haptics
        v.onStateChanged = { [weak self] engaged in
            self?.session.sendButton(button, down: engaged)
        }
        v.onDragDelta = { [weak self] dx, dy in
            self?.lookAccumulator.add(dx: dx, dy: dy)
        }
        stage.addSubview(v)
        uiButtons[id] = v
    }

    // MARK: - Layout

    private func applyLayout() {
        var inGame = profileStore.activeProfile.inGame
        var uiMode = profileStore.activeProfile.uiMode
        inGame.leftOffset  = max(inGame.leftOffset,  settings.settings.leftMarginOffset)
        inGame.rightOffset = max(inGame.rightOffset, settings.settings.rightMarginOffset)
        uiMode.leftOffset  = max(uiMode.leftOffset,  settings.settings.leftMarginOffset)
        uiMode.rightOffset = max(uiMode.rightOffset, settings.settings.rightMarginOffset)

        // Inset by the safe area so widgets don't collide with the Dynamic
        // Island / camera bump / home indicator.
        let bounds = view.bounds.inset(by: view.safeAreaInsets)

        if let js = inGame.widgets["joystick"] {
            joystick.frame = LayoutApplier.frame(for: js, in: inGame, bounds: bounds)
        }
        if let hb = inGame.widgets["hotbar"] {
            hotbar.frame = LayoutApplier.frame(for: hb, in: inGame, bounds: bounds)
        }
        for (id, view) in inGameButtons {
            guard let spec = inGame.widgets[id] else { continue }
            view.frame = LayoutApplier.frame(for: spec, in: inGame, bounds: bounds)
        }
        for (id, view) in uiButtons {
            guard let spec = uiMode.widgets[id] else { continue }
            view.frame = LayoutApplier.frame(for: spec, in: uiMode, bounds: bounds)
        }
    }

    // MARK: - Lock overlay + HUD

    private func layoutLockOverlay() {
        lockOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.88)
        lockOverlay.isHidden = true
        view.addSubview(lockOverlay)

        lockLabel.text = L.key("controller.lock.message")
        lockLabel.textColor = .white
        lockLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        lockLabel.sizeToFit()
        lockOverlay.addSubview(lockLabel)
    }

    private func layoutHUD() {
        // Top-center monospace label matching Android's HUD format.
        hud.font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        hud.textColor = .white
        hud.textAlignment = .center
        hud.numberOfLines = 1
        hud.shadowColor = UIColor.black.withAlphaComponent(0.7)
        hud.shadowOffset = CGSize(width: 0, height: 1)
        hud.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hud)
        NSLayoutConstraint.activate([
            hud.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hud.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
        ])

        // Back button (top-right of safe area) — disconnects + dismisses.
        backButton.setImage(UIImage(systemName: "xmark.circle.fill",
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)),
                            for: .normal)
        backButton.tintColor = UIColor.white.withAlphaComponent(0.6)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backButton)
        backButton.addTarget(self, action: #selector(tapBack), for: .touchUpInside)
        NSLayoutConstraint.activate([
            backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            backButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            backButton.widthAnchor.constraint(equalToConstant: 36),
            backButton.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    @objc private func tapBack() {
        prepareForExitFade()
        OrientationHelper.restorePortrait()
        onDismiss()
    }

    /// Hide every child view immediately so the rotation-driven layout pass
    /// during exit has nothing visible to reflow. The cross-fade then just
    /// dissolves the dark background.
    private func prepareForExitFade() {
        view.subviews.forEach { $0.isHidden = true }
    }

    // MARK: - Mode application

    private func apply(mode: ControllerMode) {
        lookPad.mode = mode

        let inGameVisible = (mode == .inGame)
        let uiVisible     = (mode == .uiInteract)
        let lockVisible   = (mode == .antiMistouch)

        joystick.isHidden = !inGameVisible
        hotbar.isHidden   = !inGameVisible
        inGameButtons.values.forEach { $0.isHidden = !inGameVisible }
        uiButtons.values.forEach { $0.isHidden = !uiVisible }
        lockOverlay.isHidden = !lockVisible

        if !inGameVisible {
            inGameButtons["btn_sneak"]?.forceToggleOff()
            inGameButtons["btn_sprint"]?.forceToggleOff()
            sprintFromToggle = false
            sprintFromJoystick = false
            recomputeSprint()
            session.sendJoystick(x: 0, y: 0)
        }
        if lockVisible {
            for b in Protocol.ButtonId.allCases {
                session.sendButton(b, down: false)
            }
        }
    }

    private func recomputeSprint() {
        let new = sprintFromToggle || sprintFromJoystick
        if new != sprintEffective {
            sprintEffective = new
            session.sendButton(.sprint, down: new)
        }
    }

    private func tap(_ id: Protocol.ButtonId) {
        session.sendButton(id, down: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20)) { [weak self] in
            self?.session.sendButton(id, down: false)
        }
    }

    // MARK: - HUD content

    private func updateHUD(rtt: Int?, state: ControllerSession.State) {
        // Format: "● Wi-Fi · in-game · 4ms"  (matches Android)
        let prefix = "●"
        let parts: [String]
        switch state {
        case .idle:
            parts = ["Idle"]
        case .connecting:
            parts = ["Connecting…"]
        case .connected:
            let modeStr: String
            switch session.mode {
            case .inGame:        modeStr = "in-game"
            case .uiInteract:    modeStr = "UI"
            case .antiMistouch:  modeStr = "locked"
            }
            let rttStr = rtt.map { "\($0)ms" } ?? "—"
            parts = ["Wi-Fi", modeStr, rttStr]
        case .disconnected:
            parts = ["Disconnected"]
        case .failed(let reason):
            parts = ["Failed: \(reason)"]
        }
        hud.text = "\(prefix) " + parts.joined(separator: " · ")
    }

    // MARK: - Session state

    private func handleSessionState(_ state: ControllerSession.State) {
        switch state {
        case .failed:
            // Bounce home after showing the error briefly.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                self?.onDismiss()
            }
        case .disconnected:
            // Brief grace period so a transient TCP blip immediately after
            // handshake doesn't snap the modal away with zero feedback. If
            // the session magically recovers in this window (e.g. quick
            // reconnect), we cancel the dismissal.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                guard let self else { return }
                if case .disconnected = self.session.state {
                    self.onDismiss()
                }
            }
        default:
            break
        }
    }

    // MARK: - Public — rebuild on changes

    func rebuildIfSettingsChanged() {
        lookPad.inGameQuickClicks = settings.settings.inGameQuickClicks
        lookPad.uiQuickClicks = settings.settings.uiQuickClicks
        hotbar.swipeMode = profileStore.activeProfile.hotbarSwipeMode
        hotbar.hapticsEnabled = settings.settings.haptics
        inGameButtons.values.forEach { $0.hapticsEnabled = settings.settings.haptics }
        uiButtons.values.forEach { $0.hapticsEnabled = settings.settings.haptics }
        applyLayout()
    }
}
