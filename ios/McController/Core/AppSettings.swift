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

    // MARK: - iOS-specific tuning (no Android counterpart yet)

    /// Multiplier applied to look-pad camera deltas. Default 1.5× because the
    /// baseline (1.0) feels visibly slower on iOS than on Android — the
    /// UIKit touch sampling pipeline coalesces fewer micro-deltas than
    /// Android's, so the wire signal has less resolution per finger pixel.
    /// User-tunable in Settings.
    var cameraSensitivity: Double = 1.5

    /// Hotbar relative-mode step distance (pt). Smaller value = more
    /// sensitive (less travel per slot change). Only effective when
    /// `hotbarSwipeMode == .relative`.
    var hotbarRelativeStep: CGFloat = 24

    /// Whether overdriving the joystick past `sprintEngageFactor × baseRadius`
    /// auto-engages sprint. Manual sprint button works regardless.
    var sprintFromJoystick: Bool = true
    /// Distance multiplier (×baseRadius) at which the joystick triggers
    /// sprint. Hysteresis on disengage is fixed at 1.0. Default 1.5
    /// keeps casual stick wobble from triggering sprint while staying
    /// easy to reach intentionally; matches the Android client's
    /// updated default after retuning.
    var sprintEngageFactor: CGFloat = 1.5

    // MARK: - Layout editor snapping

    /// Snap a widget's edge / centre to align with another widget when the
    /// distance is within tolerance. Renders a dashed grey alignment line.
    var editorEdgeSnap: Bool = true
    /// Snap the gap between the dragged widget and another widget when it
    /// matches the gap of another pair on screen — i.e. equal-spacing
    /// alignment, with arrow indicators on the matching pairs.
    var editorSpacingSnap: Bool = true
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
