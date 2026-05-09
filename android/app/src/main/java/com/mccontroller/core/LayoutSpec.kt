package com.mccontroller.core

/**
 * Position anchor for a widget. Maps to FrameLayout gravity flags.
 */
enum class Anchor {
    TopStart, TopEnd,
    CenterStart, CenterEnd,
    BottomStart, BottomEnd,
}

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
            // Joystick activation zone
            "joystick" to WidgetSpec("joystick", Anchor.BottomStart, 0f, 0f, 360f, 280f),
            // Sneak / Sprint row (above joystick)
            "row_sneak_sprint" to WidgetSpec("row_sneak_sprint", Anchor.BottomStart, 16f, 296f, 0f, 0f),
            // LMB / RMB / Jump arc cluster
            "btn_lmb" to WidgetSpec("btn_lmb", Anchor.BottomEnd, 20f, 20f, 76f, 76f),
            "btn_rmb" to WidgetSpec("btn_rmb", Anchor.BottomEnd, 112f, 44f, 68f, 68f),
            "btn_jump" to WidgetSpec("btn_jump", Anchor.BottomEnd, 44f, 124f, 60f, 60f),
            // Esc / Inv / Swap row
            "row_top_buttons" to WidgetSpec("row_top_buttons", Anchor.TopEnd, 16f, 8f, 0f, 0f),
            // Hotbar
            "hotbar" to WidgetSpec("hotbar", Anchor.BottomEnd, 16f, 8f, 360f, 44f),
        ),
    )

    val UI_MODE: ModeLayout = ModeLayout(
        widgets = mapOf(
            "column_ui_buttons" to WidgetSpec("column_ui_buttons", Anchor.CenterStart, 24f, 0f, 0f, 0f),
        ),
    )

    val DEFAULT_PROFILE: LayoutProfile = LayoutProfile(
        name = "Default",
        inGame = IN_GAME,
        uiMode = UI_MODE,
    )

    /** Buttons that may have width/height edited (excluding wrap_content rows). */
    val RESIZABLE_IDS: Set<String> = setOf(
        "joystick", "btn_lmb", "btn_rmb", "btn_jump", "hotbar",
    )

    /** All editable widget IDs, ordered for editor UI listing. */
    val IN_GAME_IDS: List<String> = listOf(
        "joystick", "row_sneak_sprint",
        "btn_lmb", "btn_rmb", "btn_jump",
        "row_top_buttons", "hotbar",
    )
    val UI_MODE_IDS: List<String> = listOf("column_ui_buttons")
}
