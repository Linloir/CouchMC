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

func renderPNG(size: CGFloat, withAlpha: Bool, to url: URL) {
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

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    var dst = rect
    if let cg = source.cgImage(forProposedRect: &dst, context: nil, hints: nil) {
        ctx.draw(cg, in: rect)
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
    print("Wrote \(url.lastPathComponent) (\(Int(size))×\(Int(size)))")
}

renderPNG(size: 1024, withAlpha: false, to: appIconSet.appendingPathComponent("icon-1024.png"))
renderPNG(size:  256, withAlpha: true,  to: aboutSet.appendingPathComponent("icon-256.png"))
renderPNG(size:  512, withAlpha: true,  to: aboutSet.appendingPathComponent("icon-512.png"))
