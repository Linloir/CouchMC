#!/usr/bin/env swift
//
// bake-icon.swift — Renders the isometric MC grass-block icon to PNG
// files at every size the macOS AppIcon asset catalog needs, plus
// monochrome template variants for the menu bar item.
//
// The drawing routine mirrors `pc/McController.App/IconBaker.cs`, but:
//   - The background is white per the design brief.
//   - Content is shrunk to ~78% of the canvas so the cube reads inside
//     macOS's rounded-square mask without clipping into the corners.
//   - 16/32/64 px monochrome silhouettes are also baked for the menu
//     bar item (rendered as `template` so macOS auto-tints them to
//     match dark/light bars).
//
// Run from `mac/`:
//
//     swift scripts/bake-icon.swift
//
// Output is written into
// `McController/Resources/Assets.xcassets/{AppIcon.appiconset,MenuBarIcon.imageset}/`.

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Output paths

let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0])
let scriptDir = scriptURL.deletingLastPathComponent()
let projectRoot = scriptDir.deletingLastPathComponent()  // mac/
let assetsRoot = projectRoot
    .appendingPathComponent("McController/Resources/Assets.xcassets")
let appIconDir = assetsRoot.appendingPathComponent("AppIcon.appiconset")
let menuIconDir = assetsRoot.appendingPathComponent("MenuBarIcon.imageset")
let aboutHeroDir = assetsRoot.appendingPathComponent("AboutHeroIcon.imageset")

try? FileManager.default.createDirectory(at: appIconDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: menuIconDir, withIntermediateDirectories: true)
try? FileManager.default.createDirectory(at: aboutHeroDir, withIntermediateDirectories: true)

// MARK: - Drawing primitives

let cos30 = 0.8660254037844387
let sin30 = 0.5
let textureGrid = 16

let grassBase     = CGColor(red: 0x6F/255.0, green: 0xB0/255.0, blue: 0x35/255.0, alpha: 1)
let grassDark     = CGColor(red: 0x55/255.0, green: 0x8F/255.0, blue: 0x25/255.0, alpha: 1)
let grassDarker   = CGColor(red: 0x4A/255.0, green: 0x7F/255.0, blue: 0x1F/255.0, alpha: 1)
let grassLight    = CGColor(red: 0x7F/255.0, green: 0xC3/255.0, blue: 0x42/255.0, alpha: 1)
let dirtBase      = CGColor(red: 0x88/255.0, green: 0x5C/255.0, blue: 0x36/255.0, alpha: 1)
let dirtDark      = CGColor(red: 0x6E/255.0, green: 0x46/255.0, blue: 0x25/255.0, alpha: 1)
let dirtDarker    = CGColor(red: 0x55/255.0, green: 0x36/255.0, blue: 0x1B/255.0, alpha: 1)
let dirtLight     = CGColor(red: 0xA0/255.0, green: 0x73/255.0, blue: 0x49/255.0, alpha: 1)

func variant(_ i: Int, _ j: Int, _ salt: Int) -> Int {
    let h = (i &* 73856093) ^ (j &* 19349663) ^ (salt &* 83492791)
    let mixed = (h ^ (h >> 13)) & 0x7FFFFFFF
    return mixed % 100
}

func grassTopColor(_ i: Int, _ j: Int) -> CGColor {
    switch variant(i, j, 1) {
    case 0..<10: return grassDarker
    case 10..<25: return grassDark
    case 25..<40: return grassLight
    default: return grassBase
    }
}

func dirtSideColor(_ i: Int, _ j: Int, isRight: Bool) -> CGColor {
    let v = variant(i, j, isRight ? 2 : 3)
    let raw: CGColor
    if j < 3 {
        if v < 30 { raw = grassDarker }
        else if v < 55 { raw = grassDark }
        else { raw = grassBase }
    } else if j == 3 {
        raw = v < 50 ? grassDarker : dirtDark
    } else {
        if v < 15 { raw = dirtDarker }
        else if v < 30 { raw = dirtLight }
        else if v < 50 { raw = dirtDark }
        else { raw = dirtBase }
    }
    if !isRight { return raw }
    let comps = raw.components ?? [0, 0, 0, 1]
    let r = CGFloat(comps[0]) * 0.78
    let g = CGFloat(comps[1]) * 0.78
    let b = CGFloat(comps[2]) * 0.78
    return CGColor(red: r, green: g, blue: b, alpha: 1)
}

