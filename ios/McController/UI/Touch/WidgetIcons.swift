import UIKit

/// Icons for the controller's action buttons.
///
/// Each icon is described as a sequence of subpaths (path data + fill/stroke
/// style) ported directly from the matching Android vector drawables under
/// `android/app/src/main/res/drawable/ic_btn_*.xml`. The 24×24 viewport is
/// preserved; the renderer scales to whatever rect the caller draws into.
enum WidgetIcon {
    case jump
    case sneak
    case sprint
    case mouseLeft
    case mouseRight
    case inventory
    case swap
    case esc
    case shift
    case drop
    case close

    enum Style {
        case fill(alpha: CGFloat, evenOdd: Bool)
        case stroke(width: CGFloat, alpha: CGFloat, lineCap: CGLineCap, lineJoin: CGLineJoin)
    }

    struct Subpath {
        let pathData: String
        let style: Style
    }

    var subpaths: [Subpath] {
        switch self {
        case .jump:        return jumpSubpaths
        case .sneak:       return sneakSubpaths
        case .sprint:      return sprintSubpaths
        case .mouseLeft:   return mouseLeftSubpaths
        case .mouseRight:  return mouseRightSubpaths
        case .inventory:   return inventorySubpaths
        case .swap:        return swapSubpaths
        case .esc:         return escSubpaths
        case .shift:       return shiftSubpaths
        case .drop:        return dropSubpaths
        case .close:       return closeSubpaths
        }
    }

    /// Draw the icon into `rect` of the given context, tinted with `color`.
    /// The icon's 24×24 viewport is scaled to fit `rect`, preserving aspect
    /// ratio.
    func draw(in rect: CGRect, color: UIColor, ctx: CGContext) {
        let scale = min(rect.width, rect.height) / 24
        let drawnSize = 24 * scale
        let tx = rect.midX - drawnSize / 2
        let ty = rect.midY - drawnSize / 2

        ctx.saveGState()
        ctx.translateBy(x: tx, y: ty)
        ctx.scaleBy(x: scale, y: scale)

        for sub in subpaths {
            let path = SVGPath.parse(sub.pathData)
            switch sub.style {
            case .fill(let alpha, let evenOdd):
                ctx.setFillColor(color.withAlphaComponent(alpha).cgColor)
                ctx.addPath(path)
                ctx.fillPath(using: evenOdd ? .evenOdd : .winding)
            case .stroke(let width, let alpha, let cap, let join):
                ctx.setStrokeColor(color.withAlphaComponent(alpha).cgColor)
                ctx.setLineWidth(width)
                ctx.setLineCap(cap)
                ctx.setLineJoin(join)
                ctx.addPath(path)
                ctx.strokePath()
            }
        }
        ctx.restoreGState()
    }
}

// MARK: - Per-icon subpath data
//
// Path coordinates are copied verbatim from the project's Android vector
// drawables (android/app/src/main/res/drawable/ic_btn_*.xml). Each icon
// uses a 24×24 viewport.

private let jumpSubpaths: [WidgetIcon.Subpath] = [
    // Head
    .init(pathData: "M 12.5,3.8 m -2,0 a 2,2 0 1,0 4,0 a 2,2 0 1,0 -4,0",
          style: .fill(alpha: 1, evenOdd: false)),
    // Torso
    .init(pathData: "M 11.4,6 L 13.6,6.3 L 11.6,12.4 L 9.4,12.2 Z",
          style: .fill(alpha: 1, evenOdd: false)),
    // Lead arm
    .init(pathData: "M 12.6,7 L 16.6,5",
          style: .stroke(width: 2.4, alpha: 1, lineCap: .round, lineJoin: .miter)),
    // Trailing arm
    .init(pathData: "M 10.8,7.4 L 6.8,9.6",
          style: .stroke(width: 2.4, alpha: 1, lineCap: .round, lineJoin: .miter)),
    // Lead leg
    .init(pathData: "M 11.6,12.4 L 16,11 L 18.6,13",
          style: .stroke(width: 2.6, alpha: 1, lineCap: .round, lineJoin: .round)),
    // Trailing leg
    .init(pathData: "M 9.4,12.4 L 5,14.6 L 1.6,17",
          style: .stroke(width: 2.6, alpha: 1, lineCap: .round, lineJoin: .round)),
    // Ground
    .init(pathData: "M 3,20.4 L 21,20.4 L 21,21.8 L 3,21.8 Z",
          style: .fill(alpha: 0.45, evenOdd: false)),
]

