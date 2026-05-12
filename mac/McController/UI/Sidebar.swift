import SwiftUI

enum SidebarPage: String, Hashable, CaseIterable, Identifiable {
    case discovery
    case settings
    case bindings
    case global
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .discovery: return L.get("nav.discovery", fallback: "Devices")
        case .settings:  return L.get("nav.settings",  fallback: "Settings")
        case .bindings:  return L.get("nav.bindings",  fallback: "Key Bindings")
        case .global:    return L.get("nav.global",    fallback: "Preferences")
        case .about:     return L.get("about.title",   fallback: "About")
        }
    }

    var subtitle: String {
        switch self {
        case .discovery: return L.get("discovery.subtitle", fallback: "Pick a USB or LAN device")
        case .settings:  return L.get("settings.subtitle",  fallback: "Service, profiles, and curve")
        case .bindings:  return L.get("bindings.subtitle",  fallback: "Map each controller button to a PC key")
        case .global:    return L.get("global.subtitle",    fallback: "App-wide preferences")
        case .about:     return L.get("about.subtitle",     fallback: "App info")
        }
    }

    var systemImage: String {
        switch self {
        case .discovery: return "iphone.gen2"
        case .settings:  return "slider.horizontal.3"
        case .bindings:  return "keyboard"
        case .global:    return "gearshape"
        case .about:     return "info.bubble"
        }
    }
}

/// Sidebar with the primary section scrolling on top and 全局设置 /
/// 关于 pinned to the bottom via `safeAreaInset`.
///
/// **Why this layout works now**: a previous revision saw violent
/// expand-animation jank with safeAreaInset + footer-row Buttons.
/// The root cause was `NavigationSplitView`'s built-in
/// collapse/expand animation re-running entrance transitions on
/// the sidebar's child views every time the column width passed
/// through certain intermediate widths. Now that
/// `AppDelegate.stripSidebarToggle` removes the toggle item from
/// the window's `NSToolbar` entirely, that animation can never be
/// triggered, and pinned-footer layouts are stable again.
///
/// **Why two Lists, not one**: macOS Lists with `.sidebar` style
/// scroll vertically; there's no way to "freeze" the last N rows
/// at the bottom while the rest scroll. Splitting into a primary
/// scrollable List + a fixed-height footer List in a
/// `safeAreaInset` is the cleanest way to express "scroll the
/// main items, dock these other ones" while reusing the native
/// sidebar row styling (selection highlight, hover, padding).
/// Both Lists bind to the same `$selection`, so picking a footer
/// row clears the primary's highlight and vice versa.
struct SidebarView: View {
    @Binding var selection: SidebarPage?

    var body: some View {
        List(selection: $selection) {
            Section {
                row(.discovery)
                row(.settings)
                row(.bindings)
            } header: {
                Text(L.get("nav.root", fallback: "Mobile Controller"))
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                // Explicit gap between the divider and the first
                // footer row. The inner `List` with `.sidebar`
                // style has near-zero top inset, so without this
                // the divider visually fuses with the "全局设置"
                // row (regression flagged by user).
                Color.clear.frame(height: 8)
                List(selection: $selection) {
                    row(.global)
                    row(.about)
                }
                .listStyle(.sidebar)
                .scrollDisabled(true)
                // Two rows × ~28pt row height + ~8pt vertical
                // breathing room. Fixed height pins this list at
                // a stable size — without it, the inset would
                // expand to fill remaining space and shove the
                // primary list off the top.
                .frame(height: 72)
            }
        }
    }

    @ViewBuilder
    private func row(_ page: SidebarPage) -> some View {
        NavigationLink(value: page) {
            Label(page.title, systemImage: page.systemImage)
        }
    }
}

