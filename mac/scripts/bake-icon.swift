#!/usr/bin/env swift
//
// bake-icon.swift — Renders all macOS icon variants from the canonical
// brand source `assets/icon.png` at the repo root, plus a procedural
// monochrome silhouette for the menu bar item.
//
// Outputs (under `mac/McController/Resources/Assets.xcassets/`):
//
//   AppIcon.appiconset/        Full-colour AppIcon, 10 sizes
//                              (16/32/128/256/512 × @1x/@2x), opaque
//                              RGB resampled from assets/icon.png.
//
//   AboutHeroIcon.imageset/    Same source, smaller hero variants for
//                              the About page (64/128/256 × @1x/@2x),
//                              with alpha preserved so the rounded-
//                              rect SwiftUI mask renders cleanly.
//
//   MenuBarIcon.imageset/      Procedurally-drawn dark-on-template
//                              silhouette suitable for the 22pt menu
//                              bar slot. NOT derived from icon.png —
//                              the gamepad+forest brand artwork
//                              loses all detail under 24pt.
//
// Run from `mac/`:
//
//     swift scripts/bake-icon.swift
//
// Re-run whenever assets/icon.png changes, or whenever you need to
// reset the asset catalogue after a checkout.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Paths

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let scriptDir = scriptURL.deletingLastPathComponent()
let projectRoot = scriptDir.deletingLastPathComponent()           // mac/
let repoRoot = projectRoot.deletingLastPathComponent()            // mc_controller/
let sourceURL = repoRoot.appendingPathComponent("assets/icon.png")

let assetsRoot = projectRoot
    .appendingPathComponent("McController/Resources/Assets.xcassets")
let appIconDir   = assetsRoot.appendingPathComponent("AppIcon.appiconset")
let menuIconDir  = assetsRoot.appendingPathComponent("MenuBarIcon.imageset")
let aboutHeroDir = assetsRoot.appendingPathComponent("AboutHeroIcon.imageset")

for dir in [appIconDir, menuIconDir, aboutHeroDir] {
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
}

// MARK: - Helpers

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("Cannot open \(url.path) for write") }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) {
        fatalError("Cannot finalize PNG at \(url.path)")
    }
}

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fputs("Source icon not found: \(sourceURL.path)\n", stderr)
    fputs("Make sure assets/icon.png exists at the repo root.\n", stderr)
    exit(1)
}

/// Resample `sourceImage` to a `pixelSize × pixelSize` CGImage shaped
/// like a macOS app icon: the source artwork is centred inside the
/// canvas at ~80% scale (matching Apple's published `824/1024`
/// proportion), masked by a continuous-corner squircle, and surrounded
/// by transparent margins.
///
/// macOS app icons (unlike iOS) MUST carry their rounded-square shape
/// in the icon bytes themselves — the system doesn't apply an automatic
/// squircle mask. If we shipped the raw 1024² source PNG as-is, the
/// Dock would render a flat square tile with sharp corners, which is
/// what the user reported.
///
/// `opaqueBackground` paints a white plate behind the source before the
/// squircle clip — used for the About-page hero where the rounded-rect
/// SwiftUI clip mask wants opaque pixels behind it. AppIcon variants
/// use a transparent background so macOS can render its own drop
/// shadow underneath the squircle.
func resampleSource(pixelSize: Int,
                    iconScale: CGFloat = 0.815,
                    opaqueBackground: Bool = false) -> CGImage {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    // We always need an alpha channel for the squircle mask to work.
    guard let ctx = CGContext(
        data: nil,
        width: pixelSize, height: pixelSize,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("CGContext creation failed at \(pixelSize)px") }

    ctx.interpolationQuality = .high
    ctx.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))

    // Compute the inset rect that contains the squircle. iconScale
    // controls how much of the canvas the icon occupies — Apple's
    // macOS reference is 824 / 1024 ≈ 0.805; we use 0.815 to slightly
    // bias the gamepad+forest artwork up since the source has visible
    // bottom padding on the cropped 1.20× iOS variant.
    let canvas = CGFloat(pixelSize)
    let insetSide = canvas * iconScale
    let inset = (canvas - insetSide) / 2.0
    let iconRect = CGRect(x: inset, y: inset,
                          width: insetSide, height: insetSide)

    // Continuous-corner squircle approximation. The Apple-published
    // ratio for the macOS rounded-square is roughly 0.2237 of the
    // icon's edge — visually indistinguishable from the rounded-rect
    // we render here when the corner radius matches.
    let cornerRadius = insetSide * 0.2237
    let squircle = CGPath(
        roundedRect: iconRect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil)

    ctx.saveGState()
    ctx.addPath(squircle)
    ctx.clip()

    if opaqueBackground {
        // White plate so SwiftUI's RoundedRectangle clip in AboutView
        // doesn't expose any partially-transparent edges.
        ctx.setFillColor(CGColor.white)
        ctx.fill(iconRect)
    }

    var probe = iconRect
    if let cg = sourceImage.cgImage(forProposedRect: &probe, context: nil, hints: nil) {
        ctx.draw(cg, in: iconRect)
    } else {
        fatalError("Cannot get CGImage from source at \(pixelSize)px")
    }

    ctx.restoreGState()
    return ctx.makeImage()!
}

