import Foundation

/// Translates a normalized joystick position [-1, 1] into WASD key state.
/// Convention: y > 0 means forward (W) — the Android client flips
/// screen-Y before sending. Mirrors `JoystickToWasdMapper.cs`.
///
/// Hysteresis (enter/exit thresholds) prevents jitter when the stick
/// rests near the activation boundary. Crossing zero releases the
/// previously-held opposite key first.
///
/// The `<=` comparison in dead-zone / exit checks is intentional: with
/// every threshold at 0, a release event (`abs == 0`) must still lift
/// the key, otherwise a "stuck-A" regression appears. There's a parity
/// test for this on the Windows side (see
/// `JoystickToWasdMapperTests.AllThresholdsZero_ReleaseAtZero_StillReleases`).
final class JoystickToWasdMapper {

    private let injector: InputInjector
    private let config: ServerConfig
    private let lock = NSLock()

    private var wDown = false
    private var aDown = false
    private var sDown = false
    private var dDown = false

    init(injector: InputInjector, config: ServerConfig) {
        self.injector = injector
        self.config = config
    }

    func update(x: Float, y: Float) {
        lock.lock(); defer { lock.unlock() }
        updateAxis(value: y, posKey: forwardKey(), negKey: backKey(),
                   posDown: &wDown, negDown: &sDown)
        updateAxis(value: x, posKey: rightKey(), negKey: leftKey(),
                   posDown: &dDown, negDown: &aDown)
    }

    func releaseAll() {
        lock.lock(); defer { lock.unlock() }
        if wDown { injector.key(forwardKey(), down: false); wDown = false }
        if aDown { injector.key(leftKey(),    down: false); aDown = false }
        if sDown { injector.key(backKey(),    down: false); sDown = false }
        if dDown { injector.key(rightKey(),   down: false); dDown = false }
    }

    // Resolved on every call instead of cached: the Key Bindings page
    // edits `config.movementKeys` in place and the next joystick sample
    // should already honour the new mapping, no profile reload needed.
    // `KeyCodes.resolve` accepts symbolic names ("w", "jump"), Windows
    // hex scancodes ("0x11"), and decimal scancodes. If somehow blank or
    // invalid we fall back to the matching WASD direction.
    private func forwardKey() -> UInt16 {
        KeyCodes.resolve(config.movementKeys.forward) ?? KeyCodes.w
    }
    private func backKey() -> UInt16 {
        KeyCodes.resolve(config.movementKeys.back) ?? KeyCodes.s
    }
    private func leftKey() -> UInt16 {
        KeyCodes.resolve(config.movementKeys.left) ?? KeyCodes.a
    }
    private func rightKey() -> UInt16 {
        KeyCodes.resolve(config.movementKeys.right) ?? KeyCodes.d
    }

    private func updateAxis(value v: Float, posKey: UInt16, negKey: UInt16,
                            posDown: inout Bool, negDown: inout Bool) {
        let cfg = config.movement
        let abs = Swift.abs(v)

        if abs <= cfg.deadZone {
            if posDown { injector.key(posKey, down: false); posDown = false }
            if negDown { injector.key(negKey, down: false); negDown = false }
            return
        }

        if v > 0 {
            if negDown { injector.key(negKey, down: false); negDown = false }
            if !posDown && abs > cfg.enterThreshold {
                injector.key(posKey, down: true); posDown = true
            } else if posDown && abs <= cfg.exitThreshold {
                injector.key(posKey, down: false); posDown = false
            }
        } else {
            if posDown { injector.key(posKey, down: false); posDown = false }
            if !negDown && abs > cfg.enterThreshold {
                injector.key(negKey, down: true); negDown = true
            } else if negDown && abs <= cfg.exitThreshold {
                injector.key(negKey, down: false); negDown = false
            }
        }
    }
}
