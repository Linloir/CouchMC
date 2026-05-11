import Foundation
import Combine

/// App-wide tunables. Mirror of Android `AppSettings.kt` plus iOS-specific
/// additions (design language toggle, haptics).
struct AppSettings: Codable, Equatable, Sendable {
    /// Enable the in-game LookPad tap/hold gesture FSM (LMB chain-fire).
    var inGameQuickClicks: Bool = true
    /// Enable the UI-mode LookPad tap/hold FSM (single/double-tap distinction).
    var uiQuickClicks: Bool = true
    /// Hotbar swipe behavior. Mirrored on the active profile too — the profile
    /// is authoritative; this is the picker-state seed.
    var hotbarSwipeMode: HotbarSwipeMode = .precise
    /// Global horizontal margin offsets that shift left/right anchored widgets.
    var leftMarginOffset: CGFloat = 0
    var rightMarginOffset: CGFloat = 0
    /// Haptic feedback on button presses.
    var haptics: Bool = true
    /// Design language: iOS standard (system materials) vs Liquid Glass (iOS 26+).
    var designLanguage: DesignLanguage = .standard
}

enum DesignLanguage: String, Codable, CaseIterable, Sendable {
    case standard       // iOS 18 system materials
    case liquidGlass    // iOS 26 Liquid Glass APIs (gracefully falls back on <26)
}

@MainActor
final class SettingsStore: ObservableObject {

    @Published var settings: AppSettings {
        didSet { save() }
    }

    private let url: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.url = fileURL
        } else {
            let fm = FileManager.default
            let support = try? fm.url(for: .applicationSupportDirectory,
                                      in: .userDomainMask, appropriateFor: nil, create: true)
            let dir = (support ?? URL(fileURLWithPath: NSTemporaryDirectory()))
                .appendingPathComponent("McController", isDirectory: true)
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            self.url = dir.appendingPathComponent("settings.v1.json")
        }
        if let data = try? Data(contentsOf: self.url),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = AppSettings()
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(settings) {
            try? data.write(to: url, options: [.atomic])
        }
    }
}
