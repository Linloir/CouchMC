using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

namespace McController.App;

/// <summary>
/// One-shot helper that renders an isometric Minecraft grass block as
/// pixel art and writes a multi-frame .ico file. Three faces, each
/// painted as a 16×16 texture using a deterministic hash-based color
/// pattern (no real randomness — bit-mixed seed per pixel) so the icon
/// is stable across runs and sizes.
///
/// Implemented in System.Drawing (GDI+) so it has no XAML / UI-thread
/// dependency — can run inside Program.Main before WinUI bootstraps.
/// Invoked via <c>--generate-icon &lt;path&gt;</c>.
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
            bw.Write(dim);
            bw.Write(dim);
            bw.Write((byte)0);
            bw.Write((byte)0);
            bw.Write((ushort)1);
            bw.Write((ushort)32);
            bw.Write((uint)pngFrames[i].Length);
            bw.Write((uint)dataOffset);
            dataOffset += pngFrames[i].Length;
        }
        foreach (var bytes in pngFrames) bw.Write(bytes);
    }

    private static byte[] RenderToPng(int size)
    {
        using var bmp = new Bitmap(size, size, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using var g = Graphics.FromImage(bmp);
        g.SmoothingMode = SmoothingMode.None;
        g.InterpolationMode = InterpolationMode.NearestNeighbor;
        g.PixelOffsetMode = PixelOffsetMode.None;
        DrawGrassBlock(g, size);
        using var ms = new MemoryStream();
        bmp.Save(ms, ImageFormat.Png);
        return ms.ToArray();
    }

    // ===== Isometric grass-block painter =====

    private const double Cos30 = 0.8660254037844387;
    private const double Sin30 = 0.5;
    private const int Grid = 16;

    private static void DrawGrassBlock(Graphics g, int size)
    {
        // Center the visual mass of the cube. An isometric cube reads
        // bottom-heavy because the bottom-front vertex is the widest visible
        // point — a small upward bias balances it on the canvas centerline.
        double cx = size / 2.0;
        double cy = size / 2.0 - size * 0.025;
        double scale = size * 0.42;

        PointF P(double x, double y, double z) =>
            new((float)(cx + (x - y) * Cos30 * scale),
                (float)(cy + ((x + y) * Sin30 - z) * scale));

        var vTopBack  = P(0, 0, 1);
        var vTopRight = P(1, 0, 1);
        var vTopFront = P(1, 1, 1);
        var vTopLeft  = P(0, 1, 1);
        var vBotRight = P(1, 0, 0);
        var vBotFront = P(1, 1, 0);
        var vBotLeft  = P(0, 1, 0);

        DrawFace(g, vTopBack, vTopRight, vTopFront, vTopLeft,
                 (i, j) => GrassTopColor(i, j));
        DrawFace(g, vTopLeft, vTopFront, vBotFront, vBotLeft,
                 (i, j) => DirtSideColor(i, j, isRight: false));
        DrawFace(g, vTopRight, vTopFront, vBotFront, vBotRight,
                 (i, j) => DirtSideColor(i, j, isRight: true));
    }

    private static void DrawFace(Graphics g, PointF tl, PointF tr, PointF br, PointF bl,
                                 Func<int, int, Color> colorFn)
    {
        for (int j = 0; j < Grid; j++)
        {
            for (int i = 0; i < Grid; i++)
            {
                float u0 = i / (float)Grid;
                float u1 = (i + 1) / (float)Grid;
                float v0 = j / (float)Grid;
                float v1 = (j + 1) / (float)Grid;

                var p00 = Bilinear(tl, tr, br, bl, u0, v0);
                var p10 = Bilinear(tl, tr, br, bl, u1, v0);
                var p11 = Bilinear(tl, tr, br, bl, u1, v1);
                var p01 = Bilinear(tl, tr, br, bl, u0, v1);

                var pts = new[] { p00, p10, p11, p01 };
                using var brush = new SolidBrush(colorFn(i, j));
                using var pen = new Pen(brush, 0.6f);
                g.FillPolygon(brush, pts);
                g.DrawPolygon(pen, pts);
            }
        }
    }

    private static PointF Bilinear(PointF tl, PointF tr, PointF br, PointF bl, float u, float v)
    {
        float topX = tl.X + (tr.X - tl.X) * u;
        float topY = tl.Y + (tr.Y - tl.Y) * u;
        float botX = bl.X + (br.X - bl.X) * u;
        float botY = bl.Y + (br.Y - bl.Y) * u;
        return new PointF(topX + (botX - topX) * v, topY + (botY - topY) * v);
    }

    // ===== Colors =====

    private static readonly Color GrassBase = Color.FromArgb(0x6F, 0xB0, 0x35);
    private static readonly Color GrassDark = Color.FromArgb(0x55, 0x8F, 0x25);
    private static readonly Color GrassDarker = Color.FromArgb(0x4A, 0x7F, 0x1F);
    private static readonly Color GrassLight = Color.FromArgb(0x7F, 0xC3, 0x42);
    private static readonly Color DirtBase = Color.FromArgb(0x88, 0x5C, 0x36);
    private static readonly Color DirtDark = Color.FromArgb(0x6E, 0x46, 0x25);
    private static readonly Color DirtDarker = Color.FromArgb(0x55, 0x36, 0x1B);
    private static readonly Color DirtLight = Color.FromArgb(0xA0, 0x73, 0x49);

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
        var v = Variant(i, j, isRight ? 2 : 3);
        Color color;
        if (j < 3)
        {
            if (v < 30) color = GrassDarker;
            else if (v < 55) color = GrassDark;
            else color = GrassBase;
        }
        else if (j == 3)
        {
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

        if (isRight)
        {
            color = Color.FromArgb(
                (byte)(color.R * 0.78),
                (byte)(color.G * 0.78),
                (byte)(color.B * 0.78));
        }
        return color;
    }
}
