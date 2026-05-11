namespace McController.Core.Diag;

/// <summary>
/// Lock-light counters and connection state shared between the network layer
/// and the UI. Counters are monotonic; the UI samples them periodically and
/// computes per-second rates locally.
/// </summary>
public sealed class ConnectionStats
{
    private volatile bool _connected;
    private volatile string? _clientEndpoint;
    private volatile string? _mode;

    private long _joystickCount;
    private long _lookCount;
    private long _buttonCount;
    private long _udpDropped;

    public bool Connected
    {
        get => _connected;
        set => _connected = value;
    }

    public string? ClientEndpoint
    {
        get => _clientEndpoint;
        set => _clientEndpoint = value;
    }

    /// <summary>Display label, e.g. "WiFi (TCP+UDP)" or "USB (TCP only)".</summary>
    public string? Mode
    {
        get => _mode;
        set => _mode = value;
    }

    public long JoystickCount => Interlocked.Read(ref _joystickCount);
    public long LookCount => Interlocked.Read(ref _lookCount);
    public long ButtonCount => Interlocked.Read(ref _buttonCount);
    public long UdpDropped => Interlocked.Read(ref _udpDropped);

    public void IncrementJoystick() => Interlocked.Increment(ref _joystickCount);
    public void IncrementLook() => Interlocked.Increment(ref _lookCount);
    public void IncrementButton() => Interlocked.Increment(ref _buttonCount);
    public void IncrementUdpDropped() => Interlocked.Increment(ref _udpDropped);

    private readonly Queue<int> _rttSamples = new();
    private readonly object _rttLock = new();
    private const int RttWindowSize = 60;  // ~60 1Hz samples = 1 minute window

    public void RecordRtt(int rttMs)
    {
        lock (_rttLock)
        {
            _rttSamples.Enqueue(rttMs);
            while (_rttSamples.Count > RttWindowSize) _rttSamples.Dequeue();
        }
    }

    public (int p50, int p99) RttPercentiles()
    {
        int[] sorted;
        lock (_rttLock)
        {
            if (_rttSamples.Count == 0) return (0, 0);
            sorted = _rttSamples.ToArray();
        }
        Array.Sort(sorted);
        var p50 = sorted[sorted.Length / 2];
        var p99Idx = Math.Min((int)Math.Floor(sorted.Length * 0.99), sorted.Length - 1);
        var p99 = sorted[p99Idx];
        return (p50, p99);
    }

    public void OnDisconnect()
    {
        Connected = false;
        ClientEndpoint = null;
        Mode = null;
        Interlocked.Exchange(ref _joystickCount, 0);
        Interlocked.Exchange(ref _lookCount, 0);
        Interlocked.Exchange(ref _buttonCount, 0);
        Interlocked.Exchange(ref _udpDropped, 0);
        lock (_rttLock) _rttSamples.Clear();
    }
}
