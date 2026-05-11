import SwiftUI

struct AboutView: View {

    var body: some View {
        Form {
            heroSection
            metaSection
            notesSection
        }
        .formStyle(.grouped)
        .navigationTitle(SidebarPage.about.title)
        .navigationSubtitle(SidebarPage.about.subtitle)
    }

    @ViewBuilder private var heroSection: some View {
        Section {
            HStack(alignment: .center, spacing: 16) {
                // Transparent-background hero icon — just the grass
                // block, no squircle. The white squircle that ships
                // with the app icon looks heavy at this size + reads
                // as a frame around the artwork; the bare cube sits
                // more naturally inside a `Form` row.
                Image("AboutHeroIcon")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L.get("about.app.header", fallback: "MC Controller"))
                        .font(.title2.weight(.semibold))
                    Text(L.get("about.app.tagline",
                               fallback: "Turn your phone into a touchscreen controller for Java Edition Minecraft"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder private var metaSection: some View {
        Section {
            LabeledContent(L.get("about.version.header", fallback: "Version"),
                           value: versionString)
            LabeledContent(L.get("about.author.header", fallback: "Author"),
                           value: L.get("about.author.value", fallback: "Linloir"))
        }
    }

    @ViewBuilder private var notesSection: some View {
        Section {
            Text(L.get("about.love.body",
                       fallback: "Built for my own couch-gaming setup. Hope it helps yours too."))
                .font(.callout)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text(L.get("about.love.header", fallback: "Notes"))
        }
    }

    private var versionString: String {
        let dict = Bundle.main.infoDictionary
        let short = dict?["CFBundleShortVersionString"] as? String ?? ""
        let build = dict?["CFBundleVersion"] as? String ?? ""
        if short.isEmpty && build.isEmpty { return "dev" }
        if build.isEmpty { return short }
        return "\(short) (\(build))"
    }
}
