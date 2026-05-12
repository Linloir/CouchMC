import SwiftUI

/// Saved hosts list + LAN discovery section. Tap a host to probe + connect.
struct HomeView: View {

    @EnvironmentObject var hostStore: HostStore
    @EnvironmentObject var settings: SettingsStore
    @StateObject private var discovery = DiscoveryClient()

    @State private var probingHostID: String?
    @State private var addingHost: Bool = false
    @State private var renamingHost: SavedHost?
    @State private var changingPort: SavedHost?
    @State private var probeError: String?

    @Binding var connectingTo: ConnectionRequest?
    @Binding var controllerOpacity: Double

    var theme: Theme { Theme(language: settings.settings.designLanguage) }

    var body: some View {
        NavigationStack {
            List {
                savedSection
                discoveredSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(L.key("home.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addingHost = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $addingHost) {
                AddHostSheet { name, ip, port in
                    _ = hostStore.upsert(name: name, ip: ip, port: port)
                    addingHost = false
                }
            }
            .sheet(item: $renamingHost) { h in
                RenameHostSheet(host: h) { newName in
                    hostStore.rename(id: h.id, newName: newName)
                    renamingHost = nil
                }
            }
            .sheet(item: $changingPort) { h in
                EditPortSheet(host: h) { newPort in
                    hostStore.updatePort(id: h.id, newPort: newPort)
                    changingPort = nil
                }
            }
            .alert(L.key("error.connect.title"), isPresented: Binding(
                get: { probeError != nil }, set: { if !$0 { probeError = nil } }
            )) {
                Button("OK") { probeError = nil }
            } message: {
                Text(probeError ?? "")
            }
            .onAppear { discovery.start() }
            .onDisappear { discovery.stop() }
        }
    }

    // MARK: - Saved

    private var savedSection: some View {
        Section {
            ForEach(sortedSavedHosts) { host in
                HostRow(
                    name: host.name,
                    ip: host.ip,
                    port: host.port,
                    statusBadge: badge(for: host),
                    probing: probingHostID == host.id
                )
                .contentShape(Rectangle())
                .onTapGesture { Task { await connect(to: host) } }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        // Wrap in `withAnimation` so the row-collapse
                        // animation and the empty-hint insertion below
                        // share an animation transaction. Without this,
                        // the conditional `if hostStore.hosts.isEmpty`
                        // updates on a *separate* SwiftUI commit from
                        // the swipe-delete row collapse — the LAN
                        // section header below briefly snaps upward
                        // (no row, no empty hint yet) and then back
                        // down once the hint appears, producing the
                        // visible overshoot / overlap flicker.
                        withAnimation { hostStore.remove(id: host.id) }
                    } label: { Label(L.key("host.remove"), systemImage: "trash") }
                }
                .contextMenu {
                    Button {
                        renamingHost = host
                    } label: { Label(L.key("host.rename"), systemImage: "pencil") }
                    Button {
                        changingPort = host
                    } label: { Label(L.key("host.edit_port"), systemImage: "number") }
                    Button(role: .destructive) {
                        withAnimation { hostStore.remove(id: host.id) }
                    } label: { Label(L.key("host.remove"), systemImage: "trash") }
                }
            }
            if hostStore.hosts.isEmpty {
                // `.identity` transition — the hint should be in place
                // the instant the last row starts collapsing, not
                // fade-in afterwards (which would let the LAN section
                // header below briefly slide up into the gap before
                // bouncing back).
                emptyRow(L.key("home.empty.saved"))
                    .transition(.identity)
            }
        } header: {
            Text(L.key("home.section.saved"))
        }
    }

    private var sortedSavedHosts: [SavedHost] {
        hostStore.hosts.sorted { (a, b) in
            (a.lastConnectedAt ?? .distantPast) > (b.lastConnectedAt ?? .distantPast)
        }
    }

    private func badge(for host: SavedHost) -> HostStatusDot.Status {
        if let live = discovery.hosts.first(where: { $0.value.ip == host.ip && $0.value.tcpPort == host.port })?.value {
            if live.busy { return .busy }
            if live.mcInForeground { return .mcRunning }
            return .online
        }
        return .offline
    }

    // MARK: - Discovered

