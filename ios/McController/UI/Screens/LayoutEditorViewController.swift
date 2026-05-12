import UIKit

/// Fullscreen landscape layout editor that renders the real controller widgets
/// in edit mode. Mirrors the Android `LayoutEditorActivity`:
///   - Top floating pill: title + Reset + Cancel + Save
///   - Chevron pill above the top pill: collapses both toolbars
///   - Bottom floating pill (visible when a widget is selected): widget label
///     + Reset Position + Reset Size
///   - Center hint banner: "单击选中 · 拖动移动 · 双指任意位置缩放 · 空白处取消选中"
///   - Pinch on the canvas (anywhere) resizes the currently-selected widget
///   - Tap on empty canvas deselects
final class LayoutEditorViewController: UIViewController {

    private let mode: ControllerMode
    private let profileStore: ProfileStoreObservable
    private let settings: SettingsStore
    private let onClose: () -> Void

    // Working copy of the active profile — saved or discarded as a unit.
    private var workingProfile: LayoutProfile

    private var selectedID: String?
    private var toolbarsCollapsed: Bool = false

    // MARK: - View hierarchy

    private let canvas = UIView()                        // fullscreen edit surface (transparent)
    private var widgetViews: [String: EditableWidgetView] = [:]

    // Toolbars (floating pills)
    private let topPill = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let bottomPill = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let chevronPill = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private let hintBanner = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))

    private let titleLabel = UILabel()
    private let resetBtn = UIButton(type: .system)
    private let cancelBtn = UIButton(type: .system)
    private let saveBtn = UIButton(type: .system)
    private let chevronImage = UIImageView()
    private let selectedLabel = UILabel()
    private let resetPosBtn = UIButton(type: .system)
    private let resetSizeBtn = UIButton(type: .system)
    private let hintLabel = UILabel()

    // Gestures
    private var pinchRecognizer: UIPinchGestureRecognizer!
    private var canvasTapRecognizer: UITapGestureRecognizer!

    // Drag state
    private var dragStartLocation: CGPoint?
    private var dragStartSpec: WidgetSpec?
    private var didCrossSlop: Bool = false
    /// Tracks which widget is currently being panned (single-finger drag).
    /// Used by `UIGestureRecognizerDelegate.shouldReceive` to reject touches
    /// that land on OTHER widgets mid-drag so a stray cross-finger doesn't
    /// transfer the selection or scramble the move.
    private var panningWidget: EditableWidgetView?

    // MARK: - Init

    init(mode: ControllerMode,
         profileStore: ProfileStoreObservable,
         settings: SettingsStore,
         onClose: @escaping () -> Void) {
        self.mode = mode
        self.profileStore = profileStore
        self.settings = settings
        self.workingProfile = profileStore.activeProfile
        self.onClose = onClose
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }

    // Deliberately NO `supportedInterfaceOrientations` override:
    //   - The whole orientation gate is funnelled through
    //     `AppDelegate.allowedOrientations` (queried via
    //     `application(_:supportedInterfaceOrientationsFor:)`).
    //   - Overriding it here to `.landscape` blocked the system from
    //     accepting `requestGeometryUpdate(.portrait)` on exit because iOS
    //     intersects this VC's supported set with the AppDelegate's and
    //     refused rotations outside the intersection — which manifested as
    //     "exit doesn't rotate back" + "re-entry doesn't rotate to landscape
    //     because the prior cached value is stale".

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0x21 / 255, alpha: 1) // matches Android #212121

        canvas.frame = view.bounds
        canvas.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        canvas.backgroundColor = .clear
        view.addSubview(canvas)

        buildWidgetsForMode()
        buildToolbars()

        // Pinch anywhere on the screen to resize the selected widget.
        pinchRecognizer = UIPinchGestureRecognizer(target: self, action: #selector(onPinch(_:)))
        pinchRecognizer.delegate = self
        view.addGestureRecognizer(pinchRecognizer)

        // Tap on empty canvas → deselect.
        canvasTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(onCanvasTap(_:)))
        canvasTapRecognizer.delegate = self
        canvasTapRecognizer.cancelsTouchesInView = false
        canvas.addGestureRecognizer(canvasTapRecognizer)

        updateSelectionUI()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        layoutAllWidgets()
        positionToolbars()
    }

    // MARK: - Build widgets

    private func buildWidgetsForMode() {
        let layout = currentLayout()
        for (id, _) in layout.widgets {
            let view = makeWidgetView(id: id)
            view.isEditing = true
            canvas.addSubview(view)
            widgetViews[id] = view

            // Matches Android: the joystick is rendered but not selectable /
            // movable / resizable in v3. Skip attaching recognisers AND
            // disable user interaction so taps in its zone fall through to
            // the canvas (which deselects the active widget).
            if id == "joystick" {
                view.isUserInteractionEnabled = false
                continue
            }

            // Pan recognizer for drag-to-move. Locked to single-finger so two-
            // finger gestures fall through to the canvas-level pinch.
            let pan = UIPanGestureRecognizer(target: self, action: #selector(onWidgetPan(_:)))
            pan.delegate = self
            pan.minimumNumberOfTouches = 1
            pan.maximumNumberOfTouches = 1
            view.addGestureRecognizer(pan)

            // Tap recognizer for select.
            let tap = UITapGestureRecognizer(target: self, action: #selector(onWidgetTap(_:)))
            tap.delegate = self
            view.addGestureRecognizer(tap)
        }
    }

    private func makeWidgetView(id: String) -> EditableWidgetView {
        if id == "joystick" {
            return JoystickTouchView()
        } else if id == "hotbar" {
            let h = HotbarTouchView()
            h.swipeMode = workingProfile.hotbarSwipeMode
            return h
        } else {
            let v = ActionButtonTouchView(widgetID: id)
            v.widgetIcon = widgetIcon(for: id)
            v.behavior = isToggleButton(id: id) ? .toggle : .hold
            return v
        }
    }

    private func widgetIcon(for id: String) -> WidgetIcon? {
        switch id {
        case "btn_lmb",    "btn_ui_lmb":    return .mouseLeft
        case "btn_rmb",    "btn_ui_rmb":    return .mouseRight
        case "btn_jump":                    return .jump
        case "btn_sneak":                   return .sneak
        case "btn_sprint":                  return .sprint
        case "btn_inv":                     return .inventory
        case "btn_swap":                    return .swap
        case "btn_esc",    "btn_ui_esc":    return .esc
        case "btn_ui_q":                    return .drop
        case "btn_ui_shift":                return .shift
        case "btn_close":                   return .close
        default:                            return nil
        }
    }

    private func isToggleButton(id: String) -> Bool {
        id == "btn_sneak" || id == "btn_sprint"
    }

    // MARK: - Toolbars

    private func buildToolbars() {
        // Top pill — title + reset + cancel + save
        topPill.layer.cornerRadius = 20
        topPill.layer.cornerCurve = .continuous
        topPill.clipsToBounds = true
        topPill.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topPill)

        titleLabel.text = mode == .inGame
            ? L.key("editor.title_in_game")
            : L.key("editor.title_ui")
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .white

        styleTextButton(resetBtn, title: L.key("editor.reset"))
        resetBtn.addTarget(self, action: #selector(tapResetLayout), for: .touchUpInside)

        styleTextButton(cancelBtn, title: L.key("common.cancel"))
        cancelBtn.addTarget(self, action: #selector(tapCancel), for: .touchUpInside)

        styleTonalButton(saveBtn, title: L.key("common.save"))
        saveBtn.addTarget(self, action: #selector(tapSave), for: .touchUpInside)

        let topStack = UIStackView(arrangedSubviews: [titleLabel, resetBtn, cancelBtn, saveBtn])
        topStack.axis = .horizontal
        topStack.spacing = 16
        topStack.alignment = .center
        topStack.translatesAutoresizingMaskIntoConstraints = false
        topPill.contentView.addSubview(topStack)
        NSLayoutConstraint.activate([
            topStack.topAnchor.constraint(equalTo: topPill.contentView.topAnchor, constant: 6),
            topStack.bottomAnchor.constraint(equalTo: topPill.contentView.bottomAnchor, constant: -6),
            topStack.leadingAnchor.constraint(equalTo: topPill.contentView.leadingAnchor, constant: 16),
            topStack.trailingAnchor.constraint(equalTo: topPill.contentView.trailingAnchor, constant: -16),
        ])

        // Chevron pill — collapse/expand both toolbars.
        chevronPill.layer.cornerRadius = 11
        chevronPill.layer.cornerCurve = .continuous
        chevronPill.clipsToBounds = true
        chevronPill.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chevronPill)

        chevronImage.image = UIImage(systemName: "chevron.up",
                                     withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        chevronImage.tintColor = UIColor.white.withAlphaComponent(0.85)
        chevronImage.contentMode = .center
        chevronImage.translatesAutoresizingMaskIntoConstraints = false
        chevronPill.contentView.addSubview(chevronImage)
        NSLayoutConstraint.activate([
            chevronImage.centerXAnchor.constraint(equalTo: chevronPill.contentView.centerXAnchor),
            chevronImage.centerYAnchor.constraint(equalTo: chevronPill.contentView.centerYAnchor),
        ])
        let chevronTap = UITapGestureRecognizer(target: self, action: #selector(tapChevron))
        chevronPill.addGestureRecognizer(chevronTap)
        chevronPill.isUserInteractionEnabled = true

        // Bottom pill — selected-widget label + reset position/size
        bottomPill.layer.cornerRadius = 20
        bottomPill.layer.cornerCurve = .continuous
        bottomPill.clipsToBounds = true
        bottomPill.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottomPill)

        selectedLabel.text = ""
        selectedLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        selectedLabel.textColor = UIColor(red: 0xE8/255, green: 0xC5/255, blue: 0x47/255, alpha: 1)

        styleTextButton(resetPosBtn, title: L.key("editor.reset_position"))
        resetPosBtn.addTarget(self, action: #selector(tapResetPosition), for: .touchUpInside)

        styleTextButton(resetSizeBtn, title: L.key("editor.reset_size"))
        resetSizeBtn.addTarget(self, action: #selector(tapResetSize), for: .touchUpInside)

        let botStack = UIStackView(arrangedSubviews: [selectedLabel, resetPosBtn, resetSizeBtn])
        botStack.axis = .horizontal
        botStack.spacing = 16
        botStack.alignment = .center
        botStack.translatesAutoresizingMaskIntoConstraints = false
        bottomPill.contentView.addSubview(botStack)
        NSLayoutConstraint.activate([
            botStack.topAnchor.constraint(equalTo: bottomPill.contentView.topAnchor, constant: 6),
            botStack.bottomAnchor.constraint(equalTo: bottomPill.contentView.bottomAnchor, constant: -6),
            botStack.leadingAnchor.constraint(equalTo: bottomPill.contentView.leadingAnchor, constant: 16),
            botStack.trailingAnchor.constraint(equalTo: bottomPill.contentView.trailingAnchor, constant: -16),
        ])

        // Hint banner (center)
        hintBanner.layer.cornerRadius = 14
        hintBanner.layer.cornerCurve = .continuous
        hintBanner.clipsToBounds = true
        hintBanner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hintBanner)

        hintLabel.text = L.key("editor.hint")
        hintLabel.font = .systemFont(ofSize: 14, weight: .medium)
        hintLabel.textColor = UIColor.white.withAlphaComponent(0.85)
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintBanner.contentView.addSubview(hintLabel)
        NSLayoutConstraint.activate([
            hintLabel.topAnchor.constraint(equalTo: hintBanner.contentView.topAnchor, constant: 10),
            hintLabel.bottomAnchor.constraint(equalTo: hintBanner.contentView.bottomAnchor, constant: -10),
            hintLabel.leadingAnchor.constraint(equalTo: hintBanner.contentView.leadingAnchor, constant: 22),
            hintLabel.trailingAnchor.constraint(equalTo: hintBanner.contentView.trailingAnchor, constant: -22),
        ])
        NSLayoutConstraint.activate([
            hintBanner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            hintBanner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        // Constraints for the floating bars
        NSLayoutConstraint.activate([
            topPill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            topPill.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),

            chevronPill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            chevronPill.bottomAnchor.constraint(equalTo: topPill.topAnchor, constant: -4),
            chevronPill.widthAnchor.constraint(equalToConstant: 56),
            chevronPill.heightAnchor.constraint(equalToConstant: 22),

            bottomPill.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            bottomPill.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
        ])
    }

    private func positionToolbars() {
        // Nothing dynamic — auto-layout handles the placement.
    }

    private func styleTextButton(_ b: UIButton, title: String) {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = .systemFont(ofSize: 14, weight: .medium)
            return out
        }
        b.configuration = config
    }

    private func styleTonalButton(_ b: UIButton, title: String) {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.baseForegroundColor = .black
        config.baseBackgroundColor = .white
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = .systemFont(ofSize: 14, weight: .semibold)
            return out
        }
        b.configuration = config
    }

    // MARK: - Selection

    private func selectWidget(_ id: String?) {
        guard selectedID != id else { return }
        if let old = selectedID, let v = widgetViews[old] {
            v.isSelectedInEditor = false
        }
        selectedID = id
        if let new = id, let v = widgetViews[new] {
            v.isSelectedInEditor = true
        }
        updateSelectionUI()
    }

    private func updateSelectionUI() {
        let id = selectedID
        UIView.animate(withDuration: 0.18) { [self] in
            bottomPill.alpha = id != nil ? 1 : 0
        }
        bottomPill.isUserInteractionEnabled = id != nil
        selectedLabel.text = id.map(humanizedID(_:)) ?? ""
        resetSizeBtn.isHidden = !(id.map { DefaultLayouts.resizableIDs.contains($0) } ?? false)
    }

    private func humanizedID(_ id: String) -> String {
        switch id {
        case "btn_lmb":    return L.key("widget.lmb")
        case "btn_rmb":    return L.key("widget.rmb")
        case "btn_jump":   return L.key("widget.jump")
        case "btn_sneak":  return L.key("widget.sneak")
        case "btn_sprint": return L.key("widget.sprint")
        case "btn_inv":    return L.key("widget.inv")
        case "btn_swap":   return L.key("widget.swap")
        case "btn_esc":    return L.key("widget.esc")
        case "btn_ui_lmb": return L.key("widget.ui_lmb")
        case "btn_ui_rmb": return L.key("widget.ui_rmb")
        case "btn_ui_q":   return L.key("widget.ui_q")
        case "btn_ui_shift": return L.key("widget.ui_shift")
        case "btn_ui_esc": return L.key("widget.ui_esc")
        case "btn_close":  return L.key("widget.close")
        case "joystick":   return L.key("widget.joystick")
        case "hotbar":     return L.key("widget.hotbar")
        default:           return id
        }
    }

    // MARK: - Layout application

    private func currentLayout() -> ModeLayout {
        mode == .inGame ? workingProfile.inGame : workingProfile.uiMode
    }

    private func mutateLayout(_ mutate: (inout ModeLayout) -> Void) {
        var layout = currentLayout()
        mutate(&layout)
        if mode == .inGame {
            workingProfile.inGame = layout
        } else {
            workingProfile.uiMode = layout
        }
    }

    private var widgetBounds: CGRect {
        // Inset by safe area so widgets don't sit under the Dynamic Island
        // or the home indicator. The canvas itself stays full-screen.
        view.bounds.inset(by: view.safeAreaInsets)
    }

    private func layoutAllWidgets() {
        let layout = currentLayout()
        let bounds = widgetBounds
        for (id, spec) in layout.widgets {
            guard let v = widgetViews[id] else { continue }
            v.frame = LayoutApplier.frame(for: spec, in: layout, bounds: bounds)
        }
    }

    private func reapplyWidget(_ id: String) {
        guard let v = widgetViews[id],
              let spec = currentLayout().widgets[id] else { return }
        v.frame = LayoutApplier.frame(for: spec, in: currentLayout(), bounds: widgetBounds)
    }

    // MARK: - Pan: drag widgets

    @objc private func onWidgetPan(_ recognizer: UIPanGestureRecognizer) {
        guard let widget = recognizer.view as? EditableWidgetView else { return }
        // Joystick is intentionally non-movable in v3 — leaves it as a fixed
        // activation zone (matches Android).
        if widget.widgetID == "joystick" { return }

        let translation = recognizer.translation(in: view)

        switch recognizer.state {
        case .began:
            dragStartLocation = recognizer.location(in: view)
            dragStartSpec = currentLayout().widgets[widget.widgetID]
            didCrossSlop = false
            panningWidget = widget
            selectWidget(widget.widgetID)

        case .changed:
            guard let startSpec = dragStartSpec else { return }
            let distance = hypot(translation.x, translation.y)
            // Tap-vs-drag slop window — wait until finger crosses 8pt before
            // treating as drag, matching Android's `ViewConfiguration.scaledTouchSlop`.
            if !didCrossSlop {
                guard distance > 8 else { return }
                didCrossSlop = true
                // Reset translation so the widget doesn't jump by the slop
                // amount the moment we transition into drag mode.
                recognizer.setTranslation(.zero, in: view)
                return
            }

            let edgeSign: CGFloat
            switch startSpec.anchor {
            case .topStart, .bottomStart, .centerStart:  edgeSign = 1
            case .topEnd, .bottomEnd, .centerEnd:        edgeSign = -1
            // Centre anchors treat `edge` as a signed offset from the canvas
            // centre (see LayoutApplier), so dragging right is positive.
            case .topCenter, .bottomCenter:              edgeSign = 1
            }
            let vertSign: CGFloat
            switch startSpec.anchor {
            case .topStart, .topCenter, .topEnd:               vertSign = 1
            case .bottomStart, .bottomCenter, .bottomEnd:      vertSign = -1
            case .centerStart, .centerEnd:                     vertSign = 1
            }
            // Edge-anchored widgets clamp to ≥ 0 (no off-screen).
            // Centre-anchored widgets allow negative (left of centre).
            let rawEdge = startSpec.edge + translation.x * edgeSign
            let newEdge = startSpec.anchor.isHorizontallyCentered ? rawEdge : max(0, rawEdge)
            let newVert = max(0, startSpec.vertical + translation.y * vertSign)

            mutateLayout { layout in
                var spec = startSpec
                spec.edge = newEdge
                spec.vertical = newVert
                layout.widgets[widget.widgetID] = spec
            }
            reapplyWidget(widget.widgetID)

        case .ended, .cancelled, .failed:
            dragStartSpec = nil
            dragStartLocation = nil
            didCrossSlop = false
            panningWidget = nil

        default:
            break
        }
    }

    // MARK: - Tap: select widget / deselect on empty

    @objc private func onWidgetTap(_ recognizer: UITapGestureRecognizer) {
        guard let widget = recognizer.view as? EditableWidgetView else { return }
        selectWidget(widget.widgetID)
    }

    @objc private func onCanvasTap(_ recognizer: UITapGestureRecognizer) {
        // Only fires when a widget-level recognizer didn't consume the event.
        selectWidget(nil)
    }

    // MARK: - Pinch: resize selected widget

    @objc private func onPinch(_ recognizer: UIPinchGestureRecognizer) {
        guard let id = selectedID, DefaultLayouts.resizableIDs.contains(id) else { return }
        if recognizer.state == .began {
            // Cancel any in-progress widget pan so pinch doesn't fight with
            // pan when 2 fingers land on a selected widget — without this,
            // the button visibly "twitches" because it's being translated
            // and scaled simultaneously.
            cancelActiveWidgetPans()
            dragStartSpec = currentLayout().widgets[id]
            return
        }
        guard recognizer.state == .changed else { return }
        guard let baseSpec = dragStartSpec else { return }
        let scale = recognizer.scale
        let newW = max(40, min(600, baseSpec.width * scale))
        let newH = baseSpec.height > 0 ? max(30, min(600, baseSpec.height * scale)) : 0

        mutateLayout { layout in
            var spec = baseSpec
            spec.width = newW
            spec.height = newH
            layout.widgets[id] = spec
        }
        reapplyWidget(id)
    }

    /// Toggle the `isEnabled` of every widget's pan recognizer off-then-on,
    /// which cancels any in-progress pan immediately. Called when pinch
    /// transitions to `.began` so pan + pinch can't run on the same finger.
    private func cancelActiveWidgetPans() {
        for widget in widgetViews.values {
            for r in widget.gestureRecognizers ?? [] where r is UIPanGestureRecognizer {
                r.isEnabled = false
                r.isEnabled = true
            }
        }
        panningWidget = nil
        dragStartLocation = nil
        didCrossSlop = false
    }

    // MARK: - Toolbar actions

    @objc private func tapSave() {
        // Apply only the edited mode to the active profile; leave the other
        // mode untouched.
        profileStore.updateActive { p in
            if mode == .inGame {
                p.inGame = workingProfile.inGame
            } else {
                p.uiMode = workingProfile.uiMode
            }
            // Hotbar swipe mode applies regardless of which side we're editing.
            p.hotbarSwipeMode = workingProfile.hotbarSwipeMode
        }
        prepareForExitFade()
        OrientationHelper.restorePortrait()
        onClose()
    }

    @objc private func tapCancel() {
        prepareForExitFade()
        OrientationHelper.restorePortrait()
        onClose()
    }

    /// Hide every child view immediately so the rotation-driven bounds change
    /// has nothing visible to reflow. SwiftUI's cross-fade is left with just
    /// the dark background to dissolve, which avoids the "buttons skating
    /// across the screen as the bounds change" artifact during exit.
    private func prepareForExitFade() {
        view.subviews.forEach { $0.isHidden = true }
    }

    @objc private func tapResetLayout() {
        mutateLayout { layout in
            layout = mode == .inGame ? DefaultLayouts.inGame : DefaultLayouts.uiMode
        }
        selectWidget(nil)
        layoutAllWidgets()
    }

    @objc private func tapResetPosition() {
        guard let id = selectedID else { return }
        let def = DefaultLayouts.inGame.widgets[id] ?? DefaultLayouts.uiMode.widgets[id]
        guard let def else { return }
        mutateLayout { layout in
            if var spec = layout.widgets[id] {
                spec.anchor = def.anchor
                spec.edge = def.edge
                spec.vertical = def.vertical
                layout.widgets[id] = spec
            }
        }
        reapplyWidget(id)
    }

    @objc private func tapResetSize() {
        guard let id = selectedID else { return }
        let def = DefaultLayouts.inGame.widgets[id] ?? DefaultLayouts.uiMode.widgets[id]
        guard let def else { return }
        mutateLayout { layout in
            if var spec = layout.widgets[id] {
                spec.width = def.width
                spec.height = def.height
                layout.widgets[id] = spec
            }
        }
        reapplyWidget(id)
    }

    @objc private func tapChevron() {
        toolbarsCollapsed.toggle()
        let topOffset: CGFloat = toolbarsCollapsed ? -(topPill.frame.maxY + 8) : 0
        let bottomOffset: CGFloat = toolbarsCollapsed ? (view.bounds.height - bottomPill.frame.minY + 8) : 0
        UIView.animate(withDuration: 0.22) { [self] in
            topPill.transform = CGAffineTransform(translationX: 0, y: topOffset)
            bottomPill.transform = CGAffineTransform(translationX: 0, y: bottomOffset)
            hintBanner.alpha = toolbarsCollapsed ? 0 : 1
            chevronImage.transform = CGAffineTransform(rotationAngle: toolbarsCollapsed ? .pi : 0)
        }
    }
}

// MARK: - GestureRecognizerDelegate

extension LayoutEditorViewController: UIGestureRecognizerDelegate {

    /// All editor gestures are mutually exclusive. Allowing pan + pinch to
    /// run simultaneously caused widgets to be translated AND scaled at the
    /// same time when 2 fingers landed on a selected button.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        return false
    }

    /// Block pan from starting (or restarting) while pinch is active.
    /// Combined with `cancelActiveWidgetPans()` inside `onPinch(.began)`,
    /// this guarantees a clean pinch-only resize.
    func gestureRecognizerShouldBegin(_ gr: UIGestureRecognizer) -> Bool {
        if gr is UIPanGestureRecognizer {
            switch pinchRecognizer.state {
            case .began, .changed: return false
            default: break
            }
        }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        // While a widget is being panned, ignore touches landing on other
        // widgets (or on the canvas) so a stray cross-finger doesn't
        // transfer selection or trigger a deselect mid-drag.
        if let panning = panningWidget {
            if let touchView = touch.view, touchView !== panning {
                return false
            }
        }
        // Canvas tap should only fire if the touch landed on the canvas itself
        // (not on a widget) — otherwise widget taps would also deselect.
        if gestureRecognizer === canvasTapRecognizer {
            return touch.view === canvas
        }
        return true
    }
}
