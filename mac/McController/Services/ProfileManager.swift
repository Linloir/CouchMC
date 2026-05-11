import Foundation
import Combine

/// View-side wrapper around the profile list inside `ServerConfig`.
/// Owns the `@Published` array the picker binds to and keeps it in
/// sync with the source-of-truth list on the config object. Mirrors
/// `ProfileManager.cs`.
@MainActor
final class ProfileManager: ObservableObject {

    @Published private(set) var profiles: [ControllerProfile] = []
    @Published private(set) var activeProfileId: String

    private let host: ServerHost
    private var config: ServerConfig { host.config }

    init(host: ServerHost) {
        self.host = host
        self.profiles = host.config.profiles
        self.activeProfileId = host.config.activeProfileId
    }

    var activeProfile: ControllerProfile { config.activeProfile }

    func setActive(_ p: ControllerProfile) {
        guard profiles.contains(where: { $0.id == p.id }) else { return }
        guard config.activeProfileId != p.id else { return }
        config.activeProfileId = p.id
        activeProfileId = p.id
        host.onActiveProfileChanged()
        host.saveNow()
    }

    func addNew(name: String) -> ControllerProfile {
        let p = ControllerProfile(
            id: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? L.get("settings.profile.newName.fallback", fallback: "New profile")
                : name)
        config.profiles.append(p)
        profiles = config.profiles
        host.saveNow()
        return p
    }

    func duplicate(_ source: ControllerProfile) -> ControllerProfile {
        let copy = source.duplicate(
            newId: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            nameSuffix: " 副本")
        config.profiles.append(copy)
        profiles = config.profiles
        host.saveNow()
        return copy
    }

    @discardableResult
    func delete(_ p: ControllerProfile) -> Bool {
        guard config.profiles.count > 1 else { return false }
        let wasActive = config.activeProfileId == p.id
        config.profiles.removeAll { $0.id == p.id }
        if wasActive, let next = config.profiles.first {
            config.activeProfileId = next.id
            activeProfileId = next.id
            host.onActiveProfileChanged()
        }
        profiles = config.profiles
        host.saveNow()
        return true
    }

    /// Notify the picker that a name edit on an existing profile
    /// happened. The array's contents are identity-stable but the
    /// `@Published` projection needs the assignment to re-emit.
    func refresh() {
        profiles = config.profiles
    }
}
