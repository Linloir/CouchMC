import SwiftUI
import AppKit
import Carbon.HIToolbox

/// Per-action key remapping. Mirrors the macOS *System Settings →
/// Keyboard → Keyboard Shortcuts* interaction style: each row shows a
/// human label + dimmed description, with a key-cap chip on the right
/// that you click to record a new key.
///
/// Two sections:
///   1. Movement — joystick directions (forward / back / left / right),
///      read every poll by `JoystickToWasdMapper`.
///   2. Action buttons — every ButtonId from the wire protocol (LMB,
///      RMB, jump, sneak, sprint, inventory, drop, swap hand, esc,
///      hotbar 1..9), read by `ButtonRouter`.
///
/// Capture flow:
///   - Click a chip → row enters "listening" state. The chip background
///     turns accent-tinted and shows the localized prompt
///     ("Press a key…").
///   - The next physical key-down (via local NSEvent monitor) gets
///     translated through `KeyCodes.canonicalByKeyCode` into a
///     symbolic name and committed. Esc cancels without changing the
///     binding. Modifier-only key-downs are ignored so the user can
///     hold Shift / Cmd while choosing without false captures.
///   - For LMB / RMB rows, three small "L / R / M" chips appear next to
///     the main chip *only while capturing* — you can't fire a real
///     mouse click without dismissing the picker, so on-screen mouse
///     buttons are the only sensible affordance.
///
/// All commits flow through `host.updateBindings(_:)` /
/// `host.updateMovementKeys(_:)`, which release any key still held under
/// the old mapping (no stuck keys after a mid-press rebind) and persist
/// to config.json immediately.
struct KeyBindingsView: View {

    @EnvironmentObject private var host: ServerHost
    @State private var showResetConfirm: Bool = false

    /// Which row is currently in capture mode (if any). The
    /// `MovementSlot.action` / `.movement` cases keep the two row kinds
    /// distinguishable without two parallel optionals.
    @State private var capturing: CaptureTarget? = nil

    /// Local key-down monitor active only while `capturing != nil`.
    /// `Any?` because `NSEvent.addLocalMonitorForEvents` returns an
    /// opaque token; we hand it back to `removeMonitor` on teardown.
    @State private var keyMonitor: Any? = nil

