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

    // Alternative movement layouts exposed in the Key Bindings page
    // (IJKL is a common right-hand alternative to WASD).
    static let i: UInt16 = UInt16(kVK_ANSI_I)
    static let j: UInt16 = UInt16(kVK_ANSI_J)
    static let k: UInt16 = UInt16(kVK_ANSI_K)
    static let l: UInt16 = UInt16(kVK_ANSI_L)

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
    /// from Windows. Also covers every physical key the live-capture
    /// row UI might receive (letters A..Z, digits 0..9, F1..F12, arrows,
    /// punctuation, etc.) — without this, capturing e.g. "R" would
    /// store an unresolvable name.
    static let symbolic: [String: UInt16] = {
        var m: [String: UInt16] = [:]

        // Letters A..Z
        let letters: [(String, Int)] = [
            ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C),
            ("d", kVK_ANSI_D), ("e", kVK_ANSI_E), ("f", kVK_ANSI_F),
            ("g", kVK_ANSI_G), ("h", kVK_ANSI_H), ("i", kVK_ANSI_I),
            ("j", kVK_ANSI_J), ("k", kVK_ANSI_K), ("l", kVK_ANSI_L),
            ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O),
            ("p", kVK_ANSI_P), ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R),
            ("s", kVK_ANSI_S), ("t", kVK_ANSI_T), ("u", kVK_ANSI_U),
            ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X),
            ("y", kVK_ANSI_Y), ("z", kVK_ANSI_Z),
        ]
        for (name, code) in letters { m[name] = UInt16(code) }

        // Digits 0..9 (top row)
        let digits: [(String, Int)] = [
            ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2),
            ("3", kVK_ANSI_3), ("4", kVK_ANSI_4), ("5", kVK_ANSI_5),
            ("6", kVK_ANSI_6), ("7", kVK_ANSI_7), ("8", kVK_ANSI_8),
            ("9", kVK_ANSI_9),
        ]
        for (name, code) in digits { m[name] = UInt16(code) }

        // Function keys
        let fns: [(String, Int)] = [
            ("f1", kVK_F1), ("f2", kVK_F2), ("f3", kVK_F3), ("f4", kVK_F4),
            ("f5", kVK_F5), ("f6", kVK_F6), ("f7", kVK_F7), ("f8", kVK_F8),
            ("f9", kVK_F9), ("f10", kVK_F10), ("f11", kVK_F11), ("f12", kVK_F12),
        ]
        for (name, code) in fns { m[name] = UInt16(code) }

        // Punctuation / symbols that share the QWERTY layout
        let punct: [(String, Int)] = [
            ("-", kVK_ANSI_Minus),
            ("=", kVK_ANSI_Equal),
            ("[", kVK_ANSI_LeftBracket),
            ("]", kVK_ANSI_RightBracket),
            ("\\", kVK_ANSI_Backslash),
            (";", kVK_ANSI_Semicolon),
            ("'", kVK_ANSI_Quote),
            (",", kVK_ANSI_Comma),
            (".", kVK_ANSI_Period),
            ("/", kVK_ANSI_Slash),
            ("`", kVK_ANSI_Grave),
        ]
        for (name, code) in punct { m[name] = UInt16(code) }

        // Specials + modifiers + aliases
        m["space"]   = UInt16(kVK_Space)
        m["jump"]    = UInt16(kVK_Space)        // legacy alias
        m["tab"]     = UInt16(kVK_Tab)
        m["enter"]   = UInt16(kVK_Return)
        m["return"]  = UInt16(kVK_Return)
        m["delete"]  = UInt16(kVK_Delete)       // Backspace on most keyboards
        m["backspace"] = UInt16(kVK_Delete)
        m["forwarddelete"] = UInt16(kVK_ForwardDelete)

        m["esc"]     = UInt16(kVK_Escape)
        m["escape"]  = UInt16(kVK_Escape)

        m["shift"]   = UInt16(kVK_Shift)
        m["lshift"]  = UInt16(kVK_Shift)
        m["rshift"]  = UInt16(kVK_RightShift)
        m["sneak"]   = UInt16(kVK_Shift)        // legacy alias

        m["ctrl"]    = UInt16(kVK_Control)
        m["lctrl"]   = UInt16(kVK_Control)
        m["rctrl"]   = UInt16(kVK_RightControl)
        m["sprint"]  = UInt16(kVK_Control)      // legacy alias

        m["option"]  = UInt16(kVK_Option)
        m["alt"]     = UInt16(kVK_Option)
        m["loption"] = UInt16(kVK_Option)
        m["roption"] = UInt16(kVK_RightOption)

        m["cmd"]     = UInt16(kVK_Command)
        m["command"] = UInt16(kVK_Command)
        m["meta"]    = UInt16(kVK_Command)

        m["caps"]    = UInt16(kVK_CapsLock)
        m["capslock"] = UInt16(kVK_CapsLock)

        m["up"]      = UInt16(kVK_UpArrow)
        m["down"]    = UInt16(kVK_DownArrow)
        m["left"]    = UInt16(kVK_LeftArrow)
        m["right"]   = UInt16(kVK_RightArrow)

        m["home"]    = UInt16(kVK_Home)
        m["end"]     = UInt16(kVK_End)
        m["pageup"]   = UInt16(kVK_PageUp)
        m["pagedown"] = UInt16(kVK_PageDown)

        // Legacy hotbar / action aliases used by older configs.
        m["inventory"] = UInt16(kVK_ANSI_E)
        m["drop"]      = UInt16(kVK_ANSI_Q)
        m["swaphand"]  = UInt16(kVK_ANSI_F)
        m["swap"]      = UInt16(kVK_ANSI_F)
        for i in 1...9 {
            m["hotbar\(i)"] = UInt16([
                kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
            ][i - 1])
            m["k\(i)"] = m["hotbar\(i)"]
        }

        return m
    }()

    /// Reverse mapping: VK code → canonical config name. Used by the
    /// live-capture row UI to translate `NSEvent.keyCode` into a
    /// symbolic name we can store in `ServerConfig`. Only one entry per
    /// VK code (no aliases) so the round-trip stays stable.
    static let canonicalByKeyCode: [UInt16: String] = {
        var m: [UInt16: String] = [:]
        let letters: [(String, Int)] = [
            ("a", kVK_ANSI_A), ("b", kVK_ANSI_B), ("c", kVK_ANSI_C),
            ("d", kVK_ANSI_D), ("e", kVK_ANSI_E), ("f", kVK_ANSI_F),
            ("g", kVK_ANSI_G), ("h", kVK_ANSI_H), ("i", kVK_ANSI_I),
            ("j", kVK_ANSI_J), ("k", kVK_ANSI_K), ("l", kVK_ANSI_L),
            ("m", kVK_ANSI_M), ("n", kVK_ANSI_N), ("o", kVK_ANSI_O),
            ("p", kVK_ANSI_P), ("q", kVK_ANSI_Q), ("r", kVK_ANSI_R),
            ("s", kVK_ANSI_S), ("t", kVK_ANSI_T), ("u", kVK_ANSI_U),
            ("v", kVK_ANSI_V), ("w", kVK_ANSI_W), ("x", kVK_ANSI_X),
            ("y", kVK_ANSI_Y), ("z", kVK_ANSI_Z),
        ]
        for (name, code) in letters { m[UInt16(code)] = name }
        let digits: [(String, Int)] = [
            ("0", kVK_ANSI_0), ("1", kVK_ANSI_1), ("2", kVK_ANSI_2),
            ("3", kVK_ANSI_3), ("4", kVK_ANSI_4), ("5", kVK_ANSI_5),
            ("6", kVK_ANSI_6), ("7", kVK_ANSI_7), ("8", kVK_ANSI_8),
            ("9", kVK_ANSI_9),
        ]
        for (name, code) in digits { m[UInt16(code)] = name }
        let fns: [(String, Int)] = [
            ("f1", kVK_F1), ("f2", kVK_F2), ("f3", kVK_F3), ("f4", kVK_F4),
            ("f5", kVK_F5), ("f6", kVK_F6), ("f7", kVK_F7), ("f8", kVK_F8),
            ("f9", kVK_F9), ("f10", kVK_F10), ("f11", kVK_F11), ("f12", kVK_F12),
        ]
        for (name, code) in fns { m[UInt16(code)] = name }
        let punct: [(String, Int)] = [
            ("-", kVK_ANSI_Minus), ("=", kVK_ANSI_Equal),
            ("[", kVK_ANSI_LeftBracket), ("]", kVK_ANSI_RightBracket),
            ("\\", kVK_ANSI_Backslash),
            (";", kVK_ANSI_Semicolon), ("'", kVK_ANSI_Quote),
            (",", kVK_ANSI_Comma), (".", kVK_ANSI_Period),
            ("/", kVK_ANSI_Slash), ("`", kVK_ANSI_Grave),
        ]
        for (name, code) in punct { m[UInt16(code)] = name }
        m[UInt16(kVK_Space)]   = "space"
        m[UInt16(kVK_Tab)]     = "tab"
        m[UInt16(kVK_Return)]  = "enter"
        m[UInt16(kVK_Delete)]  = "backspace"
        m[UInt16(kVK_ForwardDelete)] = "forwarddelete"
        m[UInt16(kVK_Escape)]  = "esc"
        m[UInt16(kVK_Shift)]        = "shift"
        m[UInt16(kVK_RightShift)]   = "rshift"
        m[UInt16(kVK_Control)]      = "ctrl"
        m[UInt16(kVK_RightControl)] = "rctrl"
        m[UInt16(kVK_Option)]       = "option"
        m[UInt16(kVK_RightOption)]  = "roption"
        m[UInt16(kVK_Command)]      = "cmd"
        m[UInt16(kVK_CapsLock)]     = "capslock"
        m[UInt16(kVK_UpArrow)]    = "up"
        m[UInt16(kVK_DownArrow)]  = "down"
        m[UInt16(kVK_LeftArrow)]  = "left"
        m[UInt16(kVK_RightArrow)] = "right"
        m[UInt16(kVK_Home)]    = "home"
        m[UInt16(kVK_End)]     = "end"
        m[UInt16(kVK_PageUp)]   = "pageup"
        m[UInt16(kVK_PageDown)] = "pagedown"
        return m
    }()

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
    ///   - symbolic name: "jump", "sneak", "hotbar3", "w", "f1", …
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
