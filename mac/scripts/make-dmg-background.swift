#!/usr/bin/env swift
//
// make-dmg-background.swift — Renders the drag-to-install background
// image used by `scripts/dmg.sh` when laying out the DMG window.
//
// Output: mac/scripts/dmg-assets/background.png   (600×400, opaque)
//         mac/scripts/dmg-assets/background@2x.png (1200×800)
//
// The Finder mounts the DMG and reads the background out of a hidden
// `.background/` folder inside the volume root; Apple's HIG window
// size is 600×400 pt, so we render exactly that pixel size at 1x and
// double for retina.
//
// Layout: brand-green vertical gradient, soft "drop here" caption at
// the top, and a tasteful right-pointing arrow between the two icon
// slots so users immediately understand the install gesture. The icon
// slots themselves are EMPTY in the background — Finder draws the
// `.app` icon and the `/Applications` symlink on top.
//
// Run from `mac/`:
//
//     swift scripts/make-dmg-background.swift
//
// Re-run only when you want to tweak the background. dmg.sh skips
// re-baking if the file already exists.

import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let scriptDir = scriptURL.deletingLastPathComponent()
let outDir = scriptDir.appendingPathComponent("dmg-assets", isDirectory: true)
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

// MARK: - Layout constants — kept in sync with scripts/dmg.sh

let pointWidth:  CGFloat = 600
let pointHeight: CGFloat = 400

// Where dmg.sh will tell Finder to put the icons (centre coordinates,
// in window points). The background contains visual cues at these
// same coordinates so the arrow lines up with the actual icons.
let appIconCenter = CGPoint(x: 165, y: 220)
let dstIconCenter = CGPoint(x: 435, y: 220)

// MARK: - Render

/// Render the background at `scale` (1 or 2) and write to `outPath`.
func renderBackground(scale: Int, outPath: URL) {
    let pxW = Int(pointWidth)  * scale
    let pxH = Int(pointHeight) * scale
    let s = CGFloat(scale)

    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil,
        width: pxW, height: pxH,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        // No alpha — DMG backgrounds are always composited against the
        // Finder window's solid fill, so an alpha channel just bloats
        // the file with no benefit.
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { fatalError("CGContext failed at \(scale)x") }

    // Y-up so the math below reads naturally (CoreGraphics origin is
    // bottom-left; we want top-left to match Finder's coordinate
    // system the AppleScript hands us).
    ctx.translateBy(x: 0, y: CGFloat(pxH))
    ctx.scaleBy(x: 1, y: -1)
    ctx.scaleBy(x: s, y: s)

    let bounds = CGRect(x: 0, y: 0, width: pointWidth, height: pointHeight)

    // === Background gradient ===========================================
    // Brand-tinted soft vertical gradient. Top is a slightly brighter
    // green echoing the AppIcon's sky tone; bottom fades to almost-white
    // so the install text + arrow stay legible in either light or dark
    // Finder appearance (Finder always renders the background
    // against the system window chrome — neither colour scheme should
    // wash the icons out).
    let topColor    = CGColor(red: 0.74, green: 0.91, blue: 0.62, alpha: 1)
    let bottomColor = CGColor(red: 0.97, green: 0.99, blue: 0.96, alpha: 1)
    let gradient = CGGradient(
        colorsSpace: cs,
        colors: [topColor, bottomColor] as CFArray,
        locations: [0.0, 1.0])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: 0),
                           end:   CGPoint(x: 0, y: pointHeight),
                           options: [])

    // === Caption =======================================================
    let captionPara = NSMutableParagraphStyle()
    captionPara.alignment = .center
    let captionAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
        .foregroundColor: NSColor(deviceRed: 0.10, green: 0.30, blue: 0.10, alpha: 0.85),
        .paragraphStyle: captionPara,
    ]
    drawText("Drag CouchMC into Applications to install",
             attributes: captionAttrs,
             rect: CGRect(x: 0, y: 50, width: pointWidth, height: 24),
             into: ctx)

    let subPara = NSMutableParagraphStyle()
    subPara.alignment = .center
    let subAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .regular),
        .foregroundColor: NSColor(deviceRed: 0.10, green: 0.30, blue: 0.10, alpha: 0.55),
        .paragraphStyle: subPara,
    ]
    drawText("将 CouchMC 拖入 Applications 即可完成安装",
             attributes: subAttrs,
             rect: CGRect(x: 0, y: 78, width: pointWidth, height: 20),
             into: ctx)

    // === Chevron between the two icon slots ============================
    // Just a simple ">" — the most universally readable "do this next"
    // hint, less visually loud than a full arrow with shaft. Drawn at
    // the geometric midpoint between the two icon slots, vertically
    // aligned to the icon glyph centre (Finder positions icons by
    // their glyph centre, not including the text label below).
    let yMid = appIconCenter.y
    let chevronCX = (appIconCenter.x + dstIconCenter.x) / 2.0
    let chevronArm: CGFloat = 22
    let chevronColor = CGColor(red: 0.20, green: 0.50, blue: 0.24, alpha: 0.85)

    ctx.setStrokeColor(chevronColor)
    ctx.setLineWidth(7)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.beginPath()
    ctx.move(to: CGPoint(x: chevronCX - chevronArm / 2, y: yMid - chevronArm))
    ctx.addLine(to: CGPoint(x: chevronCX + chevronArm / 2, y: yMid))
    ctx.addLine(to: CGPoint(x: chevronCX - chevronArm / 2, y: yMid + chevronArm))
    ctx.strokePath()

    // === Footer credit (subtle) ========================================
    let footPara = NSMutableParagraphStyle()
    footPara.alignment = .center
    let footAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 10, weight: .regular),
        .foregroundColor: NSColor(deviceRed: 0.10, green: 0.30, blue: 0.10, alpha: 0.40),
        .paragraphStyle: footPara,
    ]
    drawText("CouchMC · couchmc.linloir.cn",
             attributes: footAttrs,
             rect: CGRect(x: 0, y: pointHeight - 22, width: pointWidth, height: 14),
             into: ctx)

    // === Encode ========================================================
    guard let cgImage = ctx.makeImage() else { fatalError("makeImage failed") }
    guard let dest = CGImageDestinationCreateWithURL(
        outPath as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("Cannot open \(outPath.path) for write") }
    CGImageDestinationAddImage(dest, cgImage, nil)
    if !CGImageDestinationFinalize(dest) {
        fatalError("Cannot finalize \(outPath.path)")
    }
    print("Wrote \(outPath.lastPathComponent) (\(pxW)×\(pxH))")
}

/// Draw `text` (already attributed) into the given rect, with the
/// rect's coordinates expressed in the y-flipped space we set up
/// above. Core Text wants y-up, so we flip back inside this helper
/// rather than tracking it everywhere.
func drawText(_ text: String,
              attributes: [NSAttributedString.Key: Any],
              rect: CGRect,
              into ctx: CGContext)
{
    let attr = NSAttributedString(string: text, attributes: attributes)
    let setter = CTFramesetterCreateWithAttributedString(attr)
    let path = CGPath(rect: rect, transform: nil)
    let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)

    ctx.saveGState()
    // Flip back so Core Text draws right-side-up inside the rect.
    ctx.translateBy(x: 0, y: rect.maxY + rect.minY)
    ctx.scaleBy(x: 1, y: -1)
    CTFrameDraw(frame, ctx)
    ctx.restoreGState()
}

renderBackground(scale: 1, outPath: outDir.appendingPathComponent("background.png"))
renderBackground(scale: 2, outPath: outDir.appendingPathComponent("background@2x.png"))