    var body: some View {
        Form {
            // ---- Movement ----
            Section {
                movementRow(slot: .forward,
                            label: L.get("bindings.movement.forward",       fallback: "Forward"),
                            desc:  L.get("bindings.movement.forward.desc",  fallback: "Joystick pushed up"))
                movementRow(slot: .back,
                            label: L.get("bindings.movement.back",          fallback: "Back"),
                            desc:  L.get("bindings.movement.back.desc",     fallback: "Joystick pulled down"))
                movementRow(slot: .left,
                            label: L.get("bindings.movement.left",          fallback: "Strafe left"),
                            desc:  L.get("bindings.movement.left.desc",     fallback: "Joystick pushed left"))
                movementRow(slot: .right,
                            label: L.get("bindings.movement.right",         fallback: "Strafe right"),
                            desc:  L.get("bindings.movement.right.desc",    fallback: "Joystick pushed right"))
            } header: {
                Text(L.get("bindings.section.movement", fallback: "Movement"))
            } footer: {
                Text(L.get("bindings.section.movement.footer",
                           fallback: "Click a key on the right to record a new physical key. Press Esc to cancel."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // ---- Action buttons ----
            Section {
                ForEach(ActionSpec.all, id: \.buttonId) { spec in
                    actionRow(spec: spec)
                }
            } header: {
                Text(L.get("bindings.section.actions", fallback: "Action buttons"))
            }

            // ---- Reset ----
            Section {
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        showResetConfirm = true
                    } label: {
                        Text(L.get("bindings.reset", fallback: "Reset all to defaults"))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(SidebarPage.bindings.title)
        .navigationSubtitle(SidebarPage.bindings.subtitle)
        .onDisappear(perform: stopCapture)
        .confirmationDialog(
            L.get("bindings.reset.confirm", fallback: "Reset all key bindings?"),
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button(L.get("bindings.reset", fallback: "Reset all to defaults"),
                   role: .destructive) {
                stopCapture()
                host.resetBindingsToDefaults()
                showResetConfirm = false
            }
            Button(L.get("common.cancel", fallback: "Cancel"),
                   role: .cancel) { showResetConfirm = false }
        } message: {
            Text(L.get("bindings.reset.confirm.msg",
                       fallback: "All bindings will go back to Minecraft's standard layout."))
        }
    }

    // MARK: - Capture targets

    /// Identifies which row is currently capturing a key. Action rows
    /// are addressed by their hex ButtonId; movement rows by enum slot.
    private enum CaptureTarget: Equatable {
        case action(String)
        case movement(MovementSlot)
    }

    private enum MovementSlot: Equatable {
        case forward, back, left, right
    }

    // MARK: - Movement row

    @ViewBuilder
    private func movementRow(slot: MovementSlot, label: String, desc: String) -> some View {
        let current = currentMovementSymbol(slot)
        let isCapturing = capturing == .movement(slot)
        rowShell(label: label, description: desc) {
            keyCap(label: displayLabel(forSymbol: current),
                   isCapturing: isCapturing) {
                toggleCapture(.movement(slot))
            }
        }
    }

    private func currentMovementSymbol(_ slot: MovementSlot) -> String {
        let m = host.config.movementKeys
        switch slot {
        case .forward: return m.forward
        case .back:    return m.back
        case .left:    return m.left
        case .right:   return m.right
        }
    }

    private func setMovement(_ slot: MovementSlot, symbol: String) {
        var keys = host.config.movementKeys
        switch slot {
        case .forward: keys.forward = symbol
        case .back:    keys.back    = symbol
        case .left:    keys.left    = symbol
        case .right:   keys.right   = symbol
        }
        host.updateMovementKeys(keys)
    }

    // MARK: - Action row

    /// Static description of one action button. Every row supports
    /// keyboard OR mouse-button bindings — the L/R/M mini chips appear
    /// during capture for all rows so e.g. "Hotbar 1" can be rebound to
    /// "middle mouse" if the user wants.
    private struct ActionSpec {
        let buttonId: String
        let labelKey: String
        let labelFallback: String
        let descKey: String
        let descFallback: String

        static let all: [ActionSpec] = [
            .init(buttonId: "0x01",
                  labelKey: "bindings.btn.mouse_left",  labelFallback: "Left click (LMB)",
                  descKey:  "bindings.btn.mouse_left.desc",  descFallback: "Triggered by the phone's LMB button"),
            .init(buttonId: "0x02",
                  labelKey: "bindings.btn.mouse_right", labelFallback: "Right click (RMB)",
                  descKey:  "bindings.btn.mouse_right.desc", descFallback: "Triggered by the phone's RMB button"),

            .init(buttonId: "0x10",
                  labelKey: "bindings.btn.jump",   labelFallback: "Jump",
                  descKey:  "bindings.btn.jump.desc",   descFallback: "Default Space"),
            .init(buttonId: "0x11",
                  labelKey: "bindings.btn.sneak",  labelFallback: "Sneak",
                  descKey:  "bindings.btn.sneak.desc",  descFallback: "Default Left Shift"),
            .init(buttonId: "0x12",
                  labelKey: "bindings.btn.sprint", labelFallback: "Sprint",
                  descKey:  "bindings.btn.sprint.desc", descFallback: "Default Left Ctrl"),

            .init(buttonId: "0x20",
                  labelKey: "bindings.btn.inventory", labelFallback: "Inventory",
                  descKey:  "bindings.btn.inventory.desc", descFallback: "Default E"),
            .init(buttonId: "0x21",
                  labelKey: "bindings.btn.drop",      labelFallback: "Drop item",
                  descKey:  "bindings.btn.drop.desc",      descFallback: "Default Q"),
            .init(buttonId: "0x22",
                  labelKey: "bindings.btn.swap_hand", labelFallback: "Swap hand",
                  descKey:  "bindings.btn.swap_hand.desc", descFallback: "Default F"),
            .init(buttonId: "0x30",
                  labelKey: "bindings.btn.esc",       labelFallback: "Esc / Pause",
                  descKey:  "bindings.btn.esc.desc",       descFallback: "Default Esc"),

            .init(buttonId: "0x40", labelKey: "bindings.btn.hotbar1", labelFallback: "Hotbar 1",
                  descKey: "bindings.btn.hotbar1.desc", descFallback: "Default 1"),
            .init(buttonId: "0x41", labelKey: "bindings.btn.hotbar2", labelFallback: "Hotbar 2",
                  descKey: "bindings.btn.hotbar2.desc", descFallback: "Default 2"),
            .init(buttonId: "0x42", labelKey: "bindings.btn.hotbar3", labelFallback: "Hotbar 3",
                  descKey: "bindings.btn.hotbar3.desc", descFallback: "Default 3"),
            .init(buttonId: "0x43", labelKey: "bindings.btn.hotbar4", labelFallback: "Hotbar 4",
                  descKey: "bindings.btn.hotbar4.desc", descFallback: "Default 4"),
            .init(buttonId: "0x44", labelKey: "bindings.btn.hotbar5", labelFallback: "Hotbar 5",
                  descKey: "bindings.btn.hotbar5.desc", descFallback: "Default 5"),
            .init(buttonId: "0x45", labelKey: "bindings.btn.hotbar6", labelFallback: "Hotbar 6",
                  descKey: "bindings.btn.hotbar6.desc", descFallback: "Default 6"),
            .init(buttonId: "0x46", labelKey: "bindings.btn.hotbar7", labelFallback: "Hotbar 7",
                  descKey: "bindings.btn.hotbar7.desc", descFallback: "Default 7"),
            .init(buttonId: "0x47", labelKey: "bindings.btn.hotbar8", labelFallback: "Hotbar 8",
                  descKey: "bindings.btn.hotbar8.desc", descFallback: "Default 8"),
            .init(buttonId: "0x48", labelKey: "bindings.btn.hotbar9", labelFallback: "Hotbar 9",
                  descKey: "bindings.btn.hotbar9.desc", descFallback: "Default 9"),
        ]
    }

    @ViewBuilder
    private func actionRow(spec: ActionSpec) -> some View {
        let current = host.config.bindings[spec.buttonId] ?? ButtonBinding()
        let isCapturing = capturing == .action(spec.buttonId)
        rowShell(label: L.get(spec.labelKey, fallback: spec.labelFallback),
                 description: L.get(spec.descKey, fallback: spec.descFallback)) {
            HStack(spacing: 6) {
                // Every action row supports binding to a mouse button.
                // The L/R/M mini chips only show while in capture mode —
                // they'd otherwise clutter the dominant keyboard-bound
                // rows. A real mouse-down can't be captured (it would
                // steal the dismiss-click before the monitor sees it),
                // so on-screen mini buttons are the only sensible
                // affordance for "I want this row to fire a mouse
                // button when the phone button is pressed."
                if isCapturing {
                    mouseMiniButton(spec.buttonId, button: "left",
                                    glyph: "L",
                                    current: current)
                    mouseMiniButton(spec.buttonId, button: "right",
                                    glyph: "R",
                                    current: current)
                    mouseMiniButton(spec.buttonId, button: "middle",
                                    glyph: "M",
                                    current: current)
                }
                keyCap(label: displayLabel(for: current),
                       isCapturing: isCapturing) {
                    toggleCapture(.action(spec.buttonId))
                }
            }
        }
    }

    private func setBinding(_ buttonId: String, _ binding: ButtonBinding) {
        var all = host.config.bindings
        all[buttonId] = binding
        host.updateBindings(all)
    }

    // MARK: - Chip + mouse mini-button

    /// The clickable key-cap chip. Two visual states:
    ///   - idle: dim background, shows the current binding label.
    ///   - capturing: accent-tinted background, shows the prompt.
    @ViewBuilder
    private func keyCap(label: String, isCapturing: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(isCapturing
                 ? L.get("bindings.capture.prompt", fallback: "Press a key…")
                 : label)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(isCapturing ? Color.accentColor : Color.primary)
                .padding(.horizontal, 12)
                .frame(minWidth: 100, minHeight: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isCapturing
                              ? Color.accentColor.opacity(0.18)
                              : Color.secondary.opacity(0.12))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isCapturing
                                ? Color.accentColor.opacity(0.55)
                                : Color.clear,
                                lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    /// Smaller chip that appears only during LMB/RMB capture so the
    /// user can pick "mouse left/right/middle" without actually firing
    /// a mouse-down (which would steal the click before we see it).
    @ViewBuilder
    private func mouseMiniButton(_ buttonId: String,
                                 button: String,
                                 glyph: String,
                                 current: ButtonBinding) -> some View {
        let isSelected = current.type == "mouse"
            && (current.button?.lowercased() == button.lowercased())
        Button {
            setBinding(buttonId, ButtonBinding(type: "mouse", scancode: nil, button: button))
            stopCapture()
        } label: {
            Text(glyph)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .frame(width: 22, height: 22)
                .foregroundStyle(isSelected ? .white : Color.primary)
                .background(
                    Circle().fill(isSelected
                                  ? Color.accentColor
                                  : Color.secondary.opacity(0.18))
                )
        }
        .buttonStyle(.plain)
        .help({
            switch button {
            case "left":   return L.get("bindings.key.left_mouse",   fallback: "Left mouse")
            case "right":  return L.get("bindings.key.right_mouse",  fallback: "Right mouse")
            case "middle": return L.get("bindings.key.middle_mouse", fallback: "Middle mouse")
            default:       return button
            }
        }())
    }

    // MARK: - Capture lifecycle

    /// Toggle capture state for `target`. Calling on the already-active
    /// row cancels; calling on a different row switches focus to it.
    private func toggleCapture(_ target: CaptureTarget) {
        if capturing == target {
            stopCapture()
            return
        }
        stopCapture() // tear down any prior monitor before installing the new one
        capturing = target
        // Also monitor `flagsChanged` so the user can bind a *pure*
        // modifier key (Shift / Ctrl / Cmd / Option). `keyDown` only
        // fires for character keys; modifiers fire `flagsChanged`
        // on both press *and* release — we filter to press-only by
        // checking whether the matching modifier flag is now ON.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { ev in
            if ev.type == .flagsChanged {
                if isModifierPress(ev) { handleCapturedKey(ev) }
                return nil
            }
            handleCapturedKey(ev)
            // Swallow so the typed key doesn't reach any other control.
            return nil
        }
    }

    /// True when a `.flagsChanged` event is a press (modifier added),
    /// false when it's a release (modifier removed). Decided by
    /// comparing the modifier-flag bit that corresponds to the event's
    /// `keyCode` against the event's reported `modifierFlags`.
    private func isModifierPress(_ ev: NSEvent) -> Bool {
        let flags = ev.modifierFlags
        switch Int(ev.keyCode) {
        case kVK_Shift, kVK_RightShift:       return flags.contains(.shift)
        case kVK_Control, kVK_RightControl:   return flags.contains(.control)
        case kVK_Option, kVK_RightOption:     return flags.contains(.option)
        case kVK_Command:                     return flags.contains(.command)
        case kVK_CapsLock:                    return flags.contains(.capsLock)
        default:                              return false
        }
    }

    /// Remove the local key monitor and clear the capturing-row state.
    /// Safe to call even when no capture is in progress (no-op).
    private func stopCapture() {
        if let m = keyMonitor {
            NSEvent.removeMonitor(m)
            keyMonitor = nil
        }
        capturing = nil
    }

    /// Apply a captured `NSEvent.keyDown` to the active row. Every
    /// recognised key — *including Esc* — commits to the binding;
    /// cancelling is done by clicking the active chip again (which
    /// `toggleCapture` handles) or by clicking a different chip.
    private func handleCapturedKey(_ ev: NSEvent) {
        guard let target = capturing else { return }
        let code = UInt16(ev.keyCode)

        guard let symbol = KeyCodes.canonicalByKeyCode[code] else {
            // Unknown VK code (rare — fn key, media keys, …). End
            // capture without committing so the user can try another
            // key without an extra click.
            stopCapture()
            return
        }

        switch target {
        case .action(let buttonId):
            setBinding(buttonId, ButtonBinding(type: "key", scancode: symbol, button: nil))
        case .movement(let slot):
            setMovement(slot, symbol: symbol)
        }
        stopCapture()
    }

    // MARK: - Row chrome

    /// Two-line row body: bold label on top, dimmed description below,
    /// trailing control on the right. Form/grouped style supplies the
    /// inset card around each row; we own the inner stacking.
    @ViewBuilder
    private func rowShell<Trailing: View>(label: String,
                                          description: String,
                                          @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                if !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            trailing()
        }
    }

    // MARK: - Label formatting

    /// Friendly chip label for a `ButtonBinding`. Falls back to the
    /// raw scancode / mouse-button name for user-edited config files
    /// that hold something we don't recognise.
    private func displayLabel(for binding: ButtonBinding) -> String {
        switch binding.type.lowercased() {
        case "mouse":
            switch (binding.button ?? "").lowercased() {
            case "left":   return L.get("bindings.key.left_mouse",   fallback: "Left mouse")
            case "right":  return L.get("bindings.key.right_mouse",  fallback: "Right mouse")
            case "middle": return L.get("bindings.key.middle_mouse", fallback: "Middle mouse")
            default:       return binding.button ?? "—"
            }
        case "key":
            return displayLabel(forSymbol: binding.scancode ?? "")
        default:
            return "—"
        }
    }

    /// Friendly display of a symbolic key name. Special characters get
    /// the System-Settings-style glyphs (⇧ ⌃ ⌥ ⌘ ↑↓←→) so the chip is
    /// glanceable.
    private func displayLabel(forSymbol raw: String) -> String {
        let s = raw.lowercased()
        switch s {
        case "":                    return "—"
        case "space", "jump":       return L.get("bindings.key.space", fallback: "Space")
        case "tab":                 return "⇥"
        case "enter", "return":     return "↩"
        case "backspace", "delete": return "⌫"
        case "forwarddelete":       return "⌦"
        case "esc", "escape":       return "Esc"
        case "shift", "lshift",
             "sneak":               return L.get("bindings.key.shift", fallback: "⇧ Left Shift")
        case "rshift":              return L.get("bindings.key.rshift", fallback: "⇧ Right Shift")
        case "ctrl", "lctrl",
             "sprint":              return L.get("bindings.key.ctrl",  fallback: "⌃ Left Ctrl")
        case "rctrl":               return L.get("bindings.key.rctrl", fallback: "⌃ Right Ctrl")
        case "option", "alt",
             "loption":             return L.get("bindings.key.option", fallback: "⌥ Option")
        case "roption":             return L.get("bindings.key.roption", fallback: "⌥ Right Option")
        case "cmd", "command",
             "meta":                return L.get("bindings.key.cmd",   fallback: "⌘ Command")
        case "capslock", "caps":    return L.get("bindings.key.caps",  fallback: "⇪ Caps Lock")
        case "up":                  return "↑"
        case "down":                return "↓"
        case "left":                return "←"
        case "right":               return "→"
        case "home":                return "Home"
        case "end":                 return "End"
        case "pageup":              return "Page Up"
        case "pagedown":            return "Page Down"
        case "inventory":           return "E"
        case "drop":                return "Q"
        case "swaphand", "swap":    return "F"
        case "hotbar1", "k1", "1":  return "1"
        case "hotbar2", "k2", "2":  return "2"
        case "hotbar3", "k3", "3":  return "3"
        case "hotbar4", "k4", "4":  return "4"
        case "hotbar5", "k5", "5":  return "5"
        case "hotbar6", "k6", "6":  return "6"
        case "hotbar7", "k7", "7":  return "7"
        case "hotbar8", "k8", "8":  return "8"
        case "hotbar9", "k9", "9":  return "9"
        default:
            // Single ASCII letter or digit — capital case looks more
            // key-cappy. Multi-character names (e.g. "f1") get
            // uppercased verbatim ("F1").
            return raw.uppercased()
        }
    }
}