private let sneakSubpaths: [WidgetIcon.Subpath] = [
    .init(pathData: "M 15.2,5.4 m -2,0 a 2,2 0 1,0 4,0 a 2,2 0 1,0 -4,0",
          style: .fill(alpha: 1, evenOdd: false)),
    .init(pathData: "M 14.2,7.6 Q 11.6,10.4 10.4,13",
          style: .stroke(width: 3, alpha: 1, lineCap: .round, lineJoin: .miter)),
    .init(pathData: "M 13.4,8.8 L 16.8,11.6",
          style: .stroke(width: 2.4, alpha: 1, lineCap: .round, lineJoin: .miter)),
    .init(pathData: "M 12.4,8.6 L 9,11",
          style: .stroke(width: 2.4, alpha: 1, lineCap: .round, lineJoin: .miter)),
    .init(pathData: "M 10.4,13 L 14.2,15.6 L 17.8,18.8",
          style: .stroke(width: 2.6, alpha: 1, lineCap: .round, lineJoin: .round)),
    .init(pathData: "M 10.4,13 L 6.6,15 L 5.4,18.8",
          style: .stroke(width: 2.6, alpha: 1, lineCap: .round, lineJoin: .round)),
    .init(pathData: "M 3,19.6 L 21,19.6 L 21,21 L 3,21 Z",
          style: .fill(alpha: 0.45, evenOdd: false)),
]

private let sprintSubpaths: [WidgetIcon.Subpath] = [
    // Motion lines drawn first so the figure overlaps them.
    .init(pathData: "M 1,7.6 L 5.6,7.6 L 5.6,8.8 L 1,8.8 Z",
          style: .fill(alpha: 0.30, evenOdd: false)),
    .init(pathData: "M 0.6,11.4 L 5.2,11.4 L 5.2,12.7 L 0.6,12.7 Z",
          style: .fill(alpha: 0.55, evenOdd: false)),
    .init(pathData: "M 1.4,15.2 L 5,15.2 L 5,16.4 L 1.4,16.4 Z",
          style: .fill(alpha: 0.30, evenOdd: false)),
    .init(pathData: "M 16,3.8 m -2,0 a 2,2 0 1,0 4,0 a 2,2 0 1,0 -4,0",
          style: .fill(alpha: 1, evenOdd: false)),
    .init(pathData: "M 14.9,6 L 17.1,6.3 L 15.1,12.4 L 12.9,12.2 Z",
          style: .fill(alpha: 1, evenOdd: false)),
    .init(pathData: "M 16.5,7.4 L 19.5,8.6 L 17.4,11.8",
          style: .stroke(width: 2.4, alpha: 1, lineCap: .round, lineJoin: .round)),
    .init(pathData: "M 14,7.6 L 10.6,6 L 8.4,8.8",
          style: .stroke(width: 2.4, alpha: 1, lineCap: .round, lineJoin: .round)),
    .init(pathData: "M 15,12.6 L 18.5,16 L 19.5,20",
          style: .stroke(width: 2.6, alpha: 1, lineCap: .round, lineJoin: .round)),
    .init(pathData: "M 13,12.6 L 9,15.4 L 11.6,19.4",
          style: .stroke(width: 2.6, alpha: 1, lineCap: .round, lineJoin: .round)),
    .init(pathData: "M 4,21.4 L 21,21.4 L 21,22.8 L 4,22.8 Z",
          style: .fill(alpha: 0.45, evenOdd: false)),
]

