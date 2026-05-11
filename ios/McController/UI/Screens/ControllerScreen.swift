import SwiftUI
import UIKit

/// SwiftUI wrapper around the UIKit `ControllerHostingController`. The host VC
/// owns all the touch UIViews so we get max-perf multi-touch with full
/// pointer-id control (SwiftUI's gesture system can't deliver this).
struct ControllerScreen: UIViewControllerRepresentable {

    let host: SavedHost
    @Binding var dismiss: Bool

    @EnvironmentObject var session: ControllerSession
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var profileStore: ProfileStoreObservable
    @EnvironmentObject var hostStore: HostStore

    func makeUIViewController(context: Context) -> ControllerHostingController {
        ControllerHostingController(
            session: session,
            settings: settings,
            profileStore: profileStore,
            hostStore: hostStore,
            host: host,
            onDismiss: { dismiss = true }
        )
    }

    func updateUIViewController(_ vc: ControllerHostingController, context: Context) {
        vc.rebuildIfSettingsChanged()
    }
}
