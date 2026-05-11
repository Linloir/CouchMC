import SwiftUI
import UIKit

/// Two-tab shell with fade-in landscape overlays for the layout editor and
/// the active controller session.
///
/// Why we drive opacity manually instead of using `.transition`:
///   - `.transition(.opacity)` symmetric — works for both directions but the
///     removal phase snapshots the overlay's old frame, which then visibly
///     drifts to a corner as UIKit rotates the scene back to portrait.
///   - `.transition(.asymmetric(.opacity, .identity))` — fixes the drift but
///     SwiftUI caches the view's "final" alpha at 1 when removal runs with
///     `.identity`, so every *subsequent* insertion skipped the fade-in.
///
/// Manual `@State` opacity sidesteps both:
///   - Open path: caller sets binding to the new value, schedules a
///     `withAnimation { opacity = 1 }` on the next runloop tick so the
///     overlay is mounted at `opacity = 0` first, then animates.
///   - Close path: caller sets binding to `nil` and opacity back to `0`
///     synchronously. The overlay is structurally removed in one frame
///     (no snapshot, no drift), and the rotation back to portrait animates
///     on its own behind the now-missing overlay.
struct RootView: View {

    @EnvironmentObject var settings: SettingsStore

    @State private var editorMode: ControllerMode?
    @State private var editorOpacity: Double = 0

    @State private var pendingConnection: ConnectionRequest?
    @State private var controllerOpacity: Double = 0
    @State private var dismissController: Bool = false

    var body: some View {
        ZStack {
            TabView {
                HomeView(
                    connectingTo: $pendingConnection,
                    controllerOpacity: $controllerOpacity
                )
                .tabItem { Label(L.key("tab.home"), systemImage: "house") }

                SettingsView(
                    editorMode: $editorMode,
                    editorOpacity: $editorOpacity
                )
                .tabItem { Label(L.key("tab.settings"), systemImage: "gear") }
            }

            if let mode = editorMode {
                LayoutEditorScreen(mode: mode, onClose: {
                    OrientationHelper.restorePortrait()
                    editorMode = nil
                    editorOpacity = 0
                })
                .opacity(editorOpacity)
                .ignoresSafeArea()
                .statusBarHidden()
                .persistentSystemOverlays(.hidden)
                .zIndex(1)
            }

            if let req = pendingConnection {
                ControllerScreen(host: req.host, dismiss: $dismissController)
                    .opacity(controllerOpacity)
                    .ignoresSafeArea()
                    .statusBarHidden()
                    .persistentSystemOverlays(.hidden)
                    .zIndex(2)
            }
        }
        .onChange(of: dismissController) { _, newValue in
            if newValue {
                dismissController = false
                OrientationHelper.restorePortrait()
                pendingConnection = nil
                controllerOpacity = 0
            }
        }
    }
}
