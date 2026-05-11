using McController.Core.Config;
using McController.Core.Input;
using McController.Core.Net;

namespace McController.Core.Tests;

public class ButtonRouterTests
{
    private static (FakeInputInjector inj, ButtonRouter router) MakeRouter()
    {
        var inj = new FakeInputInjector();
        return (inj, new ButtonRouter(inj, new ServerConfig()));
    }

    [Fact]
    public void Jump_RoutesToSpaceKey()
    {
        var (inj, r) = MakeRouter();
        r.Handle(Protocol.ButtonId.Jump, down: true);
        Assert.Single(inj.Calls);
        Assert.Equal(new FakeInputInjector.KeyCall(Scancodes.Space, true), inj.Calls[0]);
    }

    [Fact]
    public void MouseLeft_RoutesToMouseLeft()
    {
        var (inj, r) = MakeRouter();
        r.Handle(Protocol.ButtonId.MouseLeft, down: true);
        Assert.Single(inj.Calls);
        Assert.Equal(new FakeInputInjector.MouseCall(MouseButton.Left, true), inj.Calls[0]);
    }

    [Fact]
    public void DownThenUp_FiresBothEvents()
    {
        var (inj, r) = MakeRouter();
        r.Handle(Protocol.ButtonId.Jump, down: true);
        r.Handle(Protocol.ButtonId.Jump, down: false);
        Assert.Equal(2, inj.Calls.Count);
        Assert.Equal(new FakeInputInjector.KeyCall(Scancodes.Space, true), inj.Calls[0]);
        Assert.Equal(new FakeInputInjector.KeyCall(Scancodes.Space, false), inj.Calls[1]);
    }

    [Fact]
    public void UnknownButtonId_IsIgnored()
    {
        var (inj, r) = MakeRouter();
        r.Handle(0xEE, down: true);
        Assert.Empty(inj.Calls);
    }

    [Fact]
    public void HotbarSlots_RouteToNumberKeys()
    {
        var (inj, r) = MakeRouter();
        r.Handle(Protocol.ButtonId.Hotbar1, down: true);
        r.Handle(Protocol.ButtonId.Hotbar1, down: false);
        r.Handle(Protocol.ButtonId.Hotbar5, down: true);
        r.Handle(Protocol.ButtonId.Hotbar5, down: false);
        r.Handle(Protocol.ButtonId.Hotbar9, down: true);
        r.Handle(Protocol.ButtonId.Hotbar9, down: false);

        Assert.Contains(inj.Calls, c => c is FakeInputInjector.KeyCall { Scancode: Scancodes.K1, Down: true });
        Assert.Contains(inj.Calls, c => c is FakeInputInjector.KeyCall { Scancode: Scancodes.K5, Down: true });
        Assert.Contains(inj.Calls, c => c is FakeInputInjector.KeyCall { Scancode: Scancodes.K9, Down: true });
    }

    [Fact]
    public void ReleaseAll_ReleasesHeldButtons()
    {
        var (inj, r) = MakeRouter();
        r.Handle(Protocol.ButtonId.Jump, down: true);     // Space hold
        r.Handle(Protocol.ButtonId.MouseLeft, down: true); // mouse left hold
        r.Handle(Protocol.ButtonId.Sneak, down: true);    // shift hold (toggle in UI, hold on wire)
        inj.Clear();

        r.ReleaseAll();

        Assert.Contains(inj.Calls, c => c is FakeInputInjector.KeyCall { Scancode: Scancodes.Space, Down: false });
        Assert.Contains(inj.Calls, c => c is FakeInputInjector.MouseCall { Button: MouseButton.Left, Down: false });
        Assert.Contains(inj.Calls, c => c is FakeInputInjector.KeyCall { Scancode: Scancodes.LShift, Down: false });
    }

    [Fact]
    public void ReleaseAll_OnlyReleasesActuallyHeld()
    {
        var (inj, r) = MakeRouter();
        r.Handle(Protocol.ButtonId.Jump, down: true);
        r.Handle(Protocol.ButtonId.Jump, down: false);  // released
        inj.Clear();

        r.ReleaseAll();

        // Already up — should not emit another up event.
        Assert.Empty(inj.Calls);
    }

    [Fact]
    public void Tap_DownThenUp_LeavesNothingHeld()
    {
        var (inj, r) = MakeRouter();
        r.Handle(Protocol.ButtonId.Inventory, down: true);
        r.Handle(Protocol.ButtonId.Inventory, down: false);
        inj.Clear();

        r.ReleaseAll();
        Assert.Empty(inj.Calls);
    }
}
