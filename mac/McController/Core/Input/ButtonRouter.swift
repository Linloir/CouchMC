import Foundation

/// Routes a wire-protocol ButtonId + down state to the correct OS input
/// action using bindings loaded from config. Bindings are resolved once
/// at construction. Mirrors `ButtonRouter.cs`.
///
/// Tracks currently-held buttons so `releaseAll()` on disconnect (or on
/// mode flip to `antiMistouch`) returns a clean keyboard/mouse state —
/// no stuck keys.
final class ButtonRouter {

    private enum Kind {
        case key(UInt16)
        case mouse(MouseButton)
    }

    private let injector: InputInjector
    /// Mutable so the Settings → Key Bindings page can rewire keys
    /// without restarting the server. Reads + writes go through `lock`.
    private var resolved: [UInt8: Kind]
    private var down: Set<UInt8> = []
    private let lock = NSLock()

    init(injector: InputInjector, config: ServerConfig) {
        self.injector = injector
        self.resolved = Self.resolveBindings(config.bindings)
    }

    func handle(buttonId: UInt8, down isDown: Bool) {
        lock.lock(); defer { lock.unlock() }
        guard let kind = resolved[buttonId] else { return }
        if isDown { down.insert(buttonId) } else { down.remove(buttonId) }
        switch kind {
        case .key(let kc):
            injector.key(kc, down: isDown)
        case .mouse(let mb):
            injector.setMouseButton(mb, down: isDown)
        }
    }

    func releaseAll() {
        lock.lock(); defer { lock.unlock() }
        for id in down {
            guard let kind = resolved[id] else { continue }
            switch kind {
            case .key(let kc):
                injector.key(kc, down: false)
            case .mouse(let mb):
                injector.setMouseButton(mb, down: false)
            }
        }
        down.removeAll()
    }

    /// Re-resolve from a fresh `[String: ButtonBinding]` map. Any keys
    /// currently held under the OLD bindings are released first — without
    /// that, the OS would have a stuck `W` (or whatever) after a rebind
    /// because we'd lose track of the down-key from the previous table.
    func applyBindings(_ raw: [String: ButtonBinding]) {
        lock.lock(); defer { lock.unlock() }
        // Release everything currently down using the OLD table.
        for id in down {
            guard let kind = resolved[id] else { continue }
            switch kind {
            case .key(let kc):    injector.key(kc, down: false)
            case .mouse(let mb):  injector.setMouseButton(mb, down: false)
            }
        }
        down.removeAll()
        resolved = Self.resolveBindings(raw)
    }

    private static func resolveBindings(_ raw: [String: ButtonBinding]) -> [UInt8: Kind] {
        var result: [UInt8: Kind] = [:]
        for (key, b) in raw {
            guard let id = parseHexByte(key) else { continue }
            switch b.type.lowercased() {
            case "key":
                if let scStr = b.scancode, let kc = KeyCodes.resolve(scStr) {
                    result[id] = .key(kc)
                }
            case "mouse":
                switch (b.button ?? "").lowercased() {
                case "left":   result[id] = .mouse(.left)
                case "right":  result[id] = .mouse(.right)
                case "middle": result[id] = .mouse(.middle)
                default: break
                }
            default: break
            }
        }
        return result
    }

    private static func parseHexByte(_ s: String) -> UInt8? {
        var raw = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.lowercased().hasPrefix("0x") { raw.removeFirst(2) }
        return UInt8(raw, radix: 16)
    }
}
