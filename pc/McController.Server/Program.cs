using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using McController.Server.Config;
using McController.Server.Diag;
using McController.Server.Input;
using McController.Server.Net;

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

var tcp = new TcpServer(stats);
var udp = new UdpServer(stats);

void HandleLookDelta(short dx, short dy)
{
    var (sdx, sdy) = curve.Apply(dx, dy);
    if (sdx != 0 || sdy != 0) injector.MouseMoveRelative(sdx, sdy);
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

try
{
    tcp.Start(cfg.Port);
    udp.Start(cfg.Port);
}
catch (SocketException ex)
{
    Console.Error.WriteLine($"Failed to bind port {cfg.Port}: {ex.Message}");
    Console.Error.WriteLine("Is another instance running, or is the port in use?");
    return;
}

PrintStartupBanner(cfg);

// Stats reporter (1 Hz). Only logs when a client is connected to keep idle quiet.
var statsCts = new CancellationTokenSource();
var statsTask = Task.Run(async () =>
{
    long lastJ = 0, lastL = 0, lastB = 0;
    var sw = System.Diagnostics.Stopwatch.StartNew();
    bool wasConnected = false;
    while (!statsCts.IsCancellationRequested)
    {
        try { await Task.Delay(1000, statsCts.Token).ConfigureAwait(false); }
        catch (OperationCanceledException) { break; }

        var elapsed = sw.Elapsed.TotalSeconds;
        sw.Restart();

        var j = stats.JoystickCount;
        var l = stats.LookCount;
        var b = stats.ButtonCount;

        if (stats.Connected)
        {
            var dj = (j - lastJ) / elapsed;
            var dl = (l - lastL) / elapsed;
            var db = (b - lastB) / elapsed;
            Console.WriteLine(
                $"  pkts/s: J={dj,5:F0} L={dl,5:F0} B={db,5:F0}   udpDropped={stats.UdpDropped}   mode={stats.Mode}");
        }
        else if (wasConnected)
        {
            Console.WriteLine("  (idle)");
        }

        wasConnected = stats.Connected;
        lastJ = j; lastL = l; lastB = b;
    }
});

// Wait for Ctrl+C
var exitEvent = new ManualResetEventSlim(false);
Console.CancelKeyPress += (_, e) => { e.Cancel = true; exitEvent.Set(); };
exitEvent.Wait();

Console.WriteLine();
Console.WriteLine("Shutting down...");
statsCts.Cancel();
mapper.ReleaseAll();
router.ReleaseAll();
tcp.Stop();
udp.Stop();
Console.WriteLine("Bye.");

static void PrintStartupBanner(ServerConfig cfg)
{
    Console.WriteLine("=== MC Controller — Server (Step 2) ===");
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
    Console.WriteLine($"Camera sensitivity: {cfg.Camera.UserSensitivity:F2}  curve: {cfg.Camera.CurveType}");
    Console.WriteLine($"Movement deadZone: {cfg.Movement.DeadZone:F2}  enter: {cfg.Movement.EnterThreshold:F2}  exit: {cfg.Movement.ExitThreshold:F2}");
    Console.WriteLine();
    Console.WriteLine("Press Ctrl+C to stop.");
    Console.WriteLine();
}
