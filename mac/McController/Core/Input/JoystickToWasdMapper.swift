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
        updateAxis(value: y, posKey: KeyCodes.w, negKey: KeyCodes.s,
                   posDown: &wDown, negDown: &sDown)
        updateAxis(value: x, posKey: KeyCodes.d, negKey: KeyCodes.a,
                   posDown: &dDown, negDown: &aDown)
    }

    func releaseAll() {
        lock.lock(); defer { lock.unlock() }
        if wDown { injector.key(KeyCodes.w, down: false); wDown = false }
        if aDown { injector.key(KeyCodes.a, down: false); aDown = false }
        if sDown { injector.key(KeyCodes.s, down: false); sDown = false }
        if dDown { injector.key(KeyCodes.d, down: false); dDown = false }
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
