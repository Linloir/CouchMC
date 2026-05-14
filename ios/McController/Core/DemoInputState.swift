import Foundation
import os.lock

/// Thread-safe snapshot of the inputs the user has produced while in
/// demo mode. The send hot paths on `ControllerSession` (`sendButton`,
/// `sendJoystick`, `sendLookDelta`, etc.) are nonisolated and run on a
/// mix of main + user-interactive queues; collecting demo state on a
/// MainActor-bound `@Published` would force a Task hop on every call,
/// defeating the perf optimisation we shipped in 1.0.1.
///
/// Instead we mutate this lock-protected snapshot inline (~100 ns) and
/// let the demo HUD poll a 30 Hz timer to read it. That's plenty of
/// fidelity to convince an App reviewer the inputs are flowing.
final class DemoInputState: @unchecked Sendable {

    private var lock = os_unfair_lock()

    private var _activeButtons: Set<UInt8> = []
    private var _lastDelta: (Int16, Int16) = (0, 0)
    private var _accumulatedDelta: (Int64, Int64) = (0, 0)
    private var _joystick: (Float, Float) = (0, 0)
    private var _lastHotbarSlot: Int = -1
    private var _lastButtonEvent: (id: UInt8, down: Bool)? = nil

    // MARK: - Mutation (called from any thread)

    func setButton(id: UInt8, down: Bool) {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        if down { _activeButtons.insert(id) }
        else { _activeButtons.remove(id) }
        _lastButtonEvent = (id, down)
    }

    func setJoystick(x: Float, y: Float) {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        _joystick = (x, y)
    }

    func addDelta(dx: Int16, dy: Int16) {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        _lastDelta = (dx, dy)
        _accumulatedDelta = (
            _accumulatedDelta.0 &+ Int64(dx),
            _accumulatedDelta.1 &+ Int64(dy)
        )
    }

    func setHotbarSlot(_ slot: Int) {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        _lastHotbarSlot = slot
    }

    func reset() {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        _activeButtons.removeAll()
        _lastDelta = (0, 0)
        _accumulatedDelta = (0, 0)
        _joystick = (0, 0)
        _lastHotbarSlot = -1
        _lastButtonEvent = nil
    }

    // MARK: - Read (called from main; HUD poll)

    /// One immutable snapshot of all demo state. Cheap (one lock acquire,
    /// one struct copy) — call freely from a 30 Hz timer.
    func snapshot() -> Snapshot {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        return Snapshot(
            activeButtonIDs: _activeButtons,
            lastDelta: _lastDelta,
            accumulatedDelta: _accumulatedDelta,
            joystick: _joystick,
            lastHotbarSlot: _lastHotbarSlot,
            lastButtonEvent: _lastButtonEvent
        )
    }

    struct Snapshot: Equatable {
        let activeButtonIDs: Set<UInt8>
        let lastDelta: (Int16, Int16)
        let accumulatedDelta: (Int64, Int64)
        let joystick: (Float, Float)
        let lastHotbarSlot: Int
        let lastButtonEvent: (id: UInt8, down: Bool)?

        static func == (lhs: Snapshot, rhs: Snapshot) -> Bool {
            lhs.activeButtonIDs == rhs.activeButtonIDs
                && lhs.lastDelta == rhs.lastDelta
                && lhs.accumulatedDelta == rhs.accumulatedDelta
                && lhs.joystick == rhs.joystick
                && lhs.lastHotbarSlot == rhs.lastHotbarSlot
                && lhs.lastButtonEvent?.id == rhs.lastButtonEvent?.id
                && lhs.lastButtonEvent?.down == rhs.lastButtonEvent?.down
        }
    }
}

/// Tiny lock-protected `Bool` for cross-thread reads of "are we in demo
/// mode?" without bouncing to MainActor. Could use `Atomic<Bool>` from
/// the Synchronization module, but `os_unfair_lock` is fine and matches
/// the rest of the codebase's pattern.
final class LockedBool: @unchecked Sendable {
    private var lock = os_unfair_lock()
    private var value: Bool

    init(_ initial: Bool) {
        self.value = initial
    }

    func get() -> Bool {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        return value
    }

    func set(_ v: Bool) {
        os_unfair_lock_lock(&lock); defer { os_unfair_lock_unlock(&lock) }
        value = v
    }
}
