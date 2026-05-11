using System;
using System.Collections.Generic;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace McController.App;

/// <summary>
/// One-shot helper that renders an isometric Minecraft grass block as
/// pixel art and writes a multi-frame .ico file. Three faces, each
/// painted as a 16×16 texture using a deterministic hash-based color
/// pattern (no real randomness — bit-mixed seed per pixel) so the icon
/// is stable across runs and sizes. Invoked via the <c>--generate-icon</c>
/// command line; the output is committed to <c>Assets/app.ico</c> and
/// referenced by both <c>&lt;ApplicationIcon&gt;</c> (File Explorer)
/// and the live <c>Window.Icon</c> (title bar + taskbar).
/// </summary>
public static class IconBaker
{
    private static readonly int[] s_sizes = { 16, 20, 24, 32, 40, 48, 64, 128, 256 };

    public static void BakeGrassBlockToIco(string outputPath)
    {
        var pngFrames = new List<byte[]>();
        foreach (var size in s_sizes)
            pngFrames.Add(RenderToPng(size));

        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outputPath))!);
        using var fs = File.Create(outputPath);
        using var bw = new BinaryWriter(fs);
        bw.Write((ushort)0);
        bw.Write((ushort)1);
        bw.Write((ushort)s_sizes.Length);

        int dataOffset = 6 + s_sizes.Length * 16;
        for (int i = 0; i < s_sizes.Length; i++)
        {
            byte dim = s_sizes[i] >= 256 ? (byte)0 : (byte)s_sizes[i];
            bw.Write(dim);                  // width
            bw.Write(dim);                  // height
            bw.Write((byte)0);              // palette colors (0 = no palette)
            bw.Write((byte)0);              // reserved
            bw.Write((ushort)1);            // color planes
            bw.Write((ushort)32);           // bits per pixel
            bw.Write((uint)pngFrames[i].Length);
            bw.Write((uint)dataOffset);
            dataOffset += pngFrames[i].Length;
        }
        foreach (var bytes in pngFrames) bw.Write(bytes);
    }

    private static byte[] RenderToPng(int size)
    {
        var rtb = new RenderTargetBitmap(size, size, 96, 96, PixelFormats.Pbgra32);
        var dv = new DrawingVisual();
        using (var ctx = dv.RenderOpen())
        {
            DrawGrassBlock(ctx, size);
        }
        rtb.Render(dv);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(rtb));
        using var ms = new MemoryStream();
        encoder.Save(ms);
        return ms.ToArray();
    }

    // ===== Isometric grass-block painter =====

    private const double Cos30 = 0.8660254037844387;
    private const double Sin30 = 0.5;
    private const int Grid = 16;        // texture resolution per face

    private static void DrawGrassBlock(DrawingContext ctx, int size)
    {
        // Center the visual mass of the cube. An isometric cube reads
        // bottom-heavy because the bottom-front vertex is the widest visible
        // point while the top is a single apex — nudging the geometry up by
        // a few percent puts the perceived weight on the canvas centerline.
        double cx = size / 2.0;
        double cy = size / 2.0 - size * 0.025;
        double scale = size * 0.42;

        Point P(double x, double y, double z) =>
            new(cx + (x - y) * Cos30 * scale,
                cy + ((x + y) * Sin30 - z) * scale);

        // Cube vertices (unit cube at origin, +z up, camera at +x +y +z far)
        // 7 of the 8 cube vertices are visible (the 8th — (0,0,0) — is occluded).
        var vTopBack   = P(0, 0, 1);  // apex of visible outline
        var vTopRight  = P(1, 0, 1);  // top-right ridge
        var vTopFront  = P(1, 1, 1);  // where the three faces meet
        var vTopLeft   = P(0, 1, 1);  // top-left ridge
        var vBotRight  = P(1, 0, 0);  // bottom-right (front of +x face)
        var vBotFront  = P(1, 1, 0);  // bottom apex (front-most cube vertex)
        var vBotLeft   = P(0, 1, 0);  // bottom-left (front of +y face)

        // Top face (z=1): rhombus pointing up
        DrawFace(ctx, vTopBack, vTopRight, vTopFront, vTopLeft,
                 (i, j) => GrassTopColor(i, j));

        // +y face — visible on LEFT half of screen (brighter side).
        DrawFace(ctx, vTopLeft, vTopFront, vBotFront, vBotLeft,
                 (i, j) => DirtSideColor(i, j, isRight: false));

        // +x face — visible on RIGHT half of screen (shaded side).
        DrawFace(ctx, vTopRight, vTopFront, vBotFront, vBotRight,
                 (i, j) => DirtSideColor(i, j, isRight: true));
    }

    private static void DrawFace(DrawingContext ctx, Point tl, Point tr, Point br, Point bl,
                                 Func<int, int, Color> colorFn)
    {
        for (int j = 0; j < Grid; j++)
        {
            for (int i = 0; i < Grid; i++)
            {
                double u0 = i / (double)Grid;
                double u1 = (i + 1) / (double)Grid;
                double v0 = j / (double)Grid;
                double v1 = (j + 1) / (double)Grid;

                var p00 = Bilinear(tl, tr, br, bl, u0, v0);
                var p10 = Bilinear(tl, tr, br, bl, u1, v0);
                var p11 = Bilinear(tl, tr, br, bl, u1, v1);
                var p01 = Bilinear(tl, tr, br, bl, u0, v1);

                var fig = new PathFigure { StartPoint = p00, IsClosed = true };
                fig.Segments.Add(new LineSegment(p10, false));
                fig.Segments.Add(new LineSegment(p11, false));
                fig.Segments.Add(new LineSegment(p01, false));
                fig.Freeze();
                var geo = new PathGeometry();
                geo.Figures.Add(fig);
                geo.Freeze();

                // Slight pen along the same color reduces seams between pixels
                // (subpixel snapping leaves 1px gaps otherwise at small sizes).
                var brush = new SolidColorBrush(colorFn(i, j));
                brush.Freeze();
                var pen = new Pen(brush, 0.6);
                pen.Freeze();
                ctx.DrawGeometry(brush, pen, geo);
            }
        }
    }

    private static Point Bilinear(Point tl, Point tr, Point br, Point bl, double u, double v)
    {
        // Top edge interpolates tl→tr; bottom edge interpolates bl→br.
        double topX = tl.X + (tr.X - tl.X) * u;
        double topY = tl.Y + (tr.Y - tl.Y) * u;
        double botX = bl.X + (br.X - bl.X) * u;
        double botY = bl.Y + (br.Y - bl.Y) * u;
        return new Point(topX + (botX - topX) * v, topY + (botY - topY) * v);
    }

    // ===== Color generation =====

    // Authentic MC-style palette.
    private static readonly Color GrassBase = Color.FromRgb(0x6F, 0xB0, 0x35);
    private static readonly Color GrassDark = Color.FromRgb(0x55, 0x8F, 0x25);
    private static readonly Color GrassDarker = Color.FromRgb(0x4A, 0x7F, 0x1F);
    private static readonly Color GrassLight = Color.FromRgb(0x7F, 0xC3, 0x42);

    private static readonly Color DirtBase = Color.FromRgb(0x88, 0x5C, 0x36);
    private static readonly Color DirtDark = Color.FromRgb(0x6E, 0x46, 0x25);
    private static readonly Color DirtDarker = Color.FromRgb(0x55, 0x36, 0x1B);
    private static readonly Color DirtLight = Color.FromRgb(0xA0, 0x73, 0x49);

    /// <summary>Deterministic hash-based variant index in [0, 100).</summary>
    private static int Variant(int i, int j, int salt)
    {
        unchecked
        {
            int h = i * 73856093 ^ j * 19349663 ^ salt * 83492791;
            return ((h ^ (h >> 13)) & 0x7FFFFFFF) % 100;
        }
    }

    private static Color GrassTopColor(int i, int j)
    {
        var v = Variant(i, j, 1);
        if (v < 10) return GrassDarker;
        if (v < 25) return GrassDark;
        if (v < 40) return GrassLight;
        return GrassBase;
    }

    private static Color DirtSideColor(int i, int j, bool isRight)
    {
        // Top 4 rows = grass overhang. Rest = dirt.
        var v = Variant(i, j, isRight ? 2 : 3);
        Color color;
        if (j < 3)
        {
            // Grass top band — match the top face palette
            if (v < 30) color = GrassDarker;
            else if (v < 55) color = GrassDark;
            else color = GrassBase;
        }
        else if (j == 3)
        {
            // Ragged border between grass and dirt — alternate green / dirt
            if (v < 50) color = GrassDarker;
            else color = DirtDark;
        }
        else
        {
            if (v < 15) color = DirtDarker;
            else if (v < 30) color = DirtLight;
            else if (v < 50) color = DirtDark;
            else color = DirtBase;
        }

        // Light from upper-left: right face gets a darken pass.
        if (isRight)
        {
            color = Color.FromRgb(
                (byte)(color.R * 0.78),
                (byte)(color.G * 0.78),
                (byte)(color.B * 0.78));
        }
        return color;
    }
}
