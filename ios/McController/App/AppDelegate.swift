import UIKit

/// Global orientation gate. SwiftUI doesn't let individual view controllers
/// influence which orientations the app supports — that comes from
/// `UIApplicationDelegate.application(_:supportedInterfaceOrientationsFor:)`
/// at the app level. We funnel that through a mutable static and treat it
/// as the single source of truth (no per-VC `supportedInterfaceOrientations`
/// override).
///
/// `OrientationHelper.enterLandscape()` / `.restorePortrait()` flip the gate
/// and kick off `requestGeometryUpdate`. They also call
/// `setNeedsUpdateOfSupportedInterfaceOrientations()` on the scene's root VC
/// so UIKit re-queries the now-changed supported orientations before
/// honouring the geometry request — without this, a stale cached value can
/// cause iOS to silently drop the rotation, which is exactly what we hit on
/// repeat enter/exit cycles.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Marked `@MainActor` because UIKit only ever calls
    /// `application(_:supportedInterfaceOrientationsFor:)` on the main
    /// thread, and OrientationHelper (also `@MainActor`) is the only
    /// other writer. Using a plain `static var` would require either
    /// `nonisolated(unsafe)` or an actor hop on every read; pinning
    /// to MainActor avoids both and matches reality.
    @MainActor
    static var allowedOrientations: UIInterfaceOrientationMask = .portrait

    @MainActor
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.allowedOrientations
    }
}

@MainActor
enum OrientationHelper {

    /// Cross-fade timings used by the landscape overlays. Centralised so
    /// SettingsView / HomeView / RootView all open + close their overlays
    /// with identical, explicit `withAnimation` timing — avoiding the
    /// inconsistency we saw when relying on implicit `.animation(_:value:)`
    /// on the parent view. Marked nonisolated because they're plain
    /// `Double`s — accessible from anywhere without an actor hop, even
    /// though the enum itself is @MainActor for the geometry-update calls.
    nonisolated static let enterFadeDuration: Double = 0.40
    nonisolated static let exitFadeDuration: Double = 0.22

    static func currentScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })
            ?? UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first
    }

    /// Lock to landscape and immediately kick off the system's rotation
    /// animation. Caller should set the SwiftUI binding (that drives the
    /// landscape overlay) in the same tick so the modal cross-fade and the
    /// rotation run concurrently.
    static func enterLandscape() {
        AppDelegate.allowedOrientations = .landscape
        applyRotation(.landscape)
    }

    /// Restore portrait. Caller should clear the SwiftUI binding in the same
    /// tick so the overlay cross-fades out while the rotation runs back.
    static func restorePortrait() {
        AppDelegate.allowedOrientations = .portrait
        applyRotation(.portrait)
    }

    // MARK: - Internal

    private static func applyRotation(_ mask: UIInterfaceOrientationMask) {
        guard let scene = currentScene() else { return }

        // Invalidate UIKit's cached `supportedInterfaceOrientations` for the
        // scene's VC chain. Without this iOS keeps using whatever it had
        // resolved last time and silently drops `requestGeometryUpdate` calls
        // that conflict with the cache.
        let rootVC = scene.keyWindow?.rootViewController
                  ?? scene.windows.first?.rootViewController
        rootVC?.setNeedsUpdateOfSupportedInterfaceOrientations()

        if #available(iOS 16.0, *) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
        }
    }
}
