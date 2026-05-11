import CoreGraphics
import Foundation

/// Minimal SVG path data → CGPath parser.
///
/// Supports the subset of commands used by the project's Android vector
/// drawables: M/m, L/l, A/a, C/c, Q/q, Z/z. Each command may be followed
/// by repeated parameter sets (SVG spec: an `M` followed by extra
/// coordinate pairs implicitly applies `L` to each subsequent pair).
///
/// Arc segments (A/a) are converted to up-to-four cubic Bézier curves
/// using the endpoint→center parameterisation from
/// <https://www.w3.org/TR/SVG/implnote.html#ArcImplementationNotes>.
enum SVGPath {

    static func parse(_ d: String) -> CGPath {
        let tokens = tokenize(d)
        let path = CGMutablePath()
        var i = 0
        var current = CGPoint.zero
        var subStart = CGPoint.zero
        var lastCmd: Character = " "

        while i < tokens.count {
            // Read a command, or repeat the previous one if the next token
            // is a number (implicit-repeat rule from the SVG path spec).
            let cmd: Character
            if case .command(let c) = tokens[i] {
                cmd = c
                i += 1
            } else if lastCmd != " " {
                // Implicit repeat: M repeats as L, m as l. Otherwise repeats itself.
                cmd = (lastCmd == "M") ? "L" : (lastCmd == "m") ? "l" : lastCmd
            } else {
                i += 1
                continue
            }
            lastCmd = cmd

            let absolute = cmd.isUppercase
            switch Character(cmd.lowercased()) {
            case "m":
                var p = readPoint(tokens, &i)
                if !absolute { p = CGPoint(x: current.x + p.x, y: current.y + p.y) }
                path.move(to: p)
                current = p
                subStart = p
            case "l":
                var p = readPoint(tokens, &i)
                if !absolute { p = CGPoint(x: current.x + p.x, y: current.y + p.y) }
                path.addLine(to: p)
                current = p
            case "h":
                var x = readNumber(tokens, &i)
                if !absolute { x += current.x }
                let p = CGPoint(x: x, y: current.y)
                path.addLine(to: p)
                current = p
            case "v":
                var y = readNumber(tokens, &i)
                if !absolute { y += current.y }
                let p = CGPoint(x: current.x, y: y)
                path.addLine(to: p)
                current = p
            case "c":
                var c1 = readPoint(tokens, &i)
                var c2 = readPoint(tokens, &i)
                var p  = readPoint(tokens, &i)
                if !absolute {
                    c1 = CGPoint(x: current.x + c1.x, y: current.y + c1.y)
                    c2 = CGPoint(x: current.x + c2.x, y: current.y + c2.y)
                    p  = CGPoint(x: current.x + p.x,  y: current.y + p.y)
                }
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p
            case "q":
                var cp = readPoint(tokens, &i)
                var p  = readPoint(tokens, &i)
                if !absolute {
                    cp = CGPoint(x: current.x + cp.x, y: current.y + cp.y)
                    p  = CGPoint(x: current.x + p.x,  y: current.y + p.y)
                }
                path.addQuadCurve(to: p, control: cp)
                current = p
            case "a":
                let rx = readNumber(tokens, &i)
                let ry = readNumber(tokens, &i)
                let xRot = readNumber(tokens, &i)
                let largeArc = readNumber(tokens, &i) != 0
                let sweep    = readNumber(tokens, &i) != 0
                var end = readPoint(tokens, &i)
                if !absolute { end = CGPoint(x: current.x + end.x, y: current.y + end.y) }
                appendArc(to: path, from: current, to: end,
                          rx: rx, ry: ry, xRot: xRot,
                          largeArc: largeArc, sweep: sweep)
                current = end
            case "z":
                path.closeSubpath()
                current = subStart
            default:
                break
            }
        }
        return path
    }

    // MARK: - Tokenizer

    private enum Token { case command(Character), number(CGFloat) }