func bilinear(_ tl: CGPoint, _ tr: CGPoint, _ br: CGPoint, _ bl: CGPoint,
              _ u: CGFloat, _ v: CGFloat) -> CGPoint {
    let topX = tl.x + (tr.x - tl.x) * u
    let topY = tl.y + (tr.y - tl.y) * u
    let botX = bl.x + (br.x - bl.x) * u
    let botY = bl.y + (br.y - bl.y) * u
    return CGPoint(x: topX + (botX - topX) * v, y: topY + (botY - topY) * v)
}

func drawFace(_ ctx: CGContext,
              _ tl: CGPoint, _ tr: CGPoint, _ br: CGPoint, _ bl: CGPoint,
              _ colorFn: (Int, Int) -> CGColor) {
    for j in 0..<textureGrid {
        for i in 0..<textureGrid {
            let u0 = CGFloat(i) / CGFloat(textureGrid)
            let u1 = CGFloat(i + 1) / CGFloat(textureGrid)
            let v0 = CGFloat(j) / CGFloat(textureGrid)
            let v1 = CGFloat(j + 1) / CGFloat(textureGrid)
            let p00 = bilinear(tl, tr, br, bl, u0, v0)
            let p10 = bilinear(tl, tr, br, bl, u1, v0)
            let p11 = bilinear(tl, tr, br, bl, u1, v1)
            let p01 = bilinear(tl, tr, br, bl, u0, v1)
            let color = colorFn(i, j)
            ctx.setFillColor(color)
            ctx.setStrokeColor(color)
            ctx.setLineWidth(0.6)
            ctx.move(to: p00)
            ctx.addLine(to: p10)
            ctx.addLine(to: p11)
            ctx.addLine(to: p01)
            ctx.closePath()
            ctx.drawPath(using: .fillStroke)
        }
    }
}

/// Renders the canonical isometric grass-block onto `ctx`. `size` is
/// the canvas edge in points; the cube fits inside a centered square
/// occupying `contentScale * size` so there's breathing room against
/// the macOS rounded-rect mask. `contentScale = 1.0` is full bleed.
func drawGrassBlock(into ctx: CGContext, size: CGFloat, contentScale: CGFloat) {
    let cx = size / 2.0
    // Almost geometric center — only a token 0.5 % downward bias
    // to compensate for the perceptual "top-heaviness" of an
    // isometric cube (the bright top face draws the eye up).
    // Larger biases (1.5 %, 4 %) made the cube look noticeably
    // low in Launchpad — keep this tiny.
    let cy = size / 2.0 + size * 0.005
    let baseScale = size * 0.42 * contentScale

    func P(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
        CGPoint(
            x: cx + CGFloat((x - y) * cos30) * baseScale,
            y: cy + CGFloat((x + y) * sin30 - z) * baseScale)
    }

    let vTopBack  = P(0, 0, 1)
    let vTopRight = P(1, 0, 1)
    let vTopFront = P(1, 1, 1)
    let vTopLeft  = P(0, 1, 1)
    let vBotRight = P(1, 0, 0)
    let vBotFront = P(1, 1, 0)
    let vBotLeft  = P(0, 1, 0)

    drawFace(ctx, vTopBack, vTopRight, vTopFront, vTopLeft, grassTopColor)
    drawFace(ctx, vTopLeft, vTopFront, vBotFront, vBotLeft) { dirtSideColor($0, $1, isRight: false) }
    drawFace(ctx, vTopRight, vTopFront, vBotFront, vBotRight) { dirtSideColor($0, $1, isRight: true) }
}

// MARK: - PNG writer

