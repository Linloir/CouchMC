import Foundation
import CoreGraphics

/// Anchor — eight cardinal positions on the screen rectangle. Mirrors the
/// Android `Anchor` enum.
enum Anchor: String, Codable, CaseIterable, Sendable {
    case topStart, topCenter, topEnd
    case centerStart, centerEnd
    case bottomStart, bottomCenter, bottomEnd

    /// True when the anchor's horizontal position is determined relative to
    /// the canvas centre rather than an edge. On iOS we interpret `edge` on
    /// these anchors as a **signed offset from centre** (positive = right of
    /// centre, negative = left), so a centre-anchored widget can still be
    /// dragged horizontally.
    var isHorizontallyCentered: Bool {
        self == .topCenter || self == .bottomCenter
    }
}

/// Layout descriptor for a single widget. Sizes / margins are in points.
struct WidgetSpec: Codable, Hashable, Identifiable, Sendable {
    let id: String
    var anchor: Anchor
    /// For start / end anchors: distance from the start / end edge (≥ 0).
    /// For centre anchors: signed offset from the canvas centre.
    var edge: CGFloat
    /// Distance from the top / bottom (or below-centre for centre rows).
    var vertical: CGFloat
    var width: CGFloat       // 0 = wrap content
    var height: CGFloat
}

/// All the widget specs for one mode (InGame OR UiInteract).
struct ModeLayout: Codable, Hashable, Sendable {
    var widgets: [String: WidgetSpec]
    var leftOffset: CGFloat = 0
    var rightOffset: CGFloat = 0
}

enum HotbarSwipeMode: String, Codable, CaseIterable, Sendable {
    case precise        // position-based: slot = x / slotWidth
    case relative       // scroll-wheel: every N pt of travel cycles ±1
}

/// One named layout profile (the user can keep multiple).
struct LayoutProfile: Codable, Hashable, Sendable {
    var name: String
    var inGame: ModeLayout
    var uiMode: ModeLayout
    var hotbarSwipeMode: HotbarSwipeMode = .precise
}

// MARK: - Default layouts

enum DefaultLayouts {

    /// Widgets a user can resize / reposition.
    /// `joystick` is intentionally NOT here — its 360×280 activation zone is
    /// fixed in v3 (Android also locks it).
    static let resizableIDs: Set<String> = [
        "btn_sneak", "btn_lmb", "btn_rmb", "btn_jump", "btn_sprint",
        "btn_swap", "btn_inv", "btn_esc", "btn_close",
        "hotbar",
        "btn_ui_lmb", "btn_ui_rmb", "btn_ui_q", "btn_ui_shift", "btn_ui_esc",
    ]

    static let inGame = ModeLayout(widgets: [
        "joystick":    .init(id: "joystick",    anchor: .bottomStart,  edge: 0,   vertical: 0,   width: 360, height: 280),
        "btn_sneak":   .init(id: "btn_sneak",   anchor: .bottomStart,  edge: 16,  vertical: 296, width: 56,  height: 56),
        "btn_lmb":     .init(id: "btn_lmb",     anchor: .bottomEnd,    edge: 16,  vertical: 16,  width: 88,  height: 88),
        "btn_rmb":     .init(id: "btn_rmb",     anchor: .bottomEnd,    edge: 140, vertical: 30,  width: 60,  height: 60),
        "btn_jump":    .init(id: "btn_jump",    anchor: .bottomEnd,    edge: 108, vertical: 108, width: 60,  height: 60),
        "btn_sprint":  .init(id: "btn_sprint",  anchor: .bottomEnd,    edge: 30,  vertical: 140, width: 60,  height: 60),
        "btn_swap":    .init(id: "btn_swap",    anchor: .topEnd,       edge: 16,  vertical: 8,   width: 48,  height: 48),
        "btn_inv":     .init(id: "btn_inv",     anchor: .topEnd,       edge: 72,  vertical: 8,   width: 48,  height: 48),
        "btn_esc":     .init(id: "btn_esc",     anchor: .topEnd,       edge: 128, vertical: 8,   width: 48,  height: 48),
        // iOS-only: a movable close button that replaces the floating
        // top-right "back" chevron. Placed at top-start by default so it
        // doesn't collide with the swap / inv / esc row on the top-end.
        "btn_close":   .init(id: "btn_close",   anchor: .topStart,     edge: 16,  vertical: 8,   width: 48,  height: 48),
        "hotbar":      .init(id: "hotbar",      anchor: .bottomCenter, edge: 0,   vertical: 8,   width: 288, height: 40),
    ])

    static let uiMode = ModeLayout(widgets: [
        "btn_ui_lmb":   .init(id: "btn_ui_lmb",   anchor: .bottomStart, edge: 24, vertical: 20,  width: 72, height: 72),
        "btn_ui_rmb":   .init(id: "btn_ui_rmb",   anchor: .bottomStart, edge: 24, vertical: 104, width: 72, height: 72),
        "btn_ui_q":     .init(id: "btn_ui_q",     anchor: .bottomStart, edge: 24, vertical: 188, width: 56, height: 56),
        "btn_ui_shift": .init(id: "btn_ui_shift", anchor: .bottomStart, edge: 24, vertical: 256, width: 56, height: 56),
        "btn_ui_esc":   .init(id: "btn_ui_esc",   anchor: .bottomStart, edge: 24, vertical: 324, width: 56, height: 56),
        // iOS-only close button mirrors the in-game placement.
        "btn_close":    .init(id: "btn_close",    anchor: .topStart,    edge: 16, vertical: 8,   width: 48, height: 48),
    ])

    static let defaultProfile = LayoutProfile(
        name: "Default",
        inGame: inGame,
        uiMode: uiMode,
        hotbarSwipeMode: .precise
    )
}

// MARK: - Layout application

/// Translates a `WidgetSpec + ModeLayout` into a frame inside `bounds`.
/// Returns the frame in the same coordinate system as `bounds` (typically
/// the parent view's local space). Sizes of `0` mean "wrap content" — caller
/// must supply the intrinsic size.
enum LayoutApplier {

    static func frame(
        for spec: WidgetSpec,
        in mode: ModeLayout,
        bounds: CGRect,
        intrinsicSize: CGSize = .zero
    ) -> CGRect {
        let w = spec.width  > 0 ? spec.width  : intrinsicSize.width
        let h = spec.height > 0 ? spec.height : intrinsicSize.height

        let leftAdj  = mode.leftOffset
        let rightAdj = mode.rightOffset

        let x: CGFloat
        switch spec.anchor {
        case .topStart, .centerStart, .bottomStart:
            x = bounds.minX + spec.edge + leftAdj
        case .topEnd, .centerEnd, .bottomEnd:
            x = bounds.maxX - spec.edge - rightAdj - w
        case .topCenter, .bottomCenter:
            // `edge` is a signed offset from canvas centre (positive = right).
            x = bounds.midX - w / 2 + spec.edge
        }

        let y: CGFloat
        switch spec.anchor {
        case .topStart, .topCenter, .topEnd:
            y = bounds.minY + spec.vertical
        case .bottomStart, .bottomCenter, .bottomEnd:
            y = bounds.maxY - spec.vertical - h
        case .centerStart, .centerEnd:
            y = bounds.midY + spec.vertical
        }

        return CGRect(x: x, y: y, width: w, height: h)
    }
}
