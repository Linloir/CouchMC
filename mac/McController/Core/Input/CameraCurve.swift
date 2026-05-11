import Foundation

/// Two-layer camera transform applied to raw look deltas before injection.
/// Mirrors `CameraCurve.cs` precisely — the math is identical, so a
/// profile authored on Windows feels the same after carrying over.
///
/// Layer 1 — Developer curve (hidden from end users in production):
///   Speed-dependent acceleration. Quick swipes turn fast, slow drags
///   stay precise for fine aim.
///
/// Layer 2 — User sensitivity:
///   Single 0.5..3.0 multiplier exposed in the user-facing UI.
///
/// Carries a residual fractional component across calls so a stream of
/// sub-pixel deltas eventually accumulates to a 1-pixel output instead
/// of being truncated to zero every time.
final class CameraCurve {

    private let config: ServerConfig
    private var residualX: Float = 0
    private var residualY: Float = 0

    init(config: ServerConfig) {
        self.config = config
    }

    func apply(rawDx: Float, rawDy: Float) -> (Int, Int) {
        let cam = config.camera
        let speed = (rawDx * rawDx + rawDy * rawDy).squareRoot()

        let accelMul: Float
        switch cam.curveType {
        case .power:
            let raw = 1 + cam.accelFactor * pow(speed, cam.accelExp)
            accelMul = min(raw, cam.maxAccelMultiplier)
        case .linear:
            accelMul = 1
        }

        let scale = cam.userSensitivity * accelMul
        let fx = rawDx * scale + residualX
        let fy = rawDy * scale + residualY
        let ix = Int(fx.rounded(.towardZero))
        let iy = Int(fy.rounded(.towardZero))
        residualX = fx - Float(ix)
        residualY = fy - Float(iy)
        return (ix, iy)
    }

    func reset() {
        residualX = 0
        residualY = 0
    }
}