// MARK: - AppIcon

struct AppIconSpec {
    let dimensionPoints: Int
    let scale: Int
    var pixelSize: Int { dimensionPoints * scale }
    var filename: String { "icon_\(dimensionPoints)x\(dimensionPoints)@\(scale)x.png" }
}

let appIconSpecs: [AppIconSpec] = [
    .init(dimensionPoints: 16, scale: 1),
    .init(dimensionPoints: 16, scale: 2),
    .init(dimensionPoints: 32, scale: 1),
    .init(dimensionPoints: 32, scale: 2),
    .init(dimensionPoints: 128, scale: 1),
    .init(dimensionPoints: 128, scale: 2),
    .init(dimensionPoints: 256, scale: 1),
    .init(dimensionPoints: 256, scale: 2),
    .init(dimensionPoints: 512, scale: 1),
    .init(dimensionPoints: 512, scale: 2),
]

for spec in appIconSpecs {
    // AppIcon variants: transparent corners, 81.5% icon scale (Apple's
    // reference is 824/1024 ≈ 0.805; we round up slightly for the
    // gamepad+forest artwork's visible top padding).
    let image = resampleSource(pixelSize: spec.pixelSize, iconScale: 0.815)
    writePNG(image, to: appIconDir.appendingPathComponent(spec.filename))
}

let appIconImages: [[String: String]] = appIconSpecs.map {
    [
        "size": "\($0.dimensionPoints)x\($0.dimensionPoints)",
        "idiom": "mac",
        "filename": $0.filename,
        "scale": "\($0.scale)x",
    ]
}
let appIconContents: [String: Any] = [
    "images": appIconImages,
    "info": ["version": 1, "author": "xcode"] as [String: Any],
]
try JSONSerialization.data(withJSONObject: appIconContents,
                           options: [.prettyPrinted, .sortedKeys])
    .write(to: appIconDir.appendingPathComponent("Contents.json"))

// MARK: - About hero (used inside SwiftUI's RoundedRectangle clip)

struct AboutHeroSpec {
    let dimensionPoints: Int
    let scale: Int
    var pixelSize: Int { dimensionPoints * scale }
    var filename: String { "about_hero_\(dimensionPoints)@\(scale)x.png" }
}

// macOS imagesets only support @1x + @2x.
let aboutHeroSpecs: [AboutHeroSpec] = [
    .init(dimensionPoints: 64,  scale: 1),
    .init(dimensionPoints: 64,  scale: 2),
    .init(dimensionPoints: 128, scale: 1),
    .init(dimensionPoints: 128, scale: 2),
    .init(dimensionPoints: 256, scale: 1),
    .init(dimensionPoints: 256, scale: 2),
]

for spec in aboutHeroSpecs {
    // About hero variants: ~95% scale (no Dock-tile chrome margin
    // needed) — SwiftUI's RoundedRectangle clip in AboutView makes
    // the corner masking redundant, but a slight inset still looks
    // polished against the card background.
    let image = resampleSource(pixelSize: spec.pixelSize,
                               iconScale: 0.95,
                               opaqueBackground: true)
    writePNG(image, to: aboutHeroDir.appendingPathComponent(spec.filename))
}

let aboutHeroContents: [String: Any] = [
    "images": aboutHeroSpecs.map {
        [
            "idiom": "mac",
            "filename": $0.filename,
            "scale": "\($0.scale)x",
        ] as [String: String]
    },
    "info": ["version": 1, "author": "xcode"] as [String: Any],
]
try JSONSerialization.data(withJSONObject: aboutHeroContents,
                           options: [.prettyPrinted, .sortedKeys])
    .write(to: aboutHeroDir.appendingPathComponent("Contents.json"))

// MARK: - Menu bar icon (procedural, template)
//
// We DELIBERATELY don't derive this from assets/icon.png. The brand
// artwork (a gamepad in front of a pixel-art forest) is far too
// detailed to read at the menu-bar's effective 18-22 pt size; it
// would just look like a smudge. Instead we ship a flat 4-dot
// "controller-D-pad-and-buttons" silhouette as a template image,
// so macOS auto-tints it for light / dark menu bars.

