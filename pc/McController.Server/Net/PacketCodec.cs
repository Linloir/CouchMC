using System.Buffers.Binary;
using System.Diagnostics.CodeAnalysis;

namespace McController.Server.Net;

/// <summary>
/// Stateless encode/decode for the wire protocol. All multi-byte fields are big-endian.
/// See docs/protocol.md for the spec.
///
/// TCP frame layout:
///   [u16 len][u8 type][payload (len-1 bytes)]
/// where 'len' counts the type byte + payload.
///
/// UDP datagram layout:
///   [u8 type][u32 seq][payload]
/// where the datagram boundary is the frame boundary.
/// </summary>
public static class PacketCodec
{
    // ===== Server-side outgoing (TCP) =====

    public static byte[] EncodeHelloAck(byte status, ushort udpPort)
    {
        // payload = status (1) + udpPort (2) = 3 bytes; len = 1 (type) + 3 = 4
        var buf = new byte[2 + 1 + 3];
        BinaryPrimitives.WriteUInt16BigEndian(buf.AsSpan(0, 2), 1 + 3);
        buf[2] = Protocol.MsgType.HelloAck;
        buf[3] = status;
        BinaryPrimitives.WriteUInt16BigEndian(buf.AsSpan(4, 2), udpPort);
        return buf;
    }

    public static byte[] EncodePong(uint seq)
    {
        var buf = new byte[2 + 1 + 4];
        BinaryPrimitives.WriteUInt16BigEndian(buf.AsSpan(0, 2), 1 + 4);
        buf[2] = Protocol.MsgType.Pong;
        BinaryPrimitives.WriteUInt32BigEndian(buf.AsSpan(3, 4), seq);
        return buf;
    }

    public static byte[] EncodeStateChange(Protocol.ControllerMode mode)
    {
        var buf = new byte[2 + 1 + 1];
        BinaryPrimitives.WriteUInt16BigEndian(buf.AsSpan(0, 2), 1 + 1);
        buf[2] = Protocol.MsgType.StateChange;
        buf[3] = (byte)mode;
        return buf;
    }

    // ===== TCP framing (incoming) =====

    /// <summary>
    /// Try to parse one frame from the start of <paramref name="buffer"/>.
    /// Returns false if the buffer doesn't yet contain a full frame.
    /// </summary>
    public static bool TryReadFrame(
        ReadOnlySpan<byte> buffer,
        out int consumed,
        [NotNullWhen(true)] out ControlMessage? msg)
    {
        msg = null;
        consumed = 0;

        if (buffer.Length < 3) return false;  // need at least len(2) + type(1)

        var len = BinaryPrimitives.ReadUInt16BigEndian(buffer[..2]);
        if (len < 1) return false;  // malformed
        if (buffer.Length < 2 + len) return false;  // partial

        var type = buffer[2];
        var payload = buffer.Slice(3, len - 1);
        msg = DecodeTcpPayload(type, payload);
        consumed = 2 + len;
        return true;
    }

    private static ControlMessage DecodeTcpPayload(byte type, ReadOnlySpan<byte> p)
    {
        return type switch
        {
            Protocol.MsgType.Hello when p.Length >= 6
                => new HelloMsg(p[0], BinaryPrimitives.ReadUInt32BigEndian(p.Slice(1, 4)), p[5] != 0),
            Protocol.MsgType.Joystick when p.Length >= 4
                => new JoystickMsg(
                    BinaryPrimitives.ReadInt16BigEndian(p[..2]) / 10000f,
                    BinaryPrimitives.ReadInt16BigEndian(p.Slice(2, 2)) / 10000f),
            Protocol.MsgType.LookDeltaTcp when p.Length >= 8
                => new LookDeltaTcpMsg(
                    BinaryPrimitives.ReadUInt32BigEndian(p[..4]),
                    BinaryPrimitives.ReadInt16BigEndian(p.Slice(4, 2)),
                    BinaryPrimitives.ReadInt16BigEndian(p.Slice(6, 2))),
            Protocol.MsgType.Button when p.Length >= 2
                => new ButtonMsg(p[0], p[1] != 0),
            Protocol.MsgType.Ping when p.Length >= 4
                => new PingMsg(BinaryPrimitives.ReadUInt32BigEndian(p[..4])),
            _ => new UnknownMsg(type, p.Length),
        };
    }

