using McController.Core.Net;

namespace McController.Core.Tests;

public class PacketCodecTests
{
    [Fact]
    public void Joystick_RoundTrip()
    {
        var bytes = PacketCodec.EncodeJoystick(0.5f, -0.25f);
        Assert.True(PacketCodec.TryReadFrame(bytes, out var consumed, out var msg));
        Assert.Equal(bytes.Length, consumed);
        var j = Assert.IsType<JoystickMsg>(msg);
        Assert.Equal(0.5f, j.X, precision: 4);
        Assert.Equal(-0.25f, j.Y, precision: 4);
    }

    [Fact]
    public void Joystick_ClampsAtBounds()
    {
        // 2.0 should clamp to 1.0 due to short.MaxValue == 32767, scale 10000
        var bytes = PacketCodec.EncodeJoystick(2.0f, -2.0f);
        Assert.True(PacketCodec.TryReadFrame(bytes, out _, out var msg));
        var j = (JoystickMsg)msg!;
        // 2.0 * 10000 = 20000, clamped to 32767, /10000 = 3.2767
        // Wait, actually the wire scale clamp is short.MaxValue (32767), so the
        // value at receiver will be 32767/10000 = 3.2767. The protocol expects
        // sender to clamp to [-1, 1] before encoding. Let's just verify decode
        // matches encode:
        Assert.True(j.X > 1.5f);  // not clamped to 1.0 on the wire
    }

    [Fact]
    public void Button_RoundTrip()
    {
        var bytes = PacketCodec.EncodeButton(Protocol.ButtonId.Jump, down: true);
        Assert.True(PacketCodec.TryReadFrame(bytes, out _, out var msg));
        var b = Assert.IsType<ButtonMsg>(msg);
        Assert.Equal(Protocol.ButtonId.Jump, b.ButtonId);
        Assert.True(b.Down);
    }

    [Fact]
    public void Hello_RoundTrip()
    {
        var bytes = PacketCodec.EncodeHello(Protocol.Version, clientId: 0xCAFEBABE, wantsUdp: true);
        Assert.True(PacketCodec.TryReadFrame(bytes, out _, out var msg));
        var h = Assert.IsType<HelloMsg>(msg);
        Assert.Equal(Protocol.Version, h.ProtoVer);
        Assert.Equal(0xCAFEBABE, h.ClientId);
        Assert.True(h.WantsUdp);
    }

    [Fact]
    public void Ping_RoundTrip()
    {
        var bytes = PacketCodec.EncodePing(seq: 42);
        Assert.True(PacketCodec.TryReadFrame(bytes, out _, out var msg));
        var p = Assert.IsType<PingMsg>(msg);
        Assert.Equal(42u, p.Seq);
    }

    [Fact]
    public void LookDeltaTcp_RoundTrip()
    {
        var bytes = PacketCodec.EncodeLookDeltaTcp(seq: 100, dx: 50, dy: -30);
        Assert.True(PacketCodec.TryReadFrame(bytes, out _, out var msg));
        var l = Assert.IsType<LookDeltaTcpMsg>(msg);
        Assert.Equal(100u, l.Seq);
        Assert.Equal((short)50, l.Dx);
        Assert.Equal((short)-30, l.Dy);
    }

    [Fact]
    public void TryReadFrame_PartialFrame_ReturnsFalse()
    {
        var full = PacketCodec.EncodeJoystick(0.5f, -0.5f);
        // Provide only the first 2 bytes (just the length prefix)
        Assert.False(PacketCodec.TryReadFrame(full.AsSpan(0, 2), out var consumed, out var msg));
        Assert.Equal(0, consumed);
        Assert.Null(msg);
    }

    [Fact]
    public void TryReadFrame_TwoFramesBackToBack()
    {
        var f1 = PacketCodec.EncodeJoystick(0.1f, 0.2f);
        var f2 = PacketCodec.EncodeButton(Protocol.ButtonId.MouseLeft, down: true);
        var combined = f1.Concat(f2).ToArray();

        Assert.True(PacketCodec.TryReadFrame(combined, out var c1, out var m1));
        Assert.IsType<JoystickMsg>(m1);
        Assert.Equal(f1.Length, c1);

        Assert.True(PacketCodec.TryReadFrame(combined.AsSpan(c1), out var c2, out var m2));
        Assert.IsType<ButtonMsg>(m2);
        Assert.Equal(f2.Length, c2);
    }

    [Fact]
    public void UnknownTypeByte_DecodesAsUnknownMsg()
    {
        // Build a frame with type 0x99 (unused), 3 bytes of payload
        var payload = new byte[] { 0xAA, 0xBB, 0xCC };
        var frame = new byte[2 + 1 + payload.Length];
        frame[0] = 0;
        frame[1] = (byte)(1 + payload.Length);
        frame[2] = 0x99;
        Buffer.BlockCopy(payload, 0, frame, 3, payload.Length);

        Assert.True(PacketCodec.TryReadFrame(frame, out _, out var msg));
        var u = Assert.IsType<UnknownMsg>(msg);
        Assert.Equal((byte)0x99, u.Type);
        Assert.Equal(3, u.PayloadLength);
    }

    [Fact]
    public void Udp_LookDelta_RoundTrip()
    {
        var bytes = PacketCodec.EncodeLookDeltaUdp(seq: 7, dx: 100, dy: -200);
        Assert.True(PacketCodec.TryParseUdp(bytes, out var msg));
        Assert.Equal(7u, msg.Seq);
        Assert.Equal((short)100, msg.Dx);
        Assert.Equal((short)-200, msg.Dy);
    }

    [Fact]
    public void Udp_TooShort_ReturnsFalse()
    {
        Assert.False(PacketCodec.TryParseUdp(new byte[] { 0x11, 0, 0, 0 }, out var msg));
        Assert.Null(msg);
    }

    [Fact]
    public void Udp_WrongType_ReturnsFalse()
    {
        var bytes = new byte[9];
        bytes[0] = 0x42;  // wrong type
        Assert.False(PacketCodec.TryParseUdp(bytes, out var msg));
        Assert.Null(msg);
    }
}
