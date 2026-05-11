using System.Net;
using System.Net.Sockets;
using McController.Core.Diag;

namespace McController.Core.Net;

/// <summary>
/// Single-client TCP listener. Accepts one *real* session at a time; if a
/// second client tries to HELLO while one is active, the new connection
/// receives HELLO_ACK with status=ServerBusy and closes. PROBE traffic is
/// served regardless of session state — see docs/protocol.md §PROBE/PROBE_ACK.
/// Reads length-prefixed frames and dispatches via <see cref="OnPacket"/>.
///
/// Thread model:
///   - Accept loop runs on a background task.
///   - Each accepted socket is handed to a per-connection task that peeks
///     the first frame and routes it. PROBE is fully handled in that task
///     (respond + close). A non-busy HELLO upgrades the task into the
///     active client's read loop. So the accept loop is never blocked by
///     either an active session or a slow probe peer.
///   - <see cref="OnPacket"/> fires on the active read-loop thread.
///   - <see cref="Send"/> is safe to call from any thread (guarded).
/// </summary>
public sealed class TcpServer : IDisposable
{
    private readonly ConnectionStats _stats;

    private TcpListener? _listener;
    private TcpClient? _currentClient;
    private NetworkStream? _currentStream;
    private CancellationTokenSource? _cts;
    private Task? _acceptLoop;
    private readonly object _sendLock = new();
    // Guards _currentClient against the race where two HELLOs arrive
    // concurrently from two new connections and both pass the busy check.
    private readonly object _sessionLock = new();

    /// <summary>How long we'll wait for the first frame after accept before giving up.</summary>
    private const int FirstFrameTimeoutMs = 5000;

    public TcpServer(ConnectionStats stats)
    {
        _stats = stats;
    }

    public event Action<ControlMessage>? OnPacket;
    public event Action<IPEndPoint>? OnClientConnected;
    public event Action? OnClientDisconnected;

    public void Start(int port)
    {
        if (_listener != null) throw new InvalidOperationException("Already started.");
        _cts = new CancellationTokenSource();
        _listener = new TcpListener(IPAddress.Any, port);
        _listener.Start();
        _acceptLoop = Task.Run(() => RunAcceptLoop(_cts.Token));
    }

    public void Stop()
    {
        try
        {
            _cts?.Cancel();
            _listener?.Stop();
            CloseCurrentClient();
            _acceptLoop?.Wait(TimeSpan.FromSeconds(2));
        }
        catch
        {
            // best-effort
        }
        finally
        {
            _listener = null;
            _acceptLoop = null;
            _cts?.Dispose();
            _cts = null;
        }
    }

    /// <summary>Send a frame to the current client. No-op if no client is connected.</summary>
    public void Send(byte[] frame)
    {
        lock (_sendLock)
        {
            var stream = _currentStream;
            if (stream == null) return;
            try
            {
                stream.Write(frame, 0, frame.Length);
            }
            catch
            {
                // socket dying; the read loop will clean up
            }
        }
    }

