import SwiftUI

@main
struct McControllerApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var settings = SettingsStore()
    @StateObject private var hostStore = HostStore()
    @StateObject private var profileStore = ProfileStoreObservable()
    @StateObject private var session = ControllerSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(hostStore)
                .environmentObject(profileStore)
                .environmentObject(session)
                .preferredColorScheme(nil)
        }
    }
}
