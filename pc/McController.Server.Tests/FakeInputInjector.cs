using McController.Server.Input;

namespace McController.Server.Tests;

/// <summary>
/// Records every injection call. Tests assert against <see cref="Calls"/>.
/// </summary>
public sealed class FakeInputInjector : IInputInjector
{
    public abstract record Call;
    public sealed record MoveCall(int Dx, int Dy) : Call;
    public sealed record MouseCall(MouseButton Button, bool Down) : Call;
    public sealed record KeyCall(ushort Scancode, bool Down) : Call;

    public List<Call> Calls { get; } = new();

    public void MouseMoveRelative(int dx, int dy) => Calls.Add(new MoveCall(dx, dy));
    public void SetMouseButton(MouseButton button, bool down) => Calls.Add(new MouseCall(button, down));
    public void Key(ushort scancode, bool down) => Calls.Add(new KeyCall(scancode, down));

    public void Clear() => Calls.Clear();
}
