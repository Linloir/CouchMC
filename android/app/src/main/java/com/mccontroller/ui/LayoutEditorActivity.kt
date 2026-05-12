package com.mccontroller.ui

import android.graphics.Color
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.mccontroller.R
import com.mccontroller.core.Anchor
import com.mccontroller.core.DefaultLayouts
import com.mccontroller.core.LayoutApplier
import com.mccontroller.core.LayoutProfile
import com.mccontroller.core.ModeLayout
import com.mccontroller.core.ProfileStore
import com.mccontroller.core.SettingsStore
import com.mccontroller.core.WidgetSpec
import com.mccontroller.databinding.ActivityLayoutEditorBinding
import com.mccontroller.ui.view.EditorCanvas

/**
 * Full-screen layout editor.
 *
 * - Canvas fills the screen (so widget positions match the in-game look 1:1).
 * - Top + bottom toolbars float over the canvas with semi-transparent
 *   backgrounds; a single toggle button collapses both off-screen.
 * - Tap a widget = select; drag a widget = move (auto-selects on first
 *   movement); two-finger pinch (anywhere on screen) resizes the
 *   currently-selected widget; tap on empty canvas = deselect.
 * - Reset Position / Reset Size buttons appear when something is
 *   selected and only restore that widget's position or size from
 *   factory defaults — leaving everything else untouched.
 */
class LayoutEditorActivity : AppCompatActivity(), EditorCanvas.Callback {

    private lateinit var binding: ActivityLayoutEditorBinding
    private lateinit var store: ProfileStore

    private val workingProfiles = mutableListOf<LayoutProfile>()
    private var activeIdx = 0
    /**
     * Initial mode the editor opens to. Defaults to InGame, but the caller
     * (SettingsActivity) can pass [EXTRA_MODE] to deep-link straight into
     * either tab. Phase 3 will collapse the in-activity tab control and
     * make the activity strictly per-mode.
     */
    private var currentEditMode: EditMode = EditMode.InGame

    private var selectedId: String? = null
    private var toolbarsCollapsed = false

    private val selectionDrawable: Drawable by lazy { makeSelectionDrawable() }

