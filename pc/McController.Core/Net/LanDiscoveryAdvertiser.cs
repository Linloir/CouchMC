using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace McController.Core.Net;

/// <summary>
/// PC-side advertiser for the LAN discovery protocol (Channel A — UDP
/// broadcast). Sends a small ANNOUNCE packet to <c>255.255.255.255:34556</c>
/// plus each interface's directed broadcast address every ~1 s with jitter,
/// so an Android client listening on the same LAN can find this PC without
/// the user typing an IP.
///
/// See docs/discovery.md for the wire format and field semantics. This is
/// the canonical PC implementation; the Android client mirrors the
/// receiver-side rules.
/// </summary>
public sealed class LanDiscoveryAdvertiser : IDisposable
{
    /// <summary>UDP destination port for ANNOUNCE packets (one above the default TCP port).</summary>
    public const int DiscoveryPort = 34556;

    /// <summary>Current protocol version (bumped if the wire format changes incompatibly).</summary>
    public const byte ProtocolVersion = 0x01;

    /// <summary>msgType = ANNOUNCE.</summary>
    public const byte MsgAnnounce = 0x01;

    /// <summary>ASCII "MCCT" prefix that lets a listener cheaply reject foreign packets.</summary>
    private static readonly byte[] s_magic = { 0x4D, 0x43, 0x43, 0x54 };

    [Flags]
    public enum AnnounceFlags : byte
    {
        None         = 0,
        McForeground = 1 << 0,
        AcceptsUdp   = 1 << 1,
        Busy         = 1 << 2,
    }

    private readonly string _name;
    private readonly Func<int> _tcpPortProvider;
    private readonly Func<AnnounceFlags> _flagsProvider;
    private CancellationTokenSource? _cts;

    // Set to 1 by Start() and TriggerBurst() to request a 3-packet startup
    // burst (0/100/300 ms) on the next loop iteration. Reset to 0 once consumed.
    private int _burstPending;

    public LanDiscoveryAdvertiser(
        string name,
        Func<int> tcpPortProvider,
        Func<AnnounceFlags> flagsProvider)
    {
        _name = name ?? throw new ArgumentNullException(nameof(name));
        _tcpPortProvider = tcpPortProvider ?? throw new ArgumentNullException(nameof(tcpPortProvider));
        _flagsProvider = flagsProvider ?? throw new ArgumentNullException(nameof(flagsProvider));
    }

    public void Start()
    {
        if (_cts != null) return;
        _cts = new CancellationTokenSource();
        Interlocked.Exchange(ref _burstPending, 1);
        _ = Task.Run(() => Loop(_cts.Token));
    }

    public void Stop()
    {
        _cts?.Cancel();
        _cts = null;
    }

    public void Dispose() => Stop();

    /// <summary>
    /// Schedule a 3-packet burst on the next loop tick. Call after the
    /// listen port changes so phones already on the network re-learn the
    /// new port within ~300 ms instead of waiting for the next heartbeat.
    /// </summary>
    public void TriggerBurst() => Interlocked.Exchange(ref _burstPending, 1);

    private async Task Loop(CancellationToken ct)
    {
        var rng = new Random();
        while (!ct.IsCancellationRequested)
        {
            try
            {
                if (Interlocked.Exchange(ref _burstPending, 0) == 1)
                {
                    // Spec'd burst pattern: 0 / 100 / 300 ms after start (or port change).
                    Broadcast();
                    await Task.Delay(100, ct);
                    Broadcast();
                    await Task.Delay(200, ct);
                    Broadcast();
                }
                else
                {
                    Broadcast();
                }
                // Heartbeat cadence: 1000 ms ± 100 ms jitter.
                int delayMs = 900 + rng.Next(201);
                await Task.Delay(delayMs, ct);
            }
            catch (OperationCanceledException) { return; }
            catch (Exception ex)
            {
                Debug.WriteLine($"[Discovery] broadcast loop error: {ex.Message}");
                try { await Task.Delay(1000, ct); } catch { return; }
            }
        }
    }

