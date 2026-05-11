import Foundation

/// Lock-light counters shared between the network layer and the UI.
/// Counters are monotonic; the UI samples them periodically. Mirrors
/// `ConnectionStats.cs`.
///
/// `@MainActor` is intentionally not applied — counter updates fire from
/// the network read loops. Synchronization is via an internal queue +
/// `OSAllocatedUnfairLock` for the small mutable state.
final class ConnectionStats: @unchecked Sendable {

    private let lock = NSLock()

    private var _connected: Bool = false
    private var _clientEndpoint: String?
    private var _mode: String?
    private var _joystickCount: UInt64 = 0
    private var _lookCount: UInt64 = 0
    private var _buttonCount: UInt64 = 0
    private var _udpDropped: UInt64 = 0
    private var _rttSamples: [Int] = []
    private let rttWindow = 60

    var connected: Bool {
        get { lock.withLock { _connected } }
        set { lock.withLock { _connected = newValue } }
    }

    var clientEndpoint: String? {
        get { lock.withLock { _clientEndpoint } }
        set { lock.withLock { _clientEndpoint = newValue } }
    }

    /// Display label, e.g. "WiFi (TCP+UDP)" or "USB (TCP only)".
    var mode: String? {
        get { lock.withLock { _mode } }
        set { lock.withLock { _mode = newValue } }
    }

    var joystickCount: UInt64 { lock.withLock { _joystickCount } }
    var lookCount: UInt64 { lock.withLock { _lookCount } }
    var buttonCount: UInt64 { lock.withLock { _buttonCount } }
    var udpDropped: UInt64 { lock.withLock { _udpDropped } }

    func incrementJoystick() { lock.withLock { _joystickCount &+= 1 } }
    func incrementLook()     { lock.withLock { _lookCount &+= 1 } }
    func incrementButton()   { lock.withLock { _buttonCount &+= 1 } }
    func incrementUdpDropped() { lock.withLock { _udpDropped &+= 1 } }

    func recordRtt(ms: Int) {
        lock.withLock {
            _rttSamples.append(ms)
            if _rttSamples.count > rttWindow {
                _rttSamples.removeFirst(_rttSamples.count - rttWindow)
            }
        }
    }

    func rttPercentiles() -> (p50: Int, p99: Int) {
        let sorted: [Int] = lock.withLock {
            if _rttSamples.isEmpty { return [] }
            return _rttSamples.sorted()
        }
        if sorted.isEmpty { return (0, 0) }
        let p50 = sorted[sorted.count / 2]
        let p99Idx = min(Int(floor(Double(sorted.count) * 0.99)), sorted.count - 1)
        return (p50, sorted[p99Idx])
    }

    func onDisconnect() {
        lock.withLock {
            _connected = false
            _clientEndpoint = nil
            _mode = nil
            _joystickCount = 0
            _lookCount = 0
            _buttonCount = 0
            _udpDropped = 0
            _rttSamples.removeAll()
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock(); defer { unlock() }
        return body()
    }
}
