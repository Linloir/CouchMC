#!/usr/bin/env swift
//
// iOS app-icon renderer.
//
// Mirrors the algorithm in `pc/McController.App/IconBaker.cs` — same
// isometric projection, same 16×16 grid texture, same hash-based color
// variants, same palette — so the iOS icon and the Windows .ico render
// the identical grass block. The only iOS-specific bits are:
//   1. A white square background underneath the cube (Apple icon
//      convention; the Windows .ico ships transparent).
//   2. Three output sizes (1024 for AppIcon, 256/512 for the in-app
//      About card).
//
// Run from `ios/scripts/`:  `swift generate_app_icon.swift`

import AppKit
import CoreGraphics

// MARK: - Projection constants (verbatim from IconBaker.cs)

let Cos30 = 0.8660254037844387
let Sin30 = 0.5
let Grid  = 16

// MARK: - Palette (verbatim from IconBaker.cs)

func srgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}
let GrassBase   = srgb(0x6F, 0xB0, 0x35)
let GrassDark   = srgb(0x55, 0x8F, 0x25)
let GrassDarker = srgb(0x4A, 0x7F, 0x1F)
let GrassLight  = srgb(0x7F, 0xC3, 0x42)
let DirtBase    = srgb(0x88, 0x5C, 0x36)
let DirtDark    = srgb(0x6E, 0x46, 0x25)
let DirtDarker  = srgb(0x55, 0x36, 0x1B)
let DirtLight   = srgb(0xA0, 0x73, 0x49)

// MARK: - Hash-based color variant (verbatim from IconBaker.cs)

func variant(_ i: Int, _ j: Int, _ salt: Int) -> Int {
    let h = (i &* 73856093) ^ (j &* 19349663) ^ (salt &* 83492791)
    return ((h ^ (h >> 13)) & 0x7FFFFFFF) % 100
}

func grassTopColor(_ i: Int, _ j: Int) -> NSColor {
    let v = variant(i, j, 1)
    if v < 10 { return GrassDarker }
    if v < 25 { return GrassDark }
    if v < 40 { return GrassLight }
    return GrassBase
}

func dirtSideColor(_ i: Int, _ j: Int, isRight: Bool) -> NSColor {
    let v = variant(i, j, isRight ? 2 : 3)
    var color: NSColor
    if j < 3 {
        if v < 30      { color = GrassDarker }
        else if v < 55 { color = GrassDark }
        else           { color = GrassBase }
    } else if j == 3 {
        color = (v < 50) ? GrassDarker : DirtDark
    } else {
        if v < 15      { color = DirtDarker }
        else if v < 30 { color = DirtLight }
        else if v < 50 { color = DirtDark }
        else           { color = DirtBase }
    }
    if isRight {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        // Convert to sRGB before extracting components so the 0.78 multiplier
        // operates in the expected colour space.
        let srgb = color.usingColorSpace(.sRGB) ?? color
        srgb.getRed(&r, green: &g, blue: &b, alpha: &a)
        color = NSColor(srgbRed: r * 0.78, green: g * 0.78, blue: b * 0.78, alpha: a)
    }
    return color
}

// MARK: - Drawing

func bilinear(_ tl: CGPoint, _ tr: CGPoint, _ br: CGPoint, _ bl: CGPoint,
              _ u: CGFloat, _ v: CGFloat) -> CGPoint {
    let topX = tl.x + (tr.x - tl.x) * u
    let topY = tl.y + (tr.y - tl.y) * u
    let botX = bl.x + (br.x - bl.x) * u
    let botY = bl.y + (br.y - bl.y) * u
    return CGPoint(x: topX + (botX - topX) * v, y: topY + (botY - topY) * v)
}

func drawFace(into ctx: CGContext,
              tl: CGPoint, tr: CGPoint, br: CGPoint, bl: CGPoint,
              colorFn: (Int, Int) -> NSColor) {
    for j in 0..<Grid {
        for i in 0..<Grid {
            let u0 = CGFloat(i)     / CGFloat(Grid)
            let u1 = CGFloat(i + 1) / CGFloat(Grid)
            let v0 = CGFloat(j)     / CGFloat(Grid)
            let v1 = CGFloat(j + 1) / CGFloat(Grid)

            let p00 = bilinear(tl, tr, br, bl, u0, v0)
            let p10 = bilinear(tl, tr, br, bl, u1, v0)
            let p11 = bilinear(tl, tr, br, bl, u1, v1)
            let p01 = bilinear(tl, tr, br, bl, u0, v1)

            // Fill + 0.6pt outline in the SAME colour so adjacent cells'
            // seams don't show through (matches the C# code's
            // `g.FillPolygon` + `g.DrawPolygon` pair).
            let cg = colorFn(i, j).cgColor
            ctx.setFillColor(cg)
            ctx.setStrokeColor(cg)
            ctx.setLineWidth(0.6)

            let path = CGMutablePath()
            path.move(to: p00)
            path.addLine(to: p10)
            path.addLine(to: p11)
            path.addLine(to: p01)
            path.closeSubpath()
            ctx.addPath(path)
            ctx.drawPath(using: .fillStroke)
        }
    }
}