func writePNG(_ image: CGImage, to url: URL) {
    let type = UTType.png.identifier as CFString
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
        fputs("Failed to open PNG destination at \(url.path)\n", stderr)
        exit(1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) {
        fputs("Failed to finalize PNG at \(url.path)\n", stderr)
        exit(1)
    }
}

// MARK: - App icon set

/// Mimics the macOS Big Sur+ icon shape (rounded "squircle" silhouette
/// with content centered inside). Apple's actual squircle uses
/// continuous corners (superellipse); we approximate with a standard
/// rounded rect at `cornerRadius = 0.2237 * size`, which is what
/// Apple's own template files use for the bounding shape. The visual
/// difference vs. a true continuous corner is < 1 px at 1024 and
/// invisible at 16 / 32.
///
/// **Layout** (matching what Calendar / Mail / Finder etc. ship):
///   - The squircle fills the entire canvas — no transparent border.
///     When System Settings or the Dock draws the icon, the visible
///     edge of the rounded square reads as the icon's edge. An inset
///     squircle leaves an empty halo around the icon at small sizes
///     (Accessibility list, sidebar previews) that makes the artwork
///     feel undersized.
///   - The grass block fills ~68 % of the canvas — denser than tool
///     icons (Console, Disk Utility) but still leaves room for the
///     macOS visual rhythm. Anything denser starts crowding the
///     squircle edge at sub-256 sizes.
func makeAppIcon(size: Int) -> CGImage {
    let cgSize = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("CGContext creation failed") }

    // Flip Y so we're working in screen-up coords (consistent with the
    // C# IconBaker). Without the flip the isometric cube ends up
    // mirrored — the math assumes top-left origin.
    ctx.translateBy(x: 0, y: cgSize)
    ctx.scaleBy(x: 1, y: -1)

    // Apple's macOS icon template puts content inside an
    // 824 × 824 live area centred in a 1024 canvas — a 10 % margin
    // on every side. Sampling the actual System Settings / App Store
    // icons shows their visible squircle background sits at roughly
    // an 8 % inset, leaving a small but visible "halo" around the
    // shape. We match that so MC Controller doesn't read as
    // oversized in Launchpad / Dock vs. its neighbours.
    let inset: CGFloat = cgSize * 0.08
    let squircleRect = CGRect(x: inset, y: inset,
                              width: cgSize - 2 * inset,
                              height: cgSize - 2 * inset)
    // 22.37 % corner radius of the *inscribed squircle* — matches
    // the curvature ratio Apple's icon template uses.
    let cornerRadius = squircleRect.width * 0.2237
    let path = CGPath(roundedRect: squircleRect,
                      cornerWidth: cornerRadius,
                      cornerHeight: cornerRadius,
                      transform: nil)

    // Fill the squircle with white.
    ctx.addPath(path)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillPath()

    // Hairline border so the icon reads as a discrete shape on
    // similarly-toned wallpapers / list backgrounds.
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0.08))
    ctx.setLineWidth(max(0.5, cgSize / 1024))
    ctx.strokePath()

    // `contentScale = 0.78` — picked by visually comparing the
    // System Settings gear and the App Store "A" logo inside their
    // respective squircles: both fill roughly 70-75 % of the
    // squircle width. Our cube reaches ~57 % canvas wide (because
    // the isometric diagonal is narrower than the bounding box) /
    // ~66 % canvas tall, which inside the 84 % squircle works out
    // to ~68 % × ~78 % of the squircle interior — matching the
    // Apple references.
    drawGrassBlock(into: ctx, size: cgSize, contentScale: 0.78)

    return ctx.makeImage()!
}

/// Transparent-background variant used by the About page's hero. No
/// squircle, no white fill — just the isometric grass block sitting
/// on alpha-zero pixels. Drawn larger (`contentScale = 0.86`) since
/// there's no surrounding frame to balance.
func makeAboutHeroIcon(size: Int) -> CGImage {
    let cgSize = CGFloat(size)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("CGContext creation failed") }

    ctx.translateBy(x: 0, y: cgSize)
    ctx.scaleBy(x: 1, y: -1)
    ctx.clear(CGRect(x: 0, y: 0, width: cgSize, height: cgSize))

    drawGrassBlock(into: ctx, size: cgSize, contentScale: 0.86)
    return ctx.makeImage()!
}

