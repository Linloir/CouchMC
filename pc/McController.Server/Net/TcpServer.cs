using System.Net;
using System.Net.Sockets;
using McController.Server.Diag;

namespace McController.Server.Net;

/// <summary>
/// Single-client TCP listener. Accepts one connection at a time; if a second
/// client tries to connect while one is active, the new connection is rejected.
/// Reads length-prefixed frames and dispatches via <see cref="OnPacket"/>.
///
/// Thread model: the accept and read loops run on background tasks.
/// <see cref="OnPacket"/> fires on the read loop thread. <see cref="Send"/>
/// is safe to call from any thread (guarded by an internal lock).
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

            // Demo: single-client. Reject new connections while one is active.
            if (_currentClient != null && _currentClient.Connected)
            {
                try { client.Close(); } catch { }
                continue;
            }

            client.NoDelay = true;
            _currentClient = client;
            _currentStream = client.GetStream();

            var endpoint = (IPEndPoint)client.Client.RemoteEndPoint!;
            _stats.Connected = true;
            _stats.ClientEndpoint = endpoint.ToString();
            OnClientConnected?.Invoke(endpoint);

            _ = Task.Run(() => RunReadLoop(client, ct));
        }
    }

    private async Task RunReadLoop(TcpClient client, CancellationToken ct)
    {
        var stream = client.GetStream();
        var buffer = new byte[4096];
        var filled = 0;

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
