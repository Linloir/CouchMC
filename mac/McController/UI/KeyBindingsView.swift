import SwiftUI

/// Per-button key remapping. Each row shows a controller-button label
/// (left click, jump, hotbar 3, etc.) and a Menu of candidate key / mouse
/// bindings. Selecting an option calls `host.updateBindings(_:)` which
///   - releases any key still held under the old mapping (no stuck keys),
///   - replaces the router's resolution table atomically,
///   - persists the new bindings to config.json immediately.
struct KeyBindingsView: View {

    @EnvironmentObject private var host: ServerHost
    @State private var showResetConfirm: Bool = false

    var body: some View {
        Form {
            Section(L.get("bindings.section.mouse", fallback: "Mouse")) {
                row("0x01", label: L.get("bindings.btn.mouse_left",  fallback: "Left click"))
                row("0x02", label: L.get("bindings.btn.mouse_right", fallback: "Right click"))
            }
            Section(L.get("bindings.section.movement", fallback: "Movement & camera")) {
                row("0x10", label: L.get("bindings.btn.jump",   fallback: "Jump"))
                row("0x11", label: L.get("bindings.btn.sneak",  fallback: "Sneak"))
                row("0x12", label: L.get("bindings.btn.sprint", fallback: "Sprint"))
            }
            Section(L.get("bindings.section.actions", fallback: "Actions")) {
                row("0x20", label: L.get("bindings.btn.inventory", fallback: "Inventory"))
                row("0x21", label: L.get("bindings.btn.drop",      fallback: "Drop"))
                row("0x22", label: L.get("bindings.btn.swap_hand", fallback: "Swap hand"))
                row("0x30", label: L.get("bindings.btn.esc",       fallback: "Esc / Pause"))
            }
            Section(L.get("bindings.section.hotbar", fallback: "Hotbar slots")) {
                ForEach(0..<9, id: \.self) { i in
                    let id = String(format: "0x%02X", 0x40 + i)
                    let template = L.get("bindings.btn.hotbar", fallback: "Hotbar slot %d")
                    row(id, label: String(format: template, i + 1))
                }
            }
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

    // MARK: - Row

    @ViewBuilder
    private func row(_ buttonId: String, label: String) -> some View {
        let current = host.config.bindings[buttonId] ?? ButtonBinding()
        HStack {
            Text(label)
            Spacer()
            Menu {
                bindingMenuSections(for: buttonId, current: current)
            } label: {
                Text(displayLabel(for: current))
                    .monospacedDigit()
            }
            .menuStyle(.borderlessButton)
            .frame(minWidth: 160)
        }
    }

    // MARK: - Menu sections

    @ViewBuilder
    private func bindingMenuSections(for buttonId: String, current: ButtonBinding) -> some View {
        Section(L.get("bindings.menu.mouse", fallback: "Mouse")) {
            mouseOption(buttonId, button: "left",   label: L.get("bindings.key.left_mouse",   fallback: "Left mouse"),   current: current)
            mouseOption(buttonId, button: "right",  label: L.get("bindings.key.right_mouse",  fallback: "Right mouse"),  current: current)
            mouseOption(buttonId, button: "middle", label: L.get("bindings.key.middle_mouse", fallback: "Middle mouse"), current: current)
        }
        Section(L.get("bindings.menu.movement", fallback: "Movement (WASD)")) {
            keyOption(buttonId, symbol: "w", label: "W", current: current)
            keyOption(buttonId, symbol: "a", label: "A", current: current)
            keyOption(buttonId, symbol: "s", label: "S", current: current)
            keyOption(buttonId, symbol: "d", label: "D", current: current)
        }
        Section(L.get("bindings.menu.modifiers", fallback: "Modifiers")) {
            keyOption(buttonId, symbol: "space", label: L.get("bindings.key.space", fallback: "Space"),       current: current)
            keyOption(buttonId, symbol: "shift", label: L.get("bindings.key.shift", fallback: "Left Shift"),  current: current)
            keyOption(buttonId, symbol: "ctrl",  label: L.get("bindings.key.ctrl",  fallback: "Left Ctrl"),   current: current)
        }
        Section(L.get("bindings.menu.actions", fallback: "Action keys")) {
            keyOption(buttonId, symbol: "e",   label: "E",                                        current: current)
            keyOption(buttonId, symbol: "q",   label: "Q",                                        current: current)
            keyOption(buttonId, symbol: "f",   label: "F",                                        current: current)
            keyOption(buttonId, symbol: "esc", label: L.get("bindings.key.esc", fallback: "Esc"), current: current)
        }
        Section(L.get("bindings.menu.hotbar", fallback: "Hotbar numbers")) {
            ForEach(1...9, id: \.self) { i in
                keyOption(buttonId, symbol: String(i), label: String(i), current: current)
            }
        }
    }

    private func keyOption(_ buttonId: String, symbol: String, label: String, current: ButtonBinding) -> some View {
        let isCurrent = current.type == "key" && (current.scancode?.lowercased() == symbol.lowercased())
        return Button {
            setBinding(buttonId, ButtonBinding(type: "key", scancode: symbol, button: nil))
        } label: {
            // Menu items don't render checkmark badges natively in macOS
            // SwiftUI yet; we prefix manually so the current pick is
            // glanceable inside the popover.
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

    // MARK: - Label formatting

    /// Friendly menu-button label for a binding. Falls back to the raw
    /// scancode / button name if the binding doesn't match anything we
    /// know — covers user-edited config.json files with arbitrary values.
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
            guard let s = binding.scancode?.lowercased() else { return "—" }
            switch s {
            case "space":               return L.get("bindings.key.space", fallback: "Space")
            case "shift", "lshift":     return L.get("bindings.key.shift", fallback: "Left Shift")
            case "ctrl", "lctrl":       return L.get("bindings.key.ctrl",  fallback: "Left Ctrl")
            case "esc", "escape":       return L.get("bindings.key.esc",   fallback: "Esc")
            // Common semantic aliases — surface the underlying key.
            case "jump":                return L.get("bindings.key.space", fallback: "Space")
            case "sneak":               return L.get("bindings.key.shift", fallback: "Left Shift")
            case "sprint":              return L.get("bindings.key.ctrl",  fallback: "Left Ctrl")
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
            default:                    return (binding.scancode ?? "—").uppercased()
            }
        default:
            return "—"
        }
    }
}
