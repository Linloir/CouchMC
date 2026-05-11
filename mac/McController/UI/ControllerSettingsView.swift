import SwiftUI

struct ControllerSettingsView: View {

    @EnvironmentObject private var host: ServerHost
    @StateObject private var profiles: ProfileManager

    /// Counter bumped on each slider tick so the live curve preview
    /// (`.id(liveTick)`) re-renders. SwiftUI doesn't observe
    /// mutations inside the `ControllerProfile` class automatically.
    @State private var liveTick: Int = 0
    @State private var saveStatus: String = ""
    @State private var pendingDelete: ControllerProfile?
    @State private var pendingRestore: ControllerProfile?

    init() {
        // `@EnvironmentObject` isn't readable during `init()`; the
        // singleton holder provides a stable hand-off so `ProfileManager`
        // can wire to the live `ServerHost` instance.
        _profiles = StateObject(wrappedValue: ProfileManager(host: AppEnvironment.shared.host))
    }

    var body: some View {
        Form {
            serviceSection
            profileSection
            cameraSection
            curveSection
            movementSection
        }
        .formStyle(.grouped)
        .navigationTitle(SidebarPage.settings.title)
        .navigationSubtitle(SidebarPage.settings.subtitle)
        .confirmationDialog(
            String(format: L.get("settings.profile.delete.confirm", fallback: "Delete %@?"),
                   pendingDelete?.name ?? ""),
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(L.get("settings.profile.delete", fallback: "Delete"),
                   role: .destructive) {
                if let p = pendingDelete { _ = profiles.delete(p) }
                pendingDelete = nil
                liveTick &+= 1
            }
        }
        .confirmationDialog(
            String(format: L.get("settings.profile.restore.confirm",
                                 fallback: "Reset %@ to defaults?"),
                   pendingRestore?.name ?? ""),
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }),
            titleVisibility: .visible
        ) {
            Button(L.get("settings.profile.restore", fallback: "Restore defaults")) {
                if let p = pendingRestore {
                    p.camera = CameraConfig()
                    p.movement = MovementConfig()
                    liveTick &+= 1
                    bumpAutoSave()
                }
                pendingRestore = nil
            }
        }
    }

    // MARK: - Service

    @ViewBuilder private var serviceSection: some View {
        Section {
            LabeledContent {
                TextField("", value: Binding(
                    get: { host.config.port },
                    set: { host.rebind(toPort: $0) }
                ), format: .number)
                    .frame(width: 80)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.get("settings.service.port.header", fallback: "Server port"))
                    Text(L.get("settings.service.port.listening", fallback: "Listening..."))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(L.get("settings.service.section", fallback: "Service"))
        }
    }

    // MARK: - Profile

    @ViewBuilder private var profileSection: some View {
        Section {
            LabeledContent(L.get("settings.profile.current.header",
                                 fallback: "Active profile")) {
                // macOS Pickers ignore explicit frame width and
                // `LabeledContent`'s content slot stretches the
                // child to fill — together those defaults left-align
                // the popup button to roughly the slot's midpoint.
                // Wrapping in `HStack { Spacer(); Picker }` pushes
                // the popup all the way to the right edge of the
                // row, matching what System Settings does for
                // hug-to-content menus.
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Picker("", selection: profileBinding) {
                        ForEach(profiles.profiles) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            LabeledContent(L.get("settings.profile.name.header",
                                 fallback: "Profile name")) {
                TextField("", text: Binding(
                    get: { profiles.activeProfile.name },
                    set: { newValue in
                        profiles.activeProfile.name = newValue
                        profiles.refresh()
                        bumpAutoSave()
                    }))
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
            }

            HStack(spacing: 8) {
                Button(L.get("settings.profile.new", fallback: "New")) {
                    let name = String(format: L.get("settings.profile.newName",
                                                    fallback: "New profile %d"),
                                      profiles.profiles.count + 1)
                    profiles.setActive(profiles.addNew(name: name))
                    liveTick &+= 1
                }
                Button(L.get("settings.profile.duplicate", fallback: "Duplicate")) {
                    profiles.setActive(profiles.duplicate(profiles.activeProfile))
                    liveTick &+= 1
                }
                Spacer()
                Button(L.get("settings.profile.restore", fallback: "Restore defaults")) {
                    pendingRestore = profiles.activeProfile
                }
                Button(L.get("settings.profile.delete", fallback: "Delete"),
                       role: .destructive) {
                    pendingDelete = profiles.activeProfile
                }
                .disabled(profiles.profiles.count <= 1)
            }
        } header: {
            Text(L.get("settings.profile.section", fallback: "Profiles"))
        } footer: {
            Text(L.get("settings.profile.current.desc",
                       fallback: "Swap between sensitivity / curve / deadzone presets"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var profileBinding: Binding<String> {
        Binding(
            get: { profiles.activeProfileId },
            set: { id in
                if let p = profiles.profiles.first(where: { $0.id == id }) {
                    profiles.setActive(p)
                    liveTick &+= 1
                }
            })
    }

    // MARK: - Camera (sensitivity)

    @ViewBuilder private var cameraSection: some View {
        Section {
            LabeledContent {
                HStack(spacing: 12) {
                    Slider(value: sensitivityBinding, in: 0.5...3.0, step: 0.05)
                        .frame(width: 200)
                    TextField("", value: sensitivityBinding,
                              format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 64)
                        .multilineTextAlignment(.trailing)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.get("settings.camera.sensitivity.header",
                               fallback: "Sensitivity"))
                    Text(L.get("settings.camera.sensitivity.desc",
                               fallback: "Overall mouse-move multiplier"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(L.get("settings.camera.section", fallback: "Look"))
        }
    }

    @ViewBuilder private var curveSection: some View {
        let isPower = profiles.activeProfile.camera.curveType == .power
        Section {
            LabeledContent(L.get("settings.camera.curve.type",
                                 fallback: "Curve type")) {
                Picker("", selection: Binding(
                    get: { profiles.activeProfile.camera.curveType },
                    set: { newValue in
                        profiles.activeProfile.camera.curveType = newValue
                        liveTick &+= 1
                        bumpAutoSave()
                    })) {
                    Text(L.get("settings.camera.curve.linear", fallback: "Linear"))
                        .tag(CurveType.linear)
                    Text(L.get("settings.camera.curve.power", fallback: "Power"))
                        .tag(CurveType.power)
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            LabeledContent(L.get("settings.camera.curve.factor",
                                 fallback: "Accel strength")) {
                sliderRow(accelFactorBinding, range: 0...0.05, step: 0.001, digits: 3)
            }
            .disabled(!isPower)

            LabeledContent(L.get("settings.camera.curve.exp",
                                 fallback: "Accel exponent")) {
                sliderRow(accelExpBinding, range: 0.5...2.5, step: 0.05, digits: 2)
            }
            .disabled(!isPower)

            LabeledContent(L.get("settings.camera.curve.maxmul",
                                 fallback: "Max multiplier")) {
                sliderRow(maxMulBinding, range: 1...5, step: 0.1, digits: 2)
            }
            .disabled(!isPower)

            VStack(alignment: .leading, spacing: 10) {
                Text(L.get("settings.camera.curve.preview", fallback: "Live preview"))
                CurveCanvasView(camera: profiles.activeProfile.camera)
                    .id(liveTick)
                    .frame(height: 180)
                HStack(spacing: 24) {
                    legendChip(color: Color(red: 91/255, green: 127/255, blue: 1.0),
                               label: L.get("settings.camera.curve.legend.curve",
                                            fallback: "Current curve"))
                    legendChip(color: .secondary,
                               dashed: true,
                               label: L.get("settings.camera.curve.legend.ref",
                                            fallback: "y = x reference"))
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(L.get("settings.camera.curve.header", fallback: "Curve (advanced)"))
        } footer: {
            Text(L.get("settings.camera.curve.desc",
                       fallback: "Linear is slope-only; Power adds an acceleration curve"))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func sliderRow(_ binding: Binding<Float>,
                           range: ClosedRange<Float>,
                           step: Float,
                           digits: Int) -> some View {
        HStack(spacing: 12) {
            Slider(value: binding, in: range, step: step).frame(width: 200)
            TextField("", value: binding,
                      format: .number.precision(.fractionLength(digits)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 64)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private func legendChip(color: Color, dashed: Bool = false, label: String) -> some View {
        HStack(spacing: 6) {
            if dashed {
                Path { p in
                    p.move(to: .zero)
                    p.addLine(to: CGPoint(x: 18, y: 0))
                }
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                .foregroundStyle(color)
                .frame(width: 18, height: 2)
            } else {
                Rectangle()
                    .fill(color)
                    .frame(width: 18, height: 2)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Movement

    @ViewBuilder private var movementSection: some View {
        Section {
            LabeledContent {
                sliderRow(deadZoneBinding, range: 0...0.5, step: 0.01, digits: 2)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.get("settings.movement.deadzone.header",
                               fallback: "Dead zone"))
                    Text(L.get("settings.movement.deadzone.desc",
                               fallback: "Stick center ignored range"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent {
                sliderRow(enterBinding, range: 0...0.6, step: 0.01, digits: 2)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.get("settings.movement.enter.header",
                               fallback: "Enter threshold"))
                    Text(L.get("settings.movement.enter.desc",
                               fallback: "Magnitude that engages WASD"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            LabeledContent {
                sliderRow(exitBinding, range: 0...0.5, step: 0.01, digits: 2)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L.get("settings.movement.exit.header",
                               fallback: "Exit threshold"))
                    Text(L.get("settings.movement.exit.desc",
                               fallback: "Magnitude that releases WASD"))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(L.get("settings.movement.section", fallback: "Movement"))
        } footer: {
            Text(saveStatus)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Bindings

    private var sensitivityBinding: Binding<Float> { fieldBinding(\.camera.userSensitivity) }
    private var accelFactorBinding: Binding<Float> { fieldBinding(\.camera.accelFactor) }
    private var accelExpBinding: Binding<Float>    { fieldBinding(\.camera.accelExp) }
    private var maxMulBinding: Binding<Float>      { fieldBinding(\.camera.maxAccelMultiplier) }
    private var deadZoneBinding: Binding<Float>    { fieldBinding(\.movement.deadZone) }
    private var enterBinding: Binding<Float>       { fieldBinding(\.movement.enterThreshold) }
    private var exitBinding: Binding<Float>        { fieldBinding(\.movement.exitThreshold) }

    private func fieldBinding(_ keyPath: ReferenceWritableKeyPath<ControllerProfile, Float>)
        -> Binding<Float> {
        Binding(
            get: { profiles.activeProfile[keyPath: keyPath] },
            set: { newValue in
                profiles.activeProfile[keyPath: keyPath] = newValue
                liveTick &+= 1
                bumpAutoSave()
            })
    }

    private func bumpAutoSave() {
        host.requestSave()
        saveStatus = L.get("settings.save.saved", fallback: "Saved")
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run { saveStatus = "" }
        }
    }
}
