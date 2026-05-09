using System.Net;
using System.Net.Sockets;
using McController.Server.Diag;

namespace McController.Server.Net;

/// <summary>
/// UDP listener for the camera channel. Discards out-of-order/duplicate
/// packets via the <see cref="LookDeltaUdpMsg.Seq"/> field. Captures the
/// client's UDP endpoint from the first valid packet (no separate handshake).
/// </summary>
public sealed class UdpServer : IDisposable
{
    private readonly ConnectionStats _stats;

    private UdpClient? _udp;
    private CancellationTokenSource? _cts;
    private Task? _loop;

    private uint _lastSeq;
    private bool _hasSeenSeq;

    public UdpServer(ConnectionStats stats)
    {
        _stats = stats;
    }

    /// <summary>Fired when an in-order LOOK_DELTA packet arrives.</summary>
    public event Action<short, short>? OnLookDelta;

    public IPEndPoint? ClientEndpoint { get; private set; }

    public void Start(int port)
    {
        if (_udp != null) throw new InvalidOperationException("Already started.");
        _cts = new CancellationTokenSource();
        _udp = new UdpClient(port);
        _loop = Task.Run(() => RunLoop(_cts.Token));
    }

    public void Stop()
    {
        try
        {
            _cts?.Cancel();
            _udp?.Close();
            _loop?.Wait(TimeSpan.FromSeconds(2));
        }
        catch
        {
            // best-effort
        }
        finally
        {
            _udp = null;
            _loop = null;
            _cts?.Dispose();
            _cts = null;
            _hasSeenSeq = false;
            _lastSeq = 0;
            ClientEndpoint = null;
        }
    }

    public void ResetSequence()
    {
        _hasSeenSeq = false;
        _lastSeq = 0;
        ClientEndpoint = null;
    }

    private async Task RunLoop(CancellationToken ct)
    {
        if (_udp == null) return;

        while (!ct.IsCancellationRequested)
        {
            UdpReceiveResult result;
            try
            {
                result = await _udp.ReceiveAsync(ct).ConfigureAwait(false);
            }
            catch (OperationCanceledException) { break; }
            catch (ObjectDisposedException) { break; }
            catch (SocketException) { break; }

            if (!PacketCodec.TryParseUdp(result.Buffer, out var msg)) continue;

            // Sequence-based reorder/loss handling. First packet is always accepted.
            if (_hasSeenSeq && msg.Seq <= _lastSeq)
            {
                _stats.IncrementUdpDropped();
                continue;
            }

            _lastSeq = msg.Seq;
            _hasSeenSeq = true;
            ClientEndpoint = result.RemoteEndPoint;

            try { OnLookDelta?.Invoke(msg.Dx, msg.Dy); }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"[UdpServer] OnLookDelta handler threw: {ex.Message}");
            }
        }
    }

    public void Dispose() => Stop();
}
