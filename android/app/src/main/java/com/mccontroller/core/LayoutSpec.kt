package com.mccontroller.core

/**
 * Position anchor for a widget. Maps to FrameLayout gravity flags.
 */
enum class Anchor {
    TopStart, TopCenter, TopEnd,
    CenterStart, CenterEnd,
    BottomStart, BottomCenter, BottomEnd,
}

/**
 * How the hotbar interprets left/right swipes.
 *
 * - [Precise]: a swipe lands on whatever slot the finger is over at the
 *   moment (original behavior). Drifting outside the strip clamps to the
 *   nearest extreme slot.
 * - [Relative]: scroll-wheel feel — direction matters, position doesn't.
 *   Every ~32dp of horizontal travel cycles the selection one slot in
 *   that direction, wrapping at slot 0 ↔ slot 8. Tap and long-press
 *   behaviors are unaffected.
 */
enum class HotbarSwipeMode { Precise, Relative }

/**
 * Per-widget layout: where it sits and how big it is.
 *
 * - `anchor` decides which screen edge(s) we measure from.
 * - `edgeMarginDp` is the horizontal distance from the start/end edge.
 * - `verticalMarginDp` is the distance from the top/bottom (or 0 for center).
 * - `widthDp` and `heightDp` of 0 mean "wrap_content" (used for LinearLayouts).
 */
data class WidgetSpec(
    val id: String,
    val anchor: Anchor,
    val edgeMarginDp: Float,
    val verticalMarginDp: Float,
    val widthDp: Float,
    val heightDp: Float,
)

/**
 * Per-mode layout: a map of widgets + global L/R margin offsets that
 * shift all start-anchored / end-anchored widgets uniformly (Honor-of-Kings
 * style "edge offset" sliders).
 */
data class ModeLayout(
    val widgets: Map<String, WidgetSpec>,
    val leftOffsetDp: Float = 0f,
    val rightOffsetDp: Float = 0f,
)

/**
 * Named layout profile: a complete layout for both in-game and UI modes.
 */
data class LayoutProfile(
    val name: String,
    val inGame: ModeLayout,
    val uiMode: ModeLayout,
    val hotbarSwipeMode: HotbarSwipeMode = HotbarSwipeMode.Precise,
)

/**
 * Hard-coded factory defaults — what the user sees the very first time
 * the app runs, mirroring the static positions in `activity_controller.xml`.
 *
 * Treat the LinearLayout containers (row_sneak_sprint, row_top_buttons,
 * column_ui_buttons) as single editable units — moving the row moves all
 * its children together. Sub-buttons inside keep their relative positions.
 */
object DefaultLayouts {

    val IN_GAME: ModeLayout = ModeLayout(
        widgets = mapOf(
            // Joystick activation zone (left side) — not editable in v3.
            "joystick" to WidgetSpec("joystick", Anchor.BottomStart, 0f, 0f, 360f, 280f),
            // Sneak alone above joystick (Sprint lives in the right-side fan)
            "btn_sneak" to WidgetSpec("btn_sneak", Anchor.BottomStart, 16f, 296f, 56f, 56f),

            // RIGHT-SIDE FAN (Honor-of-Kings style):
            //   LMB is the "attack" anchor — largest, deepest into the corner.
            //   RMB / Jump / Sprint fan out above-left along an arc of radius
            //   ~110dp from LMB's center, at angles 180°, 135°, 90°.
            "btn_lmb" to WidgetSpec("btn_lmb", Anchor.BottomEnd, 16f, 16f, 88f, 88f),
            "btn_rmb" to WidgetSpec("btn_rmb", Anchor.BottomEnd, 140f, 30f, 60f, 60f),
            "btn_jump" to WidgetSpec("btn_jump", Anchor.BottomEnd, 108f, 108f, 60f, 60f),
            "btn_sprint" to WidgetSpec("btn_sprint", Anchor.BottomEnd, 30f, 140f, 60f, 60f),

            // Top-right action buttons — individually editable.
            "btn_swap" to WidgetSpec("btn_swap", Anchor.TopEnd, 16f, 8f, 48f, 48f),
            "btn_inv" to WidgetSpec("btn_inv", Anchor.TopEnd, 72f, 8f, 48f, 48f),
            "btn_esc" to WidgetSpec("btn_esc", Anchor.TopEnd, 128f, 8f, 48f, 48f),

            // Hotbar — bottom-center, narrower (288dp = 9 slots × 32dp) so it
            // doesn't overlap with the right-side button fan. The slight overlap
            // with the joystick activation zone is fine since the joystick fades
            // when not in use.
            "hotbar" to WidgetSpec("hotbar", Anchor.BottomCenter, 0f, 8f, 288f, 40f),
        ),
    )

    val UI_MODE: ModeLayout = ModeLayout(
        widgets = mapOf(
            // Five individually-editable buttons stacked from the bottom-left,
            // sized to fit on a typical landscape screen (~400dp tall).
            "btn_ui_lmb" to WidgetSpec("btn_ui_lmb", Anchor.BottomStart, 24f, 20f, 72f, 72f),
            "btn_ui_rmb" to WidgetSpec("btn_ui_rmb", Anchor.BottomStart, 24f, 104f, 72f, 72f),
            "btn_ui_q" to WidgetSpec("btn_ui_q", Anchor.BottomStart, 24f, 188f, 56f, 56f),
            "btn_ui_shift" to WidgetSpec("btn_ui_shift", Anchor.BottomStart, 24f, 256f, 56f, 56f),
            "btn_ui_esc" to WidgetSpec("btn_ui_esc", Anchor.BottomStart, 24f, 324f, 56f, 56f),
        ),
    )

    val DEFAULT_PROFILE: LayoutProfile = LayoutProfile(
        name = "Default",
        inGame = IN_GAME,
        uiMode = UI_MODE,
    )

    /** Buttons that may have width/height edited (joystick excluded — v3 lock). */
    val RESIZABLE_IDS: Set<String> = setOf(
        "hotbar",
        "btn_sneak", "btn_sprint",
        "btn_lmb", "btn_rmb", "btn_jump",
        "btn_esc", "btn_inv", "btn_swap",
        "btn_ui_lmb", "btn_ui_rmb", "btn_ui_q", "btn_ui_shift", "btn_ui_esc",
    )

    /** All editable widget IDs, ordered for editor UI listing. */
    val IN_GAME_IDS: List<String> = listOf(
        "btn_sneak", "btn_sprint",
        "btn_lmb", "btn_rmb", "btn_jump",
        "btn_swap", "btn_inv", "btn_esc",
        "hotbar",
    )
    val UI_MODE_IDS: List<String> = listOf(
        "btn_ui_lmb", "btn_ui_rmb", "btn_ui_q", "btn_ui_shift", "btn_ui_esc",
    )
}
