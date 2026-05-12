import SwiftUI

/// Per-action key remapping. Mirrors the Windows `KeyBindingsPage` —
/// two sections, each row a (label, description, current-key picker)
/// triple.
///
///   1. Movement — joystick directions (forward / back / left / right),
///      read every poll by `JoystickToWasdMapper`. Defaults to W/S/A/D
///      but the user can pick arrow keys, IJKL, ESDF, etc.
///   2. Action buttons — every ButtonId from the wire protocol (LMB,
///      RMB, jump, sneak, sprint, inventory, drop, swap hand, esc,
///      hotbar 1..9), read by `ButtonRouter` from
///      `ServerConfig.bindings`.
///
/// Picking an option goes through `host.updateBindings(_:)` /
/// `host.updateMovementKeys(_:)` which:
///   - release any key still held under the OLD mapping (no stuck
///     keys after a rebind mid-press),
///   - replace the live table atomically,
///   - persist to config.json immediately.
struct KeyBindingsView: View {

    @EnvironmentObject private var host: ServerHost
    @State private var showResetConfirm: Bool = false

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
        .confirmationDialog(
            L.get("bindings.reset.confirm", fallback: "Reset all key bindings?"),
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button(L.get("bindings.reset", fallback: "Reset all to defaults"),
                   role: .destructive) {
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

    // MARK: - Movement row

    /// Identifies which of the four movement slots a row controls. Used
    /// as the input to `setMovement(_:_:)` so the switch doesn't have to
    /// thread closures through every row.
    private enum MovementSlot {
        case forward, back, left, right
    }

    @ViewBuilder
    private func movementRow(slot: MovementSlot, label: String, desc: String) -> some View {
        let current = currentMovementSymbol(slot)
        rowShell(label: label, description: desc) {
            Menu {
                movementMenuSections(slot: slot, current: current)
            } label: {
                Text(displayLabel(forSymbol: current))
                    .monospacedDigit()
            }
            .menuStyle(.borderlessButton)
            .frame(minWidth: 160)
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

    @ViewBuilder
    private func movementMenuSections(slot: MovementSlot, current: String) -> some View {
        Section(L.get("bindings.menu.movement", fallback: "WASD")) {
            movementOption(slot, symbol: "w", label: "W", current: current)
            movementOption(slot, symbol: "a", label: "A", current: current)
            movementOption(slot, symbol: "s", label: "S", current: current)
            movementOption(slot, symbol: "d", label: "D", current: current)
        }
        Section(L.get("bindings.menu.arrows", fallback: "Arrow keys")) {
            // Arrow keys aren't wired through the macOS injector's
            // symbolic table today, so we expose them by Carbon-style
            // names that `KeyCodes.resolve` understands. These four are
            // listed for parity with what users expect to see in MC's
            // controls; even if a user picks one, the mapper will fall
            // back to the WASD default if `KeyCodes.resolve` doesn't
            // know the name yet. Plain ASCII letters are the safe
            // alternative we ship right now.
            movementOption(slot, symbol: "i", label: "I", current: current)
            movementOption(slot, symbol: "j", label: "J", current: current)
            movementOption(slot, symbol: "k", label: "K", current: current)
            movementOption(slot, symbol: "l", label: "L", current: current)
        }
        Section(L.get("bindings.menu.actions", fallback: "Other keys")) {
            movementOption(slot, symbol: "e", label: "E", current: current)
            movementOption(slot, symbol: "q", label: "Q", current: current)
            movementOption(slot, symbol: "f", label: "F", current: current)
            movementOption(slot, symbol: "space",
                           label: L.get("bindings.key.space", fallback: "Space"),
                           current: current)
        }
    }

    private func movementOption(_ slot: MovementSlot, symbol: String, label: String, current: String) -> some View {
        let isCurrent = current.lowercased() == symbol.lowercased()
        return Button {
            setMovement(slot, symbol: symbol)
        } label: {
            Text(isCurrent ? "✓  " + label : "    " + label)
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

    /// Static description of one action button. The full list mirrors
    /// the Windows `ActionRow.AllSpecs` so the two pages stay in sync.
    private struct ActionSpec {
        let buttonId: String          // hex string, e.g. "0x10"
        let labelKey: String
        let labelFallback: String
        let descKey: String
        let descFallback: String
        let allowMouse: Bool

        static let all: [ActionSpec] = [
            // Mouse buttons — the only rows where "mouse" type is a valid pick.
            .init(buttonId: "0x01",
                  labelKey: "bindings.btn.mouse_left",  labelFallback: "Left click (LMB)",
                  descKey:  "bindings.btn.mouse_left.desc",  descFallback: "Triggered by the phone's left-click button",
                  allowMouse: true),
            .init(buttonId: "0x02",
                  labelKey: "bindings.btn.mouse_right", labelFallback: "Right click (RMB)",
                  descKey:  "bindings.btn.mouse_right.desc", descFallback: "Triggered by the phone's right-click button",
                  allowMouse: true),

            // Movement-modifier keys.
            .init(buttonId: "0x10",
                  labelKey: "bindings.btn.jump",   labelFallback: "Jump",
                  descKey:  "bindings.btn.jump.desc",   descFallback: "Default Space",
                  allowMouse: false),
            .init(buttonId: "0x11",
                  labelKey: "bindings.btn.sneak",  labelFallback: "Sneak",
                  descKey:  "bindings.btn.sneak.desc",  descFallback: "Default Left Shift",
                  allowMouse: false),
            .init(buttonId: "0x12",
                  labelKey: "bindings.btn.sprint", labelFallback: "Sprint",
                  descKey:  "bindings.btn.sprint.desc", descFallback: "Default Left Ctrl",
                  allowMouse: false),

            // Inventory / item actions.
            .init(buttonId: "0x20",
                  labelKey: "bindings.btn.inventory", labelFallback: "Inventory",
                  descKey:  "bindings.btn.inventory.desc", descFallback: "Default E",
                  allowMouse: false),
            .init(buttonId: "0x21",
                  labelKey: "bindings.btn.drop",      labelFallback: "Drop item",
                  descKey:  "bindings.btn.drop.desc",      descFallback: "Default Q",
                  allowMouse: false),
            .init(buttonId: "0x22",
                  labelKey: "bindings.btn.swap_hand", labelFallback: "Swap hand",
                  descKey:  "bindings.btn.swap_hand.desc", descFallback: "Default F",
                  allowMouse: false),
            .init(buttonId: "0x30",
                  labelKey: "bindings.btn.esc",       labelFallback: "Esc / Pause",
                  descKey:  "bindings.btn.esc.desc",       descFallback: "Default Esc",
                  allowMouse: false),

            // Hotbar 1..9.
            .init(buttonId: "0x40", labelKey: "bindings.btn.hotbar1", labelFallback: "Hotbar 1",
                  descKey: "bindings.btn.hotbar1.desc", descFallback: "Default 1", allowMouse: false),
            .init(buttonId: "0x41", labelKey: "bindings.btn.hotbar2", labelFallback: "Hotbar 2",
                  descKey: "bindings.btn.hotbar2.desc", descFallback: "Default 2", allowMouse: false),
            .init(buttonId: "0x42", labelKey: "bindings.btn.hotbar3", labelFallback: "Hotbar 3",
                  descKey: "bindings.btn.hotbar3.desc", descFallback: "Default 3", allowMouse: false),
            .init(buttonId: "0x43", labelKey: "bindings.btn.hotbar4", labelFallback: "Hotbar 4",
                  descKey: "bindings.btn.hotbar4.desc", descFallback: "Default 4", allowMouse: false),
            .init(buttonId: "0x44", labelKey: "bindings.btn.hotbar5", labelFallback: "Hotbar 5",
                  descKey: "bindings.btn.hotbar5.desc", descFallback: "Default 5", allowMouse: false),
            .init(buttonId: "0x45", labelKey: "bindings.btn.hotbar6", labelFallback: "Hotbar 6",
                  descKey: "bindings.btn.hotbar6.desc", descFallback: "Default 6", allowMouse: false),
            .init(buttonId: "0x46", labelKey: "bindings.btn.hotbar7", labelFallback: "Hotbar 7",
                  descKey: "bindings.btn.hotbar7.desc", descFallback: "Default 7", allowMouse: false),
            .init(buttonId: "0x47", labelKey: "bindings.btn.hotbar8", labelFallback: "Hotbar 8",
                  descKey: "bindings.btn.hotbar8.desc", descFallback: "Default 8", allowMouse: false),
            .init(buttonId: "0x48", labelKey: "bindings.btn.hotbar9", labelFallback: "Hotbar 9",
                  descKey: "bindings.btn.hotbar9.desc", descFallback: "Default 9", allowMouse: false),
        ]
    }

    @ViewBuilder
    private func actionRow(spec: ActionSpec) -> some View {
        let current = host.config.bindings[spec.buttonId] ?? ButtonBinding()
        rowShell(label: L.get(spec.labelKey, fallback: spec.labelFallback),
                 description: L.get(spec.descKey, fallback: spec.descFallback)) {
            Menu {
                actionMenuSections(for: spec, current: current)
            } label: {
                Text(displayLabel(for: current))
                    .monospacedDigit()
            }
            .menuStyle(.borderlessButton)
            .frame(minWidth: 160)
        }
    }

    @ViewBuilder
    private func actionMenuSections(for spec: ActionSpec, current: ButtonBinding) -> some View {
        if spec.allowMouse {
            Section(L.get("bindings.menu.mouse", fallback: "Mouse")) {
                mouseOption(spec.buttonId, button: "left",
                            label: L.get("bindings.key.left_mouse",   fallback: "Left mouse"),
                            current: current)
                mouseOption(spec.buttonId, button: "right",
                            label: L.get("bindings.key.right_mouse",  fallback: "Right mouse"),
                            current: current)
                mouseOption(spec.buttonId, button: "middle",
                            label: L.get("bindings.key.middle_mouse", fallback: "Middle mouse"),
                            current: current)
            }
        }
        Section(L.get("bindings.menu.modifiers", fallback: "Modifiers")) {
            keyOption(spec.buttonId, symbol: "space",
                      label: L.get("bindings.key.space", fallback: "Space"),       current: current)
            keyOption(spec.buttonId, symbol: "shift",
                      label: L.get("bindings.key.shift", fallback: "Left Shift"),  current: current)
            keyOption(spec.buttonId, symbol: "ctrl",
                      label: L.get("bindings.key.ctrl",  fallback: "Left Ctrl"),   current: current)
            keyOption(spec.buttonId, symbol: "esc",
                      label: L.get("bindings.key.esc",   fallback: "Esc"),         current: current)
        }
        Section(L.get("bindings.menu.movement", fallback: "WASD")) {
            keyOption(spec.buttonId, symbol: "w", label: "W", current: current)
            keyOption(spec.buttonId, symbol: "a", label: "A", current: current)
            keyOption(spec.buttonId, symbol: "s", label: "S", current: current)
            keyOption(spec.buttonId, symbol: "d", label: "D", current: current)
        }
        Section(L.get("bindings.menu.actions", fallback: "Action keys")) {
            keyOption(spec.buttonId, symbol: "e", label: "E", current: current)
            keyOption(spec.buttonId, symbol: "q", label: "Q", current: current)
            keyOption(spec.buttonId, symbol: "f", label: "F", current: current)
        }
        Section(L.get("bindings.menu.hotbar", fallback: "Hotbar numbers")) {
            ForEach(1...9, id: \.self) { i in
                keyOption(spec.buttonId, symbol: String(i), label: String(i), current: current)
            }
        }
    }

    private func keyOption(_ buttonId: String, symbol: String, label: String, current: ButtonBinding) -> some View {
        let isCurrent = current.type == "key" && (current.scancode?.lowercased() == symbol.lowercased())
        return Button {
            setBinding(buttonId, ButtonBinding(type: "key", scancode: symbol, button: nil))
        } label: {
            // SwiftUI's macOS `Menu` doesn't render check-mark badges for
            // the current selection — prefix manually so the active pick
            // is glanceable inside the popover.
            Text(isCurrent ? "✓  " + label : "    " + label)
        }
    }

    private func mouseOption(_ buttonId: String, button: String, label: String, current: ButtonBinding) -> some View {
        let isCurrent = current.type == "mouse" && (current.button?.lowercased() == button.lowercased())
        return Button {
            setBinding(buttonId, ButtonBinding(type: "mouse", scancode: nil, button: button))
        } label: {
            Text(isCurrent ? "✓  " + label : "    " + label)
        }
    }

    private func setBinding(_ buttonId: String, _ binding: ButtonBinding) {
        var all = host.config.bindings
        all[buttonId] = binding
        host.updateBindings(all)
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

    /// Friendly Menu-button label for a `ButtonBinding`. Falls back to
    /// the raw scancode / mouse-button name for user-edited config files
    /// that hold something we don't recognise — better to show what's
    /// actually there than render "—".
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

    /// Friendly display of a symbolic key name. Used for both action
    /// rows (where the symbol came from the binding's scancode) and
    /// movement rows (where the symbol is the slot's stored value).
    private func displayLabel(forSymbol raw: String) -> String {
        let s = raw.lowercased()
        switch s {
        case "":                    return "—"
        case "space", "jump":       return L.get("bindings.key.space", fallback: "Space")
        case "shift", "lshift",
             "sneak":               return L.get("bindings.key.shift", fallback: "Left Shift")
        case "ctrl", "lctrl",
             "sprint":              return L.get("bindings.key.ctrl",  fallback: "Left Ctrl")
        case "esc", "escape":       return L.get("bindings.key.esc",   fallback: "Esc")
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
        default:                    return raw.uppercased()
        }
    }
}