    private static func tokenize(_ s: String) -> [Token] {
        var tokens: [Token] = []
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c.isLetter {
                tokens.append(.command(c))
                i = s.index(after: i)
                continue
            }
            if c == "," || c.isWhitespace {
                i = s.index(after: i)
                continue
            }
            // Parse a number — supports optional leading sign and scientific notation.
            var numStr = ""
            if c == "-" || c == "+" {
                numStr.append(c)
                i = s.index(after: i)
            }
            while i < s.endIndex {
                let ch = s[i]
                if ch.isNumber || ch == "." {
                    numStr.append(ch)
                    i = s.index(after: i)
                } else if ch == "e" || ch == "E" {
                    numStr.append(ch)
                    i = s.index(after: i)
                    if i < s.endIndex, (s[i] == "+" || s[i] == "-") {
                        numStr.append(s[i])
                        i = s.index(after: i)
                    }
                } else {
                    break
                }
            }
            if let n = Double(numStr) {
                tokens.append(.number(CGFloat(n)))
            } else if numStr.isEmpty {
                // Unknown character — skip.
                i = s.index(after: i)
            }
        }
        return tokens
    }

    private static func readNumber(_ tokens: [Token], _ i: inout Int) -> CGFloat {
        guard i < tokens.count, case .number(let n) = tokens[i] else { return 0 }
        i += 1
        return n
    }

    private static func readPoint(_ tokens: [Token], _ i: inout Int) -> CGPoint {
        let x = readNumber(tokens, &i)
        let y = readNumber(tokens, &i)
        return CGPoint(x: x, y: y)
    }

    // MARK: - Arc → cubic Bézier conversion

    /// Convert an SVG elliptical arc from `p1` to `p2` into one or more
    /// cubic Bézier curves appended to `path`. The conversion follows the
    /// W3C SVG implementation notes (endpoint → center parameterisation).
    private static func appendArc(to path: CGMutablePath,
                                  from p1: CGPoint, to p2: CGPoint,
                                  rx rxIn: CGFloat, ry ryIn: CGFloat,
                                  xRot: CGFloat,
                                  largeArc: Bool, sweep: Bool) {
        if p1 == p2 { return }
        if rxIn == 0 || ryIn == 0 {
            path.addLine(to: p2)
            return
        }

        var rx = abs(rxIn)
        var ry = abs(ryIn)
        let phi = xRot * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)

        // Step 1: transform endpoints to the unrotated ellipse coord system.
        let dx = (p1.x - p2.x) / 2
        let dy = (p1.y - p2.y) / 2
        let x1p =  cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        // Step 2: enlarge radii if they're too small to span the chord.
        let rxSq0 = rx * rx, rySq0 = ry * ry
        let x1pSq = x1p * x1p, y1pSq = y1p * y1p
        let lambda = x1pSq / rxSq0 + y1pSq / rySq0
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s
            ry *= s
        }
        let rxSq = rx * rx, rySq = ry * ry

        // Step 3: compute center in the transformed coord system.
        let sign: CGFloat = (largeArc == sweep) ? -1 : 1
        let num = rxSq * rySq - rxSq * y1pSq - rySq * x1pSq
        let den = rxSq * y1pSq + rySq * x1pSq
        let coef = sign * sqrt(max(0, num / den))
        let cxp = coef * (rx * y1p / ry)
        let cyp = -coef * (ry * x1p / rx)

        // Step 4: untransform center back to user space.
        let cx = cosPhi * cxp - sinPhi * cyp + (p1.x + p2.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p1.y + p2.y) / 2

        // Step 5: start + sweep angles.
        func ang(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let len = sqrt((ux*ux + uy*uy) * (vx*vx + vy*vy))
            var a = acos(max(-1, min(1, dot / len)))
            if (ux * vy - uy * vx) < 0 { a = -a }
            return a
        }
        let nx1 = (x1p - cxp) / rx, ny1 = (y1p - cyp) / ry
        let nx2 = (-x1p - cxp) / rx, ny2 = (-y1p - cyp) / ry
        let theta1 = ang(1, 0, nx1, ny1)
        var delta = ang(nx1, ny1, nx2, ny2)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0  { delta += 2 * .pi }

        // Step 6: approximate with up to 4 cubic Béziers (one per 90°).
        let segments = max(1, Int(ceil(abs(delta) / (.pi / 2))))
        let deltaPerSeg = delta / CGFloat(segments)
        let t = (4.0 / 3.0) * tan(deltaPerSeg / 4)

        var theta = theta1
        for _ in 0..<segments {
            let cosT = cos(theta), sinT = sin(theta)
            let next = theta + deltaPerSeg
            let cosN = cos(next),  sinN = sin(next)

            // Control + end points in unrotated coords.
            let endX = rx * cosN, endY = ry * sinN
            let c1X  = rx * (cosT - t * sinT)
            let c1Y  = ry * (sinT + t * cosT)
            let c2X  = rx * (cosN + t * sinN)
            let c2Y  = ry * (sinN - t * cosN)

            // Rotate + translate back to user space.
            func untransform(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(x: cosPhi * x - sinPhi * y + cx,
                        y: sinPhi * x + cosPhi * y + cy)
            }
            path.addCurve(to: untransform(endX, endY),
                          control1: untransform(c1X, c1Y),
                          control2: untransform(c2X, c2Y))
            theta = next
        }
    }
}
