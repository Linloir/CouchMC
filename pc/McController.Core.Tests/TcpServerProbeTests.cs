using System.Net;
using System.Net.Sockets;
using McController.Core.Diag;
using McController.Core.Net;

namespace McController.Core.Tests;

/// <summary>
/// Integration tests for TcpServer's PROBE / HELLO / session-busy handling.
/// Each test spins up a real listener on a free localhost port, exercises
/// the wire path via TcpClient, and asserts on the response bytes plus
/// the connection-event counters.
/// </summary>
public class TcpServerProbeTests
{
    [Fact]
    public async Task Probe_WhenIdle_RespondsAlive_NoConnectionEvents()
    {
        var (server, port, events) = StartServer();
        try
        {
            var status = await ProbeServer(port);
            Assert.Equal(Protocol.ProbeAckStatus.Alive, status);

            // Give events a beat to fire if they're going to.
            await Task.Delay(150);
            Assert.Equal(0, events.Connected);
            Assert.Equal(0, events.Disconnected);
        }
        finally { server.Stop(); }
    }

    [Fact]
    public async Task Probe_WhenSessionActive_RespondsBusy_NoExtraEvents()
    {
        var (server, port, events) = StartServer();
        try
        {
            using var session = await OpenSession(port);
            // Wait briefly for OnClientConnected to land on its thread.
            await events.WaitForConnected(timeoutMs: 1000);

            // Now probe — should see BUSY without disturbing the session.
            var status = await ProbeServer(port);
            Assert.Equal(Protocol.ProbeAckStatus.Busy, status);

            await Task.Delay(150);
            Assert.Equal(1, events.Connected);     // only the session
            Assert.Equal(0, events.Disconnected);  // session still alive
        }
        finally { server.Stop(); }
    }

    [Fact]
    public async Task Hello_WhenBusy_RespondsServerBusy_NoSecondConnectedEvent()
    {
        var (server, port, events) = StartServer();
        try
        {
            using var session = await OpenSession(port);
            await events.WaitForConnected(timeoutMs: 1000);

            using var intruder = new TcpClient();
            await intruder.ConnectAsync(IPAddress.Loopback, port);
            var s = intruder.GetStream();
            var hello = PacketCodec.EncodeHello(protoVer: Protocol.Version, clientId: 0, wantsUdp: false);
            await s.WriteAsync(hello);

            var status = await ReadHelloAckStatus(s);
            Assert.Equal(Protocol.HelloAckStatus.ServerBusy, status);

            await Task.Delay(150);
            // Still only one "connected" event — the rejected HELLO is not a session.
            Assert.Equal(1, events.Connected);
        }
        finally { server.Stop(); }
    }

    [Fact]
    public async Task Probe_DoesNotFireConnectionEvents_EvenWhenIdle()
    {
        // This is the regression that motivates the whole feature: the
        // Android home screen pings repeatedly; if probes fire connection
        // events the server's UI indicator would flicker every poll.
        var (server, port, events) = StartServer();
        try
        {
            for (int i = 0; i < 5; i++) await ProbeServer(port);
            await Task.Delay(200);
            Assert.Equal(0, events.Connected);
            Assert.Equal(0, events.Disconnected);
        }
        finally { server.Stop(); }
    }

    // ===== Helpers =====

    private sealed class EventCounters
    {
        private int _connected;
        private int _disconnected;
        private readonly TaskCompletionSource _connectedTcs = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public int Connected => Volatile.Read(ref _connected);
        public int Disconnected => Volatile.Read(ref _disconnected);
        public void MarkConnected() { Interlocked.Increment(ref _connected); _connectedTcs.TrySetResult(); }
        public void MarkDisconnected() { Interlocked.Increment(ref _disconnected); }
        public Task WaitForConnected(int timeoutMs) =>
            Task.WhenAny(_connectedTcs.Task, Task.Delay(timeoutMs));
    }

    private static (TcpServer server, int port, EventCounters events) StartServer()
    {
        var events = new EventCounters();
        var server = new TcpServer(new ConnectionStats());
        server.OnClientConnected += _ => events.MarkConnected();
        server.OnClientDisconnected += () => events.MarkDisconnected();
        // Also wire up a minimal HELLO responder so OpenSession's read of
        // HELLO_ACK doesn't hang. (Mirrors what ServerHost normally does.)
        server.OnPacket += msg =>
        {
            if (msg is HelloMsg hello)
            {
                byte status = hello.ProtoVer == Protocol.Version
                    ? Protocol.HelloAckStatus.Ok
                    : Protocol.HelloAckStatus.ProtocolMismatch;
                server.Send(PacketCodec.EncodeHelloAck(status, udpPort: 0));
            }
        };
        int port = ReserveFreePort();
        server.Start(port);
        return (server, port, events);
    }

    private static int ReserveFreePort()
    {
        var l = new TcpListener(IPAddress.Loopback, 0);
        l.Start();
        int port = ((IPEndPoint)l.LocalEndpoint).Port;
        l.Stop();
        return port;
    }

    private static async Task<byte> ProbeServer(int port)
    {
        using var c = new TcpClient();
        await c.ConnectAsync(IPAddress.Loopback, port);
        var s = c.GetStream();
        var probe = PacketCodec.EncodeProbe();
        await s.WriteAsync(probe);
        var buf = await ReadFully(s, 4);
        Assert.Equal(0x00, buf[0]);                       // len high
        Assert.Equal(0x02, buf[1]);                       // len low
        Assert.Equal(Protocol.MsgType.ProbeAck, buf[2]);  // type = PROBE_ACK
        return buf[3];                                    // status
    }

    private static async Task<TcpClient> OpenSession(int port)
    {
        var c = new TcpClient();
        await c.ConnectAsync(IPAddress.Loopback, port);
        var s = c.GetStream();
        await s.WriteAsync(PacketCodec.EncodeHello(Protocol.Version, clientId: 0, wantsUdp: false));
        await ReadHelloAckStatus(s);  // drain the ACK so the test isn't racing
        return c;
    }

    private static async Task<byte> ReadHelloAckStatus(NetworkStream s)
    {
        // HELLO_ACK frame: 00 04 02 <status> <udpPortHi> <udpPortLo>
        var buf = await ReadFully(s, 6);
        Assert.Equal(Protocol.MsgType.HelloAck, buf[2]);
        return buf[3];
    }

    private static async Task<byte[]> ReadFully(NetworkStream s, int count)
    {
        var buf = new byte[count];
        int read = 0;
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(2));
        while (read < count)
        {
            int n = await s.ReadAsync(buf.AsMemory(read, count - read), cts.Token);
            if (n <= 0) break;
            read += n;
        }
        Assert.Equal(count, read);
        return buf;
    }
}
