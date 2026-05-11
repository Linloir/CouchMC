import Foundation
import Combine

/// User-tunable visual prefs for the macOS app. On the Windows side
/// the equivalent file persists Acrylic transparency sliders; on
/// macOS the analogous toggle is the *Liquid Glass* design language
/// (introduced in macOS 26 Tahoe).
///
/// The picker is **binary** — `.on` / `.off`. On systems that don't
/// support Liquid Glass (macOS < 26), the UI force-disables the
/// toggle and defaults the value to `.off`.
///
/// Stored as JSON at
/// `~/Library/Application Support/McController/appearance.json`,
/// separate from `config.json` so a controller-tuning change doesn't
/// inadvertently touch visual prefs.
@MainActor
final class AppearancePreferences: ObservableObject {

    enum LiquidGlassMode: String, Codable, CaseIterable, Identifiable {
        case on, off
        var id: String { rawValue }
    }

    static let shared = AppearancePreferences()

    @Published var liquidGlassMode: LiquidGlassMode = .off {
        didSet { save() }
    }

    private static var storageURL: URL {
        ConfigStore.applicationSupportDirectory()
            .appendingPathComponent("appearance.json", isDirectory: false)
    }

    /// Effective decision: should views render with Liquid Glass right
    /// now? Combines the user preference with runtime API availability.
    var resolvedUseLiquidGlass: Bool {
        systemSupportsLiquidGlass && liquidGlassMode == .on
    }

    /// True iff this macOS runtime has the Liquid Glass APIs (Xcode 17
    /// + macOS 26 SDK build, running on macOS 26+).
    var systemSupportsLiquidGlass: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26, *) { return true }
        #endif
        return false
    }

    private struct Snapshot: Codable {
        var liquidGlassMode: String?

        init(mode: LiquidGlassMode) { self.liquidGlassMode = mode.rawValue }
    }

    init() {
        let url = Self.storageURL
        guard let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return }
        // Map any legacy raw value (incl. the dropped "system" case) to
        // a known LiquidGlassMode, defaulting to `.off`.
        self.liquidGlassMode = LiquidGlassMode(rawValue: snap.liquidGlassMode ?? "off") ?? .off
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(Snapshot(mode: liquidGlassMode))
            try data.write(to: Self.storageURL, options: .atomic)
        } catch {
            NSLog("[Appearance] save failed: %@", String(describing: error))
        }
    }
}
