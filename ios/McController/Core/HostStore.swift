import Foundation
import Combine

/// One saved host — what the user sees in the home list.
///
/// `isDemo == true` marks an entry that should bypass the real network
/// connect / probe and instead drop the user into the in-app simulator
/// (`ControllerSession.connectDemo`). Used by the App Store reviewer
/// path: typing `0.0.0.0` + port `65537` in the Add Host sheet creates
/// a demo entry. `isDemo` defaults to `false` so old `hosts.v1.json`
/// files without this field decode correctly (custom `init(from:)` below).
struct SavedHost: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var ip: String
    var port: UInt16
    var lastConnectedAt: Date?
    var isDemo: Bool

    init(id: String, name: String, ip: String, port: UInt16,
         lastConnectedAt: Date? = nil, isDemo: Bool = false) {
        self.id = id
        self.name = name
        self.ip = ip
        self.port = port
        self.lastConnectedAt = lastConnectedAt
        self.isDemo = isDemo
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, ip, port, lastConnectedAt, isDemo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        ip = try c.decode(String.self, forKey: .ip)
        port = try c.decode(UInt16.self, forKey: .port)
        lastConnectedAt = try c.decodeIfPresent(Date.self, forKey: .lastConnectedAt)
        isDemo = try c.decodeIfPresent(Bool.self, forKey: .isDemo) ?? false
    }
}

/// CRUD-style store for saved hosts. JSON-backed; observable.
@MainActor
final class HostStore: ObservableObject {

    @Published private(set) var hosts: [SavedHost] = []

    private let url: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.url = fileURL
        } else {
            let fm = FileManager.default
            let support = try? fm.url(for: .applicationSupportDirectory,
                                      in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = (support ?? URL(fileURLWithPath: NSTemporaryDirectory()))
                .appendingPathComponent("McController", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            self.url = dir.appendingPathComponent("hosts.v1.json")
        }
        load()
    }

    func upsert(name: String, ip: String, port: UInt16, isDemo: Bool = false) -> SavedHost {
        // Treat (ip, port, isDemo) as the dedup key: a real host on
        // `0.0.0.0:0` and the demo entry both use the same numeric
        // sentinel internally but should not collapse onto each other.
        if let idx = hosts.firstIndex(where: {
            $0.ip == ip && $0.port == port && $0.isDemo == isDemo
        }) {
            hosts[idx].name = name
            save()
            return hosts[idx]
        }
        let host = SavedHost(
            id: UUID().uuidString,
            name: name,
            ip: ip,
            port: port,
            lastConnectedAt: nil,
            isDemo: isDemo
        )
        hosts.append(host)
        save()
        return host
    }

    func markConnected(id: String) {
        guard let idx = hosts.firstIndex(where: { $0.id == id }) else { return }
        hosts[idx].lastConnectedAt = Date()
        save()
    }

    func rename(id: String, newName: String) {
        guard let idx = hosts.firstIndex(where: { $0.id == id }) else { return }
        hosts[idx].name = newName
        save()
    }

    func updatePort(id: String, newPort: UInt16) {
        guard let idx = hosts.firstIndex(where: { $0.id == id }) else { return }
        hosts[idx].port = newPort
        save()
    }

    func remove(id: String) {
        hosts.removeAll { $0.id == id }
        save()
    }

    // MARK: - persistence

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([SavedHost].self, from: data) else {
            return
        }
        self.hosts = decoded
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(hosts) {
            try? data.write(to: url, options: [.atomic])
        }
    }
}
