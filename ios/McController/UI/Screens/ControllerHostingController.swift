import UIKit
import Combine

/// Landscape-locked, full-screen controller surface. Owns:
///   - LookPad (background) → camera/cursor + tap/hold gestures
///   - Joystick → WASD-equivalent movement
///   - 8 action buttons (in-game) including a movable `btn_close` that dismisses
///     the controller; 6 buttons in UI mode (5 normal + close)
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

    // Anti-mistouch overlay. The "Minecraft is not in the foreground"
    // prompt + a "back to host list" button — without that button there's
    // no way to leave anti-mistouch mode without first switching MC into
    // the foreground (which is exactly the case where the user wants
    // *out*: MC isn't running, they want to dismiss the controller).
    private let lockOverlay = UIView()
    private let lockLabel = UILabel()
    private let lockBackButton = UIButton(type: .system)

    // HUD
    private let hud = UILabel()

    // Demo mode UI (only added to the view tree when session.isDemoMode is
    // true). The mode-cycle button replaces the server-driven STATE_CHANGE
    // signal in the simulator; the bottom diagnostic label gives App
    // reviewers a live readout that proves inputs are flowing without
    // them needing to set up a PC server.
    private let demoModeButton = UIButton(type: .system)
    private let demoDiagnosticLabel = UILabel()
    private var demoPollTimer: DispatchSourceTimer?
    private weak var demoTutorialOverlay: UIView?
    private var lastDemoSnapshotKey: String = ""

    // LookAccumulator
    private var lookAccumulator: LookAccumulator!

    // Sprint OR-logic
    private var sprintFromToggle: Bool = false
    private var sprintFromJoystick: Bool = false
    private var sprintEffective: Bool = false

    // Connection retry — transient TCP drops on iOS sometimes kick us out
    // 1–2 s after handshake before any PING/PONG round-trips. Auto-reconnect
    // a few times before giving up so the user doesn't have to manually
    // re-tap the host.
    private var hasEverConnected: Bool = false
    private var lastConnectedAt: Date?
    private var retryCount: Int = 0
    private let maxRetries: Int = 3
    /// Set when the user taps the close widget so we don't auto-reconnect
    /// against an intentional dismissal.
    private var userInitiatedDismiss: Bool = false

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
        applyCurrentSettingsToWidgets()
        layoutLockOverlay()
        layoutHUD()
        layoutDemoControls()

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

        session.$isDemoMode.sink { [weak self] isDemo in
            self?.applyDemoMode(isDemo)
        }.store(in: &cancellables)

        // Demo mode: skip the network stack entirely; the session is
        // already in `.connected` from `HomeView.connect(to:)`.
        if host.isDemo {
            session.connectDemo()
            hostStore.markConnected(id: host.id)
        } else {
            Task {
                await session.connect(host: host.ip, port: host.port)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.hostStore.markConnected(id: self.host.id)
                }
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isIdleTimerDisabled = false
        lookAccumulator?.stop()
        stopDemoPolling()
        Task { await session.disconnect() }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Nudge UIKit to re-query `prefersHomeIndicatorAutoHidden` +
        // `preferredScreenEdgesDeferringSystemGestures` once we're on
        // screen. Without an explicit need-update, the cached values from
        // the cross-fade insertion sometimes don't apply until the user
        // first interacts with the screen, which is exactly when they're
        // mid-swipe on the hotbar and get yanked out to Home.
        setNeedsUpdateOfHomeIndicatorAutoHidden()
        setNeedsUpdateOfScreenEdgesDeferringSystemGestures()
    }

    // No `supportedInterfaceOrientations` override — the AppDelegate is the
    // single source of truth, switched dynamically by `OrientationHelper`.
    // Hardcoding `.landscape` here would block `requestGeometryUpdate(.portrait)`
    // on exit (iOS intersects the VC's mask with the AppDelegate's).

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        applyLayout()
        lockOverlay.frame = view.bounds

        // Compose: prompt-text + button, vertically stacked, vertically
        // centred as a group. We size the label and button to their
        // intrinsic content, then place the label above the midline and
        // the button below by (groupHeight / 2), so the entire stack
        // optically centres on the screen.
        lockLabel.sizeToFit()
        let buttonSize = lockBackButton.sizeThatFits(view.bounds.size)
        let spacing: CGFloat = 24
        let groupHeight = lockLabel.bounds.height + spacing + buttonSize.height
        let groupTop = view.bounds.midY - groupHeight / 2

        lockLabel.frame = CGRect(
            x: view.bounds.midX - lockLabel.bounds.width / 2,
            y: groupTop,
            width: lockLabel.bounds.width,
            height: lockLabel.bounds.height
        )
        lockBackButton.frame = CGRect(
            x: view.bounds.midX - buttonSize.width / 2,
            y: groupTop + lockLabel.bounds.height + spacing,
            width: buttonSize.width,
            height: buttonSize.height
        )
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
        // iOS-only movable close button — replaces the old floating top-right
        // chevron. Fires close on press (engaged=true) only.
        addInGameButton(id: "btn_close",  icon: .close,      behavior: .tap,    button: nil) {
            [weak self] engaged in
            if engaged { self?.closeRequested() }
        }

        // UI mode buttons
        addUIButton(id: "btn_ui_lmb",   icon: .mouseLeft,  behavior: .hold, button: .mouseLeft)
        addUIButton(id: "btn_ui_rmb",   icon: .mouseRight, behavior: .hold, button: .mouseRight)
        addUIButton(id: "btn_ui_q",     icon: .drop,       behavior: .tap,  button: .drop)
        addUIButton(id: "btn_ui_shift", icon: .shift,      behavior: .hold, button: .sneak)
        addUIButton(id: "btn_ui_esc",   icon: .esc,        behavior: .tap,  button: .esc)
        // UI-mode close mirrors in-game close.
        addUIButton(id: "btn_close",    icon: .close,      behavior: .tap,  button: nil) {
            [weak self] engaged in
            if engaged { self?.closeRequested() }
        }
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
        uiButtons[id] = v
    }

    // MARK: - Settings → widgets

    /// Apply every user-tunable setting to the touch views in one go. Called
    /// from `viewDidLoad` after widgets are built and from
    /// `rebuildIfSettingsChanged` on subsequent settings updates.
    private func applyCurrentSettingsToWidgets() {
        let s = settings.settings
        lookPad.inGameQuickClicks = s.inGameQuickClicks
        lookPad.uiQuickClicks = s.uiQuickClicks
        lookPad.cameraSensitivity = s.cameraSensitivity

        joystick.sprintFromJoystickEnabled = s.sprintFromJoystick
        joystick.sprintEngageFactor = s.sprintEngageFactor

        hotbar.swipeMode = profileStore.activeProfile.hotbarSwipeMode
        hotbar.hapticsEnabled = s.haptics
        hotbar.slotStep = s.hotbarRelativeStep

        inGameButtons.values.forEach { $0.hapticsEnabled = s.haptics }
        uiButtons.values.forEach { $0.hapticsEnabled = s.haptics }
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
        lockLabel.textAlignment = .center
        lockLabel.numberOfLines = 0
        lockOverlay.addSubview(lockLabel)

        // Pill button — plain title text + faint rounded-rect bg.
        // UIButton.Configuration.contentInsets handles the inner padding
        // symmetrically; baseBackgroundColor + cornerStyle does the chip
        // look. The button auto-sizes to fit (text height + insets),
        // so the title is reliably centred both axes.
        var cfg = UIButton.Configuration.plain()
        // Build the title via NSAttributedString → AttributedString
        // instead of either `titleTextAttributesTransformer` or
        // AttributedString's `.font` setter. Both of those would form a
        // `KeyPath<AttributeScopes.UIKitAttributes, …FontAttribute>` —
        // that key path isn't Sendable and trips Swift 6 strict-
        // concurrency warnings even when used at top-level (because
        // forming the key path itself is the issue, not capture). The
        // NSAttributedString.Key route stays in plain Foundation types
        // and produces the same UIButton appearance.
        let titleNS = NSAttributedString(
            string: L.key("controller.lock.back_to_home"),
            attributes: [.font: UIFont.systemFont(ofSize: 17, weight: .medium)]
        )
        cfg.attributedTitle = AttributedString(titleNS)
        cfg.baseForegroundColor = UIColor.white.withAlphaComponent(0.92)
        cfg.background.backgroundColor = UIColor.white.withAlphaComponent(0.10)
        cfg.background.cornerRadius = 12
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 28,
                                                    bottom: 12, trailing: 28)
        lockBackButton.configuration = cfg
        // Keep the highlight tint coherent with the pill background.
        lockBackButton.tintColor = .white
        lockBackButton.addTarget(self, action: #selector(lockBackTapped), for: .touchUpInside)
        lockOverlay.addSubview(lockBackButton)
    }

    /// Tap-target for the "back to host list" pill on the anti-mistouch
    /// overlay. Same as the close-widget path: marks the dismiss as user-
    /// initiated (so the auto-retry can't fight it) and bounces back.
    @objc private func lockBackTapped() {
        closeRequested()
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
        // Note: no standalone "back" button anymore — replaced by the
        // movable / resizable `btn_close` widget that ships in the default
        // layout and can be repositioned through the editor.
    }

    // MARK: - Demo mode UI
    //
    // Two extra views, both `isHidden` until `applyDemoMode(true)`:
    //   • demoModeButton — top-leading capsule, taps cycle through the
    //     three controller modes (replaces server-driven STATE_CHANGE).
    //   • demoDiagnosticLabel — bottom-centre monospace label with live
    //     input readout (active buttons, last delta, joystick, hotbar).

    private func layoutDemoControls() {
        // Mode-cycle button. Capsule chip styled like the lock-back
        // button so demo controls stylistically match the rest of the
        // landscape overlay.
        var cfg = UIButton.Configuration.plain()
        let titleNS = NSAttributedString(
            string: L.key("demo.mode_button"),
            attributes: [.font: UIFont.systemFont(ofSize: 13, weight: .semibold)]
        )
        cfg.attributedTitle = AttributedString(titleNS)
        cfg.image = UIImage(systemName: "arrow.triangle.2.circlepath")
        cfg.imagePadding = 6
        cfg.imagePlacement = .leading
        cfg.baseForegroundColor = UIColor.white.withAlphaComponent(0.92)
        cfg.background.backgroundColor = UIColor.systemOrange.withAlphaComponent(0.20)
        cfg.background.strokeColor = UIColor.systemOrange.withAlphaComponent(0.55)
        cfg.background.strokeWidth = 1
        cfg.background.cornerRadius = 14
        cfg.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12,
                                                    bottom: 6, trailing: 14)
        demoModeButton.configuration = cfg
        demoModeButton.tintColor = .white
        demoModeButton.translatesAutoresizingMaskIntoConstraints = false
        demoModeButton.isHidden = true
        demoModeButton.addTarget(self, action: #selector(demoCycleMode), for: .touchUpInside)
        view.addSubview(demoModeButton)
        NSLayoutConstraint.activate([
            demoModeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            demoModeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
        ])

        // Bottom-centre diagnostic label.
        demoDiagnosticLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        demoDiagnosticLabel.textColor = .white
        demoDiagnosticLabel.textAlignment = .center
        demoDiagnosticLabel.numberOfLines = 0
        demoDiagnosticLabel.shadowColor = UIColor.black.withAlphaComponent(0.7)
        demoDiagnosticLabel.shadowOffset = CGSize(width: 0, height: 1)
        demoDiagnosticLabel.translatesAutoresizingMaskIntoConstraints = false
        demoDiagnosticLabel.isHidden = true
        // Pass-through touches so widgets directly under the label still
        // receive taps. The label is purely decorative.
        demoDiagnosticLabel.isUserInteractionEnabled = false
        view.addSubview(demoDiagnosticLabel)
        NSLayoutConstraint.activate([
            demoDiagnosticLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            demoDiagnosticLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
            demoDiagnosticLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            demoDiagnosticLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
        ])
    }

    private func applyDemoMode(_ isDemo: Bool) {
        demoModeButton.isHidden = !isDemo
        demoDiagnosticLabel.isHidden = !isDemo
        if isDemo {
            startDemoPolling()
            // First-time tutorial for whichever mode we land in
            // (`antiMistouch` on connect).
            showDemoTutorialIfNeeded(for: session.mode)
        } else {
            stopDemoPolling()
        }
    }

    private func startDemoPolling() {
        stopDemoPolling()
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + .milliseconds(33),
                       repeating: .milliseconds(33))
        timer.setEventHandler { [weak self] in
            self?.refreshDemoDiagnostic()
        }
        timer.resume()
        demoPollTimer = timer
    }

    private func stopDemoPolling() {
        demoPollTimer?.cancel()
        demoPollTimer = nil
    }

    private func refreshDemoDiagnostic() {
        let snap = session.demoInputState.snapshot()
        // Build a multi-line live readout. All fields are clamped to one
        // line each so the bottom box doesn't grow unbounded.
        var lines: [String] = []

        // Active buttons row
        if snap.activeButtonIDs.isEmpty {
            lines.append(L.key("demo.line.no_buttons"))
        } else {
            let names = snap.activeButtonIDs
                .sorted()
                .map { Self.demoButtonName(for: $0) }
                .joined(separator: " · ")
            lines.append(String(format: L.key("demo.line.active_buttons"), names))
        }

        // Joystick row (only show if non-zero so the panel isn't noisy)
        let jx = snap.joystick.0
        let jy = snap.joystick.1
        if abs(jx) > 0.01 || abs(jy) > 0.01 {
            lines.append(String(format: L.key("demo.line.joystick"), jx, jy))
        }

        // Look delta row
        let (dx, dy) = snap.lastDelta
        let (ax, ay) = snap.accumulatedDelta
        lines.append(String(format: L.key("demo.line.look_delta"), dx, dy, ax, ay))

        // Hotbar slot (1-indexed for humans)
        if snap.lastHotbarSlot >= 0 {
            lines.append(String(format: L.key("demo.line.hotbar"), snap.lastHotbarSlot + 1))
        }

        let text = lines.joined(separator: "\n")
        // Avoid layout churn when nothing changed.
        if text != demoDiagnosticLabel.text {
            demoDiagnosticLabel.text = text
        }
    }

    @objc private func demoCycleMode() {
        let next: ControllerMode
        switch session.mode {
        case .antiMistouch: next = .inGame
        case .inGame:       next = .uiInteract
        case .uiInteract:   next = .antiMistouch
        }
        session.setDemoMode(next)
        showDemoTutorialIfNeeded(for: next)
    }

    /// Best-effort short label for a button id. Falls back to the raw hex
    /// for any id we don't have a friendly name for (forward-compat).
    private static func demoButtonName(for id: UInt8) -> String {
        switch id {
        case 0x01: return "LMB"
        case 0x02: return "RMB"
        case 0x10: return "Jump"
        case 0x11: return "Sneak"
        case 0x12: return "Sprint"
        case 0x20: return "Inv"
        case 0x21: return "Drop"
        case 0x22: return "Swap"
        case 0x30: return "Esc"
        case 0x40...0x48: return "Slot\(Int(id - 0x40) + 1)"
        default: return String(format: "0x%02X", id)
        }
    }

    // MARK: - Demo tutorial overlay

    private func userDefaultsKey(for mode: ControllerMode) -> String {
        switch mode {
        case .antiMistouch: return "demo.tutorial.shown.locked"
        case .inGame:       return "demo.tutorial.shown.inGame"
        case .uiInteract:   return "demo.tutorial.shown.uiInteract"
        }
    }

    private func showDemoTutorialIfNeeded(for mode: ControllerMode) {
        let key = userDefaultsKey(for: mode)
        if UserDefaults.standard.bool(forKey: key) { return }
        UserDefaults.standard.set(true, forKey: key)
        presentDemoTutorial(for: mode)
    }

    private func presentDemoTutorial(for mode: ControllerMode) {
        // Tear down any earlier tutorial first (mode flips can stack).
        demoTutorialOverlay?.removeFromSuperview()

        let dim = UIView()
        dim.backgroundColor = UIColor.black.withAlphaComponent(0.78)
        dim.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(dim)
        NSLayoutConstraint.activate([
            dim.topAnchor.constraint(equalTo: view.topAnchor),
            dim.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            dim.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        let card = UIView()
        card.backgroundColor = UIColor(white: 0.10, alpha: 0.96)
        card.layer.cornerRadius = 16
        card.layer.cornerCurve = .continuous
        card.layer.borderColor = UIColor.systemOrange.withAlphaComponent(0.55).cgColor
        card.layer.borderWidth = 1
        card.translatesAutoresizingMaskIntoConstraints = false
        dim.addSubview(card)
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: dim.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: dim.centerYAnchor),
            card.widthAnchor.constraint(lessThanOrEqualTo: dim.widthAnchor, multiplier: 0.7),
            card.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
        ])

        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 10
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -22),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -24),
        ])

        // Header: "Demo Mode — current mode name"
        let header = UILabel()
        header.text = String(format: L.key("demo.tutorial.header"), Self.modeName(mode))
        header.textColor = .systemOrange
        header.font = .systemFont(ofSize: 18, weight: .bold)
        header.textAlignment = .center
        header.numberOfLines = 0
        stack.addArrangedSubview(header)

        // Generic blurb (always shown).
        let intro = UILabel()
        intro.text = L.key("demo.tutorial.intro")
        intro.textColor = UIColor.white.withAlphaComponent(0.92)
        intro.font = .systemFont(ofSize: 14, weight: .regular)
        intro.textAlignment = .center
        intro.numberOfLines = 0
        stack.addArrangedSubview(intro)

        // Per-mode body.
        let body = UILabel()
        body.text = Self.tutorialBody(for: mode)
        body.textColor = UIColor.white.withAlphaComponent(0.85)
        body.font = .systemFont(ofSize: 13, weight: .regular)
        body.textAlignment = .natural
        body.numberOfLines = 0
        stack.addArrangedSubview(body)

        // Dismiss button.
        let dismissBtn = UIButton(type: .system)
        var btnCfg = UIButton.Configuration.filled()
        let btnTitle = NSAttributedString(
            string: L.key("demo.tutorial.dismiss"),
            attributes: [.font: UIFont.systemFont(ofSize: 14, weight: .semibold)]
        )
        btnCfg.attributedTitle = AttributedString(btnTitle)
        btnCfg.baseBackgroundColor = .systemOrange
        btnCfg.baseForegroundColor = .white
        btnCfg.cornerStyle = .capsule
        btnCfg.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 22,
                                                       bottom: 8, trailing: 22)
        dismissBtn.configuration = btnCfg
        dismissBtn.addTarget(self, action: #selector(dismissDemoTutorial), for: .touchUpInside)
        stack.addArrangedSubview(dismissBtn)

        // Tap anywhere on the dim layer (outside card) also dismisses.
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissDemoTutorial))
        dim.addGestureRecognizer(tap)
        // Don't let taps inside the card propagate up and dismiss the
        // whole thing (we want the user to be able to read it).
        let cardTapBlocker = UITapGestureRecognizer(target: nil, action: nil)
        cardTapBlocker.cancelsTouchesInView = true
        card.addGestureRecognizer(cardTapBlocker)

        demoTutorialOverlay = dim
    }

    @objc private func dismissDemoTutorial() {
        demoTutorialOverlay?.removeFromSuperview()
        demoTutorialOverlay = nil
    }

    private static func modeName(_ m: ControllerMode) -> String {
        switch m {
        case .antiMistouch: return L.key("demo.mode.locked")
        case .inGame:       return L.key("demo.mode.in_game")
        case .uiInteract:   return L.key("demo.mode.ui")
        }
    }

    private static func tutorialBody(for m: ControllerMode) -> String {
        switch m {
        case .antiMistouch: return L.key("demo.tutorial.body.locked")
        case .inGame:       return L.key("demo.tutorial.body.in_game")
        case .uiInteract:   return L.key("demo.tutorial.body.ui")
        }
    }

    // MARK: - Close request (from btn_close widget)

    private func closeRequested() {
        userInitiatedDismiss = true
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
            // Surface retry attempts in the HUD so the user knows we're
            // chasing a flaky link rather than silently spinning.
            if retryCount > 0 {
                parts = ["Reconnecting (\(retryCount)/\(maxRetries))…"]
            } else {
                parts = ["Connecting…"]
            }
        case .connected:
            let modeStr: String
            switch session.mode {
            case .inGame:        modeStr = "in-game"
            case .uiInteract:    modeStr = "UI"
            case .antiMistouch:  modeStr = "locked"
            }
            let rttStr = rtt.map { "\($0)ms" } ?? "—"
            let transportStr: String
            if session.isDemoMode {
                // In simulator we don't actually move bytes — surface
                // that to the App reviewer (and to ourselves) so it's
                // unambiguous this isn't a real network session.
                transportStr = "DEMO/SIMULATED"
            } else {
                // Distinguish UDP (the low-latency camera path) from the
                // TCP-framed fallback. If users report "look is laggy",
                // the first thing to check is whether this says
                // "Wi-Fi/UDP" or "Wi-Fi/TCP".
                transportStr = session.isCameraUDP ? "Wi-Fi/UDP" : "Wi-Fi/TCP"
            }
            parts = [transportStr, modeStr, rttStr]
        case .disconnected:
            parts = ["Disconnected"]
        case .failed(let reason):
            parts = ["Failed: \(reason)"]
        }
        hud.text = "\(prefix) " + parts.joined(separator: " · ")
    }

    // MARK: - Session state + retry

    private func handleSessionState(_ state: ControllerSession.State) {
        switch state {
        case .connected:
            hasEverConnected = true
            lastConnectedAt = Date()
            retryCount = 0
        case .failed:
            // Initial-connect or mid-session hard failure. The two
            // scenarios that bring us here:
            //
            //  1. HELLO_ACK timeout — `HybridTransport.connect` threw
            //     because the server didn't respond inside the handshake
            //     window. Happens intermittently on iOS when NWConnection
            //     reaches .ready a hair before the server's accept loop
            //     dequeues the socket, so HELLO either lands in a stalled
            //     read buffer or the response packet gets reordered. The
            //     server is almost always reachable on the next attempt.
            //
            //  2. Server actively rejected — `serverBusy` or
            //     `protocolMismatch`. These are deterministic; retrying
            //     won't fix them and we should surface the error and
            //     dismiss.
            //
            // We can't tell (1) from (2) by inspecting State.failed alone
            // (the reason string is human-formatted), but retrying a hard
            // reject just gets the same reject back instantly — the user
            // sees a slightly delayed bounce instead of an instant one.
            // The cost of the extra attempt is low; the win when it WAS
            // case (1) is large. Retry up to `maxRetries`, then dismiss.
            if !userInitiatedDismiss && retryCount < maxRetries {
                retryCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self else { return }
                    Task { await self.session.connect(host: self.host.ip, port: self.host.port) }
                }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                self?.onDismiss()
            }
        case .disconnected:
            // iOS-specific: NWConnection sometimes drops the TCP within
            // ~1–2 s of handshake, before the first PING/PONG round-trip
            // completes. RTT stays "—" and the modal would otherwise pop
            // away with zero recovery attempt. Retry up to `maxRetries`
            // times if the disconnect was short-lived and the user didn't
            // ask to close.
            let recent = lastConnectedAt.map { Date().timeIntervalSince($0) < 5 } ?? false
            if !userInitiatedDismiss && recent && retryCount < maxRetries {
                retryCount += 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                    guard let self else { return }
                    Task { await self.session.connect(host: self.host.ip, port: self.host.port) }
                }
                return
            }
            // Out of retries / not transient → fall through to the
            // graceful-exit timer. Re-check state inside the delay so
            // a recovery during the grace window cancels the dismiss.
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
        applyCurrentSettingsToWidgets()
        applyLayout()
    }
}
