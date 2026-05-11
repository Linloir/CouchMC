using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Net;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using McController.App.Services;
using McController.Core.Diag;
using McController.Core.Net;

namespace McController.App.Views;

/// <summary>
/// Device discovery view. Two sections:
///
/// - **USB**: polls <c>adb devices</c> every ~3 s. Each phone shows its
///   model + serial + whether the controller app is installed.
/// - **LAN**: hooks the future UDP-broadcast discovery (Phase 2). For now
///   the section just states it's listening — phone-side advertising lands
///   in a follow-up commit.
///
/// "当前连接" pill mirrors the live <see cref="ConnectionStats"/> state so
/// the user can tell at a glance whether a phone is actually paired.
/// </summary>
public partial class DeviceDiscoveryPage : Page
{
    private readonly ServerHost _host = App.Host;
    private readonly AdbDiscovery _adb;

    public DeviceDiscoveryPage()
    {
        InitializeComponent();
        _adb = new AdbDiscovery(Dispatcher);
        _adb.OnUpdate += OnAdbUpdate;

        Loaded += OnLoaded;
        Unloaded += OnUnloaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        ListeningOnText.Text = $"TCP/UDP 34555 · 服务端口: {_host.Config.Port}";
        IpList.ItemsSource = _host.LocalIPv4s;
        SubscribeConnectionEvents();
        RefreshConnectionDisplay();
        _adb.Start();
    }

    private void OnUnloaded(object sender, RoutedEventArgs e)
    {
        UnsubscribeConnectionEvents();
        _adb.Stop();
    }

    // ===== Live connection display =====
    private void SubscribeConnectionEvents()
    {
        _host.Tcp.OnClientConnected += OnClientConnected;
        _host.Tcp.OnClientDisconnected += OnClientDisconnected;
    }

    private void UnsubscribeConnectionEvents()
    {
        _host.Tcp.OnClientConnected -= OnClientConnected;
        _host.Tcp.OnClientDisconnected -= OnClientDisconnected;
    }

    private void OnClientConnected(IPEndPoint ep)
    {
        Dispatcher.BeginInvoke(() =>
        {
            CurrentConnectionText.Text = $"已连接: {ep}";
            SetPill("已连接", "#1A6E58", "#34D8B8");
        });
    }

    private void OnClientDisconnected()
    {
        Dispatcher.BeginInvoke(RefreshConnectionDisplay);
    }

    private void RefreshConnectionDisplay()
    {
        CurrentConnectionText.Text = "等待连接...";
        SetPill("未连接", "#3A3A3A", "#BBB");
    }

    private void SetPill(string text, string bgHex, string fgHex)
    {
        StatusPillText.Text = text;
        StatusPill.Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString(bgHex));
        StatusPillText.Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString(fgHex));
    }

    // ===== ADB list =====
    private void OnAdbUpdate(IReadOnlyList<AdbDiscovery.Device> devices)
    {
        UsbDeviceList.ItemsSource = devices;
        UsbEmptyText.Visibility = devices.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    }

    private async void AdbReverse_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            var psi = new ProcessStartInfo("adb", $"reverse tcp:{_host.Config.Port} tcp:{_host.Config.Port}")
            {
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
            };
            using var proc = Process.Start(psi);
            if (proc is null) return;
            await proc.WaitForExitAsync();
        }
        catch { /* shown via stats if it actually broke something */ }
    }
}