// macOS AppIcon sizes (point × scale): 16/16×2, 32/32×2, 128/128×2,
// 256/256×2, 512/512×2.
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
    let image = makeAppIcon(size: spec.pixelSize)
    writePNG(image, to: appIconDir.appendingPathComponent(spec.filename))
}

// AppIcon Contents.json
var appIconImages: [[String: String]] = []
for spec in appIconSpecs {
    appIconImages.append([
        "size": "\(spec.dimensionPoints)x\(spec.dimensionPoints)",
        "idiom": "mac",
        "filename": spec.filename,
        "scale": "\(spec.scale)x",
    ])
}
let appIconContents: [String: Any] = [
    "images": appIconImages,
    "info": ["version": 1, "author": "xcode"] as [String: Any],
]
let appIconJSON = try JSONSerialization.data(
    withJSONObject: appIconContents,
    options: [.prettyPrinted, .sortedKeys])
try appIconJSON.write(to: appIconDir.appendingPathComponent("Contents.json"))

// MARK: - About hero icon (transparent background)

struct AboutHeroSpec {
    let dimensionPoints: Int
    let scale: Int
    var pixelSize: Int { dimensionPoints * scale }
    var filename: String { "about_hero_\(dimensionPoints)@\(scale)x.png" }
}

// macOS only supports @1x + @2x in image sets.
let aboutHeroSpecs: [AboutHeroSpec] = [
    .init(dimensionPoints: 64, scale: 1),
    .init(dimensionPoints: 64, scale: 2),
]

// Menu bar icon: 18 pt canvas (16 pt is the historical default but
// reads visibly small in the 22-pt-tall Sequoia menu bar).

for spec in aboutHeroSpecs {
    let image = makeAboutHeroIcon(size: spec.pixelSize)
    writePNG(image, to: aboutHeroDir.appendingPathComponent(spec.filename))
}

let aboutHeroContents: [String: Any] = [
    "images": aboutHeroSpecs.map { spec in
        [
            "idiom": "mac",
            "filename": spec.filename,
            "scale": "\(spec.scale)x",
        ] as [String: String]
    },
    "info": ["version": 1, "author": "xcode"] as [String: Any],
]
let aboutHeroJSON = try JSONSerialization.data(
    withJSONObject: aboutHeroContents,
    options: [.prettyPrinted, .sortedKeys])
try aboutHeroJSON.write(to: aboutHeroDir.appendingPathComponent("Contents.json"))

// MARK: - Menu bar icon (template)

