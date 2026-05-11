using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.UI.Dispatching;

namespace McController.App.Services;

/// <summary>
/// Polls <c>adb devices</c> on a background timer and surfaces the result
/// on the UI thread via <see cref="OnUpdate"/>. Each row is enriched with
/// the device model from <c>adb shell getprop ro.product.model</c> (best
/// effort — failures fall back to the serial).
///
/// Cheap: shells out once per <see cref="PollIntervalMs"/>; the model
/// lookup is cached per serial so it only runs the first time a device
/// shows up.
///
/// All invocations go via the standard port 5037 daemon and are wrapped
/// in <c>cmd /c "adb args > tempfile 2>&amp;1"</c>. The cmd.exe wrapping
/// is what makes this safe to run from a WinUI app — see <see cref="RunAdb"/>
/// for the full reasoning. We deliberately do NOT spin up a private adb
/// daemon on an alternate port, because only one daemon at a time can
/// claim the USB device — if the user already has Android Studio /
/// scrcpy / similar running a daemon at 5037, our private daemon would
/// be unable to see the phone.
/// </summary>
public sealed class AdbDiscovery : IDisposable
{
    public record Device(string Serial, string Model, string State, bool HasControllerApp)
    {
        /// <summary>Single-line "serial · state" subtitle for SettingsCard binding.</summary>
        public string Subtitle => $"{Serial} · {State}";

        /// <summary>
        /// Localized "App installed" tag bound from the device row template.
        /// Looking it up here keeps the DataTemplate static — no per-row
        /// code needed.
        /// </summary>
        public string AppInstalledLabel => Util.L.Get("discovery.usb.appInstalled", "已安装 App");
    }

    public event Action<IReadOnlyList<Device>>? OnUpdate;

    public int PollIntervalMs { get; set; } = 3000;

    /// <summary>Port to auto-forward via <c>adb reverse</c> on each new device.</summary>
    public int ReversePort { get; }

    private readonly DispatcherQueue _ui;
    private readonly Dictionary<string, string> _modelCache = new();
    private readonly Dictionary<string, bool> _appCache = new();
    // Serials we've already reverse-forwarded since last connect, so we
    // don't re-run adb reverse every 3 s. Cleared when the device drops.
    private readonly HashSet<string> _forwardedSerials = new();
    private CancellationTokenSource? _cts;
    // Cache of the last list we emitted. If a new poll produces an
    // equivalent list, we skip the OnUpdate call so the UI's ItemsControl
    // doesn't rebuild every 3 s and flicker.
    private List<Device>? _lastEmitted;

    // ===== Presence debouncing =====
    //
    // Single polls are unreliable: the adb daemon momentarily loses sight
    // of the device during a USB hot-plug glitch, during its own version-
    // mismatch restart dance, or simply because of timing between this
    // poll and adb's internal device enumeration. Without debouncing the
    // UI flickers — device row appears, vanishes 3 s later, reappears.
    // We keep a previously-seen device visible for up to MissThreshold
    // consecutive empty polls (~9 s at 3 s cadence) before treating it
    // as truly gone.
    private const int MissThreshold = 3;
    private readonly Dictionary<string, Device> _knownDevices = new();
    private readonly Dictionary<string, int> _missCount = new();

    public AdbDiscovery(DispatcherQueue ui, int reversePort)
    {
        _ui = ui;
        ReversePort = reversePort;
    }

    public void Start()
    {
        if (_cts != null) return;
        _cts = new CancellationTokenSource();
        _ = Task.Run(() => Loop(_cts.Token));
    }

    public void Stop()
    {
        _cts?.Cancel();
        _cts = null;
    }

    public void Dispose() => Stop();
    // Note: we deliberately don't kill the adb daemon on dispose. It
    // probably belongs to someone else on this machine (Android Studio,
    // scrcpy, etc.); ripping it out from under them on every quit is
    // unfriendly. If we forked it ourselves it'll keep running, no harm.

