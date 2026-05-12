import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var host: ServerHost
    @EnvironmentObject private var appearance: AppearancePreferences

    @State private var selection: SidebarPage? = .discovery

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
        } detail: {
            detail
                .navigationSplitViewColumnWidth(min: 600, ideal: 880)
        }
        .navigationSplitViewStyle(.balanced)
        // Remove the sidebar toggle button entirely. macOS's
        // `NavigationSplitView` ships a built-in collapse/expand
        // animation: when the user clicks the toggle, the sidebar
        // contents fade-and-scale into a chevron in the toolbar, and
        // back out on expand. The chevron's transition is
        // *transient and uncancellable*, and its disappearance at
        // the end of the animation forcibly invalidates the sidebar
        // column's width animation — that's the visible "jank"
        // (user observation: "在它消失的时候动画会抽搐一下").
        //
        // The chevron animation is a built-in SwiftUI behaviour
        // we cannot turn off. The only way to escape the jank is
        // to remove the trigger: take the toggle button out of the
        // toolbar entirely, so the user can't collapse the
        // sidebar in the first place. macOS's own System Settings
        // takes the same approach — its sidebar is permanently
        // visible, with no toggle. Since this app is essentially
        // a System-Settings-style configuration panel, the
        // trade-off is appropriate.
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 880, minHeight: 600)
    }

    /// Each detail leaf sets its own `.navigationTitle` /
    /// `.navigationSubtitle`, which SwiftUI propagates to the window
    /// title bar — that's how the per-tab title switches without
    /// any explicit window-title binding here.
    @ViewBuilder private var detail: some View {
        switch selection ?? .discovery {
        case .discovery: DeviceDiscoveryView()
        case .settings:  ControllerSettingsView()
        case .bindings:  KeyBindingsView()
        case .global:    GlobalSettingsView()
        case .about:     AboutView()
        }
    }
}
