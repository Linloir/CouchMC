using McController.Server.Config;
using McController.Server.Input;

namespace McController.Server.Tests;

public class CameraCurveTests
{
    private static CameraCurve MakeCurve(
        float sensitivity = 1.5f,
        CurveType type = CurveType.Linear,
        float accelFactor = 0f,
        float accelExp = 1f,
        float maxMul = 3f)
    {
        return new CameraCurve(new ServerConfig
        {
            Camera = new CameraConfig
            {
                UserSensitivity = sensitivity,
                CurveType = type,
                AccelFactor = accelFactor,
                AccelExp = accelExp,
                MaxAccelMultiplier = maxMul,
            },
        });
    }

    [Fact]
    public void Linear_AppliesSensitivityScale()
    {
        var curve = MakeCurve(sensitivity: 2.0f);
        var (sdx, sdy) = curve.Apply(10, -5);
        Assert.Equal(20, sdx);
        Assert.Equal(-10, sdy);
    }

    [Fact]
    public void Linear_PassesThroughAtSensitivity1()
    {
        var curve = MakeCurve(sensitivity: 1.0f);
        var (sdx, sdy) = curve.Apply(7, -3);
        Assert.Equal(7, sdx);
        Assert.Equal(-3, sdy);
    }

    [Fact]
    public void Residual_AccumulatesSmallDeltasIntoIntegerOutput()
    {
        // sensitivity 0.4, raw delta (1, 0): each call produces 0.4
        // after 3 calls: 1.2 -> truncate 1
        var curve = MakeCurve(sensitivity: 0.4f);
        Assert.Equal((0, 0), curve.Apply(1, 0));   // 0.4 truncated
        Assert.Equal((0, 0), curve.Apply(1, 0));   // 0.8 truncated
        Assert.Equal((1, 0), curve.Apply(1, 0));   // 1.2 -> 1
    }

    [Fact]
    public void Reset_ClearsResidual()
    {
        var curve = MakeCurve(sensitivity: 0.4f);
        curve.Apply(1, 0);  // residualX = 0.4
        curve.Apply(1, 0);  // residualX = 0.8
        curve.Reset();
        Assert.Equal((0, 0), curve.Apply(1, 0));   // back to 0.4 — residual cleared
    }

    [Fact]
    public void PowerCurve_AccelMultiplierBoundedByMax()
    {
        var curve = MakeCurve(
            sensitivity: 1.0f,
            type: CurveType.Power,
            accelFactor: 100f,    // crazy high
            accelExp: 2f,
            maxMul: 2.5f);

        // very fast input — accel would explode without cap
        var (sdx, _) = curve.Apply(100, 0);
        // expected: sdx <= 100 * 1.0 * 2.5 = 250
        Assert.True(sdx <= 250 + 1, $"sdx={sdx} exceeds maxMul-bounded ceiling");
    }

    [Fact]
    public void PowerCurve_ZeroAccelFactor_BehavesLinear()
    {
        var curve = MakeCurve(
            sensitivity: 1.5f,
            type: CurveType.Power,
            accelFactor: 0f);

        // accelMul = 1 + 0 * speed^exp = 1, so equivalent to Linear
        var (sdx, sdy) = curve.Apply(10, 0);
        Assert.Equal(15, sdx);
        Assert.Equal(0, sdy);
    }

    [Fact]
    public void NegativeDeltas_HandledSymmetrically()
    {
        var curve = MakeCurve(sensitivity: 0.5f);
        // -10 * 0.5 = -5
        var (sdx, _) = curve.Apply(-10, 0);
        Assert.Equal(-5, sdx);
    }
}
