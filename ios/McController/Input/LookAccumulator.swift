import Foundation
import os.lock

/// Buffers look-pad camera deltas and flushes them at a fixed cadence.
///
/// The touch thread atomically adds to an accumulator; a CADisplayLink-free
/// dispatch timer at ~125 Hz (8 ms) reads-and-resets the counters and emits a
/// single `LOOK_DELTA` packet per tick. Zero deltas are skipped so the PC
/// doesn't get idle traffic when the finger is still.
///
/// Critical perf note: touch handlers MUST be non-blocking. This class is the
/// "fan-in → throttle → fan-out" buffer between the 120 Hz touch source and
/// the 125 Hz network sender.
final class LookAccumulator: @unchecked Sendable {

    private var dxAcc: Int32 = 0
    private var dyAcc: Int32 = 0
    private var lock = os_unfair_lock()

    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "mcc.look.flush", qos: .userInteractive)
    private let flushIntervalMs: Int
    private let send: @Sendable (Int16, Int16) -> Void

    init(intervalMs: Int = 8, send: @escaping @Sendable (Int16, Int16) -> Void) {
        self.flushIntervalMs = intervalMs
        self.send = send
    }

    func start() {
        stop()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .milliseconds(flushIntervalMs),
                   repeating: .milliseconds(flushIntervalMs))
        t.setEventHandler { [weak self] in
            self?.flush()
        }
        t.resume()
        self.timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
        os_unfair_lock_lock(&lock)
        dxAcc = 0
        dyAcc = 0
        os_unfair_lock_unlock(&lock)
    }

    func add(dx: Int, dy: Int) {
        guard dx != 0 || dy != 0 else { return }
        os_unfair_lock_lock(&lock)
        dxAcc = dxAcc.addingReportingOverflow(Int32(clamping: dx)).partialValue
        dyAcc = dyAcc.addingReportingOverflow(Int32(clamping: dy)).partialValue
        os_unfair_lock_unlock(&lock)
    }

    private func flush() {
        os_unfair_lock_lock(&lock)
        let dx = dxAcc
        let dy = dyAcc
        dxAcc = 0
        dyAcc = 0
        os_unfair_lock_unlock(&lock)
        if dx == 0 && dy == 0 { return }
        let sdx = Int16(clamping: Int(dx))
        let sdy = Int16(clamping: Int(dy))
        send(sdx, sdy)
    }
}
