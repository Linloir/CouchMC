using System.Diagnostics;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;
using McController.Core.Net;

namespace McController.Core.Diag;

/// <summary>
/// Polls the foreground window + cursor visibility state every 100ms and
/// emits <see cref="OnModeChanged"/> when the derived <see cref="Protocol.ControllerMode"/>
/// changes. Also tracks the active MC client rect (in screen coordinates)
/// so that <see cref="Input.CursorInjector"/> can clamp UI-mode cursor
/// movement to the MC window.
/// </summary>
public sealed partial class WindowStateMonitor : IDisposable
{
    public event Action<Protocol.ControllerMode>? OnModeChanged;

    private readonly string[] _matchProcessNames;
    private readonly TimeSpan _pollInterval;
    private CancellationTokenSource? _cts;
    private Task? _loop;

    public Protocol.ControllerMode CurrentMode { get; private set; } = Protocol.ControllerMode.AntiMistouch;
    public IntPtr CurrentWindow { get; private set; } = IntPtr.Zero;

    /// <summary>Screen-coord rect of the MC window's client area (drawable region).</summary>
    public Rectangle CurrentClientRect { get; private set; } = Rectangle.Empty;

    public WindowStateMonitor(IEnumerable<string>? processNames = null, int pollIntervalMs = 100)
    {
        _matchProcessNames = (processNames ?? DefaultProcessNames)
            .Select(s => s.Trim().ToLowerInvariant())
            .Where(s => s.Length > 0)
            .ToArray();
        _pollInterval = TimeSpan.FromMilliseconds(pollIntervalMs);
    }

    public void Start()
    {
        if (_loop != null) return;
        _cts = new CancellationTokenSource();
        _loop = Task.Run(() => RunLoop(_cts.Token));
    }

    public void Stop()
    {
        try
        {
            _cts?.Cancel();
            _loop?.Wait(TimeSpan.FromSeconds(1));
        }
        catch { }
        finally
        {
            _cts?.Dispose();
            _cts = null;
            _loop = null;
        }
    }

    public void Dispose() => Stop();

    private async Task RunLoop(CancellationToken ct)
    {
        // 100ms debounce: we require two consecutive identical readings
        // before emitting a state change. Avoids flapping when MC opens
        // an inventory window (cursor visibility may toggle briefly).
        Protocol.ControllerMode? pendingMode = null;
        int pendingTicks = 0;

        while (!ct.IsCancellationRequested)
        {
            var fg = GetForegroundWindow();
            var isMc = IsMatchedWindow(fg);
            Protocol.ControllerMode reading;

            if (!isMc)
            {
                reading = Protocol.ControllerMode.AntiMistouch;
            }
            else
            {
                var ci = new CURSORINFO { cbSize = (uint)Marshal.SizeOf<CURSORINFO>() };
                if (GetCursorInfo(ref ci) && ci.flags == 0)
                    reading = Protocol.ControllerMode.InGame;
                else
                    reading = Protocol.ControllerMode.UiInteract;
            }

            if (reading == CurrentMode)
            {
                pendingMode = null;
                pendingTicks = 0;
            }
            else if (reading == pendingMode)
            {
                pendingTicks++;
                if (pendingTicks >= 1)  // 2 consecutive ticks (this + previous)
                {
                    CurrentMode = reading;
                    CurrentWindow = isMc ? fg : IntPtr.Zero;
                    UpdateClientRect();
                    OnModeChanged?.Invoke(reading);
                    pendingMode = null;
                    pendingTicks = 0;
                }
            }
            else
            {
                pendingMode = reading;
                pendingTicks = 0;
            }

            // Keep client rect fresh even if mode didn't change (window may move).
            if (CurrentMode != Protocol.ControllerMode.AntiMistouch && isMc)
                UpdateClientRect();

            try { await Task.Delay(_pollInterval, ct).ConfigureAwait(false); }
            catch (OperationCanceledException) { break; }
        }
    }

    private void UpdateClientRect()
    {
        if (CurrentWindow == IntPtr.Zero)
        {
            CurrentClientRect = Rectangle.Empty;
            return;
        }
        if (!GetClientRect(CurrentWindow, out RECT r)) return;
        var pt = new POINT { X = r.Left, Y = r.Top };
        if (!ClientToScreen(CurrentWindow, ref pt)) return;
        CurrentClientRect = new Rectangle(pt.X, pt.Y, r.Right - r.Left, r.Bottom - r.Top);
    }

    private bool IsMatchedWindow(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return false;
        try
        {
            GetWindowThreadProcessId(hwnd, out uint pid);
            if (pid == 0) return false;
            using var process = Process.GetProcessById((int)pid);
            var name = process.ProcessName.ToLowerInvariant();
            return _matchProcessNames.Any(n => name.Contains(n));
        }
        catch
        {
            return false;
        }
    }

    private static readonly string[] DefaultProcessNames =
    {
        "javaw", "java", "minecraft",
    };

    // ===== P/Invoke =====

    [LibraryImport("user32.dll")]
    private static partial IntPtr GetForegroundWindow();

    [LibraryImport("user32.dll")]
    private static partial uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetCursorInfo(ref CURSORINFO pci);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetClientRect(IntPtr hWnd, out RECT lpRect);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool ClientToScreen(IntPtr hWnd, ref POINT lpPoint);

    [StructLayout(LayoutKind.Sequential)]
    private struct CURSORINFO
    {
        public uint cbSize;
        public uint flags;       // 0 = hidden, 1 = showing, 2 = suppressed
        public IntPtr hCursor;
        public POINT ptScreenPos;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct POINT
    {
        public int X;
        public int Y;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left, Top, Right, Bottom;
    }
}
