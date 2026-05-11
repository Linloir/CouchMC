import SwiftUI

struct GlobalSettingsView: View {

    @EnvironmentObject private var appearance: AppearancePreferences
    @State private var startupEnabled: Bool = StartupRegistration.isEnabled

    var body: some View {
        Form {
            generalSection
            appearanceSection
        }
        .formStyle(.grouped)
        .navigationTitle(SidebarPage.global.title)
        .navigationSubtitle(SidebarPage.global.subtitle)
    }

    @ViewBuilder private var generalSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { startupEnabled },
                set: { newValue in
                    if StartupRegistration.setEnabled(newValue) {
                        startupEnabled = newValue
                    }
                })) {
                Text(L.get("global.startup.header", fallback: "Launch at login"))
                Text(L.get("global.startup.desc",
                           fallback: "Run quietly in the background after sign-in"))
            }
        } header: {
            Text(L.get("global.section.general", fallback: "General"))
        }
    }

    @ViewBuilder private var appearanceSection: some View {
        let supported = appearance.systemSupportsLiquidGlass
        Section {
            Toggle(isOn: Binding(
                get: { supported && appearance.liquidGlassMode == .on },
                set: { newValue in
                    appearance.liquidGlassMode = newValue ? .on : .off
                })) {
                Text(L.get("global.liquidGlass.header",
                           fallback: "Liquid Glass design"))
                Text(L.get("global.liquidGlass.desc",
                           fallback: "macOS 26 glass material; older systems fall back to standard translucency"))
            }
            .disabled(!supported)
        } header: {
            Text(L.get("global.section.appearance", fallback: "Appearance"))
        } footer: {
            if !supported {
                Text(L.get("global.liquidGlass.unsupported",
                           fallback: "Current macOS doesn't support Liquid Glass (requires macOS 26 Tahoe or later)."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
