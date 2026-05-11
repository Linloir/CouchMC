using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using McController.App.Services;
using Wpf.Ui.Controls;

namespace McController.App.Views;

/// <summary>
/// Device discovery view. Two sections:
///
/// - **USB**: polls <c>adb devices</c> every ~3 s. Each phone shows its
///   model + serial + state + "App installed" tag, on a hoverable row.
///   The "USB 端口转发" button runs <c>adb reverse</c> and surfaces the
///   result (success / no-adb / failure) via an inline <c>InfoBar</c>.
/// - **LAN**: hooks the future UDP-broadcast discovery (Phase 2). For now
///   the section just states it's listening — phone-side advertising lands
///   in a follow-up commit.
///
/// "当前连接" pill mirrors the live <see cref="Core.Diag.ConnectionStats"/>
/// state so the user can tell at a glance whether a phone is actually paired.
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

    private void Scroller_PreviewMouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (e.Handled) return;
        var sv = (ScrollViewer)sender;
        sv.ScrollToVerticalOffset(sv.VerticalOffset - e.Delta);
        e.Handled = true;
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
        ShowInfo("正在执行 adb reverse...", InfoBarSeverity.Informational);
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
            if (proc is null)
            {
                ShowInfo("无法启动 adb，请检查 PATH 中是否包含 platform-tools", InfoBarSeverity.Error);
                return;
            }
            var stderrTask = proc.StandardError.ReadToEndAsync();
            await proc.WaitForExitAsync();
            var stderr = await stderrTask;

            if (proc.ExitCode == 0)
            {
                ShowInfo($"已转发 tcp:{_host.Config.Port} → 手机本地。可在手机端连接 127.0.0.1。",
                         InfoBarSeverity.Success);
            }
            else
            {
                var msg = string.IsNullOrWhiteSpace(stderr) ? $"adb 退出码 {proc.ExitCode}" : stderr.Trim();
                ShowInfo($"adb reverse 失败：{msg}", InfoBarSeverity.Error);
            }
        }
        catch (System.ComponentModel.Win32Exception)
        {
            ShowInfo("未找到 adb，请将 platform-tools 加入 PATH", InfoBarSeverity.Error);
        }
        catch (Exception ex)
        {
            ShowInfo($"adb reverse 失败：{ex.Message}", InfoBarSeverity.Error);
        }
    }

    private void ShowInfo(string msg, InfoBarSeverity severity)
    {
        AdbInfoBar.Message = msg;
        AdbInfoBar.Severity = severity;
        AdbInfoBar.IsOpen = true;
    }
}
