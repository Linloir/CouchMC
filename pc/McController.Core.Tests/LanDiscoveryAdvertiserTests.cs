using System.Text;
using McController.Core.Net;

namespace McController.Core.Tests;

public class LanDiscoveryAdvertiserTests
{
    [Fact]
    public void EncodePayload_MatchesSpecExample()
    {
        // docs/discovery.md §Channel A worked example:
        // server "JonDesk", TCP port 34555, MC foregrounded, accepts UDP, not busy.
        var adv = new LanDiscoveryAdvertiser(
            name: "JonDesk",
            tcpPortProvider: () => 34555,
            flagsProvider: () => LanDiscoveryAdvertiser.AnnounceFlags.McForeground
                              | LanDiscoveryAdvertiser.AnnounceFlags.AcceptsUdp);

        // Note: the docs/discovery.md worked example shows the bytes
        // "87 0B" for port 34555, but 0x870B actually = 34571 (typo in
        // the spec). The correct big-endian encoding of 34555 is 0x86FB.
        var expected = new byte[]
        {
            0x4D, 0x43, 0x43, 0x54,                 // 'M' 'C' 'C' 'T'
            0x01,                                    // ver = 1
            0x01,                                    // msg = ANNOUNCE
            0x03,                                    // flags = mc_foreground | accepts_udp
            0x86, 0xFB,                              // tcpPort = 0x86FB = 34555
            0x00, 0x07,                              // nameLen = 7
            0x4A, 0x6F, 0x6E, 0x44, 0x65, 0x73, 0x6B,// "JonDesk"
        };

        Assert.Equal(expected, adv.EncodePayload());
    }

    [Fact]
    public void EncodePayload_EmptyName_Has11Bytes()
    {
        var adv = new LanDiscoveryAdvertiser(
            name: "",
            tcpPortProvider: () => 34555,
            flagsProvider: () => LanDiscoveryAdvertiser.AnnounceFlags.None);

        var bytes = adv.EncodePayload();
        Assert.Equal(11, bytes.Length);
        Assert.Equal(0x00, bytes[9]);   // nameLen high
        Assert.Equal(0x00, bytes[10]);  // nameLen low
    }

    [Fact]
    public void EncodePayload_TruncatesNameAbove255Bytes()
    {
        // 200 Chinese characters is ~600 UTF-8 bytes — must truncate to <= 255.
        var name = new string('字', 200);
        var adv = new LanDiscoveryAdvertiser(
            name: name,
            tcpPortProvider: () => 34555,
            flagsProvider: () => LanDiscoveryAdvertiser.AnnounceFlags.None);

        var bytes = adv.EncodePayload();
        int nameLen = (bytes[9] << 8) | bytes[10];
        Assert.True(nameLen <= 255, $"nameLen={nameLen} should be <= 255");
        Assert.Equal(11 + nameLen, bytes.Length);
        // The truncated name must still be valid UTF-8.
        Encoding.UTF8.GetString(bytes, 11, nameLen);
    }

    [Fact]
    public void EncodePayload_AllFlagsSet()
    {
        var adv = new LanDiscoveryAdvertiser(
            name: "x",
            tcpPortProvider: () => 0x1234,
            flagsProvider: () => LanDiscoveryAdvertiser.AnnounceFlags.McForeground
                              | LanDiscoveryAdvertiser.AnnounceFlags.AcceptsUdp
                              | LanDiscoveryAdvertiser.AnnounceFlags.Busy);

        var bytes = adv.EncodePayload();
        Assert.Equal(0x07, bytes[6]);   // flags byte
        Assert.Equal(0x12, bytes[7]);   // tcpPort high
        Assert.Equal(0x34, bytes[8]);   // tcpPort low
    }

    [Fact]
    public void EncodePayload_ReflectsLatestProviderValues()
    {
        // The advertiser must re-read its providers on each encode so flag
        // / port changes propagate without re-instantiation.
        int port = 34555;
        var flags = LanDiscoveryAdvertiser.AnnounceFlags.None;
        var adv = new LanDiscoveryAdvertiser(
            name: "x",
            tcpPortProvider: () => port,
            flagsProvider: () => flags);

        var first = adv.EncodePayload();
        Assert.Equal(0x00, first[6]);
        Assert.Equal(0x86, first[7]);   // 34555 high byte
        Assert.Equal(0xFB, first[8]);   // 34555 low byte

        port = 0xBEEF;
        flags = LanDiscoveryAdvertiser.AnnounceFlags.Busy;
        var second = adv.EncodePayload();
        Assert.Equal(0x04, second[6]);
        Assert.Equal(0xBE, second[7]);
        Assert.Equal(0xEF, second[8]);
    }
}
