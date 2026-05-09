namespace McController.Server.Input;

/// <summary>
/// Abstraction over OS-level input injection. Win32InputInjector is the
/// production implementation; tests use a mock that records calls.
/// </summary>
public interface IInputInjector
{
    void MouseMoveRelative(int dx, int dy);
    void SetMouseButton(MouseButton button, bool down);
    void Key(ushort scancode, bool down);
}
