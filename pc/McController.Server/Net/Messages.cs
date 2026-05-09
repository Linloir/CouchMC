namespace McController.Server.Net;

/// <summary>
/// Decoded form of a TCP control packet. Discriminated by record type
/// so callers can pattern-match.
/// </summary>
public abstract record ControlMessage;

public sealed record HelloMsg(byte ProtoVer, uint ClientId, bool WantsUdp) : ControlMessage;
public sealed record JoystickMsg(float X, float Y) : ControlMessage;
public sealed record LookDeltaTcpMsg(uint Seq, short Dx, short Dy) : ControlMessage;
public sealed record ButtonMsg(byte ButtonId, bool Down) : ControlMessage;
public sealed record PingMsg(uint Seq) : ControlMessage;

/// <summary>Unrecognized type byte — caller can log and ignore.</summary>
public sealed record UnknownMsg(byte Type, int PayloadLength) : ControlMessage;

/// <summary>UDP camera datagram. Carried on its own (non-TCP) channel.</summary>
public sealed record LookDeltaUdpMsg(uint Seq, short Dx, short Dy);
