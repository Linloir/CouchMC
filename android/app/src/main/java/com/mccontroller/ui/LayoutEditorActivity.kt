package com.mccontroller.ui

import android.graphics.Color
import android.graphics.drawable.Drawable
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.widget.AdapterView
import android.widget.ArrayAdapter
import android.widget.EditText
import android.widget.SeekBar
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
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

        setupSpinner()
        setupModeTabs()
        setupSliders()
        setupActions()
        setupResetSelectionButtons()
        setupToolbarToggle()
        attachWidgetEditListeners()

        applyCurrentToCanvas()
        updateModeVisibility()
        refreshSliders()
        updateSelectionUi()
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

    // ===== Profile spinner =====

    private fun setupSpinner() {
        refreshSpinner(initial = true)
        binding.spinnerProfile.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                if (position != activeIdx) {
                    activeIdx = position
                    setSelectedWidget(null)
                    applyCurrentToCanvas()
                    refreshSliders()
                }
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }
    }

    private fun refreshSpinner(initial: Boolean = false) {
        val adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_dropdown_item,
            workingProfiles.map { it.name },
        )
        binding.spinnerProfile.adapter = adapter
        binding.spinnerProfile.setSelection(activeIdx, !initial)
    }

    // ===== Mode tabs =====

    private fun setupModeTabs() {
        binding.modeTabs.setOnCheckedChangeListener { _, id ->
            currentEditMode =
                if (id == binding.modeInGame.id) EditMode.InGame else EditMode.UiInteract
            setSelectedWidget(null)  // selection doesn't carry across modes
            updateModeVisibility()
            refreshSliders()
        }
    }

    private fun updateModeVisibility() {
        val showInGame = currentEditMode == EditMode.InGame
        inGameViews().forEach { it.visibility = if (showInGame) View.VISIBLE else View.GONE }
        binding.columnUiButtons.visibility = if (!showInGame) View.VISIBLE else View.GONE
    }

    // ===== Sliders =====

    private fun setupSliders() {
        binding.sliderLMargin.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(sb: SeekBar?, progress: Int, fromUser: Boolean) {
                if (!fromUser) return
                binding.txtLMarginValue.text = progress.toString()
                mutateMode { it.copy(leftOffsetDp = progress.toFloat()) }
                applyCurrentToCanvas()
            }
            override fun onStartTrackingTouch(sb: SeekBar?) {}
            override fun onStopTrackingTouch(sb: SeekBar?) {}
        })
        binding.sliderRMargin.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
            override fun onProgressChanged(sb: SeekBar?, progress: Int, fromUser: Boolean) {
                if (!fromUser) return
                binding.txtRMarginValue.text = progress.toString()
                mutateMode { it.copy(rightOffsetDp = progress.toFloat()) }
                applyCurrentToCanvas()
            }
            override fun onStartTrackingTouch(sb: SeekBar?) {}
            override fun onStopTrackingTouch(sb: SeekBar?) {}
        })
    }

    private fun refreshSliders() {
        val mode = currentMode()
        binding.sliderLMargin.progress = mode.leftOffsetDp.toInt().coerceIn(0, 120)
        binding.sliderRMargin.progress = mode.rightOffsetDp.toInt().coerceIn(0, 120)
        binding.txtLMarginValue.text = mode.leftOffsetDp.toInt().toString()
        binding.txtRMarginValue.text = mode.rightOffsetDp.toInt().toString()
    }

    // ===== Profile actions =====

    private fun setupActions() {
        binding.btnSave.setOnClickListener {
            store.saveAll(workingProfiles, workingProfiles[activeIdx].name)
            Toast.makeText(this, "已保存", Toast.LENGTH_SHORT).show()
            finish()
        }
        binding.btnCancel.setOnClickListener { finish() }
        binding.btnNewProfile.setOnClickListener { onNewProfile() }
        binding.btnRenameProfile.setOnClickListener { onRenameProfile() }
        binding.btnDeleteProfile.setOnClickListener { onDeleteProfile() }
        binding.btnResetLayout.setOnClickListener { onResetLayout() }
    }

    private fun onNewProfile() {
        showInputDialog(getString(R.string.editor_new_profile_dialog), prefill = "") { name ->
            if (name.isBlank()) return@showInputDialog
            if (workingProfiles.any { it.name == name }) {
                Toast.makeText(this, "名称已存在", Toast.LENGTH_SHORT).show()
                return@showInputDialog
            }
            val source = workingProfiles[activeIdx]
            workingProfiles.add(source.copy(name = name))
            activeIdx = workingProfiles.size - 1
            refreshSpinner()
        }
    }

    private fun onRenameProfile() {
        val current = workingProfiles[activeIdx]
        showInputDialog(getString(R.string.editor_rename_profile_dialog), prefill = current.name) { name ->
            if (name.isBlank() || name == current.name) return@showInputDialog
            if (workingProfiles.any { it.name == name }) {
                Toast.makeText(this, "名称已存在", Toast.LENGTH_SHORT).show()
                return@showInputDialog
            }
            workingProfiles[activeIdx] = current.copy(name = name)
            refreshSpinner()
        }
    }

    private fun onDeleteProfile() {
        if (workingProfiles.size <= 1) {
            Toast.makeText(this, R.string.editor_cannot_delete_last, Toast.LENGTH_SHORT).show()
            return
        }
        val current = workingProfiles[activeIdx]
        AlertDialog.Builder(this)
            .setMessage(getString(R.string.editor_delete_confirm, current.name))
            .setPositiveButton(android.R.string.ok) { _, _ ->
                workingProfiles.removeAt(activeIdx)
                if (activeIdx >= workingProfiles.size) activeIdx = workingProfiles.size - 1
                setSelectedWidget(null)
                refreshSpinner()
                applyCurrentToCanvas()
                refreshSliders()
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
    }

    private fun onResetLayout() {
        val current = workingProfiles[activeIdx]
        workingProfiles[activeIdx] = current.copy(
            inGame = DefaultLayouts.IN_GAME,
            uiMode = DefaultLayouts.UI_MODE,
        )
        setSelectedWidget(null)
        applyCurrentToCanvas()
        refreshSliders()
    }

    private fun showInputDialog(title: String, prefill: String, onResult: (String) -> Unit) {
        val edit = EditText(this).apply {
            setText(prefill)
            selectAll()
        }
        AlertDialog.Builder(this)
            .setTitle(title)
            .setView(edit)
            .setPositiveButton(android.R.string.ok) { _, _ ->
                onResult(edit.text.toString().trim())
            }
            .setNegativeButton(android.R.string.cancel, null)
            .show()
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
        binding.txtSelectedLabel.visibility = if (id != null) View.VISIBLE else View.GONE
        binding.txtSelectedLabel.text = id?.let { "已选: $it" } ?: ""
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
        binding.btnToggleToolbars.setOnClickListener {
            toolbarsCollapsed = !toolbarsCollapsed
            animateToolbars()
        }
    }

    private fun animateToolbars() {
        val topTarget = if (toolbarsCollapsed) -binding.toolbarTop.height.toFloat() else 0f
        val bottomTarget = if (toolbarsCollapsed) binding.toolbarBottom.height.toFloat() else 0f
        binding.toolbarTop.animate().translationY(topTarget).setDuration(180).start()
        binding.toolbarBottom.animate().translationY(bottomTarget).setDuration(180).start()
        binding.txtHint.animate().alpha(if (toolbarsCollapsed) 0f else 1f).setDuration(180).start()
    }

    // ===== Drag handling on each widget =====

    private fun attachWidgetEditListeners() {
        for ((id, view) in allWidgetMap()) {
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
                    val moved = (rawDx * rawDx + rawDy * rawDy) > (touchSlop * touchSlop)
                    if (moved) {
                        if (!didMove) {
                            didMove = true
                            // First movement → also select this widget
                            if (selectedId != id) setSelectedWidget(id)
                        }
                        val spec = currentSpec(id) ?: return@setOnTouchListener true
                        val edgeSign = if (spec.anchor.isStart()) 1f else -1f
                        val vertSign = if (spec.anchor.isTop()) 1f else -1f
                        val dxDp = rawDx / density
                        val dyDp = rawDy / density
                        val newEdge = (startEdge + dxDp * edgeSign).coerceAtLeast(0f)
                        val newVert = (startVert + dyDp * vertSign).coerceAtLeast(0f)
                        updateSpec(id) {
                            it.copy(edgeMarginDp = newEdge, verticalMarginDp = newVert)
                        }
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
        this == Anchor.TopStart || this == Anchor.TopEnd

    // ===== Widget maps =====

    private fun inGameWidgetMap(): Map<String, View> = mapOf(
        "joystick" to binding.joystick,
        "btn_sneak" to binding.btnSneak,
        "btn_sprint" to binding.btnSprint,
        "btn_lmb" to binding.btnLmb,
        "btn_rmb" to binding.btnRmb,
        "btn_jump" to binding.btnJump,
        "row_top_buttons" to binding.rowTopButtons,
        "hotbar" to binding.hotbar,
    )

    private fun uiModeWidgetMap(): Map<String, View> = mapOf(
        "column_ui_buttons" to binding.columnUiButtons,
    )

    private fun allWidgetMap(): Map<String, View> = inGameWidgetMap() + uiModeWidgetMap()

    private fun inGameViews(): List<View> = inGameWidgetMap().values.toList()
}
