using System.Runtime.InteropServices;

namespace McController.Core.Input;

public enum MouseButton
{
    Left,
    Right,
    Middle,
}

public sealed partial class Win32InputInjector : IInputInjector
{
    [LibraryImport("user32.dll", SetLastError = true)]
    private static partial uint SendInput(uint cInputs, [In] INPUT[] pInputs, int cbSize);

    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT
    {
        public uint Type;
        public InputUnion U;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public MOUSEINPUT Mi;
        [FieldOffset(0)] public KEYBDINPUT Ki;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT
    {
        public int Dx;
        public int Dy;
        public uint MouseData;
        public uint DwFlags;
        public uint Time;
        public IntPtr DwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT
    {
        public ushort WVk;
        public ushort WScan;
        public uint DwFlags;
        public uint Time;
        public IntPtr DwExtraInfo;
    }

    private const uint INPUT_MOUSE = 0;
    private const uint INPUT_KEYBOARD = 1;

    private const uint MOUSEEVENTF_MOVE = 0x0001;
    private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    private const uint MOUSEEVENTF_LEFTUP = 0x0004;
    private const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    private const uint MOUSEEVENTF_RIGHTUP = 0x0010;
    private const uint MOUSEEVENTF_MIDDLEDOWN = 0x0020;
    private const uint MOUSEEVENTF_MIDDLEUP = 0x0040;

    private const uint KEYEVENTF_KEYUP = 0x0002;
    private const uint KEYEVENTF_SCANCODE = 0x0008;

    private static readonly int InputSize = Marshal.SizeOf<INPUT>();

    public void MouseMoveRelative(int dx, int dy)
    {
        var input = new INPUT
        {
            Type = INPUT_MOUSE,
            U = new InputUnion
            {
                Mi = new MOUSEINPUT
                {
                    Dx = dx,
                    Dy = dy,
                    DwFlags = MOUSEEVENTF_MOVE,
                },
            },
        };
        SendInput(1, [input], InputSize);
    }

    public void SetMouseButton(MouseButton button, bool down)
    {
        uint flag = button switch
        {
            MouseButton.Left => down ? MOUSEEVENTF_LEFTDOWN : MOUSEEVENTF_LEFTUP,
            MouseButton.Right => down ? MOUSEEVENTF_RIGHTDOWN : MOUSEEVENTF_RIGHTUP,
            MouseButton.Middle => down ? MOUSEEVENTF_MIDDLEDOWN : MOUSEEVENTF_MIDDLEUP,
            _ => throw new ArgumentOutOfRangeException(nameof(button)),
        };
        var input = new INPUT
        {
            Type = INPUT_MOUSE,
            U = new InputUnion
            {
                Mi = new MOUSEINPUT { DwFlags = flag },
            },
        };
        SendInput(1, [input], InputSize);
    }

    public void Key(ushort scancode, bool down)
    {
        uint flags = KEYEVENTF_SCANCODE;
        if (!down) flags |= KEYEVENTF_KEYUP;

        var input = new INPUT
        {
            Type = INPUT_KEYBOARD,
            U = new InputUnion
            {
                Ki = new KEYBDINPUT
                {
                    WScan = scancode,
                    DwFlags = flags,
                },
            },
        };
        SendInput(1, [input], InputSize);
    }
}
