using McController.Core.Input;

namespace McController.Core.Diag;

/// <summary>
/// Step 1 validation: drives mouse/keyboard via SendInput at 125Hz to verify
/// that injection works on this machine + Minecraft combination.
///
/// Invoked via the `--selftest` command-line argument.
/// </summary>
public static class SelfTest
{
    public static void Run()
    {
        Console.WriteLine("=== MC Controller — Self Test (SendInput @ 125Hz) ===");
        Console.WriteLine();
        Console.WriteLine("This will run a sequence of mouse/keyboard injections at 125Hz");
        Console.WriteLine("to validate that SendInput correctly drives Minecraft's view");
        Console.WriteLine("and movement smoothly.");
        Console.WriteLine();
        Console.WriteLine("PRECONDITIONS:");
        Console.WriteLine("  1. Open Minecraft Java Edition.");
        Console.WriteLine("  2. Spawn into a world (creative flat is recommended).");
        Console.WriteLine("  3. Make sure 'Enhance pointer precision' is OFF in Windows mouse settings.");
        Console.WriteLine("  4. Inside MC, set Mouse Sensitivity to 100% as a baseline.");
        Console.WriteLine();
        Console.WriteLine("After pressing Enter, you have 5 seconds to ALT-TAB into Minecraft.");
        Console.WriteLine();
        Console.Write("Press Enter to start...");
        Console.ReadLine();

        // Raise system timer resolution to ~1ms for the duration of the test.
        using var _ = PrecisionTimer.Raise(1);

        for (int i = 5; i > 0; i--)
        {
            Console.Write($"\rStarting in {i}...  ");
            Thread.Sleep(1000);
        }
        Console.WriteLine("\rStarting now!          ");

        var injector = new Win32InputInjector();
        const double frameMs = 8.0;  // 125Hz

        Console.WriteLine("[Test 1] Panning camera RIGHT smoothly (~1s, 125Hz)...");
        for (int i = 0; i < 125; i++)
        {
            injector.MouseMoveRelative(4, 0);
            PrecisionTimer.PreciseSleep(frameMs);
        }
        PrecisionTimer.PreciseSleep(500);

        Console.WriteLine("[Test 2] Panning camera LEFT smoothly (~1s, 125Hz)...");
        for (int i = 0; i < 125; i++)
        {
            injector.MouseMoveRelative(-4, 0);
            PrecisionTimer.PreciseSleep(frameMs);
        }
        PrecisionTimer.PreciseSleep(500);

        Console.WriteLine("[Test 3] Panning camera DOWN slightly (~0.5s, 125Hz)...");
        for (int i = 0; i < 60; i++)
        {
            injector.MouseMoveRelative(0, 3);
            PrecisionTimer.PreciseSleep(frameMs);
        }
        PrecisionTimer.PreciseSleep(500);

        Console.WriteLine("[Test 4] Panning camera UP smoothly (~0.5s, 125Hz)...");
        for (int i = 0; i < 60; i++)
        {
            injector.MouseMoveRelative(0, -3);
            PrecisionTimer.PreciseSleep(frameMs);
        }
        PrecisionTimer.PreciseSleep(500);

        Console.WriteLine("[Test 5] Walking forward (W held for 1.5s)...");
        injector.Key(Scancodes.W, down: true);
        PrecisionTimer.PreciseSleep(1500);
        injector.Key(Scancodes.W, down: false);
        PrecisionTimer.PreciseSleep(500);

        Console.WriteLine("[Test 6] Jumping (Space tap)...");
        injector.Key(Scancodes.Space, down: true);
        PrecisionTimer.PreciseSleep(50);
        injector.Key(Scancodes.Space, down: false);
        PrecisionTimer.PreciseSleep(500);

        Console.WriteLine("[Test 7] Mouse LEFT click (attack/break)...");
        injector.SetMouseButton(MouseButton.Left, down: true);
        PrecisionTimer.PreciseSleep(150);
        injector.SetMouseButton(MouseButton.Left, down: false);
        PrecisionTimer.PreciseSleep(500);

        Console.WriteLine("[Test 8] Mouse RIGHT click (use/place)...");
        injector.SetMouseButton(MouseButton.Right, down: true);
        PrecisionTimer.PreciseSleep(150);
        injector.SetMouseButton(MouseButton.Right, down: false);

        Console.WriteLine();
        Console.WriteLine("=== Self test complete ===");
        Console.WriteLine();
        Console.WriteLine("Expected: smooth camera panning (no stutter) + walk + jump + click.");
        Console.WriteLine();
        Console.Write("Press Enter to exit...");
        Console.ReadLine();
    }
}
