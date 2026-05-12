using System.Collections.Generic;
using System.Globalization;

namespace McController.App.Util;

/// <summary>
/// Human-friendly labels for the Windows hardware-scancode values that
/// drive <see cref="McController.Core.Input.JoystickToWasdMapper"/> and
/// the <c>Bindings</c> table. Used by the Key Bindings page to render
/// the current binding ("W", "Space", "Left Shift", …) and to translate
/// a captured key-press scancode back into something the user recognises.
/// </summary>
internal static class ScancodeNames
{
    // Subset of the IBM PC Set-1 (XT) scancodes that MC actually uses
    // in practice. Anything not in the map renders as its raw hex value
    // (e.g. "0x57"), which is still actionable — the user can just see
    // it sat on an obscure key and remap.
    private static readonly Dictionary<ushort, string> _names = new()
    {
        // Top row
        [0x01] = "Esc",
        [0x02] = "1", [0x03] = "2", [0x04] = "3", [0x05] = "4", [0x06] = "5",
        [0x07] = "6", [0x08] = "7", [0x09] = "8", [0x0A] = "9", [0x0B] = "0",
        [0x0C] = "-",  [0x0D] = "=",
        [0x0E] = "Backspace",
        [0x0F] = "Tab",

        // QWERTY row
        [0x10] = "Q", [0x11] = "W", [0x12] = "E", [0x13] = "R", [0x14] = "T",
        [0x15] = "Y", [0x16] = "U", [0x17] = "I", [0x18] = "O", [0x19] = "P",
        [0x1A] = "[", [0x1B] = "]", [0x1C] = "Enter",

        // Modifiers + ASDF row
        [0x1D] = "Left Ctrl",
        [0x1E] = "A", [0x1F] = "S", [0x20] = "D", [0x21] = "F", [0x22] = "G",
        [0x23] = "H", [0x24] = "J", [0x25] = "K", [0x26] = "L",
        [0x27] = ";", [0x28] = "'", [0x29] = "`",

        // Shift + ZXCV row
        [0x2A] = "Left Shift",
        [0x2B] = "\\",
        [0x2C] = "Z", [0x2D] = "X", [0x2E] = "C", [0x2F] = "V", [0x30] = "B",
        [0x31] = "N", [0x32] = "M",
        [0x33] = ",", [0x34] = ".", [0x35] = "/",
        [0x36] = "Right Shift",

        // Bottom row
        [0x37] = "Numpad *",
        [0x38] = "Left Alt",
        [0x39] = "Space",
        [0x3A] = "Caps Lock",

        // F-keys
        [0x3B] = "F1",  [0x3C] = "F2",  [0x3D] = "F3",  [0x3E] = "F4",
        [0x3F] = "F5",  [0x40] = "F6",  [0x41] = "F7",  [0x42] = "F8",
        [0x43] = "F9",  [0x44] = "F10",
        [0x57] = "F11", [0x58] = "F12",

        // Numpad
        [0x45] = "Num Lock",
        [0x46] = "Scroll Lock",
        [0x47] = "Numpad 7", [0x48] = "Numpad 8", [0x49] = "Numpad 9",
        [0x4A] = "Numpad -",
        [0x4B] = "Numpad 4", [0x4C] = "Numpad 5", [0x4D] = "Numpad 6",
        [0x4E] = "Numpad +",
        [0x4F] = "Numpad 1", [0x50] = "Numpad 2", [0x51] = "Numpad 3",
        [0x52] = "Numpad 0", [0x53] = "Numpad .",
    };

    /// <summary>Hex-string form, e.g. "0x11" → 17 → "W".</summary>
    public static string LabelForHex(string? hex)
    {
        if (string.IsNullOrWhiteSpace(hex)) return "—";
        var trimmed = hex.Trim();
        var span = trimmed.StartsWith("0x", System.StringComparison.OrdinalIgnoreCase)
            ? trimmed[2..]
            : trimmed;
        if (!ushort.TryParse(span, NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var sc))
            return hex;
        return _names.TryGetValue(sc, out var name) ? name : $"0x{sc:X2}";
    }

    public static string LabelFor(ushort scancode) =>
        _names.TryGetValue(scancode, out var name) ? name : $"0x{scancode:X2}";

    /// <summary>Formatted as the 2-char uppercase hex string our config stores.</summary>
    public static string FormatHex(ushort scancode) => $"0x{scancode:X2}";
}