    private async Task RunAcceptLoop(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested && _listener != null)
        {
            TcpClient client;
            try
            {
                client = await _listener.AcceptTcpClientAsync(ct).ConfigureAwait(false);
            }
            catch (OperationCanceledException) { break; }
            catch (ObjectDisposedException) { break; }
            catch (SocketException) { break; }

            // Always accept the socket here. The first-frame router decides
            // whether it's a probe (cheap reply + close, no events) or a
            // session HELLO (busy → reject with HELLO_ACK; free → become
            // the active client). Fire-and-forget so the accept loop keeps
            // running while a real session is active.
            client.NoDelay = true;
            _ = Task.Run(() => RouteNewConnection(client, ct));
        }
    }

    private async Task RouteNewConnection(TcpClient client, CancellationToken ct)
    {
        NetworkStream stream;
        try { stream = client.GetStream(); }
        catch { try { client.Close(); } catch { } return; }

        // Read the first frame with a bounded timeout so a half-open peer
        // (sends nothing) can't tie up a per-connection task forever.
        var (msg, remainder) = await ReadFirstFrame(stream, ct);
        if (msg == null)
        {
            try { client.Close(); } catch { }
            return;
        }

        switch (msg)
        {
            case ProbeMsg:
                HandleProbe(client, stream);
                return;

            case HelloMsg hello:
                HandleFirstHello(client, stream, hello, remainder, ct);
                return;

            default:
                // Any other first frame is a protocol error from a client
                // that isn't following the spec. Close quietly.
                try { client.Close(); } catch { }
                return;
        }
    }

    /// <summary>
    /// Read enough bytes from <paramref name="stream"/> to decode one frame,
    /// applying a hard timeout. Returns the decoded message + any extra
    /// bytes that arrived in the same read (to be replayed into the read
    /// loop's buffer if the connection is promoted to a session).
    /// </summary>
    private static async Task<(ControlMessage? msg, byte[]? extra)> ReadFirstFrame(
        NetworkStream stream, CancellationToken outerCt)
    {
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(outerCt);
        cts.CancelAfter(FirstFrameTimeoutMs);

        var buf = new byte[4096];
        int filled = 0;
        while (filled < buf.Length)
        {
            int n;
            try
            {
                n = await stream.ReadAsync(buf.AsMemory(filled, buf.Length - filled), cts.Token)
                                .ConfigureAwait(false);
            }
            catch { return (null, null); }
            if (n <= 0) return (null, null);
            filled += n;
            if (PacketCodec.TryReadFrame(new ReadOnlySpan<byte>(buf, 0, filled), out var consumed, out var msg))
            {
                int extraLen = filled - consumed;
                byte[]? extra = null;
                if (extraLen > 0)
                {
                    extra = new byte[extraLen];
                    Array.Copy(buf, consumed, extra, 0, extraLen);
                }
                return (msg, extra);
            }
        }
        return (null, null);
    }

    private void HandleProbe(TcpClient client, NetworkStream stream)
    {
        // ALIVE if no real session is in flight; BUSY otherwise. The protocol
        // version mismatch case currently can't surface here because PROBE
        // carries no version field — reserved for future use.
        byte status = (_currentClient != null && _currentClient.Connected)
            ? Protocol.ProbeAckStatus.Busy
            : Protocol.ProbeAckStatus.Alive;
        try
        {
            var ack = PacketCodec.EncodeProbeAck(status);
            stream.Write(ack, 0, ack.Length);
        }
        catch { /* peer hung up between accept and write; nothing to do */ }
        try { client.Close(); } catch { }
        // Intentionally NO OnClientConnected / OnClientDisconnected here —
        // probes must be invisible to the UI's connection indicator.
    }

    private void HandleFirstHello(
        TcpClient client, NetworkStream stream, HelloMsg hello, byte[]? remainder, CancellationToken ct)
    {
        bool busy;
        lock (_sessionLock)
        {
            busy = _currentClient != null && _currentClient.Connected;
            if (!busy)
            {
                _currentClient = client;
                _currentStream = stream;
            }
        }

        if (busy)
        {
            // Tell the peer we're occupied and close. No events fired —
            // this isn't a successful session.
            try
            {
                var nack = PacketCodec.EncodeHelloAck(Protocol.HelloAckStatus.ServerBusy, 0);
                stream.Write(nack, 0, nack.Length);
            }
            catch { }
            try { client.Close(); } catch { }
            return;
        }

        // Become the active session.
        var endpoint = (IPEndPoint)client.Client.RemoteEndPoint!;
        _stats.Connected = true;
        _stats.ClientEndpoint = endpoint.ToString();
        OnClientConnected?.Invoke(endpoint);

        // The HELLO message itself still needs to be delivered to subscribers
        // (they generate HELLO_ACK from it). Do that on the read loop thread
        // for consistent ordering with subsequent packets.
        _ = Task.Run(() => RunReadLoop(client, hello, remainder, ct));
    }

    private async Task RunReadLoop(TcpClient client, HelloMsg initialHello, byte[]? initialExtra, CancellationToken ct)
    {
        var stream = client.GetStream();
        var buffer = new byte[4096];
        var filled = 0;

        // Dispatch the HELLO we already read in RouteNewConnection.
        try { OnPacket?.Invoke(initialHello); }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[TcpServer] OnPacket handler threw on HELLO: {ex.Message}");
        }

        // Seed the read buffer with anything that arrived alongside the
        // HELLO (it's rare but possible — TCP doesn't preserve packet
        // boundaries, so the client could have batched HELLO + JOYSTICK
        // in a single send).
        if (initialExtra != null && initialExtra.Length > 0)
        {
            Array.Copy(initialExtra, 0, buffer, 0, initialExtra.Length);
            filled = initialExtra.Length;
            ProcessAndCompactBuffer(buffer, ref filled);
        }

        try
        {
            while (!ct.IsCancellationRequested)
            {
                int read;
                try
                {
                    read = await stream.ReadAsync(buffer.AsMemory(filled, buffer.Length - filled), ct)
                                        .ConfigureAwait(false);
                }
                catch (OperationCanceledException) { break; }
                catch (IOException) { break; }
                catch (ObjectDisposedException) { break; }

                if (read <= 0) break;
                filled += read;

                if (!ProcessAndCompactBuffer(buffer, ref filled))
                {
                    Console.Error.WriteLine("[TcpServer] frame exceeds buffer; closing connection.");
                    break;
                }
            }
        }
        finally
        {
            CloseCurrentClient();
            OnClientDisconnected?.Invoke();
        }
    }

    /// <summary>
    /// Processes whole frames from the start of <paramref name="buffer"/>, fires events,
    /// and compacts any partial trailing data. Returns false if the buffer is full but
    /// no frame can be parsed (frame larger than buffer = protocol violation).
    /// Synchronous because async methods can't hold ref-struct locals (C# 12).
    /// </summary>
    private bool ProcessAndCompactBuffer(byte[] buffer, ref int filled)
    {
        int consumed = 0;
        while (consumed < filled)
        {
            var slice = new ReadOnlySpan<byte>(buffer, consumed, filled - consumed);
            if (!PacketCodec.TryReadFrame(slice, out var frameLen, out var msg)) break;
            consumed += frameLen;
            try { OnPacket?.Invoke(msg); }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"[TcpServer] OnPacket handler threw: {ex.Message}");
            }
        }
        if (consumed > 0)
        {
            Array.Copy(buffer, consumed, buffer, 0, filled - consumed);
            filled -= consumed;
        }
        return filled < buffer.Length;
    }

    private void CloseCurrentClient()
    {
        lock (_sendLock)
        {
            try { _currentStream?.Dispose(); } catch { }
            try { _currentClient?.Close(); } catch { }
            _currentStream = null;
            _currentClient = null;
        }
    }

    public void Dispose() => Stop();
}
