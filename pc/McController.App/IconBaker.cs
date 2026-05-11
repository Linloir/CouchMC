using System;
using System.Collections.Generic;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace McController.App;

/// <summary>
/// One-shot helper that rasterizes the in-XAML <c>GrassBlockIcon</c>
/// <see cref="DrawingImage"/> at standard sizes and writes a multi-frame
/// .ico file. Invoked once via <c>--generate-icon</c> on the command line
/// to produce <c>Assets/app.ico</c>, which the csproj then references
/// via <c>&lt;ApplicationIcon&gt;</c> for File Explorer + Start menu
/// display. Not used at normal runtime.
/// </summary>
public static class IconBaker
{
    private static readonly int[] s_sizes = { 16, 20, 24, 32, 40, 48, 64, 128, 256 };

    public static void BakeGrassBlockToIco(string outputPath)
    {
        // App resources must be loaded — make sure App ctor has run.
        if (Application.Current is null) throw new InvalidOperationException("No Application instance.");
        var src = Application.Current.Resources["GrassBlockIcon"] as DrawingImage
            ?? throw new InvalidOperationException("GrassBlockIcon resource missing.");

        var pngFrames = new List<byte[]>();
        foreach (var size in s_sizes)
            pngFrames.Add(RenderToPng(src, size));

        Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(outputPath))!);
        using var fs = File.Create(outputPath);
        using var bw = new BinaryWriter(fs);
        // ICONDIR
        bw.Write((ushort)0);                 // reserved
        bw.Write((ushort)1);                 // type: ICO
        bw.Write((ushort)s_sizes.Length);    // image count

        // ICONDIRENTRY headers
        int dataOffset = 6 + s_sizes.Length * 16;
        for (int i = 0; i < s_sizes.Length; i++)
        {
            byte dim = s_sizes[i] >= 256 ? (byte)0 : (byte)s_sizes[i];
            bw.Write(dim);                   // width
            bw.Write(dim);                   // height
            bw.Write((byte)0);               // palette colors (0 = no palette)
            bw.Write((byte)0);               // reserved
            bw.Write((ushort)1);             // color planes
            bw.Write((ushort)32);            // bits per pixel
            bw.Write((uint)pngFrames[i].Length);
            bw.Write((uint)dataOffset);
            dataOffset += pngFrames[i].Length;
        }
        // Image payloads — each is a complete PNG file.
        foreach (var bytes in pngFrames) bw.Write(bytes);
    }

    private static byte[] RenderToPng(DrawingImage src, int size)
    {
        var rtb = new RenderTargetBitmap(size, size, 96, 96, PixelFormats.Pbgra32);
        var dv = new DrawingVisual();
        using (var ctx = dv.RenderOpen())
        {
            ctx.DrawImage(src, new Rect(0, 0, size, size));
        }
        rtb.Render(dv);
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(rtb));
        using var ms = new MemoryStream();
        encoder.Save(ms);
        return ms.ToArray();
    }
}