private let mouseLeftSubpaths: [WidgetIcon.Subpath] = [
    // Highlighted top-left cap
    .init(pathData: "M 8,4 A 4,4 0 0 0 5,8 L 5,11 L 11.25,11 L 11.25,4 Z",
          style: .fill(alpha: 1, evenOdd: false)),
    // Outline
    .init(pathData: "M 9,4 L 15,4 A 4,4 0 0 1 19,8 L 19,16 A 4,4 0 0 1 15,20 L 9,20 A 4,4 0 0 1 5,16 L 5,8 A 4,4 0 0 1 9,4 Z",
          style: .stroke(width: 1.6, alpha: 1, lineCap: .butt, lineJoin: .miter)),
    // Horizontal divider
    .init(pathData: "M 5,11 L 19,11",
          style: .stroke(width: 1.4, alpha: 1, lineCap: .butt, lineJoin: .miter)),
    // Vertical divider
    .init(pathData: "M 12,4 L 12,11",
          style: .stroke(width: 1.4, alpha: 1, lineCap: .butt, lineJoin: .miter)),
]

private let mouseRightSubpaths: [WidgetIcon.Subpath] = [
    .init(pathData: "M 16,4 A 4,4 0 0 1 19,8 L 19,11 L 12.75,11 L 12.75,4 Z",
          style: .fill(alpha: 1, evenOdd: false)),
    .init(pathData: "M 9,4 L 15,4 A 4,4 0 0 1 19,8 L 19,16 A 4,4 0 0 1 15,20 L 9,20 A 4,4 0 0 1 5,16 L 5,8 A 4,4 0 0 1 9,4 Z",
          style: .stroke(width: 1.6, alpha: 1, lineCap: .butt, lineJoin: .miter)),
    .init(pathData: "M 5,11 L 19,11",
          style: .stroke(width: 1.4, alpha: 1, lineCap: .butt, lineJoin: .miter)),
    .init(pathData: "M 12,4 L 12,11",
          style: .stroke(width: 1.4, alpha: 1, lineCap: .butt, lineJoin: .miter)),
]

private let inventorySubpaths: [WidgetIcon.Subpath] = [
    // Left strap loop
    .init(pathData: "M 8.4,2.4 L 9.8,2.4 A 0.4,0.4 0 0 1 10.2,2.8 L 10.2,6 L 8,6 L 8,2.8 A 0.4,0.4 0 0 1 8.4,2.4 Z",
          style: .fill(alpha: 1, evenOdd: false)),
    // Right strap loop
    .init(pathData: "M 14.2,2.4 L 15.6,2.4 A 0.4,0.4 0 0 1 16,2.8 L 16,6 L 13.8,6 L 13.8,2.8 A 0.4,0.4 0 0 1 14.2,2.4 Z",
          style: .fill(alpha: 1, evenOdd: false)),
    // Bag silhouette + pocket cutout (even-odd fill).
    .init(pathData:
          "M 8,6 C 4.8,6.4 4,9 4,12 L 4,14.4 L 2.4,14.4 L 2.4,18.2 L 4,18.2 L 4,20.4 " +
          "A 1.6,1.6 0 0 0 5.6,22 L 18.4,22 A 1.6,1.6 0 0 0 20,20.4 L 20,18.2 L 21.6,18.2 " +
          "L 21.6,14.4 L 20,14.4 L 20,12 C 20,9 19.2,6.4 16,6 Z " +
          "M 8.4,14 L 15.6,14 A 0.6,0.6 0 0 1 16.2,14.6 L 16.2,18.4 A 0.6,0.6 0 0 1 15.6,19 " +
          "L 8.4,19 A 0.6,0.6 0 0 1 7.8,18.4 L 7.8,14.6 A 0.6,0.6 0 0 1 8.4,14 Z",
          style: .fill(alpha: 1, evenOdd: true)),
]