/// Draws three faces of the cube at distinct alpha levels. macOS
/// renders template images in the menu-bar tint of the active
/// appearance (black on light, white on dark), so varying the alpha
/// per face is the only way to convey 3D depth — a flat 100 %-alpha
/// silhouette reads as a hexagon at 16 pt.
///
/// Alpha assignment chosen to mimic the lit / shaded look of the full
/// color icon:
///   - top face (grass)   : alpha 1.0  (brightest)
///   - left face (sunlit) : alpha 0.70
///   - right face (shadow): alpha 0.45
///
/// The canvas is 18 pt rather than the usual 16 — macOS's menu bar
/// slot is ~22 pt tall, so a 16 pt canvas centers with ~3 pt
/// vertical padding on each side and reads as visibly small. 18 pt
/// leaves enough breathing room while filling the slot more
/// confidently. The `+0.025` vertical bias the *app* icon uses (to
/// compensate for the cube's bottom-heavy isometric silhouette)
/// is dropped here — at 18 pt the bias becomes a visible upward
/// nudge that makes the icon look mis-centered against
/// adjacent menu items.
func makeMenuBarIcon(pixelSize: Int) -> CGImage {
    let cgSize = CGFloat(pixelSize)
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil, width: pixelSize, height: pixelSize,
        bitsPerComponent: 8, bytesPerRow: 0, space: cs,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { fatalError("CGContext creation failed") }

    ctx.translateBy(x: 0, y: cgSize)
    ctx.scaleBy(x: 1, y: -1)
    ctx.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))

    let cx = cgSize / 2.0
    // Isometric cubes have a *visual* center that sits slightly
    // ABOVE the geometric center — the top face is fully visible
    // while the bottom is a single point peeking through the front
    // edges, so the rendered pixel mass leans up-left. Compensate
    // by nudging the cube DOWN; users perceived the un-biased
    // version as "shifted up by ~1 px" in the menu bar slot.
    let cy = cgSize / 2.0 + cgSize * 0.05
    // Slightly oversize (the `*1.10` factor) so the cube reaches
    // the top edge of the 18 pt canvas — the isometric silhouette
    // is bounded by the diagonal across the top face, which leaves
    // visible left/right padding even at 100% scale, making the
    // icon read smaller than its bounding box.
    let scale = cgSize * 0.42 * 1.10

    func P(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
        CGPoint(
            x: cx + CGFloat((x - y) * cos30) * scale,
            y: cy + CGFloat((x + y) * sin30 - z) * scale)
    }
    let vTopBack  = P(0, 0, 1)
    let vTopRight = P(1, 0, 1)
    let vTopFront = P(1, 1, 1)
    let vTopLeft  = P(0, 1, 1)
    let vBotRight = P(1, 0, 0)
    let vBotFront = P(1, 1, 0)
    let vBotLeft  = P(0, 1, 0)

    func fillFace(_ pts: [CGPoint], alpha: CGFloat) {
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: alpha))
        ctx.move(to: pts[0])
        for p in pts.dropFirst() { ctx.addLine(to: p) }
        ctx.closePath()
        ctx.fillPath()
    }

    // Right (shadow) face — drawn first so the other faces overlap
    // any anti-alias bleed at the seams.
    fillFace([vTopRight, vTopFront, vBotFront, vBotRight], alpha: 0.45)
    // Left (sunlit) face.
    fillFace([vTopLeft, vTopFront, vBotFront, vBotLeft], alpha: 0.70)
    // Top (grass) face — full alpha so it reads as the brightest plane.
    fillFace([vTopBack, vTopRight, vTopFront, vTopLeft], alpha: 1.0)

    return ctx.makeImage()!
}

// macOS only supports @1x + @2x menu bar icons; an @3x file triggers
// a "unassigned child" warning from the asset catalog compiler.
let menuSpecs: [(Int, Int, String)] = [
    (18, 1, "menu_18@1x.png"),
    (18, 2, "menu_18@2x.png"),
]
for (points, scale, filename) in menuSpecs {
    let image = makeMenuBarIcon(pixelSize: points * scale)
    writePNG(image, to: menuIconDir.appendingPathComponent(filename))
}

let menuContents: [String: Any] = [
    "images": menuSpecs.map { (points, scale, filename) in
        [
            "idiom": "mac",
            "filename": filename,
            "scale": "\(scale)x",
        ] as [String: String]
    },
    "info": ["version": 1, "author": "xcode"] as [String: Any],
    "properties": ["template-rendering-intent": "template"],
]
let menuJSON = try JSONSerialization.data(
    withJSONObject: menuContents,
    options: [.prettyPrinted, .sortedKeys])
try menuJSON.write(to: menuIconDir.appendingPathComponent("Contents.json"))

// MARK: - Root Contents.json for Assets.xcassets

let rootContents: [String: Any] = [
    "info": ["version": 1, "author": "xcode"] as [String: Any],
]
let rootJSON = try JSONSerialization.data(
    withJSONObject: rootContents,
    options: [.prettyPrinted, .sortedKeys])
try rootJSON.write(to: assetsRoot.appendingPathComponent("Contents.json"))

print("✅ Baked AppIcon (\(appIconSpecs.count) files), AboutHeroIcon (\(aboutHeroSpecs.count) files), and MenuBarIcon (\(menuSpecs.count) files).")
print("   AppIcon dir:        \(appIconDir.path)")
print("   AboutHeroIcon dir:  \(aboutHeroDir.path)")
print("   MenuBar dir:        \(menuIconDir.path)")