    enum class EditMode { InGame, UiInteract }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityLayoutEditorBinding.inflate(layoutInflater)
        setContentView(binding.root)

        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, binding.root).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }

        binding.canvas.callback = this

        store = ProfileStore(this)
        val (loaded, activeName) = store.loadAll()
        workingProfiles.addAll(loaded)
        activeIdx = workingProfiles.indexOfFirst { it.name == activeName }.coerceAtLeast(0)

        // SettingsActivity launches with EXTRA_MODE = MODE_IN_GAME / MODE_UI
        // to land directly on a tab; legacy direct launch (no extra) leaves
        // the default in-game tab selected.
        currentEditMode = when (intent.getStringExtra(EXTRA_MODE)) {
            MODE_UI -> EditMode.UiInteract
            else -> EditMode.InGame
        }

        // Title reflects the mode the editor was launched into.
        binding.txtEditorTitle.setText(
            when (currentEditMode) {
                EditMode.InGame -> R.string.editor_title_in_game
                EditMode.UiInteract -> R.string.editor_title_ui
            },
        )

        // Apply current app settings (hotbar swipe mode, edge offsets) to
        // the preview so the editor reflects exactly what will be rendered
        // in the controller — but these aren't editable here anymore.
        applyAppSettingsToPreview()

        setupActions()
        setupResetSelectionButtons()
        setupToolbarToggle()
        attachWidgetEditListeners()

        applyCurrentToCanvas()
        applyModeVisibility()
        updateSelectionUi()
    }

    private fun applyAppSettingsToPreview() {
        val s = SettingsStore.get(this).current
        binding.hotbar.swipeMode = s.hotbarSwipeMode
    }

    private fun applyModeVisibility() {
        val showInGame = currentEditMode == EditMode.InGame
        inGameViews().forEach { it.visibility = if (showInGame) View.VISIBLE else View.GONE }
        uiModeWidgetMap().values.forEach {
            it.visibility = if (!showInGame) View.VISIBLE else View.GONE
        }
        // Joystick + look-pad are intentionally hidden in the editor.
        // Both are full-area touch surfaces in the real controller:
        // joystick claims the left half, look-pad covers the entire
        // canvas (match_parent). When visible, their native onTouchEvent
        // consumes every tap before EditorCanvas can see it, which
        // breaks the tap-empty-to-deselect detection — there would
        // effectively be no "empty area" anywhere on the canvas. They
        // also aren't user-editable here (attachWidgetEditListeners
        // skips them for the same reason), so hiding them is purely
        // an editor-time concern.
        binding.joystick.visibility = View.GONE
        binding.lookPad.visibility = View.GONE
    }

    // ===== EditorCanvas.Callback =====

    override fun onPinch(scaleFactor: Float) {
        val id = selectedId ?: return
        if (id !in DefaultLayouts.RESIZABLE_IDS) return
        updateSpec(id) { spec ->
            val newW = (spec.widthDp * scaleFactor).coerceIn(40f, 600f)
            val newH = if (spec.heightDp > 0)
                (spec.heightDp * scaleFactor).coerceIn(30f, 600f)
            else 0f
            spec.copy(widthDp = newW, heightDp = newH)
        }
    }

    override fun onTapEmpty() {
        setSelectedWidget(null)
    }

    // ===== Empty-area nudge (fine-adjust selected widget) =====
    //
    // Empty-area swipe in the editor canvas micro-nudges the SELECTED
    // widget along the dominant gesture axis. The user's finger travels
    // ~NUDGE_DIVISOR× the distance the widget moves, so a long sweep
    // produces a few-pixel adjustment — exactly the "I just want to
    // touch this thing up" use case. Snap engine sits on top of the
    // raw nudge: edge alignment + spacing alignment, each independently
    // toggleable via Settings.

    /** Captured at NudgeStart for the selected widget; reset on End. */
    private data class NudgeAnchor(
        val edgeMarginDp: Float,
        val verticalMarginDp: Float,
        val anchor: Anchor,
    )
    private var nudgeAnchor: NudgeAnchor? = null

    override fun onNudgeStart() {
        val id = selectedId ?: return
        val spec = currentSpec(id) ?: return
        nudgeAnchor = NudgeAnchor(
            edgeMarginDp = spec.edgeMarginDp,
            verticalMarginDp = spec.verticalMarginDp,
            anchor = spec.anchor,
        )
    }

    override fun onNudgeDelta(axis: com.mccontroller.ui.view.EditorCanvas.NudgeAxis, deltaPx: Float) {
        val id = selectedId ?: return
        val anchor = nudgeAnchor ?: return
        val density = resources.displayMetrics.density

        // Scale the finger travel down by NUDGE_DIVISOR so the user gets
        // sub-px precision over a sane swipe distance.
        val effectivePx = deltaPx / com.mccontroller.ui.view.EditorCanvas.NUDGE_DIVISOR
        val effectiveDp = effectivePx / density

        val (proposedEdge, proposedVert) = when (axis) {
            com.mccontroller.ui.view.EditorCanvas.NudgeAxis.Horizontal -> {
                val sign = when {
                    anchor.anchor.isHorizontalCenter() -> 0f      // center-anchored = no horizontal adjust
                    anchor.anchor.isStart() -> 1f                  // start: finger right = bigger edge
                    else -> -1f                                    // end: finger right = smaller edge
                }
                (anchor.edgeMarginDp + effectiveDp * sign).coerceAtLeast(0f) to anchor.verticalMarginDp
            }
            com.mccontroller.ui.view.EditorCanvas.NudgeAxis.Vertical -> {
                val sign = if (anchor.anchor.isTop()) 1f else -1f
                anchor.edgeMarginDp to (anchor.verticalMarginDp + effectiveDp * sign).coerceAtLeast(0f)
            }
        }
        updateSpec(id) { it.copy(edgeMarginDp = proposedEdge, verticalMarginDp = proposedVert) }

        // After applying the proposed move, run the snap pass and (if it
        // matches) re-apply with the corrective offset. We snap in screen
        // pixels — that's where alignment visually means something — then
        // translate the px delta back into dp-space spec adjustments.
        runSnapPass(id, axis)
    }

    override fun onNudgeEnd() {
        nudgeAnchor = null
        binding.canvas.setGuides(emptyList())
    }

    /**
     * Read the rects of every other in-mode widget, run the snap engine,
     * and apply any returned correction to the moving widget's spec.
     * Sets the canvas overlay guides as a side effect.
     */
    private fun runSnapPass(id: String, axis: com.mccontroller.ui.view.EditorCanvas.NudgeAxis) {
        val s = SettingsStore.get(this).current
        if (!s.editorEdgeSnap && !s.editorSpacingSnap) {
            binding.canvas.setGuides(emptyList())
            return
        }
        val movingView = allWidgetMap()[id] ?: return
        if (movingView.width == 0 || movingView.height == 0) return

        val canvas = binding.canvas
        // Build rects in canvas-local pixel coords. Use the views' .left /
        // .top etc. directly — those are already in canvas-local space
        // since the views are direct children of the canvas FrameLayout.
        val moving = android.graphics.RectF(
            movingView.left.toFloat(), movingView.top.toFloat(),
            movingView.right.toFloat(), movingView.bottom.toFloat(),
        )
        val others = activeModeWidgetMap().entries
            .asSequence()
            .filter { it.key != id }
            .map { it.value }
            .filter { it.width > 0 && it.height > 0 && it.visibility == View.VISIBLE }
            .map {
                android.graphics.RectF(
                    it.left.toFloat(), it.top.toFloat(),
                    it.right.toFloat(), it.bottom.toFloat(),
                )
            }
            .toList()

        val threshold = SNAP_THRESHOLD_DP * resources.displayMetrics.density
        val result = com.mccontroller.ui.editor.SnapEngine.compute(
            moving = moving,
            others = others,
            axis = axis,
            edgeSnap = s.editorEdgeSnap,
            spacingSnap = s.editorSpacingSnap,
            thresholdPx = threshold,
        )
        canvas.setGuides(result.guides)
        if (result.snappedDx == 0f) return

        val density = resources.displayMetrics.density
        val snappedDp = result.snappedDx / density
        // Translate the px-space snap correction back into dp-space spec
        // edits respecting the active anchor's sign.
        val spec = currentSpec(id) ?: return
        val newSpec = when (axis) {
            com.mccontroller.ui.view.EditorCanvas.NudgeAxis.Horizontal -> {
                val sign = when {
                    spec.anchor.isHorizontalCenter() -> 0f
                    spec.anchor.isStart() -> 1f
                    else -> -1f
                }
                spec.copy(edgeMarginDp = (spec.edgeMarginDp + snappedDp * sign).coerceAtLeast(0f))
            }
            com.mccontroller.ui.view.EditorCanvas.NudgeAxis.Vertical -> {
                val sign = if (spec.anchor.isTop()) 1f else -1f
                spec.copy(verticalMarginDp = (spec.verticalMarginDp + snappedDp * sign).coerceAtLeast(0f))
            }
        }
        updateSpec(id) { newSpec }
    }

    /** Returns the widgets visible in the currently-edited mode. */
    private fun activeModeWidgetMap(): Map<String, View> = when (currentEditMode) {
        EditMode.InGame -> inGameWidgetMap()
        EditMode.UiInteract -> uiModeWidgetMap()
    }

    // ===== Save / cancel / reset-all =====

    private fun setupActions() {
        binding.btnSave.setOnClickListener {
            store.saveAll(workingProfiles, workingProfiles[activeIdx].name)
            Toast.makeText(this, R.string.editor_save, Toast.LENGTH_SHORT).show()
            finish()
        }
        binding.btnCancel.setOnClickListener { finish() }
        binding.btnResetLayout.setOnClickListener { onResetLayout() }
    }

    /**
     * Reset the currently-edited mode's widgets back to factory defaults.
     * The other mode (not visible right now) is left untouched, as is the
     * profile name.
     */
    private fun onResetLayout() {
        val current = workingProfiles[activeIdx]
        workingProfiles[activeIdx] = when (currentEditMode) {
            EditMode.InGame -> current.copy(inGame = DefaultLayouts.IN_GAME)
            EditMode.UiInteract -> current.copy(uiMode = DefaultLayouts.UI_MODE)
        }
        setSelectedWidget(null)
        applyCurrentToCanvas()
    }

    // ===== Reset position / size for selection =====

    private fun setupResetSelectionButtons() {
        binding.btnResetPosition.setOnClickListener {
            val id = selectedId ?: return@setOnClickListener
            val def = defaultSpec(id) ?: return@setOnClickListener
            updateSpec(id) {
                it.copy(
                    anchor = def.anchor,
                    edgeMarginDp = def.edgeMarginDp,
                    verticalMarginDp = def.verticalMarginDp,
                )
            }
        }
        binding.btnResetSize.setOnClickListener {
            val id = selectedId ?: return@setOnClickListener
            val def = defaultSpec(id) ?: return@setOnClickListener
            updateSpec(id) { it.copy(widthDp = def.widthDp, heightDp = def.heightDp) }
        }
    }

    private fun defaultSpec(id: String): WidgetSpec? =
        DefaultLayouts.IN_GAME.widgets[id] ?: DefaultLayouts.UI_MODE.widgets[id]

    // ===== Selection state =====

    private fun setSelectedWidget(id: String?) {
        if (selectedId == id) return
        selectedId?.let { allWidgetMap()[it]?.foreground = null }
        selectedId = id
        id?.let { allWidgetMap()[it]?.foreground = selectionDrawable }
        updateSelectionUi()
    }

    private fun updateSelectionUi() {
        val id = selectedId
        // The whole bottom selection-actions pill collapses when nothing
        // is selected — cleaner than three separately-toggled buttons.
        binding.toolbarBottom.visibility = if (id != null) View.VISIBLE else View.GONE
        binding.txtSelectedLabel.text = id ?: ""
        binding.btnResetPosition.visibility = if (id != null) View.VISIBLE else View.GONE
        binding.btnResetSize.visibility =
            if (id != null && id in DefaultLayouts.RESIZABLE_IDS) View.VISIBLE else View.GONE
    }

    private fun makeSelectionDrawable(): Drawable = GradientDrawable().apply {
        shape = GradientDrawable.RECTANGLE
        cornerRadius = resources.displayMetrics.density * 6f
        setStroke(
            (resources.displayMetrics.density * 2.5f).toInt(),
            Color.parseColor("#FFE8C547"),
        )
    }

    // ===== Toolbar collapse / expand =====

    private fun setupToolbarToggle() {
        // Default state is "expanded" — chevron points up (rotation 180°),
        // meaning "tap me to collapse upward". Each tap animates 180°
        // around so the user sees the direction it would expand into.
        binding.toggleChevron.rotation = 180f
        binding.btnToggleToolbars.setOnClickListener {
            toolbarsCollapsed = !toolbarsCollapsed
            animateToolbars()
        }
    }

    private fun animateToolbars() {
        // Use `bottom` (toolbar's bottom edge in parent coords) so that
        // translating by -bottom puts the toolbar's whole rectangle —
        // marginTop included — above the screen edge. Using height
        // alone left a small strip visible.
        val topTarget = if (toolbarsCollapsed) -binding.toolbarTop.bottom.toFloat() else 0f
        val parentH = (binding.toolbarBottom.parent as android.view.View).height
        val bottomTarget = if (toolbarsCollapsed)
            (parentH - binding.toolbarBottom.top).toFloat()
        else 0f
        binding.toolbarTop.animate().translationY(topTarget).setDuration(220).start()
        binding.toolbarBottom.animate().translationY(bottomTarget).setDuration(220).start()
        binding.txtHint.animate().alpha(if (toolbarsCollapsed) 0f else 1f).setDuration(220).start()
        // Chevron flips 180° each tap. Down (0°) when toolbars are
        // hidden → "tap to bring them back". Up (180°) when toolbars
        // are visible → "tap to put them away".
        val chevronTarget = if (toolbarsCollapsed) 0f else 180f
        binding.toggleChevron.animate().rotation(chevronTarget).setDuration(220).start()
    }

    // ===== Drag handling on each widget =====

    private fun attachWidgetEditListeners() {
        for ((id, view) in allWidgetMap()) {
            // Joystick is intentionally non-editable in v3 — its activation
            // zone is large and dragging it would only confuse the layout.
            if (id == "joystick") continue
            attachListener(id, view)
        }
    }

    private fun attachListener(id: String, view: View) {
        var startRawX = 0f
        var startRawY = 0f
        var startEdge = 0f
        var startVert = 0f
        var didMove = false
        val touchSlop = ViewConfiguration.get(this).scaledTouchSlop.toFloat()
        val density = resources.displayMetrics.density

        view.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    val spec = currentSpec(id) ?: return@setOnTouchListener false
                    startRawX = event.rawX
                    startRawY = event.rawY
                    startEdge = spec.edgeMarginDp
                    startVert = spec.verticalMarginDp
                    didMove = false
                }
                MotionEvent.ACTION_MOVE -> {
                    val rawDx = event.rawX - startRawX
                    val rawDy = event.rawY - startRawY
                    if (!didMove) {
                        // Still inside the tap-vs-drag slop region. Wait
                        // until the finger has moved enough to be
                        // unambiguously a drag.
                        if ((rawDx * rawDx + rawDy * rawDy) <= (touchSlop * touchSlop)) {
                            return@setOnTouchListener true
                        }
                        didMove = true
                        if (selectedId != id) setSelectedWidget(id)
                        // Re-anchor at the slop-crossing point so the
                        // widget doesn't jump by `touchSlop` pixels the
                        // moment we transition out of tap territory.
                        // Without this, a slow drag pauses for several
                        // hundred ms (slop accumulates), then teleports —
                        // which read as "stuttery / hard to fine-adjust".
                        startRawX = event.rawX
                        startRawY = event.rawY
                        return@setOnTouchListener true
                    }
                    val spec = currentSpec(id) ?: return@setOnTouchListener true
                    // Horizontally-centered anchors (Top/BottomCenter) are
                    // always centered horizontally — drag the widget up/down
                    // only; horizontal drag is a no-op for them.
                    val edgeSign = when {
                        spec.anchor.isHorizontalCenter() -> 0f
                        spec.anchor.isStart() -> 1f
                        else -> -1f
                    }
                    val vertSign = if (spec.anchor.isTop()) 1f else -1f
                    val dxDp = rawDx / density
                    val dyDp = rawDy / density
                    val newEdge = (startEdge + dxDp * edgeSign).coerceAtLeast(0f)
                    val newVert = (startVert + dyDp * vertSign).coerceAtLeast(0f)
                    updateSpec(id) {
                        it.copy(edgeMarginDp = newEdge, verticalMarginDp = newVert)
                    }
                }
                MotionEvent.ACTION_UP -> {
                    if (!didMove) setSelectedWidget(id)  // tap → select
                }
                MotionEvent.ACTION_CANCEL -> {
                    // Canvas grabbed for pinch — treat as a non-tap, no select change.
                }
            }
            true
        }
    }

    // ===== State helpers =====

    private fun currentMode(): ModeLayout = when (currentEditMode) {
        EditMode.InGame -> workingProfiles[activeIdx].inGame
        EditMode.UiInteract -> workingProfiles[activeIdx].uiMode
    }

    private fun mutateMode(transform: (ModeLayout) -> ModeLayout) {
        val active = workingProfiles[activeIdx]
        workingProfiles[activeIdx] = when (currentEditMode) {
            EditMode.InGame -> active.copy(inGame = transform(active.inGame))
            EditMode.UiInteract -> active.copy(uiMode = transform(active.uiMode))
        }
    }

    private fun applyCurrentToCanvas() {
        val profile = workingProfiles[activeIdx]
        LayoutApplier.applyAll(inGameWidgetMap(), profile.inGame)
        LayoutApplier.applyAll(uiModeWidgetMap(), profile.uiMode)
        binding.hotbar.swipeMode = profile.hotbarSwipeMode
    }

    private fun currentSpec(id: String): WidgetSpec? = when (currentEditMode) {
        EditMode.InGame -> workingProfiles[activeIdx].inGame.widgets[id]
        EditMode.UiInteract -> workingProfiles[activeIdx].uiMode.widgets[id]
    }

    private fun updateSpec(id: String, transform: (WidgetSpec) -> WidgetSpec) {
        mutateMode { mode ->
            val cur = mode.widgets[id] ?: return@mutateMode mode
            mode.copy(widgets = mode.widgets + (id to transform(cur)))
        }
        val view = allWidgetMap()[id] ?: return
        val spec = currentSpec(id) ?: return
        LayoutApplier.apply(view, spec, currentMode())
    }

    private fun Anchor.isStart() =
        this == Anchor.TopStart || this == Anchor.BottomStart || this == Anchor.CenterStart

    private fun Anchor.isTop() =
        this == Anchor.TopStart || this == Anchor.TopEnd || this == Anchor.TopCenter

    private fun Anchor.isHorizontalCenter() =
        this == Anchor.TopCenter || this == Anchor.BottomCenter

    // ===== Widget maps =====

    private fun inGameWidgetMap(): Map<String, View> = mapOf(
        "joystick" to binding.joystick,
        "btn_sneak" to binding.btnSneak,
        "btn_sprint" to binding.btnSprint,
        "btn_lmb" to binding.btnLmb,
        "btn_rmb" to binding.btnRmb,
        "btn_jump" to binding.btnJump,
        "btn_swap" to binding.btnSwap,
        "btn_inv" to binding.btnInv,
        "btn_esc" to binding.btnEsc,
        "hotbar" to binding.hotbar,
    )

    private fun uiModeWidgetMap(): Map<String, View> = mapOf(
        "btn_ui_lmb" to binding.btnUiLmb,
        "btn_ui_rmb" to binding.btnUiRmb,
        "btn_ui_q" to binding.btnUiQ,
        "btn_ui_shift" to binding.btnUiShift,
        "btn_ui_esc" to binding.btnUiEsc,
    )

    private fun allWidgetMap(): Map<String, View> = inGameWidgetMap() + uiModeWidgetMap()

    private fun inGameViews(): List<View> = inGameWidgetMap().values.toList()

    companion object {
        /** Optional Intent extra: pre-selects which mode tab to land on. */
        const val EXTRA_MODE = "mode"
        /** Value for [EXTRA_MODE] — open the in-game layout. */
        const val MODE_IN_GAME = "in_game"
        /** Value for [EXTRA_MODE] — open the UI-mode layout. */
        const val MODE_UI = "ui"

        /** Distance (dp) within which an alignment counts as a snap candidate. */
        private const val SNAP_THRESHOLD_DP = 6f
    }
}
