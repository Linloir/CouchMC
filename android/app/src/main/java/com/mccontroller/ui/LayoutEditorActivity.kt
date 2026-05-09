package com.mccontroller.ui

import android.os.Bundle
import android.view.MotionEvent
import android.view.View
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
import kotlin.math.sqrt

/**
 * Layout editor: drag-to-move + pinch-to-resize each widget per mode,
 * manage multiple named profiles, and adjust global L/R margin offsets.
 *
 * Edit gestures override the widgets' normal behavior (joystick doesn't
 * drive WASD here, hotbar doesn't trigger drop, etc.) — `setOnTouchListener`
 * on each widget pre-empts its `onTouchEvent` and consumes the gesture.
 */
class LayoutEditorActivity : AppCompatActivity() {

    private lateinit var binding: ActivityLayoutEditorBinding
    private lateinit var store: ProfileStore

    private val workingProfiles = mutableListOf<LayoutProfile>()
    private var activeIdx = 0
    private var currentEditMode: EditMode = EditMode.InGame

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

        store = ProfileStore(this)
        val (loaded, activeName) = store.loadAll()
        workingProfiles.addAll(loaded)
        activeIdx = workingProfiles.indexOfFirst { it.name == activeName }.coerceAtLeast(0)

        setupSpinner()
        setupModeTabs()
        setupSliders()
        setupActions()
        attachWidgetEditListeners()

        applyCurrentToCanvas()
        updateModeVisibility()
        refreshSliders()
    }

    // ===== Profile spinner =====

    private fun setupSpinner() {
        refreshSpinner(initial = true)
        binding.spinnerProfile.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                if (position != activeIdx) {
                    activeIdx = position
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

    // ===== Action buttons =====

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
            // New profile copies the active one as a starting point.
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

    // ===== Drag / pinch listeners =====

    private fun attachWidgetEditListeners() {
        for ((id, view) in inGameWidgetMap() + uiModeWidgetMap()) {
            attachListener(id, view)
        }
    }

    private fun attachListener(id: String, view: View) {
        var startX = 0f
        var startY = 0f
        var startEdge = 0f
        var startVert = 0f
        var startWidth = 0f
        var startHeight = 0f
        var startDistance = 0f
        var resizeMode = false

        val density = resources.displayMetrics.density

        view.setOnTouchListener { _, event ->
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    val spec = currentSpec(id) ?: return@setOnTouchListener false
                    startX = event.rawX
                    startY = event.rawY
                    startEdge = spec.edgeMarginDp
                    startVert = spec.verticalMarginDp
                    startWidth = spec.widthDp
                    startHeight = spec.heightDp
                    resizeMode = false
                }
                MotionEvent.ACTION_POINTER_DOWN -> {
                    if (event.pointerCount >= 2 && id in DefaultLayouts.RESIZABLE_IDS) {
                        startDistance = pointerDistance(event)
                        // Re-anchor size baseline to current spec at pinch start.
                        currentSpec(id)?.let {
                            startWidth = it.widthDp
                            startHeight = it.heightDp
                        }
                        resizeMode = true
                    }
                }
                MotionEvent.ACTION_MOVE -> {
                    if (resizeMode && event.pointerCount >= 2 &&
                        id in DefaultLayouts.RESIZABLE_IDS && startDistance > 0
                    ) {
                        val curDist = pointerDistance(event)
                        val scale = curDist / startDistance
                        val newW = (startWidth * scale).coerceIn(40f, 480f)
                        // For square buttons, keep 1:1; for hotbar/joystick, scale H by same factor.
                        val newH = if (startHeight > 0)
                            (startHeight * scale).coerceIn(30f, 480f)
                        else 0f
                        updateSpec(id) { it.copy(widthDp = newW, heightDp = newH) }
                    } else if (!resizeMode) {
                        val spec = currentSpec(id) ?: return@setOnTouchListener false
                        val dxDp = (event.rawX - startX) / density
                        val dyDp = (event.rawY - startY) / density
                        val edgeSign = if (spec.anchor.isStart()) 1f else -1f
                        val vertSign = if (spec.anchor.isTop()) 1f else -1f
                        val newEdge = (startEdge + dxDp * edgeSign).coerceAtLeast(0f)
                        val newVert = (startVert + dyDp * vertSign).coerceAtLeast(0f)
                        updateSpec(id) {
                            it.copy(edgeMarginDp = newEdge, verticalMarginDp = newVert)
                        }
                    }
                }
                MotionEvent.ACTION_POINTER_UP -> {
                    if (event.pointerCount <= 2) {
                        resizeMode = false
                        // Reset drag baseline if a finger was lifted mid-gesture.
                        startX = event.rawX
                        startY = event.rawY
                        currentSpec(id)?.let {
                            startEdge = it.edgeMarginDp
                            startVert = it.verticalMarginDp
                        }
                    }
                }
                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    resizeMode = false
                }
            }
            true  // consume; pre-empts the widget's normal onTouchEvent
        }
    }

    private fun pointerDistance(e: MotionEvent): Float {
        if (e.pointerCount < 2) return 0f
        val dx = e.getX(0) - e.getX(1)
        val dy = e.getY(0) - e.getY(1)
        return sqrt(dx * dx + dy * dy)
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
        // Apply the new spec to the actual view immediately.
        val view = inGameWidgetMap()[id] ?: uiModeWidgetMap()[id] ?: return
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
        "row_sneak_sprint" to binding.rowSneakSprint,
        "btn_lmb" to binding.btnLmb,
        "btn_rmb" to binding.btnRmb,
        "btn_jump" to binding.btnJump,
        "row_top_buttons" to binding.rowTopButtons,
        "hotbar" to binding.hotbar,
    )

    private fun uiModeWidgetMap(): Map<String, View> = mapOf(
        "column_ui_buttons" to binding.columnUiButtons,
    )

    private fun inGameViews(): List<View> = inGameWidgetMap().values.toList()
}
