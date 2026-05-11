import SwiftUI

/// Live preview of the camera sensitivity curve. Mirrors
/// `Controls/CurveCanvas.xaml.cs` on the Windows side.
///
/// X axis: raw finger speed (pixels/frame, 0..maxInput).
/// Y axis: effective on-screen pixels after curve + user sensitivity.
/// The dashed reference is the y = x identity (no scaling) so the live
/// curve always reads as a distinct line above it.
struct CurveCanvasView: View {

    let camera: CameraConfig
    var maxInput: Double = 200
    var maxOutput: Double = 600

    private let samples = 80
    private let padL: CGFloat = 32
    private let padR: CGFloat = 12
    private let padT: CGFloat = 12
    private let padB: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width - padL - padR
            let h = geo.size.height - padT - padB
            if w > 0 && h > 0 {
                let displayMax = effectiveMaxOutput()
                ZStack {
                    gridPath(w: w, h: h)
                        .stroke(.white.opacity(0.08), lineWidth: 1)

                    identityPath(w: w, h: h, displayMax: displayMax)
                        .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundColor(.white.opacity(0.45))

                    curvePath(w: w, h: h, displayMax: displayMax)
                        .stroke(Color(red: 91/255, green: 127/255, blue: 1.0),
                                style: StrokeStyle(lineWidth: 2.0, lineJoin: .round))
                }
            }
        }
        .background(Color.black.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func effectiveMaxOutput() -> Double {
        let raw = sampleOutput(rawSpeed: maxInput)
        return Swift.max(maxOutput, raw * 1.1)
    }

    private func gridPath(w: CGFloat, h: CGFloat) -> Path {
        Path { p in
            for i in 0...4 {
                let x = padL + w * CGFloat(i) / 4
                p.move(to: CGPoint(x: x, y: padT))
                p.addLine(to: CGPoint(x: x, y: padT + h))
                let y = padT + h * CGFloat(i) / 4
                p.move(to: CGPoint(x: padL, y: y))
                p.addLine(to: CGPoint(x: padL + w, y: y))
            }
        }
    }

    private func identityPath(w: CGFloat, h: CGFloat, displayMax: Double) -> Path {
        Path { p in
            let xEnd = padL + w
            let yEnd = padT + h - h * CGFloat(maxInput / displayMax)
            p.move(to: CGPoint(x: padL, y: padT + h))
            p.addLine(to: CGPoint(x: xEnd, y: Swift.max(padT, yEnd)))
        }
    }

    private func curvePath(w: CGFloat, h: CGFloat, displayMax: Double) -> Path {
        Path { p in
            p.move(to: CGPoint(x: padL, y: padT + h))
            for i in 1...samples {
                let raw = maxInput * Double(i) / Double(samples)
                let out = sampleOutput(rawSpeed: raw)
                let px = padL + w * CGFloat(raw / maxInput)
                let py = Swift.max(padT, padT + h - h * CGFloat(out / displayMax))
                p.addLine(to: CGPoint(x: px, y: py))
            }
        }
    }

    private func sampleOutput(rawSpeed: Double) -> Double {
        var accel = 1.0
        if camera.curveType == .power {
            let computed = 1.0 + Double(camera.accelFactor) * pow(rawSpeed, Double(camera.accelExp))
            accel = Swift.min(computed, Double(camera.maxAccelMultiplier))
            if accel < 1.0 { accel = 1.0 }
        }
        return rawSpeed * accel * Double(camera.userSensitivity)
    }
}