    // ===== UDP datagram (incoming) =====

    public static bool TryParseUdp(
        ReadOnlySpan<byte> datagram,
        [NotNullWhen(true)] out LookDeltaUdpMsg? msg)
    {
        msg = null;
        if (datagram.Length < 5) return false;  // type(1) + seq(4)

        var type = datagram[0];
        if (type != Protocol.MsgType.LookDeltaUdp) return false;
        if (datagram.Length < 1 + 4 + 4) return false;  // need type+seq+(dx,dy)

        var seq = BinaryPrimitives.ReadUInt32BigEndian(datagram.Slice(1, 4));
        var dx = BinaryPrimitives.ReadInt16BigEndian(datagram.Slice(5, 2));
        var dy = BinaryPrimitives.ReadInt16BigEndian(datagram.Slice(7, 2));
        msg = new LookDeltaUdpMsg(seq, dx, dy);
        return true;
    }

    // ===== Helpers used by tests / Android-side reference =====

    public static byte[] EncodeHello(byte protoVer, uint clientId, bool wantsUdp)
    {
        var buf = new byte[2 + 1 + 6];
        BinaryPrimitives.WriteUInt16BigEndian(buf.AsSpan(0, 2), 1 + 6);
        buf[2] = Protocol.MsgType.Hello;
        buf[3] = protoVer;
        BinaryPrimitives.WriteUInt32BigEndian(buf.AsSpan(4, 4), clientId);
        buf[8] = (byte)(wantsUdp ? 1 : 0);
        return buf;
    }

    public static byte[] EncodeJoystick(float x, float y)
    {
        var ix = (short)Math.Clamp((int)Math.Round(x * 10000f), short.MinValue, short.MaxValue);
        var iy = (short)Math.Clamp((int)Math.Round(y * 10000f), short.MinValue, short.MaxValue);
        var buf = new byte[2 + 1 + 4];
        BinaryPrimitives.WriteUInt16BigEndian(buf.AsSpan(0, 2), 1 + 4);
        buf[2] = Protocol.MsgType.Joystick;
        BinaryPrimitives.WriteInt16BigEndian(buf.AsSpan(3, 2), ix);
        BinaryPrimitives.WriteInt16BigEndian(buf.AsSpan(5, 2), iy);
        return buf;
    }

    public static byte[] EncodeButton(byte buttonId, bool down)
    {
        var buf = new byte[2 + 1 + 2];
        BinaryPrimitives.WriteUInt16BigEndian(buf.AsSpan(0, 2), 1 + 2);
        buf[2] = Protocol.MsgType.Button;
        buf[3] = buttonId;
        buf[4] = (byte)(down ? 1 : 0);
        return buf;
    }

    public static byte[] EncodePing(uint seq)
    {
        var buf = new byte[2 + 1 + 4];
        BinaryPrimitives.WriteUInt16BigEndian(buf.AsSpan(0, 2), 1 + 4);
        buf[2] = Protocol.MsgType.Ping;
        BinaryPrimitives.WriteUInt32BigEndian(buf.AsSpan(3, 4), seq);
        return buf;
    }

    public static byte[] EncodeLookDeltaUdp(uint seq, short dx, short dy)
    {
        var buf = new byte[1 + 4 + 4];
        buf[0] = Protocol.MsgType.LookDeltaUdp;
        BinaryPrimitives.WriteUInt32BigEndian(buf.AsSpan(1, 4), seq);
        BinaryPrimitives.WriteInt16BigEndian(buf.AsSpan(5, 2), dx);
        BinaryPrimitives.WriteInt16BigEndian(buf.AsSpan(7, 2), dy);
        return buf;
    }

    public static byte[] EncodeLookDeltaTcp(uint seq, short dx, short dy)
    {
        var buf = new byte[2 + 1 + 8];
        BinaryPrimitives.WriteUInt16BigEndian(buf.AsSpan(0, 2), 1 + 8);
        buf[2] = Protocol.MsgType.LookDeltaTcp;
        BinaryPrimitives.WriteUInt32BigEndian(buf.AsSpan(3, 4), seq);
        BinaryPrimitives.WriteInt16BigEndian(buf.AsSpan(7, 2), dx);
        BinaryPrimitives.WriteInt16BigEndian(buf.AsSpan(9, 2), dy);
        return buf;
    }
}
