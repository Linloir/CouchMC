using McController.Core.Config;

namespace McController.Core.Input;

/// <summary>
/// Translates a normalized joystick position [-1, 1] into WASD key state.
///
/// Convention: y > 0 means forward (W). Android flips screen-Y before sending.
///
/// Hysteresis (enter/exit thresholds) prevents jitter when the stick rests near
/// the activation boundary. If the user reverses direction across zero, the
/// previously-held key is released first.
/// </summary>
public sealed class JoystickToWasdMapper
{
    private readonly IInputInjector _injector;
    private readonly ServerConfig _config;
    private readonly object _lock = new();

    private bool _w, _a, _s, _d;

    public JoystickToWasdMapper(IInputInjector injector, ServerConfig config)
    {
        _injector = injector;
        _config = config;
    }

    public void Update(float x, float y)
    {
        lock (_lock)
        {
            UpdateAxis(y, ForwardKey(), BackKey(), ref _w, ref _s);
            UpdateAxis(x, RightKey(), LeftKey(), ref _d, ref _a);
        }
    }

    public void ReleaseAll()
    {
        lock (_lock)
        {
            if (_w) { _injector.Key(ForwardKey(), false); _w = false; }
            if (_a) { _injector.Key(LeftKey(),    false); _a = false; }
            if (_s) { _injector.Key(BackKey(),    false); _s = false; }
            if (_d) { _injector.Key(RightKey(),   false); _d = false; }
        }
    }

    // The four direction scancodes are resolved on every call rather than
    // cached, because the Key Bindings page edits ServerConfig.Movement_Keys
    // in place and we want the next sample to honour the new mapping
    // without forcing a profile reload. ParseScancode tolerates the user
    // typing values with or without the 0x prefix and falls back to the
    // hard-coded WASD defaults if the field is somehow blank.
    private ushort ForwardKey() => ParseScancode(_config.Movement_Keys.Forward, Scancodes.W);
    private ushort BackKey()    => ParseScancode(_config.Movement_Keys.Back,    Scancodes.S);
    private ushort LeftKey()    => ParseScancode(_config.Movement_Keys.Left,    Scancodes.A);
    private ushort RightKey()   => ParseScancode(_config.Movement_Keys.Right,   Scancodes.D);

    private static ushort ParseScancode(string? s, ushort fallback)
    {
        if (string.IsNullOrWhiteSpace(s)) return fallback;
        s = s.Trim();
        var span = s.StartsWith("0x", StringComparison.OrdinalIgnoreCase) ? s[2..] : s;
        return ushort.TryParse(span, System.Globalization.NumberStyles.HexNumber,
            System.Globalization.CultureInfo.InvariantCulture, out var v) ? v : fallback;
    }

    private void UpdateAxis(
        float v, ushort posKey, ushort negKey,
        ref bool posDown, ref bool negDown)
    {
        var cfg = _config.Movement;
        var abs = Math.Abs(v);

        // Use <= so that abs=0 (release event) always triggers release,
        // even when the user has set DeadZone or ExitThreshold to 0.
        if (abs <= cfg.DeadZone)
        {
            if (posDown) { _injector.Key(posKey, false); posDown = false; }
            if (negDown) { _injector.Key(negKey, false); negDown = false; }
            return;
        }

        if (v > 0)
        {
            // Target = posKey. Release opposite if held.
            if (negDown) { _injector.Key(negKey, false); negDown = false; }
            if (!posDown && abs > cfg.EnterThreshold)
            {
                _injector.Key(posKey, true);
                posDown = true;
            }
            else if (posDown && abs <= cfg.ExitThreshold)
            {
                _injector.Key(posKey, false);
                posDown = false;
            }
        }
        else
        {
            // Target = negKey.
            if (posDown) { _injector.Key(posKey, false); posDown = false; }
            if (!negDown && abs > cfg.EnterThreshold)
            {
                _injector.Key(negKey, true);
                negDown = true;
            }
            else if (negDown && abs <= cfg.ExitThreshold)
            {
                _injector.Key(negKey, false);
                negDown = false;
            }
        }
    }
}
