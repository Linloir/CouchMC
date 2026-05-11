import Foundation
import Carbon.HIToolbox

/// macOS virtual key codes used by the controller. These come from
/// `<Carbon/HIToolbox/Events.h>` and are stable across macOS versions.
///
/// We intentionally use `kVK_*` (HID virtual keys) rather than scan
/// codes — the names differ from the Windows side but the *symbolic*
/// meaning is what matters at the protocol level (ButtonId 0x10 =
/// JUMP → Space, regardless of platform).
enum KeyCodes {
    // Movement
    static let w: UInt16 = UInt16(kVK_ANSI_W)
    static let a: UInt16 = UInt16(kVK_ANSI_A)
    static let s: UInt16 = UInt16(kVK_ANSI_S)
    static let d: UInt16 = UInt16(kVK_ANSI_D)

    // Modifiers + movement-modifier keys
    static let space: UInt16 = UInt16(kVK_Space)
    static let lshift: UInt16 = UInt16(kVK_Shift)
    static let lctrl: UInt16 = UInt16(kVK_Control)

    // Actions
    static let e: UInt16 = UInt16(kVK_ANSI_E)
    static let q: UInt16 = UInt16(kVK_ANSI_Q)
    static let f: UInt16 = UInt16(kVK_ANSI_F)
    static let esc: UInt16 = UInt16(kVK_Escape)

    // Hotbar 1..9 (top number row)
    static let k1: UInt16 = UInt16(kVK_ANSI_1)
    static let k2: UInt16 = UInt16(kVK_ANSI_2)
    static let k3: UInt16 = UInt16(kVK_ANSI_3)
    static let k4: UInt16 = UInt16(kVK_ANSI_4)
    static let k5: UInt16 = UInt16(kVK_ANSI_5)
    static let k6: UInt16 = UInt16(kVK_ANSI_6)
    static let k7: UInt16 = UInt16(kVK_ANSI_7)
    static let k8: UInt16 = UInt16(kVK_ANSI_8)
    static let k9: UInt16 = UInt16(kVK_ANSI_9)

    /// Lookup table mapping the *symbolic* names used in the JSON config
    /// (e.g. `"jump"`, `"hotbar1"`) to macOS virtual key codes. This
    /// keeps the config file readable across platforms — the JSON
    /// reference is meaningful even if the underlying integer differs
    /// from Windows.
    static let symbolic: [String: UInt16] = [
        "w": w, "a": a, "s": s, "d": d,
        "space": space, "jump": space,
        "shift": lshift, "lshift": lshift, "sneak": lshift,
        "ctrl": lctrl, "lctrl": lctrl, "sprint": lctrl,
        "e": e, "inventory": e,
        "q": q, "drop": q,
        "f": f, "swapHand": f, "swaphand": f,
        "esc": esc, "escape": esc,
        "1": k1, "k1": k1, "hotbar1": k1,
        "2": k2, "k2": k2, "hotbar2": k2,
        "3": k3, "k3": k3, "hotbar3": k3,
        "4": k4, "k4": k4, "hotbar4": k4,
        "5": k5, "k5": k5, "hotbar5": k5,
        "6": k6, "k6": k6, "hotbar6": k6,
        "7": k7, "k7": k7, "hotbar7": k7,
        "8": k8, "k8": k8, "hotbar8": k8,
        "9": k9, "k9": k9, "hotbar9": k9,
    ]

    /// Windows scancode → macOS virtual key code, so a config file
    /// migrated from a Windows install still resolves to the right
    /// macOS key. Covers everything the default `ServerConfig` ships.
    static let winScancodeToMac: [UInt16: UInt16] = [
        0x11: w, 0x1E: a, 0x1F: s, 0x20: d,
        0x39: space, 0x2A: lshift, 0x1D: lctrl,
        0x12: e, 0x10: q, 0x21: f, 0x01: esc,
        0x02: k1, 0x03: k2, 0x04: k3, 0x05: k4, 0x06: k5,
        0x07: k6, 0x08: k7, 0x09: k8, 0x0A: k9,
    ]

    /// Resolve a binding string into a macOS virtual key code. Accepts:
    ///   - symbolic name: "jump", "sneak", "hotbar3"
    ///   - hex scancode (Windows): "0x39" / "39"
    ///   - decimal scancode (Windows): "57"
    static func resolve(_ raw: String) -> UInt16? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = symbolic[trimmed.lowercased()] { return direct }
        // Hex
        var s = trimmed
        if s.lowercased().hasPrefix("0x") { s.removeFirst(2) }
        if let n = UInt16(s, radix: 16), let mac = winScancodeToMac[n] {
            return mac
        }
        // Decimal
        if let n = UInt16(s), let mac = winScancodeToMac[n] {
            return mac
        }
        return nil
    }
}