private let swapSubpaths: [WidgetIcon.Subpath] = [
    // Top-left rounded square
    .init(pathData:
          "M 4.2,2.4 L 7.8,2.4 A 1.8,1.8 0 0 1 9.6,4.2 L 9.6,7.8 A 1.8,1.8 0 0 1 7.8,9.6 " +
          "L 4.2,9.6 A 1.8,1.8 0 0 1 2.4,7.8 L 2.4,4.2 A 1.8,1.8 0 0 1 4.2,2.4 Z",
          style: .fill(alpha: 1, evenOdd: false)),
    // Bottom-right rounded square
    .init(pathData:
          "M 16.2,14.4 L 19.8,14.4 A 1.8,1.8 0 0 1 21.6,16.2 L 21.6,19.8 A 1.8,1.8 0 0 1 19.8,21.6 " +
          "L 16.2,21.6 A 1.8,1.8 0 0 1 14.4,19.8 L 14.4,16.2 A 1.8,1.8 0 0 1 16.2,14.4 Z",
          style: .fill(alpha: 1, evenOdd: false)),
    // Upper curve (top-left → bottom-right)
    .init(pathData: "M 10.5,6 Q 17.4,6 17.4,12.6",
          style: .stroke(width: 1.8, alpha: 1, lineCap: .round, lineJoin: .miter)),
    // Upper arrowhead
    .init(pathData: "M 17.4,14 L 15,11.4 L 19.8,11.4 Z",
          style: .fill(alpha: 1, evenOdd: false)),
    // Lower curve (bottom-right → top-left)
    .init(pathData: "M 13.5,18 Q 6.6,18 6.6,11.4",
          style: .stroke(width: 1.8, alpha: 1, lineCap: .round, lineJoin: .miter)),
    // Lower arrowhead
    .init(pathData: "M 6.6,10 L 9,12.6 L 4.2,12.6 Z",
          style: .fill(alpha: 1, evenOdd: false)),
]

private let escSubpaths: [WidgetIcon.Subpath] = [
    .init(pathData: "M 20,10.5 L 8.7,10.5 L 13.3,5.9 L 11.4,4 L 3.4,12 L 11.4,20 L 13.3,18.1 L 8.7,13.5 L 20,13.5 Z",
          style: .fill(alpha: 1, evenOdd: false)),
]

private let shiftSubpaths: [WidgetIcon.Subpath] = [
    // Key cap with up-arrow cutout (even-odd fill).
    .init(pathData:
          "M 4,5 L 20,5 A 1.4,1.4 0 0 1 21.4,6.4 L 21.4,18.6 A 1.4,1.4 0 0 1 20,20 " +
          "L 4,20 A 1.4,1.4 0 0 1 2.6,18.6 L 2.6,6.4 A 1.4,1.4 0 0 1 4,5 Z " +
          "M 12,8 L 17,13 L 14.5,13 L 14.5,17 L 9.5,17 L 9.5,13 L 7,13 Z",
          style: .fill(alpha: 1, evenOdd: true)),
]

private let dropSubpaths: [WidgetIcon.Subpath] = [
    // Lift handle
    .init(pathData: "M 9.5,3 L 14.5,3 L 14.5,5 L 9.5,5 Z",
          style: .fill(alpha: 1, evenOdd: false)),
    // Lid
    .init(pathData: "M 5,5.5 L 19,5.5 L 19,7.5 L 5,7.5 Z",
          style: .fill(alpha: 1, evenOdd: false)),
    // Body + three vertical cutouts (even-odd fill).
    .init(pathData:
          "M 7,8.5 L 17,8.5 L 17,19 A 2,2 0 0 1 15,21 L 9,21 A 2,2 0 0 1 7,19 Z " +
          "M 10,11.5 L 10.8,11.5 L 10.8,18 L 10,18 Z " +
          "M 12,11.5 L 12.8,11.5 L 12.8,18 L 12,18 Z " +
          "M 14,11.5 L 14.8,11.5 L 14.8,18 L 14,18 Z",
          style: .fill(alpha: 1, evenOdd: true)),
]

// Close — bold filled X. Geometry tuned so the visual stroke weight
// matches the esc back-arrow at the same display size (user asked for
// "same size + thickness as esc"). Built from two filled parallelograms
// rather than two stroked lines so the centre overlap reads as a solid
// node (matching the esc arrow's solid character) instead of as a thin
// crossed-line glyph.
private let closeSubpaths: [WidgetIcon.Subpath] = [
    // Top-left ↘ bottom-right diagonal
    .init(pathData:
          "M 5.6,4.2 L 7.5,4.2 L 19.8,16.5 L 19.8,18.4 L 17.9,18.4 " +
          "L 5.6,6.1 Z",
          style: .fill(alpha: 1, evenOdd: false)),
    // Top-right ↙ bottom-left diagonal
    .init(pathData:
          "M 16.5,4.2 L 18.4,4.2 L 18.4,6.1 L 6.1,18.4 L 4.2,18.4 " +
          "L 4.2,16.5 Z",
          style: .fill(alpha: 1, evenOdd: false)),
]