func makeMenuBarIcon(pixelSize: Int) -> CGImage {
    let cgSize = CGFloat(pixelSize)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: pixelSize, height: pixelSize,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("CGContext failed at \(pixelSize)px") }

    ctx.translateBy(x: 0, y: cgSize)
    ctx.scaleBy(x: 1, y: -1)
    ctx.clear(CGRect(x: 0, y: 0, width: cgSize, height: cgSize))

    // Coordinates expressed as fractions of canvas size so we draw
    // the same shape at 18/36 px without re-tuning. The ink color is
    // pure black; the template renderer recolours at runtime.
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))

    // Outer rounded-rect "controller body": narrow horizontal pill
    // taking ~80% width × ~50% height, centred slightly above
    // geometric centre to leave room for the inner cluster.
    let bodyWidth  = cgSize * 0.86
    let bodyHeight = cgSize * 0.46
    let bodyX = (cgSize - bodyWidth) / 2.0
    let bodyY = (cgSize - bodyHeight) / 2.0 + cgSize * 0.04
    let bodyRect = CGRect(x: bodyX, y: bodyY, width: bodyWidth, height: bodyHeight)
    let bodyCorner = bodyHeight * 0.45
    let bodyPath = CGPath(roundedRect: bodyRect,
                          cornerWidth: bodyCorner, cornerHeight: bodyCorner,
                          transform: nil)
    ctx.addPath(bodyPath)
    ctx.fillPath()

    // Cut out the four button areas + D-pad with even-odd fill so
    // the silhouette reads as a controller, not a pill.
    let cutoutPath = CGMutablePath()

    // Centre Y for the inner symbols — slightly higher than body
    // centre because the controller body itself is offset down.
    let innerCY = bodyRect.midY

    // D-pad on the LEFT third — a "+" shape made of two overlapping
    // rectangles. Sizing tuned to read at 18 pt.
    let dpadCX = bodyRect.minX + bodyRect.width * 0.27
    let dpadArm = cgSize * 0.07
    let dpadThk = cgSize * 0.07
    cutoutPath.addRect(CGRect(x: dpadCX - dpadArm, y: innerCY - dpadThk / 2,
                              width: dpadArm * 2, height: dpadThk))
    cutoutPath.addRect(CGRect(x: dpadCX - dpadThk / 2, y: innerCY - dpadArm,
                              width: dpadThk, height: dpadArm * 2))

    // Two button dots on the RIGHT third.
    let btnCX1 = bodyRect.minX + bodyRect.width * 0.66
    let btnCX2 = bodyRect.minX + bodyRect.width * 0.81
    let btnR   = cgSize * 0.055
    cutoutPath.addEllipse(in: CGRect(x: btnCX1 - btnR, y: innerCY - btnR,
                                     width: btnR * 2, height: btnR * 2))
    cutoutPath.addEllipse(in: CGRect(x: btnCX2 - btnR, y: innerCY - btnR,
                                     width: btnR * 2, height: btnR * 2))

    // Punch out via a second pass — clear blend mode keeps the pill
    // outline crisp.
    ctx.setBlendMode(.clear)
    ctx.addPath(cutoutPath)
    ctx.fillPath()
    ctx.setBlendMode(.normal)

    return ctx.makeImage()!
}

let menuSpecs: [(Int, Int, String)] = [
    (18, 1, "menu_18@1x.png"),
    (18, 2, "menu_18@2x.png"),
]
for (points, scale, filename) in menuSpecs {
    let image = makeMenuBarIcon(pixelSize: points * scale)
    writePNG(image, to: menuIconDir.appendingPathComponent(filename))
}

let menuContents: [String: Any] = [
    "images": menuSpecs.map { (_, scale, filename) in
        [
            "idiom": "mac",
            "filename": filename,
            "scale": "\(scale)x",
        ] as [String: String]
    },
    "info": ["version": 1, "author": "xcode"] as [String: Any],
    "properties": ["template-rendering-intent": "template"],
]
try JSONSerialization.data(withJSONObject: menuContents,
                           options: [.prettyPrinted, .sortedKeys])
    .write(to: menuIconDir.appendingPathComponent("Contents.json"))

// MARK: - Root Contents.json for Assets.xcassets

let rootContents: [String: Any] = [
    "info": ["version": 1, "author": "xcode"] as [String: Any],
]
try JSONSerialization.data(withJSONObject: rootContents,
                           options: [.prettyPrinted, .sortedKeys])
    .write(to: assetsRoot.appendingPathComponent("Contents.json"))

print("Baked AppIcon (\(appIconSpecs.count) variants), AboutHero (\(aboutHeroSpecs.count) variants), MenuBarIcon (\(menuSpecs.count) variants) from \(sourceURL.lastPathComponent)")
