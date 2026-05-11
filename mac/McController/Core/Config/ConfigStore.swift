import Foundation

/// JSON-backed config persistence with one-shot migration for the
/// pre-profile flat layout (camera/movement at the root). Mirrors
/// `ConfigStore.cs` on the PC side but writes to
/// `~/Library/Application Support/McController/config.json` per
/// Apple's storage guidelines.
enum ConfigStore {

    /// Canonical location: `~/Library/Application Support/McController/config.json`.
    /// Created on demand. Falling back to NSHomeDirectory means the
    /// caller never crashes if `FileManager.default` returns nil for
    /// the app-support search.
    static func defaultConfigURL() -> URL {
        applicationSupportDirectory().appendingPathComponent("config.json", isDirectory: false)
    }

    static func applicationSupportDirectory() -> URL {
        let fm = FileManager.default
        let base = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("McController", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func loadOrDefault(at url: URL) -> ServerConfig {
        do {
            guard FileManager.default.fileExists(atPath: url.path) else {
                return ServerConfig()
            }
            let data = try Data(contentsOf: url)
            let migrated = migrateIfNeeded(data)
            let decoder = JSONDecoder()
            return try decoder.decode(ServerConfig.self, from: migrated)
        } catch {
            NSLog("[ConfigStore] load failed: %@. Using defaults.", String(describing: error))
            return ServerConfig()
        }
    }

    static func save(_ config: ServerConfig, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(config)
        let dir = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Pre-profile configs had `camera`/`movement` at the top level and
    /// no `profiles` array. Wrap them into a single default profile so
    /// the rest of deserialization sees the new shape. New-shape
    /// configs pass through unchanged.
    private static func migrateIfNeeded(_ data: Data) -> Data {
        guard
            let any = try? JSONSerialization.jsonObject(with: data, options: []),
            var obj = any as? [String: Any]
        else { return data }

        if obj["profiles"] != nil { return data }
        let camera = obj["camera"]
        let movement = obj["movement"]
        if camera == nil && movement == nil { return data }

        let profile: [String: Any] = [
            "id": "default",
            "name": "默认",
            "camera": camera ?? [:],
            "movement": movement ?? [:],
        ]
        // Some legacy configs spelled cameraConfig / movementConfig under
        // CamelCase variations; pass them through whatever shape they're in.
        obj["profiles"] = [profile]
        obj["activeProfileId"] = "default"
        obj.removeValue(forKey: "camera")
        obj.removeValue(forKey: "movement")
        return (try? JSONSerialization.data(withJSONObject: obj, options: [])) ?? data
    }
}