/// Draw a single grass block onto `ctx`, optionally painting a white square
/// background underneath. The cube's geometry / colours are identical to
/// the Windows `IconBaker`.
func drawIcon(into ctx: CGContext, size: CGFloat, whiteBackground: Bool) {
    if whiteBackground {
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }

    ctx.saveGState()
    // The C# `IconBaker` operates in GDI+ coordinates (y-down). CoreGraphics
    // is y-up. Flip the context so the projection math below is line-for-line
    // identical to the C# implementation.
    ctx.translateBy(x: 0, y: size)
    ctx.scaleBy(x: 1, y: -1)
    // Match `SmoothingMode.None` from the C# code so the grid cells stay
    // crisp at the pixel-art aesthetic.
    ctx.setShouldAntialias(false)

    // iOS-specific tuning. The Windows .ico fills its canvas (transparent
    // background, taskbar use); on iOS the icon sits on a white square and
    // wants Apple-HIG breathing room. Smaller scale + geometric centre.
    let cx = size / 2.0
    let cy = size / 2.0
    let scale = size * 0.34

    func P(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
        let sx = cx + CGFloat((x - y) * Cos30) * scale
        let sy = cy + CGFloat((x + y) * Sin30 - z) * scale
        return CGPoint(x: sx, y: sy)
    }

    let vTopBack  = P(0, 0, 1)
    let vTopRight = P(1, 0, 1)
    let vTopFront = P(1, 1, 1)
    let vTopLeft  = P(0, 1, 1)
    let vBotRight = P(1, 0, 0)
    let vBotFront = P(1, 1, 0)
    let vBotLeft  = P(0, 1, 0)

    drawFace(into: ctx, tl: vTopBack,  tr: vTopRight, br: vTopFront, bl: vTopLeft,
             colorFn: grassTopColor)
    drawFace(into: ctx, tl: vTopLeft,  tr: vTopFront, br: vBotFront, bl: vBotLeft,
             colorFn: { i, j in dirtSideColor(i, j, isRight: false) })
    drawFace(into: ctx, tl: vTopRight, tr: vTopFront, br: vBotFront, bl: vBotRight,
             colorFn: { i, j in dirtSideColor(i, j, isRight: true) })

    ctx.restoreGState()
}

// MARK: - PNG writer

func renderPNG(size: CGFloat, withBackground: Bool, to url: URL) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil,
        width: Int(size), height: Int(size),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("Cannot create bitmap context") }

    drawIcon(into: ctx, size: size, whiteBackground: withBackground)
    guard let cgImage = ctx.makeImage() else { fatalError("Cannot finalize image") }

    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("PNG encode failed")
    }
    try! data.write(to: url, options: [.atomic])
    print("Wrote \(url.lastPathComponent) (\(Int(size))×\(Int(size)))")
}

// MARK: - Entry

let fm = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let assetsRoot = scriptURL
    .deletingLastPathComponent()
    .appendingPathComponent("McController/Resources/Assets.xcassets", isDirectory: true)

let appIconSet = assetsRoot.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
let aboutSet   = assetsRoot.appendingPathComponent("AppIconAbout.imageset", isDirectory: true)

try? fm.createDirectory(at: appIconSet, withIntermediateDirectories: true)
try? fm.createDirectory(at: aboutSet, withIntermediateDirectories: true)

// 1024×1024 single source for AppIcon. Xcode 14+ auto-scales to every
// device-specific size from this single artwork.
renderPNG(size: 1024, withBackground: true,
          to: appIconSet.appendingPathComponent("icon-1024.png"))

// In-app About card icons.
renderPNG(size: 256, withBackground: true,
          to: aboutSet.appendingPathComponent("icon-256.png"))
renderPNG(size: 512, withBackground: true,
          to: aboutSet.appendingPathComponent("icon-512.png"))
