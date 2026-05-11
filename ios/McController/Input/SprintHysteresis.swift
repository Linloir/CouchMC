import Foundation

/// Joystick-extension sprint detector with engage / disengage hysteresis so
/// the boundary doesn't jitter. Mirrors the Android `SPRINT_ENGAGE_FACTOR /
/// SPRINT_DISENGAGE_FACTOR` constants in `JoystickView`.
struct SprintHysteresis {
    let engageThreshold: Float       // squared distance to engage
    let disengageThreshold: Float    // squared distance to disengage
    private(set) var engaged: Bool = false

    init(engage: Float = 0.81, disengage: Float = 0.64) {
        // Defaults: engage at 0.9 norm distance (0.9² ≈ 0.81),
        // disengage at 0.8 (0.8² ≈ 0.64).
        self.engageThreshold = engage
        self.disengageThreshold = disengage
    }

    /// Feed normalized (-1...1) joystick deflection. Returns the new state.
    @discardableResult
    mutating func update(x: Float, y: Float) -> Bool {
        let d2 = x * x + y * y
        if engaged {
            if d2 < disengageThreshold { engaged = false }
        } else {
            if d2 > engageThreshold { engaged = true }
        }
        return engaged
    }

    mutating func reset() { engaged = false }
}
