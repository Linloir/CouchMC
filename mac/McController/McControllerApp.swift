import SwiftUI
import AppKit

@main
struct McControllerApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // Hold the shared host + appearance via the singleton so child
    // views that need a pre-init reference can still reach them.
    @StateObject private var host = AppEnvironment.shared.host
    @StateObject private var appearance = AppEnvironment.shared.appearance

    var body: some Scene {
        // The menu bar item + window close-to-hide behavior live in
        // `AppDelegate` — we want left-click=toggle / right-click=menu
        // semantics, which SwiftUI's `MenuBarExtra` doesn't support.
        WindowGroup(id: "main") {
            ContentView()
                .environmentObject(host)
                .environmentObject(appearance)
                .task {
                    // Bind sockets + start the window-state monitor +
                    // discovery advertiser. Accessibility permission
                    // is prompted on-demand from the Discovery view
                    // (auto-prompting on every launch re-fires the
                    // dialog after every rebuild because TCC keys on
                    // the binary's cdhash).
                    host.start()
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // Trim defaults that don't fit this app's document-less
            // shape — no "New" / no auto-About menu (the in-app About
            // page covers it).
            CommandGroup(replacing: .newItem) { }
            CommandGroup(replacing: .appInfo) { }
        }
    }
}
