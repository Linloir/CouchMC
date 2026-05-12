import UIKit

/// Transparent overlay that renders alignment guides (dashed lines for
/// edge snap + arrow-tipped segments for equal-spacing snap) on top of
/// the editor's canvas. Owns a pool of `CAShapeLayer` sublayers and
/// updates them in place rather than rebuilding every frame so the
/// dashed lines don't flicker as guides come and go during a drag.
final class AlignmentGuideOverlay: UIView {

    private var pool: [CAShapeLayer] = []
    private var inUse: Int = 0

    /// Edge-snap line colour — light grey with enough alpha to read
    /// against dark game backgrounds and the editor's #212121 canvas.
    private let edgeColor = UIColor(white: 0.78, alpha: 0.9).cgColor
    /// Spacing-snap line colour — warm amber to match the selection
    /// highlight, so the user reads it as "this gap was picked".
    private let spacingColor = UIColor(red: 0xE8/255, green: 0xC5/255, blue: 0x47/255, alpha: 0.9).cgColor

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false  // never block touches
        isOpaque = false
    }
    required init?(coder: NSCoder) { fatalError() }

    func setGuides(_ guides: [AlignmentSnapper.Guide]) {
        // Reuse existing layers where possible. New layers are appended
        // to `pool` lazily.
        inUse = 0
        for g in guides {
            apply(g, to: nextLayer())
        }
        // Hide any leftover pooled layers.
        for i in inUse..<pool.count {
            pool[i].isHidden = true
        }
    }

    func clear() {
        setGuides([])
    }

    // MARK: - Pool management

    private func nextLayer() -> CAShapeLayer {
        if inUse < pool.count {
            let layer = pool[inUse]
            layer.isHidden = false
            inUse += 1
            return layer
        }
        let layer = CAShapeLayer()
        layer.fillColor = nil
        layer.lineWidth = 1
        self.layer.addSublayer(layer)
        pool.append(layer)
        inUse += 1
        return layer
    }

    private func apply(_ guide: AlignmentSnapper.Guide, to layer: CAShapeLayer) {
        let path = UIBezierPath()
        switch guide {
        case .verticalLine(let x, let yMin, let yMax):
            layer.strokeColor = edgeColor
            layer.lineDashPattern = [4, 3]
            layer.lineWidth = 1
            // Extend slightly past the matched range so the guide reads
            // as a continuous line rather than a tiny segment.
            let pad: CGFloat = 12
            path.move(to: CGPoint(x: x, y: yMin - pad))
            path.addLine(to: CGPoint(x: x, y: yMax + pad))
        case .horizontalLine(let y, let xMin, let xMax):
            layer.strokeColor = edgeColor
            layer.lineDashPattern = [4, 3]
            layer.lineWidth = 1
            let pad: CGFloat = 12
            path.move(to: CGPoint(x: xMin - pad, y: y))
            path.addLine(to: CGPoint(x: xMax + pad, y: y))
        case .spacingHorizontal(let y, let aStartX, let aEndX, let bStartX, let bEndX):
            layer.strokeColor = spacingColor
            layer.lineDashPattern = nil
            layer.lineWidth = 1.5
            appendArrowSegment(to: path, from: CGPoint(x: aStartX, y: y), to: CGPoint(x: aEndX, y: y), vertical: false)
            appendArrowSegment(to: path, from: CGPoint(x: bStartX, y: y), to: CGPoint(x: bEndX, y: y), vertical: false)
        case .spacingVertical(let x, let aStartY, let aEndY, let bStartY, let bEndY):
            layer.strokeColor = spacingColor
            layer.lineDashPattern = nil
            layer.lineWidth = 1.5
            appendArrowSegment(to: path, from: CGPoint(x: x, y: aStartY), to: CGPoint(x: x, y: aEndY), vertical: true)
            appendArrowSegment(to: path, from: CGPoint(x: x, y: bStartY), to: CGPoint(x: x, y: bEndY), vertical: true)
        }
        layer.path = path.cgPath
    }

    /// Draw `|—————|` shape: small perpendicular caps + a line between them.
    /// Used to mark each "gap" segment in an equal-spacing guide.
    private func appendArrowSegment(to path: UIBezierPath,
                                    from start: CGPoint,
                                    to end: CGPoint,
                                    vertical: Bool) {
        let capHalf: CGFloat = 4
        path.move(to: start)
        path.addLine(to: end)
        if vertical {
            path.move(to: CGPoint(x: start.x - capHalf, y: start.y))
            path.addLine(to: CGPoint(x: start.x + capHalf, y: start.y))
            path.move(to: CGPoint(x: end.x - capHalf, y: end.y))
            path.addLine(to: CGPoint(x: end.x + capHalf, y: end.y))
        } else {
            path.move(to: CGPoint(x: start.x, y: start.y - capHalf))
            path.addLine(to: CGPoint(x: start.x, y: start.y + capHalf))
            path.move(to: CGPoint(x: end.x, y: end.y - capHalf))
            path.addLine(to: CGPoint(x: end.x, y: end.y + capHalf))
        }
    }
}
