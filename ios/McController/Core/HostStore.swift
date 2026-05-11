import Foundation
import Combine

/// One saved host — what the user sees in the home list.
struct SavedHost: Identifiable, Hashable, Codable, Sendable {
    let id: String
    var name: String
    var ip: String
    var port: UInt16
    var lastConnectedAt: Date?
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

    func upsert(name: String, ip: String, port: UInt16) -> SavedHost {
        if let idx = hosts.firstIndex(where: { $0.ip == ip && $0.port == port }) {
            hosts[idx].name = name
            save()
            return hosts[idx]
        }
        let host = SavedHost(
            id: UUID().uuidString,
            name: name,
            ip: ip,
            port: port,
            lastConnectedAt: nil
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
