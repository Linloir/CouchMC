using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Net;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.UI;
using McController.App.Services;
using McController.Core.Net;

namespace McController.App.Views;

/// <summary>
/// Device discovery view. Two sections:
///
/// - **USB**: polls <c>adb devices</c> every ~3 s. Each phone shows its
///   model + serial + state + "App installed" tag, on a ListView row
///   with WinUI 3's built-in hover/selection visuals.
/// - **LAN**: hooks the future UDP-broadcast discovery (Phase 2).
///
/// "当前连接" pill mirrors the live <see cref="Core.Diag.ConnectionStats"/>
/// state so the user can tell at a glance whether a phone is paired.
/// </summary>
public sealed partial class DeviceDiscoveryPage : Page
{
    private readonly ServerHost _host = App.Host;
    private readonly AdbDiscovery _adb;

    public DeviceDiscoveryPage()
    {
        InitializeComponent();
        _adb = new AdbDiscovery(DispatcherQueue);
        _adb.OnUpdate += OnAdbUpdate;

        // Collapse the InfoBar back into 0-height when the user dismisses
        // it; otherwise IsOpen=false leaves the layout slot allocated and
        // creates a permanent gap.
        AdbInfoBar.Closed += (_, _) => AdbInfoBar.Visibility = Visibility.Collapsed;

        Loaded += OnLoaded;
        Unloaded += OnUnloaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        StatusCard.Description = $"等待连接... · TCP/UDP {_host.Config.Port}";
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
        DispatcherQueue.TryEnqueue(() =>
        {
            StatusCard.Description = $"已连接: {ep}";
            SetPill("已连接", Color.FromArgb(255, 0x1A, 0x6E, 0x58), Color.FromArgb(255, 0x34, 0xD8, 0xB8));
        });
    }

    private void OnClientDisconnected()
    {
        DispatcherQueue.TryEnqueue(RefreshConnectionDisplay);
    }

    private void RefreshConnectionDisplay()
    {
        StatusCard.Description = $"等待连接... · TCP/UDP {_host.Config.Port}";
        SetPill("未连接", Color.FromArgb(255, 0x3A, 0x3A, 0x3A), Color.FromArgb(255, 0xBB, 0xBB, 0xBB));
    }

    private void SetPill(string text, Color bg, Color fg)
    {
        StatusPillText.Text = text;
        StatusPill.Background = new SolidColorBrush(bg);
        StatusPillText.Foreground = new SolidColorBrush(fg);
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
        AdbInfoBar.Visibility = Visibility.Visible;
        AdbInfoBar.IsOpen = true;
    }
}
