using System.Diagnostics;
using System.Runtime.InteropServices;

namespace McController.Server.Diag;

/// <summary>
/// Wraps Windows multimedia timer APIs to raise system clock resolution
/// from the default ~15.6ms to ~1ms. Without this, Thread.Sleep is too
/// coarse for sub-frame input scheduling (visible as uniform stutter).
/// Pair every Begin() call with End() (use a using-statement style).
/// </summary>
internal static partial class PrecisionTimer
{
    [LibraryImport("winmm.dll")]
    private static partial uint timeBeginPeriod(uint uPeriod);

    [LibraryImport("winmm.dll")]
    private static partial uint timeEndPeriod(uint uPeriod);

    public static IDisposable Raise(uint periodMs = 1)
    {
        timeBeginPeriod(periodMs);
        return new Restorer(periodMs);
    }

    /// <summary>
    /// Sleep that targets sub-millisecond accuracy. Combine with Raise(1)
    /// to get reliable behavior — Thread.Sleep alone is bound to system
    /// timer granularity.
    /// </summary>
    public static void PreciseSleep(double targetMs)
    {
        var sw = Stopwatch.StartNew();
        while (true)
        {
            var remain = targetMs - sw.Elapsed.TotalMilliseconds;
            if (remain <= 0) return;
            if (remain > 1.5) Thread.Sleep(1);
            else Thread.SpinWait(200);
        }
    }

    private sealed class Restorer(uint periodMs) : IDisposable
    {
        private bool _disposed;
        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            timeEndPeriod(periodMs);
        }
    }
}
