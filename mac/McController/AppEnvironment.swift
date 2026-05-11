import Foundation

/// Process-wide hand-off between the SwiftUI `@StateObject` (which can't
/// be read from inside another view's `init()`) and child views that
/// want to wire a non-environment dependency at construction time —
/// notably `ProfileManager(host:)` inside `ControllerSettingsView`.
///
/// `ServerHost` is expensive to construct (loads config, binds sockets
/// once started) so we keep exactly one instance. The `@StateObject`
/// wrapper in `McControllerApp` reads from this singleton's stored
/// value; subsequent `AppEnvironment.shared.host` accesses return the
/// same instance.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let host: ServerHost
    let appearance: AppearancePreferences

    private init() {
        self.host = ServerHost()
        self.appearance = AppearancePreferences.shared
    }
}