    private var discoveredSection: some View {
        Section {
            let knownKeys = Set(hostStore.hosts.map { "\($0.ip):\($0.port)" })
            let extras = discovery.hosts.values
                .filter { !knownKeys.contains($0.id) }
                .sorted { $0.name < $1.name }

            ForEach(extras) { live in
                HostRow(
                    name: live.name,
                    ip: live.ip,
                    port: live.tcpPort,
                    statusBadge: live.busy ? .busy : (live.mcInForeground ? .mcRunning : .online),
                    probing: false
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    let saved = hostStore.upsert(name: live.name, ip: live.ip, port: live.tcpPort)
                    Task { await connect(to: saved) }
                }
            }
            if extras.isEmpty && hostStore.hosts.isEmpty == false {
                emptyRow(L.key("home.empty.discovered"))
            }
        } header: {
            Text(L.key("home.section.discovered"))
        } footer: {
            Text(L.key("home.discovered.hint"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Connect flow

    private func connect(to host: SavedHost) async {
        probingHostID = host.id
        defer { probingHostID = nil }
        let result = await ConnectivityProbe.probe(host: host.ip, port: host.port)
        switch result {
        case .alive:
            OrientationHelper.enterLandscape()
            controllerOpacity = 0
            connectingTo = ConnectionRequest(host: host)
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: OrientationHelper.enterFadeDuration)) {
                    controllerOpacity = 1
                }
            }
        case .busy:
            probeError = L.key("error.connect.busy")
        case .incompatible:
            probeError = L.key("error.connect.incompatible")
        case .failed(let reason):
            probeError = String(format: L.key("error.connect.failed"), reason)
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .font(.subheadline)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
    }
}

// MARK: - Row

private struct HostRow: View {
    let name: String
    let ip: String
    let port: UInt16
    let statusBadge: HostStatusDot.Status
    let probing: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                Text(verbatim: HostFormat.endpoint(ip: ip, port: port))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if probing {
                ProgressView()
            } else {
                HostStatusDot(status: statusBadge)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Sheets

private struct AddHostSheet: View {
    @State private var name: String = ""
    @State private var ip: String = ""
    @State private var portText: String = "34555"
    @Environment(\.dismiss) var dismiss
    let onSave: (String, String, UInt16) -> Void

    var body: some View {
        NavigationStack {
            Form {
                TextField(L.key("host.field.name"), text: $name)
                TextField(L.key("host.field.ip"), text: $ip)
                    .keyboardType(.numbersAndPunctuation)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                TextField(L.key("host.field.port"), text: $portText)
                    .keyboardType(.numberPad)
            }
            .navigationTitle(L.key("host.add.title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.key("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.key("common.save")) {
                        let port = UInt16(portText) ?? 34555
                        let n = name.isEmpty ? ip : name
                        onSave(n, ip, port)
                    }
                    .disabled(ip.isEmpty)
                }
            }
        }
    }
}

private struct RenameHostSheet: View {
    let host: SavedHost
    let onSave: (String) -> Void
    @State private var name: String
    @Environment(\.dismiss) var dismiss

    init(host: SavedHost, onSave: @escaping (String) -> Void) {
        self.host = host
        self.onSave = onSave
        self._name = State(initialValue: host.name)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(L.key("host.field.name"), text: $name)
            }
            .navigationTitle(L.key("host.rename"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.key("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.key("common.save")) { onSave(name) }
                        .disabled(name.isEmpty)
                }
            }
        }
    }
}

private struct EditPortSheet: View {
    let host: SavedHost
    let onSave: (UInt16) -> Void
    @State private var portText: String
    @Environment(\.dismiss) var dismiss

    init(host: SavedHost, onSave: @escaping (UInt16) -> Void) {
        self.host = host
        self.onSave = onSave
        self._portText = State(initialValue: "\(host.port)")
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(L.key("host.field.port"), text: $portText)
                    .keyboardType(.numberPad)
            }
            .navigationTitle(L.key("host.edit_port"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L.key("common.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L.key("common.save")) {
                        if let p = UInt16(portText) { onSave(p) }
                    }
                }
            }
        }
    }
}

/// Marker payload sent up to the root view to trigger the Controller screen.
struct ConnectionRequest: Identifiable, Hashable {
    let host: SavedHost
    var id: String { host.id }
}
