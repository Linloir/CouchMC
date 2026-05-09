using System.Runtime.InteropServices;

namespace McController.Server.Input;

/// <summary>
/// Forces the active foreground window onto the US English (00000409)
/// keyboard layout. Used when the controller mode flips to in-game so that
/// WASD scancodes register in MC instead of being intercepted by an active
/// Chinese / Japanese / Korean IME.
///
/// No-op if English is already active or if loading the layout fails.
/// </summary>
internal static partial class InputLanguageManager
{
    [LibraryImport("user32.dll", StringMarshalling = StringMarshalling.Utf16)]
    private static partial IntPtr LoadKeyboardLayout(string pwszKLID, uint Flags);

    [LibraryImport("user32.dll")]
    private static partial IntPtr GetForegroundWindow();

    [LibraryImport("user32.dll")]
    private static partial uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);

    [LibraryImport("user32.dll")]
    private static partial IntPtr GetKeyboardLayout(uint idThread);

    [LibraryImport("user32.dll", EntryPoint = "PostMessageW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

    private const uint KLF_ACTIVATE = 0x00000001;
    private const uint WM_INPUTLANGCHANGEREQUEST = 0x0050;
    private const uint LANG_ENGLISH = 0x09;
    private const string EN_US_KLID = "00000409";

    public static void EnsureEnglishLayout()
    {
        var hwnd = GetForegroundWindow();
        if (hwnd == IntPtr.Zero) return;

        var threadId = GetWindowThreadProcessId(hwnd, out _);
        if (threadId == 0) return;

        var current = GetKeyboardLayout(threadId);
        var langId = (uint)(current.ToInt64() & 0xFFFF);
        var primaryLang = langId & 0x3FF;
        if (primaryLang == LANG_ENGLISH) return;  // already English

        var hklEn = LoadKeyboardLayout(EN_US_KLID, KLF_ACTIVATE);
        if (hklEn == IntPtr.Zero)
        {
            Console.WriteLine("[IME] LoadKeyboardLayout(en-US) failed; layout not installed?");
            return;
        }

        // Ask the foreground window's thread to switch to en-US. PostMessage
        // is non-blocking and works cross-process for standard Win32 messages.
        if (!PostMessage(hwnd, WM_INPUTLANGCHANGEREQUEST, IntPtr.Zero, hklEn))
        {
            Console.WriteLine("[IME] PostMessage(WM_INPUTLANGCHANGEREQUEST) failed.");
            return;
        }

        Console.WriteLine($"[IME] Requested en-US layout for foreground window (was lang 0x{primaryLang:X3}).");
    }
}
