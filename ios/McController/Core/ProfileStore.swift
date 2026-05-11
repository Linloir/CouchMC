import Foundation
import Combine

/// Persistent storage for layout profiles.
///
/// On-disk schema is `Application Support/McController/profiles.v1.json` —
/// a single JSON blob. Reads and writes are atomic.
final class ProfileStore {

    struct Snapshot: Codable, Equatable {
        var active: String
        var profiles: [String: LayoutProfile]
    }

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
            self.url = dir.appendingPathComponent("profiles.v1.json")
        }
    }

    func load() -> Snapshot {
        guard let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return seed()
        }
        return snap
    }

    func save(_ snapshot: Snapshot) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(snapshot) {
            try? data.write(to: url, options: [.atomic])
        }
    }

    private func seed() -> Snapshot {
        let profile = DefaultLayouts.defaultProfile
        let snap = Snapshot(active: profile.name, profiles: [profile.name: profile])
        save(snap)
        return snap
    }
}

/// SwiftUI-friendly wrapper. Mirrors Android's profile-management surface:
///   - active profile selection
///   - CRUD (add / rename / delete / reset)
///   - per-mode layout updates (editor save)
@MainActor
final class ProfileStoreObservable: ObservableObject {
    @Published var snapshot: ProfileStore.Snapshot

    private let store: ProfileStore

    init(store: ProfileStore = ProfileStore()) {
        self.store = store
        self.snapshot = store.load()
    }

    // MARK: - Active profile

    var activeProfile: LayoutProfile {
        snapshot.profiles[snapshot.active] ?? DefaultLayouts.defaultProfile
    }

    var allNames: [String] {
        snapshot.profiles.keys.sorted()
    }

    func setActive(_ name: String) {
        guard snapshot.profiles[name] != nil else { return }
        snapshot.active = name
        store.save(snapshot)
    }

    // MARK: - CRUD

    /// Add a new profile, seeded from the active profile's current layouts.
    /// Returns false if the name is empty, already taken, or invalid.
    @discardableResult
    func addProfile(named name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, snapshot.profiles[trimmed] == nil else { return false }
        let seed = activeProfile
        let newProfile = LayoutProfile(
            name: trimmed,
            inGame: seed.inGame,
            uiMode: seed.uiMode,
            hotbarSwipeMode: seed.hotbarSwipeMode
        )
        snapshot.profiles[trimmed] = newProfile
        snapshot.active = trimmed
        store.save(snapshot)
        return true
    }

    @discardableResult
    func renameProfile(_ old: String, to new: String) -> Bool {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed != old,
              snapshot.profiles[old] != nil,
              snapshot.profiles[trimmed] == nil
        else { return false }
        var profile = snapshot.profiles[old]!
        profile.name = trimmed
        snapshot.profiles.removeValue(forKey: old)
        snapshot.profiles[trimmed] = profile
        if snapshot.active == old { snapshot.active = trimmed }
        store.save(snapshot)
        return true
    }

    @discardableResult
    func deleteProfile(_ name: String) -> Bool {
        // Refuse to delete the last profile — there must always be one.
        guard snapshot.profiles.count > 1 else { return false }
        guard snapshot.profiles.removeValue(forKey: name) != nil else { return false }
        if snapshot.active == name {
            snapshot.active = snapshot.profiles.keys.sorted().first ?? DefaultLayouts.defaultProfile.name
        }
        store.save(snapshot)
        return true
    }

    // MARK: - Updates from editor

    /// Apply a mutation to the currently-active profile and persist.
    func updateActive(_ mutate: (inout LayoutProfile) -> Void) {
        var p = activeProfile
        mutate(&p)
        snapshot.profiles[p.name] = p
        store.save(snapshot)
    }

    /// Reset only the in-game layout of the active profile.
    func resetActiveInGame() {
        updateActive { $0.inGame = DefaultLayouts.inGame }
    }

    /// Reset only the UI-mode layout of the active profile.
    func resetActiveUI() {
        updateActive { $0.uiMode = DefaultLayouts.uiMode }
    }
}
