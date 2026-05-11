import SwiftUI
import UIKit

/// SwiftUI entry point for the layout editor. Wraps a UIKit
/// `LayoutEditorViewController` that locks landscape and renders the real
/// widget visuals in edit mode.
///
/// The `onClose` closure is supplied by the parent (RootView) so it can
/// drive the cross-fading ZStack overlay transition (and trigger
/// `OrientationHelper.restorePortrait()`).
struct LayoutEditorScreen: UIViewControllerRepresentable {
    let mode: ControllerMode
    let onClose: () -> Void

    @EnvironmentObject var profileStore: ProfileStoreObservable
    @EnvironmentObject var settings: SettingsStore

    func makeUIViewController(context: Context) -> LayoutEditorViewController {
        LayoutEditorViewController(
            mode: mode,
            profileStore: profileStore,
            settings: settings,
            onClose: onClose
        )
    }

    func updateUIViewController(_ vc: LayoutEditorViewController, context: Context) {}
}
