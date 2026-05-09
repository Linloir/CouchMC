using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Windows.Forms;
using McController.Server.Config;
using McController.Server.Diag;
using McController.Server.Input;
using McController.Server.Net;
using McController.Server.Tuner;

if (args.Length > 0 && string.Equals(args[0], "--selftest", StringComparison.OrdinalIgnoreCase))
{
    SelfTest.Run();
    return;
}

const string ConfigPath = "config.json";
var cfg = ConfigStore.LoadOrDefault(ConfigPath);

var injector = new Win32InputInjector();
var curve = new CameraCurve(cfg);
var mapper = new JoystickToWasdMapper(injector, cfg);
var router = new ButtonRouter(injector, cfg);
var stats = new ConnectionStats();

var monitor = new WindowStateMonitor();
var cursorInjector = new CursorInjector(monitor);

var tcp = new TcpServer(stats);
var udp = new UdpServer(stats);

// Wire deltas come in tenths-of-pixel (Android-side SUBPIXEL_SCALE = 10),
// so divide before applying sensitivity. Float keeps the sub-pixel info
// for CameraCurve to accumulate via its own residual.
const float WIRE_SUBPIXEL_SCALE = 10f;
void HandleLookDelta(short dx, short dy)
{
    var fdx = dx / WIRE_SUBPIXEL_SCALE;
    var fdy = dy / WIRE_SUBPIXEL_SCALE;
    var (sdx, sdy) = curve.Apply(fdx, fdy);
    if (sdx == 0 && sdy == 0) return;
    switch (monitor.CurrentMode)
    {
        case Protocol.ControllerMode.InGame:
            // Raw-input style relative move into MC's GLFW capture.
            injector.MouseMoveRelative(sdx, sdy);
            break;
        case Protocol.ControllerMode.UiInteract:
            // Cooked cursor move (visible cursor), clamped to MC window.
            cursorInjector.ApplyDelta(sdx, sdy);
            break;
        case Protocol.ControllerMode.AntiMistouch:
            // Drop the delta — phone shouldn't be sending in this mode anyway.
            break;
    }
    stats.IncrementLook();
}

tcp.OnPacket += msg =>
{
    switch (msg)
    {
        case HelloMsg hello:
            Console.WriteLine($"[TCP] HELLO proto={hello.ProtoVer} clientId={hello.ClientId} wantsUdp={hello.WantsUdp}");
            byte status = hello.ProtoVer == Protocol.Version
                ? Protocol.HelloAckStatus.Ok
                : Protocol.HelloAckStatus.ProtocolMismatch;
            ushort udpPort = hello.WantsUdp ? (ushort)cfg.Port : (ushort)0;
            tcp.Send(PacketCodec.EncodeHelloAck(status, udpPort));
            stats.Mode = hello.WantsUdp ? "WiFi (TCP+UDP)" : "USB (TCP only)";
            udp.ResetSequence();
            curve.Reset();
            mapper.ReleaseAll();
            router.ReleaseAll();
            // Push current controller mode immediately so the client UI
            // doesn't render in-game widgets before knowing the real state.
            tcp.Send(PacketCodec.EncodeStateChange(monitor.CurrentMode));
            break;

        case JoystickMsg j:
            mapper.Update(j.X, j.Y);
            stats.IncrementJoystick();
            break;

        case LookDeltaTcpMsg look:
            HandleLookDelta(look.Dx, look.Dy);
            break;

        case ButtonMsg btn:
            router.Handle(btn.ButtonId, btn.Down);
            stats.IncrementButton();
            break;

        case PingMsg ping:
            tcp.Send(PacketCodec.EncodePong(ping.Seq));
            break;

        case UnknownMsg unk:
            Console.WriteLine($"[TCP] unknown msg type 0x{unk.Type:X2} ({unk.PayloadLength} B payload)");
            break;
    }
};

tcp.OnClientConnected += ep => Console.WriteLine($"[TCP] client connected: {ep}");
tcp.OnClientDisconnected += () =>
{
    Console.WriteLine("[TCP] client disconnected; releasing all keys/buttons");
    mapper.ReleaseAll();
    router.ReleaseAll();
    stats.OnDisconnect();
    udp.ResetSequence();
};

udp.OnLookDelta += HandleLookDelta;

monitor.OnModeChanged += newMode =>
{
    Console.WriteLine($"[Mode] -> {newMode}");
    tcp.Send(PacketCodec.EncodeStateChange(newMode));
    if (newMode == Protocol.ControllerMode.AntiMistouch)
    {
        // Safety: don't leave keys/buttons stuck if the user can't see the screen.
        mapper.ReleaseAll();
        router.ReleaseAll();
    }
    if (newMode == Protocol.ControllerMode.InGame)
    {
        // WASD scancodes get eaten by Chinese / Japanese IMEs in their
        // native input mode; force MC's foreground window to en-US so the
        // movement keys register reliably.
        InputLanguageManager.EnsureEnglishLayout();
    }
};

try
{
    tcp.Start(cfg.Port);
    udp.Start(cfg.Port);
    monitor.Start();
}
catch (SocketException ex)
{
    Console.Error.WriteLine($"Failed to bind port {cfg.Port}: {ex.Message}");
    Console.Error.WriteLine("Is another instance running, or is the port in use?");
    return;
}

PrintStartupBanner(cfg);

Application.EnableVisualStyles();
Application.SetCompatibleTextRenderingDefault(false);

using var form = new TuningForm(cfg, stats, monitor, ConfigPath);

// Ctrl+C in console gracefully closes the form (which triggers shutdown below).
Console.CancelKeyPress += (_, e) =>
{
    e.Cancel = true;
    if (form.IsHandleCreated)
    {
        try { form.Invoke(() => form.Close()); }
        catch { /* form may be closing already */ }
    }
};

Application.Run(form);

Console.WriteLine("Form closed; shutting down server...");
mapper.ReleaseAll();
router.ReleaseAll();
monitor.Stop();
tcp.Stop();
udp.Stop();
Console.WriteLine("Bye.");

static void PrintStartupBanner(ServerConfig cfg)
{
    Console.WriteLine("=== MC Controller — Server (Step 3) ===");
    Console.WriteLine();
    Console.WriteLine($"Listening on TCP+UDP port {cfg.Port}.");
    Console.WriteLine();
    Console.WriteLine("Local IPv4 addresses (use one of these in the Android app):");
    foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
    {
        if (ni.OperationalStatus != OperationalStatus.Up) continue;
        if (ni.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
        foreach (var addr in ni.GetIPProperties().UnicastAddresses)
        {
            if (addr.Address.AddressFamily == AddressFamily.InterNetwork)
            {
                Console.WriteLine($"  {ni.Name,-30}  {addr.Address}");
            }
        }
    }
    Console.WriteLine();
    Console.WriteLine("Tuning UI is open in a separate window. Close it (or press Ctrl+C here) to stop.");
    Console.WriteLine();
}
