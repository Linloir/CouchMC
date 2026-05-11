import Foundation

/// Polls the bundled `adb` for connected USB devices and auto-runs
/// `adb reverse tcp:<port> tcp:<port>` per device so phones can reach
/// this Mac at `127.0.0.1` with no manual setup. Mirrors
/// `AdbDiscovery.cs` semantics.
///
/// The adb binary is bundled inside the .app at
/// `Contents/Resources/adb/adb`. If it's not present (e.g., debug
/// build from sources before running `scripts/fetch-adb.sh`), this
/// service surfaces an empty device list and `adbAvailable = false`
/// so the UI can prompt the user.
@MainActor
final class AdbDiscovery: ObservableObject {

    struct Device: Identifiable, Hashable {
        var id: String { serial }
        let serial: String
        let model: String
        let state: String
        let hasControllerApp: Bool

        var subtitle: String { "\(serial) · \(state)" }
    }

    @Published private(set) var devices: [Device] = []
    @Published private(set) var adbAvailable: Bool = true

    let reversePort: Int
    var pollIntervalSeconds: TimeInterval = 3.0

    private var modelCache: [String: String] = [:]
    private var appCache: [String: Bool] = [:]
    private var forwarded: Set<String> = []

    private var task: Task<Void, Never>?

    init(reversePort: Int) {
        self.reversePort = reversePort
    }

    func start() {
        guard task == nil else { return }
        adbAvailable = AdbDiscovery.adbExecutableURL() != nil
        task = Task.detached { [weak self] in
            await self?.loop()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    // MARK: - Polling loop

    private func loop() async {
        while !Task.isCancelled {
            let result: [Device] = await Task.detached(priority: .utility) { [weak self] in
                guard let self else { return [] }
                return await self.probe()
            }.value
            await MainActor.run {
                if result != self.devices { self.devices = result }
            }
            try? await Task.sleep(nanoseconds: UInt64(pollIntervalSeconds * 1_000_000_000))
        }
    }

    private func probe() async -> [Device] {
        guard let adb = AdbDiscovery.adbExecutableURL() else {
            await MainActor.run { self.adbAvailable = false }
            return []
        }
        await MainActor.run { self.adbAvailable = true }

        let raw = (try? Self.runAdb(executable: adb, args: ["devices"])) ?? ""
        var out: [Device] = []
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("List of devices") { continue }
            if trimmed.hasPrefix("*") { continue }
            let parts = trimmed.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            let serial = String(parts[0])
            let state = String(parts[1]).trimmingCharacters(in: .whitespaces)
            let model = await self.modelFor(serial: serial, adb: adb)
            let hasApp = await self.hasControllerAppFor(serial: serial, adb: adb)
            out.append(Device(serial: serial, model: model, state: state,
                              hasControllerApp: hasApp))
        }

        // Auto-forward the server port on any newly-ready USB device.
        let snapshot = await MainActor.run { self.forwarded }
        var nextForwarded = snapshot
        for d in out where d.state == "device" && !nextForwarded.contains(d.serial) {
            do {
                _ = try Self.runAdb(executable: adb,
                                    args: ["-s", d.serial, "reverse",
                                           "tcp:\(reversePort)", "tcp:\(reversePort)"])
                nextForwarded.insert(d.serial)
            } catch {
                NSLog("[Adb] auto-forward for %@ failed: %@",
                      d.serial, String(describing: error))
            }
        }
        // Drop serials that vanished so we'll re-forward on reconnect.
        let seenSerials = Set(out.map(\.serial))
        nextForwarded = nextForwarded.intersection(seenSerials)
        await MainActor.run { self.forwarded = nextForwarded }

        return out
    }

    private func modelFor(serial: String, adb: URL) async -> String {
        if let cached = modelCache[serial] { return cached }
        let raw = (try? Self.runAdb(executable: adb,
                                    args: ["-s", serial, "shell",
                                           "getprop", "ro.product.model"])) ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = trimmed.isEmpty ? serial : trimmed
        await MainActor.run { self.modelCache[serial] = model }
        return model
    }

    private func hasControllerAppFor(serial: String, adb: URL) async -> Bool {
        if let cached = appCache[serial] { return cached }
        let raw = (try? Self.runAdb(executable: adb,
                                    args: ["-s", serial, "shell",
                                           "pm", "list", "packages", "com.mccontroller"])) ?? ""
        let has = raw.contains("package:com.mccontroller")
        await MainActor.run { self.appCache[serial] = has }
        return has
    }

    // MARK: - Binary resolution + process invocation

    /// Returns the bundled adb if present. Search order:
    ///   1. `<bundle>/Contents/Resources/adb/adb`
    ///   2. `<bundle>/Contents/Resources/adb`
    ///   3. `$PATH` resolution as a last resort (so a dev-built binary
    ///      finds the system adb without needing to bundle one).
    static func adbExecutableURL() -> URL? {
        let bundle = Bundle.main
        if let resourceURL = bundle.resourceURL {
            let nested = resourceURL.appendingPathComponent("adb/adb")
            if FileManager.default.isExecutableFile(atPath: nested.path) { return nested }
            let flat = resourceURL.appendingPathComponent("adb")
            if FileManager.default.isExecutableFile(atPath: flat.path) { return flat }
        }
        // Dev fallback: look on PATH.
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"
        for dir in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(dir)).appendingPathComponent("adb")
            if FileManager.default.isExecutableFile(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    private static func runAdb(executable: URL, args: [String]) throws -> String {
        let proc = Process()
        proc.executableURL = executable
        proc.arguments = args
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        // Run adb without a server-restart prompt — the user's
        // HOME/.android/adbkey gets created automatically on first run.
        try proc.run()
        proc.waitUntilExit()
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
