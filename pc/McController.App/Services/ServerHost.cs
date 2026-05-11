using System;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using McController.Core.Config;
using McController.Core.Diag;
using McController.Core.Input;
using McController.Core.Net;

namespace McController.App.Services;

/// <summary>
/// Owns the server-side lifecycle: TCP/UDP listeners, input injector,
/// joystick/look/button routing, window-state polling. Exposes the live
/// objects so pages can bind to them.
///
/// Lifetime is bound to the app process — created in <see cref="App.OnLaunched"/>,
/// disposed when the main window closes. UI pages keep references to the
/// stats/config/curve objects directly (they're plain CLR data); changes
/// in the UI thread are picked up by the input thread on the next packet.
/// </summary>
public sealed class ServerHost : IDisposable
{
    public string ConfigPath { get; }
    public ServerConfig Config { get; private set; }
    public ConnectionStats Stats { get; }
    public WindowStateMonitor WindowMonitor { get; }
    public CameraCurve Curve { get; }
    public JoystickToWasdMapper Mapper { get; }
    public ButtonRouter Router { get; }
    public IInputInjector Injector { get; }
    public CursorInjector CursorInjector { get; }
    public TcpServer Tcp { get; }
    public UdpServer Udp { get; }

    public IReadOnlyList<string> LocalIPv4s => CollectLocalIPv4s();

    /// <summary>Fires after the server attempts a port bind. Null = success.</summary>
    public event Action<Exception?>? StartResult;

    private bool _disposed;

    public ServerHost(string configPath = "config.json")
    {
        ConfigPath = configPath;
        Config = ConfigStore.LoadOrDefault(configPath);
        Stats = new ConnectionStats();
        WindowMonitor = new WindowStateMonitor();
        Injector = new Win32InputInjector();
        Curve = new CameraCurve(Config);
        Mapper = new JoystickToWasdMapper(Injector, Config);
        Router = new ButtonRouter(Injector, Config);
        CursorInjector = new CursorInjector(WindowMonitor);
        Tcp = new TcpServer(Stats);
        Udp = new UdpServer(Stats);

        Tcp.OnPacket += HandlePacket;
        Tcp.OnClientConnected += ep => Stats.Mode ??= "TCP";
        Tcp.OnClientDisconnected += () =>
        {
            Mapper.ReleaseAll();
            Router.ReleaseAll();
            Stats.OnDisconnect();
            Udp.ResetSequence();
        };
        Udp.OnLookDelta += HandleLookDelta;
        WindowMonitor.OnModeChanged += newMode =>
        {
            Tcp.Send(PacketCodec.EncodeStateChange(newMode));
            if (newMode == Protocol.ControllerMode.AntiMistouch)
            {
                Mapper.ReleaseAll();
                Router.ReleaseAll();
            }
        };
    }

    public void Start()
    {
        try
        {
            Tcp.Start(Config.Port);
            Udp.Start(Config.Port);
            WindowMonitor.Start();
            StartResult?.Invoke(null);
        }
        catch (Exception ex)
        {
            StartResult?.Invoke(ex);
        }
    }

    public void SaveConfig() => ConfigStore.Save(ConfigPath, Config);

    /// <summary>
    /// Called when the user switches the active profile. Resets the curve
    /// residuals (sub-pixel carryover from previous profile would feel like
    /// a jolt) and releases any held inputs that the previous profile may
    /// have been driving.
    /// </summary>
    public void OnActiveProfileChanged()
    {
        Curve.Reset();
        Mapper.ReleaseAll();
        Router.ReleaseAll();
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        try { Mapper.ReleaseAll(); } catch { }
        try { Router.ReleaseAll(); } catch { }
        try { WindowMonitor.Stop(); } catch { }
        try { Tcp.Stop(); } catch { }
        try { Udp.Stop(); } catch { }
    }

    // Wire deltas are tenths-of-pixel (Android-side SUBPIXEL_SCALE = 10).
    private const float WireSubpixelScale = 10f;

    private void HandlePacket(ControlMessage msg)
    {
        switch (msg)
        {
            case HelloMsg hello:
                byte status = hello.ProtoVer == Protocol.Version
                    ? Protocol.HelloAckStatus.Ok
                    : Protocol.HelloAckStatus.ProtocolMismatch;
                ushort udpPort = hello.WantsUdp ? (ushort)Config.Port : (ushort)0;
                Tcp.Send(PacketCodec.EncodeHelloAck(status, udpPort));
                Stats.Mode = hello.WantsUdp ? "WiFi (TCP+UDP)" : "USB (TCP only)";
                Udp.ResetSequence();
                Curve.Reset();
                Mapper.ReleaseAll();
                Router.ReleaseAll();
                Tcp.Send(PacketCodec.EncodeStateChange(WindowMonitor.CurrentMode));
                break;

            case JoystickMsg j:
                Mapper.Update(j.X, j.Y);
                Stats.IncrementJoystick();
                break;

            case LookDeltaTcpMsg look:
                HandleLookDelta(look.Dx, look.Dy);
                break;

            case ButtonMsg btn:
                Router.Handle(btn.ButtonId, btn.Down);
                Stats.IncrementButton();
                break;

            case PingMsg ping:
                Tcp.Send(PacketCodec.EncodePong(ping.Seq));
                break;
        }
    }

    private void HandleLookDelta(short dx, short dy)
    {
        var fdx = dx / WireSubpixelScale;
        var fdy = dy / WireSubpixelScale;
        var (sdx, sdy) = Curve.Apply(fdx, fdy);
        if (sdx == 0 && sdy == 0) return;
        switch (WindowMonitor.CurrentMode)
        {
            case Protocol.ControllerMode.InGame:
                Injector.MouseMoveRelative(sdx, sdy);
                break;
            case Protocol.ControllerMode.UiInteract:
                CursorInjector.ApplyDelta(sdx, sdy);
                break;
            case Protocol.ControllerMode.AntiMistouch:
                break;
        }
        Stats.IncrementLook();
    }

    private static IReadOnlyList<string> CollectLocalIPv4s()
    {
        var result = new List<string>();
        foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
        {
            if (ni.OperationalStatus != OperationalStatus.Up) continue;
            if (ni.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
            foreach (var addr in ni.GetIPProperties().UnicastAddresses)
            {
                if (addr.Address.AddressFamily == AddressFamily.InterNetwork)
                {
                    result.Add($"{ni.Name}: {addr.Address}");
                }
            }
        }
        return result;
    }
}
