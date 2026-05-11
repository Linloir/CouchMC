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
        _adb = new AdbDiscovery(DispatcherQueue, _host.Config.Port);
        _adb.OnUpdate += OnAdbUpdate;

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

}
