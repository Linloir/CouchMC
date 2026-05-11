using McController.Core.Config;
using McController.Core.Input;

namespace McController.Core.Tests;

public class JoystickToWasdMapperTests
{
    private static (FakeInputInjector inj, JoystickToWasdMapper mapper) MakeMapper(
        float deadZone = 0.15f, float enter = 0.30f, float exit = 0.20f)
    {
        var cfg = new ServerConfig
        {
            Movement = new MovementConfig
            {
                DeadZone = deadZone,
                EnterThreshold = enter,
                ExitThreshold = exit,
            },
        };
        var inj = new FakeInputInjector();
        return (inj, new JoystickToWasdMapper(inj, cfg));
    }

    [Fact]
    public void DeadZone_NoKeyPress()
    {
        var (inj, m) = MakeMapper();
        m.Update(0.1f, 0.1f);
        Assert.Empty(inj.Calls);
    }

    [Fact]
    public void Forward_PressesW()
    {
        var (inj, m) = MakeMapper();
        m.Update(0f, 0.5f);  // y > enter
        Assert.Contains(inj.Calls, c => c is FakeInputInjector.KeyCall { Scancode: Scancodes.W, Down: true });
    }

    [Fact]
    public void Backward_PressesS()
    {
        var (inj, m) = MakeMapper();
        m.Update(0f, -0.5f);
        Assert.Contains(inj.Calls, c => c is FakeInputInjector.KeyCall { Scancode: Scancodes.S, Down: true });
    }

    [Fact]
    public void Right_PressesD()
    {
        var (inj, m) = MakeMapper();
        m.Update(0.5f, 0f);
        Assert.Contains(inj.Calls, c => c is FakeInputInjector.KeyCall { Scancode: Scancodes.D, Down: true });
    }

    [Fact]
    public void Diagonal_PressesBothAxes()
    {
        var (inj, m) = MakeMapper();
        m.Update(0.5f, 0.5f);  // forward + right
        Assert.Contains(inj.Calls, c => c is FakeInputInjector.KeyCall { Scancode: Scancodes.W, Down: true });
        Assert.Contains(inj.Calls, c => c is FakeInputInjector.KeyCall { Scancode: Scancodes.D, Down: true });
    }

    [Fact]
    public void Hysteresis_BetweenThresholds_DoesNotEnter()
    {
        var (inj, m) = MakeMapper(enter: 0.30f, exit: 0.20f);
        m.Update(0f, 0.25f);  // between exit (0.2) and enter (0.3), no prior press
        Assert.DoesNotContain(inj.Calls, c => c is FakeInputInjector.KeyCall { Down: true });
    }

    [Fact]
    public void Hysteresis_OnceEntered_StaysHeldAcrossTrough()
    {
        var (inj, m) = MakeMapper(enter: 0.30f, exit: 0.20f);
        m.Update(0f, 0.5f);   // enter
        inj.Clear();
        m.Update(0f, 0.25f);  // back to between exit and enter — should stay held
        Assert.DoesNotContain(inj.Calls, c => c is FakeInputInjector.KeyCall { Down: false });
    }

    [Fact]
    public void Hysteresis_FallsBelowExit_Releases()
    {
        var (inj, m) = MakeMapper(enter: 0.30f, exit: 0.20f);
        m.Update(0f, 0.5f);   // enter
        inj.Clear();
        m.Update(0f, 0.15f);  // below exit
        Assert.Contains(inj.Calls, c => c is FakeInputInjector.KeyCall { Scancode: Scancodes.W, Down: false });
    }

    [Fact]
    public void DirectionReverse_ReleasesOpposite_PressesNew()
    {
        var (inj, m) = MakeMapper();
        m.Update(0f, 0.5f);   // W down
        inj.Clear();
        m.Update(0f, -0.5f);  // reverse to S
        // Expect: W up THEN S down
        Assert.Contains(inj.Calls, c => c is FakeInputInjector.KeyCall { Scancode: Scancodes.W, Down: false });
        Assert.Contains(inj.Calls, c => c is FakeInputInjector.KeyCall { Scancode: Scancodes.S, Down: true });
        var wUpIdx = inj.Calls.FindIndex(c => c is FakeInputInjector.KeyCall { Scancode: Scancodes.W, Down: false });
        var sDownIdx = inj.Calls.FindIndex(c => c is FakeInputInjector.KeyCall { Scancode: Scancodes.S, Down: true });
        Assert.True(wUpIdx < sDownIdx, "W release must precede S press");
    }

    [Fact]
    public void ReleaseAll_ReleasesHeldKeys()
    {
        var (inj, m) = MakeMapper();
        m.Update(0.5f, 0.5f);  // W + D down
        inj.Clear();
        m.ReleaseAll();
        Assert.Contains(inj.Calls, c => c is FakeInputInjector.KeyCall { Scancode: Scancodes.W, Down: false });
        Assert.Contains(inj.Calls, c => c is FakeInputInjector.KeyCall { Scancode: Scancodes.D, Down: false });
    }

    [Fact]
    public void ReleaseAll_NoOp_IfNoneHeld()
    {
        var (inj, m) = MakeMapper();
        m.ReleaseAll();
        Assert.Empty(inj.Calls);
    }

    [Fact]
    public void AllThresholdsZero_ReleaseAtZero_StillReleases()
    {
        // Regression for "stuck A key" bug: with all thresholds at 0, sending
        // (0, 0) (release) must still lift the held key. The mapper now uses
        // <= for the dead-zone and exit-threshold checks.
        var (inj, m) = MakeMapper(deadZone: 0f, enter: 0f, exit: 0f);
        m.Update(0f, 0.5f);  // press W (0.5 > 0)
        inj.Clear();
        m.Update(0f, 0f);    // release event
        Assert.Contains(inj.Calls, c => c is FakeInputInjector.KeyCall { Scancode: Scancodes.W, Down: false });
    }

    [Fact]
    public void Stick_StuckBetweenExitEnter_DoesNotChatter()
    {
        var (inj, m) = MakeMapper(enter: 0.30f, exit: 0.20f);
        // Walk through threshold band repeatedly; key state should not flip
        m.Update(0f, 0.5f);  // W down
        inj.Clear();
        for (int i = 0; i < 10; i++)
        {
            m.Update(0f, 0.25f);  // in hysteresis band
        }
        Assert.Empty(inj.Calls);
    }
}
