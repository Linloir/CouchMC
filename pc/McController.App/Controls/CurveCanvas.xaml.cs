using System;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Foundation;
using McController.Core.Config;

namespace McController.App.Controls;

/// <summary>
/// Live preview of the camera sensitivity curve.
///
/// X axis: raw finger speed (pixels/frame, 0..MaxInput).
/// Y axis: effective on-screen pixels after curve + user sensitivity.
/// Dashed line is the y = x identity reference (no scaling), so the live
/// curve always shows up as a distinct line above it.
/// </summary>
public sealed partial class CurveCanvas : UserControl
{
    public double MaxInput { get; set; } = 200;
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
            g.Children.Add(new LineGeometry { StartPoint = new Point(x, PadT), EndPoint = new Point(x, PadT + h) });
            double y = PadT + h * i / 4;
            g.Children.Add(new LineGeometry { StartPoint = new Point(PadL, y), EndPoint = new Point(PadL + w, y) });
        }
        return g;
    }

    private Geometry BuildIdentityReferenceGeometry(double w, double h, double displayMax)
    {
        double xEnd = PadL + w;
        double yEnd = PadT + h - h * (MaxInput / displayMax);
        yEnd = Math.Max(PadT, yEnd);
        return new LineGeometry { StartPoint = new Point(PadL, PadT + h), EndPoint = new Point(xEnd, yEnd) };
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
            figure.Segments.Add(new LineSegment { Point = new Point(px, py) });
        }
        var geometry = new PathGeometry();
        geometry.Figures.Add(figure);
        return geometry;
    }

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
