using System.Drawing;
using System.Runtime.InteropServices;
using McController.Core.Diag;

namespace McController.Core.Input;

/// <summary>
/// Drives the system cursor via SetCursorPos for UI-mode interactions
/// (inventory / menu navigation). Reads current cursor position before
/// each move so that user mouse activity isn't fought.
///
/// Clamps the new position to the MC client rect (from
/// <see cref="WindowStateMonitor.CurrentClientRect"/>) so the cursor
/// can't drift outside the game window.
/// </summary>
public sealed partial class CursorInjector
{
    private readonly WindowStateMonitor _monitor;

    public CursorInjector(WindowStateMonitor monitor)
    {
        _monitor = monitor;
    }

    public void ApplyDelta(int dx, int dy)
    {
        if (!GetCursorPos(out POINT p)) return;
        var newX = p.X + dx;
        var newY = p.Y + dy;

        var rect = _monitor.CurrentClientRect;
        if (!rect.IsEmpty)
        {
            newX = Math.Clamp(newX, rect.Left, rect.Right - 1);
            newY = Math.Clamp(newY, rect.Top, rect.Bottom - 1);
        }
        SetCursorPos(newX, newY);
    }

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetCursorPos(out POINT lpPoint);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SetCursorPos(int x, int y);

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int X;
        public int Y;
    }
}
