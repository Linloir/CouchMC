namespace McController.Server.Net;

/// <summary>
/// Wire protocol constants, mirrored from docs/protocol.md.
/// Both Android and PC implementations must agree on these.
/// </summary>
public static class Protocol
{
    public const byte Version = 1;
    public const int DefaultPort = 34555;

    public static class MsgType
    {
        public const byte Hello         = 0x01;
        public const byte HelloAck      = 0x02;
        public const byte Joystick      = 0x10;
        public const byte LookDeltaTcp  = 0x11;  // TCP fallback for USB mode
        public const byte LookDeltaUdp  = 0x11;  // same byte, but on UDP channel
        public const byte Button        = 0x20;
        public const byte Ping          = 0xF0;
        public const byte Pong          = 0xF1;
    }

    public static class HelloAckStatus
    {
        public const byte Ok                   = 0;
        public const byte ProtocolMismatch     = 1;
        public const byte ServerBusy           = 2;
    }

    public static class ButtonId
    {
        public const byte MouseLeft  = 0x01;
        public const byte MouseRight = 0x02;
        public const byte Jump       = 0x10;
        public const byte Sneak      = 0x11;
        public const byte Sprint     = 0x12;
        public const byte Inventory  = 0x20;
        public const byte Drop       = 0x21;
        public const byte SwapHand   = 0x22;
        public const byte Esc        = 0x30;
        public const byte Hotbar1    = 0x40;
        public const byte Hotbar2    = 0x41;
        public const byte Hotbar3    = 0x42;
        public const byte Hotbar4    = 0x43;
        public const byte Hotbar5    = 0x44;
        public const byte Hotbar6    = 0x45;
        public const byte Hotbar7    = 0x46;
        public const byte Hotbar8    = 0x47;
        public const byte Hotbar9    = 0x48;
    }
}
