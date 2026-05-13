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
                    Toggle(L.key("settings.editor.edge_snap"),
                           isOn: $settings.settings.editorEdgeSnap)
                    Toggle(L.key("settings.editor.spacing_snap"),
                           isOn: $settings.settings.editorSpacingSnap)
                } header: {
                    Text(L.key("settings.section.layout"))
                } footer: {
                    if settings.settings.editorEdgeSnap || settings.settings.editorSpacingSnap {
                        Text(L.key("settings.editor.snap_hint"))
                    }
                }

                // === Hotbar ===
                Section {
                    Picker(L.key("settings.hotbar_swipe"), selection: hotbarSwipeBinding) {
                        Text(L.key("settings.hotbar_swipe.precise")).tag(HotbarSwipeMode.precise)
                        Text(L.key("settings.hotbar_swipe.relative")).tag(HotbarSwipeMode.relative)
                    }
                    if profileStore.activeProfile.hotbarSwipeMode == .relative {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(L.key("settings.hotbar_step"))
                                Spacer()
                                Text(verbatim: "\(Int(settings.settings.hotbarRelativeStep)) pt")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            Slider(value: $settings.settings.hotbarRelativeStep,
                                   in: 12...60, step: 1)
                        }
                    }
                } header: {
                    Text(L.key("settings.section.hotbar"))
                } footer: {
                    if profileStore.activeProfile.hotbarSwipeMode == .relative {
                        Text(L.key("settings.hotbar_step.hint"))
                    }
                }

                // === Camera ===
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(L.key("settings.camera_sensitivity"))
                            Spacer()
                            Text(verbatim: String(format: "%.1f×", settings.settings.cameraSensitivity))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.settings.cameraSensitivity,
                               in: 0.5...3.0)
                            .onChange(of: settings.settings.cameraSensitivity) { _, raw in
                                let snapped = snapToStep(raw, step: 0.1, in: 0.5...3.0)
                                if abs(snapped - raw) > 0.0005 {
                                    settings.settings.cameraSensitivity = snapped
                                }
                            }
                    }
                } header: {
                    Text(L.key("settings.section.camera"))
                } footer: {
                    Text(L.key("settings.camera_sensitivity.hint"))
                }

                // === Sprint ===
                Section {
                    Toggle(L.key("settings.sprint_from_joystick"),
                           isOn: $settings.settings.sprintFromJoystick)
                    if settings.settings.sprintFromJoystick {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(L.key("settings.sprint_engage"))
                                Spacer()
                                Text(verbatim: String(format: "%.2f×",
                                                      Double(settings.settings.sprintEngageFactor)))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                            // Slider range expanded to 2.0× so users
                            // who prefer "stick all the way out" sprint
                            // triggering have headroom past the
                            // joystick's nominal 1.0 radius. The
                            // joystick can travel out to ~2× the dead-
                            // zone before clamping (controlled by
                            // `JoystickTouchView`'s knob extent), so
                            // values above 1.0 mean "user has pushed
                            // past the visual ring by N%".
                            //
                            // Snap via `.onChange(of:)` instead of the
                            // slider's own `step:` parameter — IEEE
                            // round-off (`1.05 + 19*0.05 == 2.0+ε`)
                            // would otherwise cap the slider at 1.95
                            // even though 2.0 is in-range.
                            Slider(value: $settings.settings.sprintEngageFactor,
                                   in: 1.05...2.00)
                                .onChange(of: settings.settings.sprintEngageFactor) { _, raw in
                                    let snapped = snapToStep(raw, step: 0.05, in: 1.05...2.00)
                                    if abs(snapped - raw) > 0.001 {
                                        settings.settings.sprintEngageFactor = snapped
                                    }
                                }
                        }
                    }
                } header: {
                    Text(L.key("settings.section.sprint"))
                } footer: {
                    Text(L.key("settings.sprint.hint"))
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
                    let isActive = name == profileStore.snapshot.active
                    HStack(spacing: 8) {
                        // Reserve the slot with an empty 22pt-wide
                        // box even on inactive rows so the profile
                        // titles line up vertically — only the
                        // checkmark glyph renders on the active row,
                        // matching the visual cleanliness of iOS
                        // Settings > Wi-Fi (the unselected networks
                        // have no leading indicator at all).
                        Group {
                            if isActive {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            } else {
                                Color.clear
                            }
                        }
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
                        Text("CouchMC").font(.headline)
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
            // Trademark / non-affiliation disclaimer required to ride the line
            // between App Store Review Guideline 5.2.1 (third-party IP) and
            // 4.1 (don't suggest you're an official product). Keep this
            // section visible by default — Apple reviewers explicitly look
            // for it when an app's purpose centres on a trademarked third-
            // party game.
            Section {
                Text(L.key("about.legal.body"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } header: {
                Text(L.key("about.section.legal"))
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

// MARK: - Slider snapping

/// Round `raw` to the nearest multiple of `step` measured from
/// `bounds.lowerBound`, then clamp to `bounds`.
///
/// We snap inside `.onChange(of:)` rather than via `Slider(step:)` because
/// SwiftUI's native step parameter computes the snap as
/// `lowerBound + n*step` and compares against `upperBound`; IEEE 754
/// round-off can make the largest valid snapped value test as *just over*
/// the upper bound, so the slider falls back to `n-1` and the user can't
/// reach the max. Concretely: a `1.05…2.0` / `step 0.05` slider tops out
/// at 1.95 because `1.05 + 19*0.05` evaluates to `2.0 + ε`.
///
/// Used to be a `Binding.stepped(...)` extension, but the
/// `Binding(get:set:)` initialiser became `@Sendable` in the iOS 26 SDK,
/// which made the captured `Binding` / `ClosedRange` / `Value.Type`
/// trigger Swift 6 strict-concurrency warnings. `.onChange(of:)` runs on
/// the main actor and the snap is a pure function, so this approach is
/// concurrency-clean.
private func snapToStep<T: BinaryFloatingPoint>(
    _ raw: T, step: T, in bounds: ClosedRange<T>
) -> T {
    let n = ((raw - bounds.lowerBound) / step).rounded()
    let snapped = bounds.lowerBound + n * step
    return Swift.min(bounds.upperBound, Swift.max(bounds.lowerBound, snapped))
}
