using McController.Server.Config;

namespace McController.Server.Input;

/// <summary>
/// Two-layer camera transform applied to raw look deltas before SendInput.
///
/// Layer 1 — Developer curve (hidden from end users in production):
///   Speed-dependent acceleration. Lets quick swipes turn the view fast
///   while slow drags stay precise for fine aim.
///
/// Layer 2 — User sensitivity:
///   Single 0.5..3.0 multiplier exposed in the user-facing UI.
///
/// A residual fractional component is carried across calls so that when
/// sensitivity is low, sequences of small deltas eventually accumulate
/// to a 1-pixel output instead of being truncated to zero.
/// </summary>
public sealed class CameraCurve
{
    private readonly ServerConfig _config;
    private float _residualX;
    private float _residualY;

    public CameraCurve(ServerConfig config)
    {
        _config = config;
    }

    public (int sdx, int sdy) Apply(int rawDx, int rawDy)
    {
        var cam = _config.Camera;
        var speed = MathF.Sqrt((float)(rawDx * rawDx + rawDy * rawDy));

        float accelMul = cam.CurveType switch
        {
            CurveType.Power => Math.Min(
                1f + cam.AccelFactor * MathF.Pow(speed, cam.AccelExp),
                cam.MaxAccelMultiplier),
            _ => 1f,
        };

        var scale = cam.UserSensitivity * accelMul;
        var fx = rawDx * scale + _residualX;
        var fy = rawDy * scale + _residualY;
        var ix = (int)MathF.Truncate(fx);
        var iy = (int)MathF.Truncate(fy);
        _residualX = fx - ix;
        _residualY = fy - iy;
        return (ix, iy);
    }

    public void Reset()
    {
        _residualX = 0;
        _residualY = 0;
    }
}
