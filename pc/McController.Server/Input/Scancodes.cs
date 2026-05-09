namespace McController.Server.Input;

public static class Scancodes
{
    // Movement
    public const ushort W = 0x11;
    public const ushort A = 0x1E;
    public const ushort S = 0x1F;
    public const ushort D = 0x20;

    // Modifiers / movement modifiers
    public const ushort Space = 0x39;
    public const ushort LShift = 0x2A;
    public const ushort LCtrl = 0x1D;

    // Action keys
    public const ushort E = 0x12;
    public const ushort Q = 0x10;
    public const ushort F = 0x21;
    public const ushort Esc = 0x01;

    // Hotbar (number row 1..9)
    public const ushort K1 = 0x02;
    public const ushort K2 = 0x03;
    public const ushort K3 = 0x04;
    public const ushort K4 = 0x05;
    public const ushort K5 = 0x06;
    public const ushort K6 = 0x07;
    public const ushort K7 = 0x08;
    public const ushort K8 = 0x09;
    public const ushort K9 = 0x0A;
}
