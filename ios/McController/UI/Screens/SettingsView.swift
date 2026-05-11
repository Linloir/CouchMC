import SwiftUI

/// Top-level Settings. Mirrors the visual structure of Apple's own Settings
/// app — plain rows, no leading icons, trailing chevrons / values. Profile
/// management is a push-detail screen rather than inline buttons.
struct SettingsView: View {

    /// Driven by `RootView` so the layout editor can be presented as a
    /// cross-fading ZStack overlay covering the tab bar (rather than via
    /// SwiftUI's default-slide `fullScreenCover`).
    @Binding var editorMode: ControllerMode?
    /// Manual fade-in alpha driven by the open-action below — see
    /// `RootView` for the rationale.
    @Binding var editorOpacity: Double

    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var profileStore: ProfileStoreObservable

    @State private var showingAbout: Bool = false

    var body: some View {
        NavigationStack {
            Form {
                // === Profile ===
                Section {
                    NavigationLink {
                        ProfileListView()
                    } label: {
                        HStack {
                            Text(L.key("settings.profile.row"))
                            Spacer()
                            Text(profileStore.snapshot.active)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(L.key("settings.section.profile"))
                }

                // === Layout ===
                Section {
                    Button {
                        openEditor(.inGame)
                    } label: {
                        HStack {
                            Text(L.key("settings.layout.edit_in_game"))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Button {
                        openEditor(.uiInteract)
                    } label: {
                        HStack {
                            Text(L.key("settings.layout.edit_ui"))
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Picker(L.key("settings.hotbar_swipe"), selection: hotbarSwipeBinding) {
                        Text(L.key("settings.hotbar_swipe.precise")).tag(HotbarSwipeMode.precise)
                        Text(L.key("settings.hotbar_swipe.relative")).tag(HotbarSwipeMode.relative)
                    }
                    Stepper(value: $settings.settings.leftMarginOffset, in: 0...80, step: 1) {
                        HStack {
                            Text(L.key("settings.left_margin_offset"))
                            Spacer()
                            Text(verbatim: "\(Int(settings.settings.leftMarginOffset))")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    Stepper(value: $settings.settings.rightMarginOffset, in: 0...80, step: 1) {
                        HStack {
                            Text(L.key("settings.right_margin_offset"))
                            Spacer()
                            Text(verbatim: "\(Int(settings.settings.rightMarginOffset))")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(L.key("settings.section.layout"))
                }

                // === Gameplay ===
                Section {
                    Toggle(L.key("settings.in_game_quick_clicks"),
                           isOn: $settings.settings.inGameQuickClicks)
                    Toggle(L.key("settings.ui_quick_clicks"),
                           isOn: $settings.settings.uiQuickClicks)
                    Toggle(L.key("settings.haptics"), isOn: $settings.settings.haptics)
                } header: {
                    Text(L.key("settings.section.gameplay"))
                }

                // === Appearance ===
                Section {
                    Picker(L.key("settings.design_language"),
                           selection: $settings.settings.designLanguage) {
                        Text(L.key("settings.design.standard"))
                            .tag(DesignLanguage.standard)
                        Text(L.key("settings.design.liquid_glass"))
                            .tag(DesignLanguage.liquidGlass)
                    }
                } header: {
                    Text(L.key("settings.section.appearance"))
                } footer: {
                    if settings.settings.designLanguage == .liquidGlass {
                        Text(L.key("settings.design.liquid_glass_hint"))
                    }
                }

                // === About ===
                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Text(L.key("settings.about.open"))
                    }
                }
            }
            .navigationTitle(L.key("settings.title"))
            // Editor presentation is owned by RootView (ZStack overlay with
            // cross-fade transition) so the rotation animation behind the
            // overlay stays visible while it fades in.
        }
    }

    /// Open the layout editor with a guaranteed fade-in regardless of how
    /// many times the user has opened/closed it. We mount the overlay at
    /// `editorOpacity = 0`, defer the `withAnimation` to the next runloop
    /// (after SwiftUI has rendered the new view tree at alpha 0), then
    /// animate to 1.
    private func openEditor(_ mode: ControllerMode) {
        OrientationHelper.enterLandscape()
        editorOpacity = 0
        editorMode = mode
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: OrientationHelper.enterFadeDuration)) {
                editorOpacity = 1
            }
        }
    }

    private var hotbarSwipeBinding: Binding<HotbarSwipeMode> {
        Binding(
            get: { profileStore.activeProfile.hotbarSwipeMode },
            set: { newValue in
                profileStore.updateActive { $0.hotbarSwipeMode = newValue }
                settings.settings.hotbarSwipeMode = newValue
            }
        )
    }
}

// MARK: - Profile list (push-detail screen, native iOS Settings pattern)

struct ProfileListView: View {
    @EnvironmentObject var profileStore: ProfileStoreObservable
    @Environment(\.editMode) private var editMode

    @State private var newProfileSheet: Bool = false
    @State private var renamingProfile: String?
    @State private var deleteCandidate: String?
    @State private var inlineError: String?

    var body: some View {
        List {
            Section {
                ForEach(profileStore.allNames, id: \.self) { name in
                    HStack(spacing: 8) {
                        Image(systemName: name == profileStore.snapshot.active
                              ? "checkmark"
                              : "circle.dashed")
                            .foregroundStyle(name == profileStore.snapshot.active ? Color.accentColor : .secondary)
                            .frame(width: 22)
                            .opacity(editMode?.wrappedValue.isEditing == true ? 0 : 1)
                        Text(name)
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if editMode?.wrappedValue.isEditing == true {
                            renamingProfile = name
                        } else {
                            profileStore.setActive(name)
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if profileStore.snapshot.profiles.count > 1 {
                            Button(role: .destructive) {
                                deleteCandidate = name
                            } label: {
                                Label(L.key("common.delete"), systemImage: "trash")
                            }
                        }
                        Button {
                            renamingProfile = name
                        } label: {
                            Label(L.key("common.rename"), systemImage: "pencil")
                        }
                        .tint(.indigo)
                    }
                }
            } footer: {
                Text(L.key("settings.profile.list_footer"))
            }

            Section {
                Button {
                    newProfileSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus")
                            .frame(width: 22)
                        Text(L.key("settings.profile.new"))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(L.key("settings.section.profile"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(isPresented: $newProfileSheet) {
            ProfileNameSheet(
                title: L.key("settings.profile.new"),
                initial: "",
                confirmLabel: L.key("common.create"),
                existingNames: Set(profileStore.allNames)
            ) { name in
                if profileStore.addProfile(named: name) {
                    newProfileSheet = false
                } else {
                    inlineError = L.key("settings.profile.invalid_name")
                }
            }
        }
        .sheet(item: $renamingProfile) { name in
            ProfileNameSheet(
                title: L.key("settings.profile.rename"),
                initial: name,
                confirmLabel: L.key("common.save"),
                existingNames: Set(profileStore.allNames).subtracting([name])
            ) { newName in
                if profileStore.renameProfile(name, to: newName) {
                    renamingProfile = nil
                } else {
                    inlineError = L.key("settings.profile.invalid_name")
                }
            }
        }
        .alert(L.key("settings.profile.delete_confirm_title"),
               isPresented: Binding(
                   get: { deleteCandidate != nil },
                   set: { if !$0 { deleteCandidate = nil } }
               )) {
            Button(L.key("common.delete"), role: .destructive) {
                if let name = deleteCandidate {
                    profileStore.deleteProfile(name)
                }
                deleteCandidate = nil
            }
            Button(L.key("common.cancel"), role: .cancel) {
                deleteCandidate = nil
            }
        } message: {
            if let name = deleteCandidate {
                Text(String(format: L.key("settings.profile.delete_confirm_msg"), name))
            }
        }
        .alert("",
               isPresented: Binding(get: { inlineError != nil },
                                    set: { if !$0 { inlineError = nil } })) {
            Button("OK") { inlineError = nil }
        } message: {
            Text(inlineError ?? "")
        }
    }
}

// Make String Identifiable so .sheet(item:) can take a name directly.
extension String: @retroactive Identifiable {
    public var id: String { self }
}

// MARK: - Name sheet (used for both create and rename)

private struct ProfileNameSheet: View {
    let title: String
    let initial: String
    let confirmLabel: String
    let existingNames: Set<String>
    let onConfirm: (String) -> Void

    @State private var name: String
    @Environment(\.dismiss) var dismiss
    @FocusState private var focused: Bool

    init(title: String,
         initial: String,
         confirmLabel: String,
         existingNames: Set<String>,
         onConfirm: @escaping (String) -> Void) {
        self.title = title
        self.initial = initial
        self.confirmLabel = confirmLabel
        self.existingNames = existingNames
        self.onConfirm = onConfirm
        self._name = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L.key("settings.profile.field.name"), text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .focused($focused)
                } footer: {
                    if isDuplicate {
                        Text(L.key("settings.profile.duplicate_name"))
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.key("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmLabel) { onConfirm(name) }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isDuplicate)
                }
            }
            .onAppear { focused = true }
        }
        .presentationDetents([.medium])
    }

    private var isDuplicate: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && existingNames.contains(trimmed)
    }
}

// MARK: - About

struct AboutView: View {
    var body: some View {
        List {
            Section {
                HStack {
                    Image("AppIconAbout")
                        .resizable()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(.white.opacity(0.1), lineWidth: 1)
                        )
                    VStack(alignment: .leading) {
                        Text("MC Controller").font(.headline)
                        Text(L.key("about.subtitle"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                LabeledContent(L.key("about.version"), value: appVersion)
                LabeledContent(L.key("about.build"), value: buildNumber)
            }
            Section {
                Text(L.key("about.notes.body"))
                    .font(.subheadline)
            }
        }
        .navigationTitle(L.key("settings.about.open"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}

// Make ControllerMode Identifiable so we can drive fullScreenCover with it.
extension ControllerMode: Identifiable {
    public var id: UInt8 { rawValue }
}