    private void Broadcast()
    {
        var payload = EncodePayload();
        // A fresh UdpClient each tick is fine — sockets are cheap and the
        // alternative (long-lived socket bound per interface) means
        // re-binding when interfaces come and go (laptop closing the lid,
        // VPN connecting). Re-collecting the interface list each tick keeps
        // the advertiser correct under network changes.
        using var sock = new UdpClient();
        sock.EnableBroadcast = true;
        foreach (var ep in CollectBroadcastEndpoints())
        {
            try { sock.Send(payload, payload.Length, ep); }
            catch (SocketException) { /* one interface down shouldn't kill others */ }
        }
    }

    /// <summary>
    /// Pack the ANNOUNCE payload per docs/discovery.md §Channel A wire format.
    /// </summary>
    internal byte[] EncodePayload()
    {
        var nameBytes = Encoding.UTF8.GetBytes(_name);
        // Field is u16 length-prefixed but capped at 255 by spec.
        if (nameBytes.Length > 255)
        {
            // Truncate at a UTF-8 boundary so we don't emit a malformed
            // partial multi-byte character.
            var n = _name;
            while (Encoding.UTF8.GetByteCount(n) > 255 && n.Length > 0)
                n = n[..^1];
            nameBytes = Encoding.UTF8.GetBytes(n);
        }

        ushort port = (ushort)_tcpPortProvider();
        byte flags = (byte)_flagsProvider();
        ushort nameLen = (ushort)nameBytes.Length;

        var buf = new byte[11 + nameBytes.Length];
        buf[0] = s_magic[0]; buf[1] = s_magic[1];
        buf[2] = s_magic[2]; buf[3] = s_magic[3];
        buf[4] = ProtocolVersion;
        buf[5] = MsgAnnounce;
        buf[6] = flags;
        buf[7] = (byte)(port >> 8);
        buf[8] = (byte)(port & 0xFF);
        buf[9] = (byte)(nameLen >> 8);
        buf[10] = (byte)(nameLen & 0xFF);
        Array.Copy(nameBytes, 0, buf, 11, nameBytes.Length);
        return buf;
    }

    /// <summary>
    /// Returns the limited broadcast address (255.255.255.255) plus each
    /// active IPv4 interface's directed broadcast (e.g. 192.168.1.255) on
    /// <see cref="DiscoveryPort"/>. Sending to both forms maximizes reach
    /// across home routers that drop one or the other.
    /// </summary>
    private static List<IPEndPoint> CollectBroadcastEndpoints()
    {
        var list = new List<IPEndPoint>
        {
            new(IPAddress.Broadcast, DiscoveryPort),
        };
        try
        {
            foreach (var ni in NetworkInterface.GetAllNetworkInterfaces())
            {
                if (ni.OperationalStatus != OperationalStatus.Up) continue;
                if (ni.NetworkInterfaceType == NetworkInterfaceType.Loopback) continue;
                foreach (var ua in ni.GetIPProperties().UnicastAddresses)
                {
                    if (ua.Address.AddressFamily != AddressFamily.InterNetwork) continue;
                    var broadcast = ComputeBroadcastAddress(ua.Address, ua.IPv4Mask);
                    if (broadcast != null)
                        list.Add(new IPEndPoint(broadcast, DiscoveryPort));
                }
            }
        }
        catch
        {
            // Network info APIs can fail in odd VPN / sandbox situations.
            // We've still got the limited broadcast in the list.
        }
        return list;
    }

    private static IPAddress? ComputeBroadcastAddress(IPAddress ip, IPAddress mask)
    {
        if (mask == null || mask.Equals(IPAddress.None) || mask.Equals(IPAddress.Any))
            return null;
        var ipBytes = ip.GetAddressBytes();
        var maskBytes = mask.GetAddressBytes();
        if (ipBytes.Length != 4 || maskBytes.Length != 4) return null;
        var result = new byte[4];
        for (int i = 0; i < 4; i++)
            result[i] = (byte)(ipBytes[i] | (~maskBytes[i] & 0xFF));
        return new IPAddress(result);
    }
}
