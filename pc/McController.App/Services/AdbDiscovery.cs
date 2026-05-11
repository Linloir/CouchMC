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
/// </summary>
public sealed class AdbDiscovery : IDisposable
{
    public record Device(string Serial, string Model, string State, bool HasControllerApp);

    public event Action<IReadOnlyList<Device>>? OnUpdate;

    public int PollIntervalMs { get; set; } = 3000;

    private readonly DispatcherQueue _ui;
    private readonly Dictionary<string, string> _modelCache = new();
    private readonly Dictionary<string, bool> _appCache = new();
    private CancellationTokenSource? _cts;

    public AdbDiscovery(DispatcherQueue ui)
    {
        _ui = ui;
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

    private async Task Loop(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            try
            {
                var devices = await Probe(ct);
                _ui.TryEnqueue(() => OnUpdate?.Invoke(devices));
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"[Adb] poll failed: {ex.Message}");
                _ui.TryEnqueue(() => OnUpdate?.Invoke(Array.Empty<Device>()));
            }
            try { await Task.Delay(PollIntervalMs, ct); } catch (TaskCanceledException) { return; }
        }
    }

    private async Task<List<Device>> Probe(CancellationToken ct)
    {
        var raw = await RunAdb("devices", ct);
        var list = new List<Device>();
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
            list.Add(new Device(serial, model, state, hasApp));
        }
        return list;
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

    private static async Task<string> RunAdb(string args, CancellationToken ct)
    {
        var psi = new ProcessStartInfo("adb", args)
        {
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true,
        };
        using var proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
        try { proc.Start(); }
        catch (System.ComponentModel.Win32Exception)
        {
            return string.Empty;
        }
        var stdoutTask = proc.StandardOutput.ReadToEndAsync(ct);
        await proc.WaitForExitAsync(ct);
        return await stdoutTask;
    }
}