    private async Task Loop(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            try
            {
                var devices = await Probe(ct);
                if (!ListsEqual(devices, _lastEmitted))
                {
                    _lastEmitted = devices;
                    _ui.TryEnqueue(() => OnUpdate?.Invoke(devices));
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"[Adb] poll failed: {ex.Message}");
                if (_lastEmitted is null || _lastEmitted.Count > 0)
                {
                    _lastEmitted = new List<Device>();
                    _ui.TryEnqueue(() => OnUpdate?.Invoke(Array.Empty<Device>()));
                }
            }
            try { await Task.Delay(PollIntervalMs, ct); } catch (TaskCanceledException) { return; }
        }
    }

    private static bool ListsEqual(List<Device>? a, List<Device>? b)
    {
        if (ReferenceEquals(a, b)) return true;
        if (a is null || b is null) return false;
        if (a.Count != b.Count) return false;
        for (int i = 0; i < a.Count; i++)
        {
            if (!a[i].Equals(b[i])) return false;
        }
        return true;
    }

    private async Task<List<Device>> Probe(CancellationToken ct)
    {
        var raw = await RunAdb("devices", ct);
        var freshList = new List<Device>();
        foreach (var line in raw.Split('\n'))
        {
            var trimmed = line.Trim();
            if (string.IsNullOrEmpty(trimmed)) continue;
            if (trimmed.StartsWith("List of devices")) continue;
            if (trimmed.StartsWith("*")) continue;
            var parts = trimmed.Split('\t', 2);
            if (parts.Length < 2) parts = trimmed.Split(' ', 2, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length < 2) continue;
            var serial = parts[0].Trim();
            var state = parts[1].Trim();
            string model = await GetModel(serial, ct);
            bool hasApp = await HasControllerApp(serial, ct);
            freshList.Add(new Device(serial, model, state, hasApp));
        }

        // Merge freshList into _knownDevices with debouncing. A device
        // that just showed up resets its miss counter; one that's been
        // missing accumulates. Only on the MissThreshold-th miss do we
        // drop it from the visible list — so a single empty poll caused
        // by a daemon hiccup leaves the UI alone.
        var freshSerials = new HashSet<string>(freshList.Count);
        foreach (var d in freshList)
        {
            freshSerials.Add(d.Serial);
            _knownDevices[d.Serial] = d;
            _missCount.Remove(d.Serial);
        }
        foreach (var serial in new List<string>(_knownDevices.Keys))
        {
            if (freshSerials.Contains(serial)) continue;
            var miss = _missCount.GetValueOrDefault(serial, 0) + 1;
            if (miss >= MissThreshold)
            {
                _knownDevices.Remove(serial);
                _missCount.Remove(serial);
                _forwardedSerials.Remove(serial); // re-forward when it returns
            }
            else
            {
                _missCount[serial] = miss;
            }
        }

        // Auto-forward newly seen ready devices. We key off freshList,
        // not _knownDevices, so we don't waste a forward call on a row
        // that's currently in its grace-period miss window.
        foreach (var d in freshList)
        {
            if (d.State == "device" && _forwardedSerials.Add(d.Serial))
            {
                _ = AutoReverse(d.Serial, ct);
            }
        }

        return new List<Device>(_knownDevices.Values);
    }

    private async Task AutoReverse(string serial, CancellationToken ct)
    {
        try
        {
            await RunAdb($"-s {serial} reverse tcp:{ReversePort} tcp:{ReversePort}", ct);
            Debug.WriteLine($"[Adb] auto-forwarded port {ReversePort} for {serial}");
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[Adb] auto-forward for {serial} failed: {ex.Message}");
            // Allow retry on the next poll cycle.
            _forwardedSerials.Remove(serial);
        }
    }

    private async Task<string> GetModel(string serial, CancellationToken ct)
    {
        if (_modelCache.TryGetValue(serial, out var cached)) return cached;
        string model;
        try { model = (await RunAdb($"-s {serial} shell getprop ro.product.model", ct)).Trim(); }
        catch { model = serial; }
        if (string.IsNullOrEmpty(model)) model = serial;
        _modelCache[serial] = model;
        return model;
    }

    private async Task<bool> HasControllerApp(string serial, CancellationToken ct)
    {
        if (_appCache.TryGetValue(serial, out var cached)) return cached;
        try
        {
            var raw = await RunAdb($"-s {serial} shell pm list packages com.mccontroller", ct);
            var has = raw.Contains("package:com.mccontroller");
            _appCache[serial] = has;
            return has;
        }
        catch { _appCache[serial] = false; return false; }
    }

    // ===== adb invocation =====
    //
    // We wrap every adb call in `cmd.exe /c "adb args > tempfile 2>&1"`
    // rather than spawning adb directly with .NET's RedirectStandardOutput.
    // Two reasons:
    //
    //   (1) A WinUI app has no console attached. If we don't redirect
    //       adb's stdout/stderr to *something*, adb (and the daemon it
    //       may fork) inherit invalid handles and behave erratically —
    //       we observed empty output, exit 0, and runaway respawn loops.
    //
    //   (2) If we redirect via .NET's anonymous pipes, the daemon adb
    //       forks inherits the pipe's write end and keeps it open for
    //       the lifetime of the daemon (forever). Our ReadToEndAsync
    //       then waits for the pipe to close and hangs the polling loop.
    //
    // A file handle handed in by cmd.exe has neither problem: the daemon
    // can hold it open indefinitely without blocking us, and the file is
    // still readable once cmd.exe (and the adb client) exits.

    // Per-call timeout. Most adb commands complete in well under a second
    // once the daemon is up; if one takes longer something is wedged
    // (typically an unresponsive USB device or a version-mismatch fight
    // between two daemons) and we'd rather surface an empty poll than
    // block the discovery loop forever.
    private static readonly TimeSpan AdbCommandTimeout = TimeSpan.FromSeconds(10);

    private static async Task<string> RunAdb(string args, CancellationToken ct)
    {
        var adb = ResolveAdbPath();
        var tempOut = Path.Combine(Path.GetTempPath(), $"mcc_adb_{Guid.NewGuid():N}.txt");

        // Outer "..."  is consumed by cmd.exe's /c rule; the inner quoting
        // protects the adb path and the temp-file path (both may contain
        // spaces).
        var cmdArgs = $"/c \"\"{adb}\" {args} > \"{tempOut}\" 2>&1\"";
        var psi = new ProcessStartInfo("cmd.exe", cmdArgs)
        {
            UseShellExecute = false,
            CreateNoWindow = true,
        };

        using var proc = new Process { StartInfo = psi };
        try { proc.Start(); }
        catch (System.ComponentModel.Win32Exception)
        {
            try { File.Delete(tempOut); } catch { }
            return string.Empty;
        }

        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeout.CancelAfter(AdbCommandTimeout);
        try
        {
            await proc.WaitForExitAsync(timeout.Token);
        }
        catch (OperationCanceledException)
        {
            // Kill the wedged process tree (cmd.exe + adb client). The
            // daemon, if one was successfully forked along the way,
            // lives in a separate tree and survives — that's deliberate,
            // we want it to stick around for the next poll.
            try { if (!proc.HasExited) proc.Kill(entireProcessTree: true); } catch { }
            try { File.Delete(tempOut); } catch { }
            return string.Empty;
        }

        string content;
        try { content = await File.ReadAllTextAsync(tempOut, ct); }
        catch { content = string.Empty; }
        // Daemon may still hold an inherited handle on the file — that's
        // fine, the delete will just fail silently and Windows will GC
        // the file when the daemon eventually exits (or on next reboot).
        try { File.Delete(tempOut); } catch { }
        return content;
    }

    // Resolved once at first use. Order of preference:
    //
    //   1. If `adb` is on the user's PATH (Android Studio / platform-tools
    //      / scrcpy install / etc.), use that. The user's existing
    //      tooling has probably already started an adb daemon on port
    //      5037; reusing the SAME adb binary means client + daemon are
    //      always the same version, so we sidestep the version-mismatch
    //      dance that fights us when our v37 client meets a v35 daemon.
    //
    //   2. Otherwise, use the bundled adb shipped under Tools\Adb\ in
    //      the publish output (installed by the .iss script for end
    //      users). It'll spin up its own daemon on first call and take
    //      exclusive USB ownership — fine in the no-other-adb case.
    //
    //   3. As a last-ditch fallback (e.g. a dev tree with the bundled
    //      binaries stripped out and adb not on PATH), use the bare
    //      name "adb" and let Process.Start surface the failure.
    private static string? _resolvedAdbPath;

    private static string ResolveAdbPath()
    {
        if (_resolvedAdbPath != null) return _resolvedAdbPath;
        if (IsAdbOnPath())
        {
            _resolvedAdbPath = "adb";
            Debug.WriteLine("[Adb] using system adb on PATH");
            return _resolvedAdbPath;
        }
        var bundled = Path.Combine(AppContext.BaseDirectory, "Tools", "Adb", "adb.exe");
        if (File.Exists(bundled))
        {
            _resolvedAdbPath = bundled;
            Debug.WriteLine($"[Adb] using bundled adb at {bundled}");
            return _resolvedAdbPath;
        }
        _resolvedAdbPath = "adb";
        Debug.WriteLine("[Adb] WARNING: no bundled adb found, falling back to bare \"adb\"");
        return _resolvedAdbPath;
    }

    private static bool IsAdbOnPath()
    {
        // `where.exe adb` exits 0 if anything matching "adb" / "adb.exe"
        // is on PATH, 1 otherwise. It's a pure lookup — doesn't run adb
        // itself, so it's safe to call regardless of daemon state. The
        // 2 s wait is conservative; on a healthy system this returns in
        // milliseconds.
        try
        {
            var psi = new ProcessStartInfo("where.exe", "adb")
            {
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
            };
            using var proc = Process.Start(psi);
            if (proc == null) return false;
            if (!proc.WaitForExit(2000)) { try { proc.Kill(); } catch { } return false; }
            return proc.ExitCode == 0;
        }
        catch { return false; }
    }
}
