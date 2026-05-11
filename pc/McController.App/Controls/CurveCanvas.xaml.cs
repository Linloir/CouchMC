using System;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using McController.Core.Config;

namespace McController.App.Controls;

/// <summary>
/// Live preview of the camera sensitivity curve.
///
/// X axis: raw finger speed (pixels/frame, 0..MaxInput).
/// Y axis: effective on-screen pixels after curve + user sensitivity.
/// Dashed line is the y = x identity reference (no scaling), so the live
/// curve always shows up as a distinct line above it whenever sensitivity
/// or curve params change. (An earlier version used sensitivity*x as the
/// reference, which made Linear mode look frozen — reference and curve
/// were identical.)
///
/// Recomputes whenever <see cref="SetCamera"/> is called — cheap (samples
/// ~80 points), no animation, just sets a Path's data.
/// </summary>
public partial class CurveCanvas : UserControl
{
    /// <summary>Max input speed shown on the X axis (px/frame, ≈ 200 = a fast swipe).</summary>
    public double MaxInput { get; set; } = 200;

    /// <summary>Max output on Y axis; gets stretched if the curve exceeds it.</summary>
    public double MaxOutput { get; set; } = 600;

    private CameraConfig? _camera;
    private const int Samples = 80;
    private const double PadL = 32, PadR = 12, PadT = 12, PadB = 24;

    public CurveCanvas()
    {
        InitializeComponent();
        SizeChanged += (_, _) => Redraw();
        Loaded += (_, _) => Redraw();
    }

    public void SetCamera(CameraConfig camera)
    {
        _camera = camera;
        Redraw();
    }

    private void Redraw()
    {
        if (_camera is null || ActualWidth <= 0 || ActualHeight <= 0) return;

        double w = ActualWidth - PadL - PadR;
        double h = ActualHeight - PadT - PadB;
        if (w <= 0 || h <= 0) return;

        var maxOut = SampleOutput(_camera, MaxInput);
        var displayMax = Math.Max(MaxOutput, maxOut * 1.1);

        GridPath.Data = BuildGridGeometry(w, h);
        ReferencePath.Data = BuildIdentityReferenceGeometry(w, h, displayMax);
        CurvePath.Data = BuildCurveGeometry(_camera, w, h, displayMax);
    }

    private Geometry BuildGridGeometry(double w, double h)
    {
        var g = new GeometryGroup();
        for (int i = 0; i <= 4; i++)
        {
            double x = PadL + w * i / 4;
            g.Children.Add(new LineGeometry(new Point(x, PadT), new Point(x, PadT + h)));
            double y = PadT + h * i / 4;
            g.Children.Add(new LineGeometry(new Point(PadL, y), new Point(PadL + w, y)));
        }
        return g;
    }

    private Geometry BuildIdentityReferenceGeometry(double w, double h, double displayMax)
    {
        // y = x identity (slope 1.0). The live curve must always sit above
        // this, so the user can see "raw finger speed → mouse pixels" gain.
        double xEnd = PadL + w;
        double yEnd = PadT + h - h * (MaxInput / displayMax);
        yEnd = Math.Max(PadT, yEnd);
        return new LineGeometry(new Point(PadL, PadT + h), new Point(xEnd, yEnd));
    }

    private Geometry BuildCurveGeometry(CameraConfig c, double w, double h, double displayMax)
    {
        var figure = new PathFigure { StartPoint = new Point(PadL, PadT + h) };
        for (int i = 1; i <= Samples; i++)
        {
            double raw = MaxInput * i / Samples;
            double output = SampleOutput(c, raw);
            double px = PadL + w * (raw / MaxInput);
            double py = PadT + h - h * (output / displayMax);
            py = Math.Max(PadT, py);
            figure.Segments.Add(new LineSegment(new Point(px, py), true));
        }
        return new PathGeometry(new[] { figure });
    }

    /// <summary>Pure function form of <see cref="Input.CameraCurve"/> output magnitude — no residual state.</summary>
    private static double SampleOutput(CameraConfig c, double rawSpeed)
    {
        double accel = 1.0;
        if (c.CurveType == CurveType.Power)
        {
            accel = Math.Min(1.0 + c.AccelFactor * Math.Pow(rawSpeed, c.AccelExp), c.MaxAccelMultiplier);
            if (accel < 1.0) accel = 1.0;
        }
        return rawSpeed * accel * c.UserSensitivity;
    }
}
