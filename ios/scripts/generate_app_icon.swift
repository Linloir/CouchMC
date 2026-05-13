#!/usr/bin/env swift
//
// Regenerate iOS app-icon assets from `assets/icon.png` (the canonical
// 1024×1024 source at the repo root).
//
// Run from `ios/scripts/`:
//
//     swift generate_app_icon.swift
//
// What it produces:
//
//   ios/McController/Resources/Assets.xcassets/
//     AppIcon.appiconset/icon-1024.png     — 1024×1024 sRGB, NO alpha
//                                            (Apple rejects alpha on AppIcon).
//     AppIconAbout.imageset/icon-256.png   — 256×256, with alpha.
//     AppIconAbout.imageset/icon-512.png   — 512×512, with alpha.
//
// This script is iOS-only. The matching Android mipmap PNGs live under
// `android/app/src/main/res/mipmap-*/`. To regenerate both platforms in
// one shot from Windows / cross-platform PowerShell, use:
//
//     pwsh scripts/regenerate_app_icons.ps1
//
// Older revisions of this file procedurally rendered a pixel-art grass
// block; we now ship a static source PNG instead so the iOS / Android
// / macOS / Windows icons can stay visually identical without duplicating
// the rendering algorithm in four languages.

import AppKit
import CoreGraphics

// Resolve repo paths relative to this script.
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let iosRoot = scriptURL.deletingLastPathComponent()
let repoRoot = iosRoot.deletingLastPathComponent()
let sourceURL = repoRoot.appendingPathComponent("assets/icon.png")
let assetsRoot = iosRoot.appendingPathComponent("McController/Resources/Assets.xcassets", isDirectory: true)
let appIconSet = assetsRoot.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
let aboutSet   = assetsRoot.appendingPathComponent("AppIconAbout.imageset", isDirectory: true)

guard let source = NSImage(contentsOf: sourceURL) else {
    fputs("Source icon not found: \(sourceURL.path)\n", stderr)
    exit(1)
}

/// Render `source` into a `size × size` PNG.
///
/// `zoom > 1.0` scales the source up before drawing, then center-crops back
/// to the canvas. Used for the AppIcon to compensate for the visual
/// padding the source PNG carries — at 1.0 the gamepad+forest reads quite
/// small once iOS applies its own ~22 % squircle mask on top, so we
/// pre-zoom to give the subject more presence on the home screen.
///
/// The about-card icons stay at zoom 1.0 — they're shown inside SwiftUI
/// `RoundedRectangle(cornerRadius: 12)` and don't need extra cropping.
func renderPNG(size: CGFloat, withAlpha: Bool, zoom: CGFloat = 1.0, to url: URL) {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let bitmapInfo: UInt32 = withAlpha
        ? CGImageAlphaInfo.premultipliedLast.rawValue
        : CGImageAlphaInfo.noneSkipLast.rawValue
    guard let ctx = CGContext(
        data: nil,
        width: Int(size), height: Int(size),
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: bitmapInfo
    ) else { fatalError("Cannot create bitmap context") }

    ctx.interpolationQuality = .high
    if !withAlpha {
        // Apple requires AppIcon to be flat RGB. Paint a white background
        // before drawing so any stray edge antialiasing falls onto white
        // (matching the source PNG which has no alpha to begin with).
        ctx.setFillColor(CGColor.white)
        ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
    }

    // Compute a centered, zoomed destination rect. At zoom == 1.0 this is
    // just the canvas. At zoom > 1.0 the source overflows on all four
    // sides equally, effectively cropping a uniform border.
    let drawSize = size * zoom
    let origin = (size - drawSize) / 2
    let drawRect = CGRect(x: origin, y: origin, width: drawSize, height: drawSize)

    var probe = CGRect(x: 0, y: 0, width: size, height: size)
    if let cg = source.cgImage(forProposedRect: &probe, context: nil, hints: nil) {
        ctx.draw(cg, in: drawRect)
    } else {
        fatalError("Cannot get CGImage from source")
    }

    guard let cgImage = ctx.makeImage() else { fatalError("Cannot finalize image") }
    let bitmap = NSBitmapImageRep(cgImage: cgImage)
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("PNG encode failed")
    }
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                             withIntermediateDirectories: true)
    try! data.write(to: url, options: [.atomic])
    let zoomLabel = zoom == 1.0 ? "" : ", zoom: \(String(format: "%.2f", Double(zoom)))×"
    print("Wrote \(url.lastPathComponent) (\(Int(size))×\(Int(size))\(zoomLabel))")
}

// AppIcon: zoom in 1.20× to crop ~10 % off each edge, so the gamepad +
// forest fill more of the icon on the home screen. Tune this if you
// re-render the source PNG with different padding.
renderPNG(size: 1024, withAlpha: false, zoom: 1.20,
          to: appIconSet.appendingPathComponent("icon-1024.png"))

// About-card icons: no zoom; they live behind a SwiftUI RoundedRectangle
// and the source's padding looks fine at small sizes.
renderPNG(size:  256, withAlpha: true,
          to: aboutSet.appendingPathComponent("icon-256.png"))
renderPNG(size:  512, withAlpha: true,
          to: aboutSet.appendingPathComponent("icon-512.png"))
