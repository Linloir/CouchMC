package com.mccontroller.ui

import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.TextView
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import androidx.fragment.app.Fragment
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.materialswitch.MaterialSwitch
import com.mccontroller.BuildConfig
import com.mccontroller.R
import com.mccontroller.core.AppSettings
import com.mccontroller.core.ButtonBindingRegistry
import com.mccontroller.core.HotbarSwipeMode
import com.mccontroller.core.LayoutProfile
import com.mccontroller.core.ProfileStore
import com.mccontroller.core.SettingsStore
import com.mccontroller.databinding.FragmentSettingsBinding
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

/**
 * App-wide preferences. Sections are pure Material 3 cards; backing
 * stores are [SettingsStore] (app-wide tunables) and [ProfileStore]
 * (layout profiles).
 */
class SettingsFragment : Fragment() {

    private var _binding: FragmentSettingsBinding? = null
    private val binding get() = _binding!!

    private lateinit var settingsStore: SettingsStore
    private lateinit var profileStore: ProfileStore

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        _binding = FragmentSettingsBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        applyEdgeToEdgeInsets()

        settingsStore = SettingsStore.get(requireContext())
        profileStore = ProfileStore(requireContext())

        wireLayoutShortcuts()
        wireProfileSection()
        wireHotbar()
        wireGestureSwitches()
        wireVolumePickers()
        wireMarginSliders()

        binding.txtVersion.text = getString(R.string.settings_version, BuildConfig.VERSION_NAME)

        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                settingsStore.settings.collectLatest { render(it) }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        renderActiveProfileButton()
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    // ----------------------------------------------------------- insets

    private fun applyEdgeToEdgeInsets() {
        ViewCompat.setOnApplyWindowInsetsListener(binding.appBar) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.updatePadding(top = bars.top)
            insets
        }
        ViewCompat.setOnApplyWindowInsetsListener(binding.scroller) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.updatePadding(left = bars.left, right = bars.right)
            insets
        }
    }

    // ---------------------------------------------------------- sections

    private fun wireLayoutShortcuts() {
        binding.rowLayoutInGame.root.findViewById<TextView>(R.id.nav_title)
            .setText(R.string.settings_layout_in_game)
        binding.rowLayoutInGame.root.findViewById<TextView>(R.id.nav_summary)
            .setText(R.string.settings_layout_in_game_summary)
        binding.rowLayoutInGame.root.setOnClickListener { launchEditor(LayoutEditorActivity.MODE_IN_GAME) }

        binding.rowLayoutUi.root.findViewById<TextView>(R.id.nav_title)
            .setText(R.string.settings_layout_ui)
        binding.rowLayoutUi.root.findViewById<TextView>(R.id.nav_summary)
            .setText(R.string.settings_layout_ui_summary)
        binding.rowLayoutUi.root.setOnClickListener { launchEditor(LayoutEditorActivity.MODE_UI) }
    }

    private fun launchEditor(mode: String) {
        val intent = Intent(requireContext(), LayoutEditorActivity::class.java).apply {
            putExtra(LayoutEditorActivity.EXTRA_MODE, mode)
        }
        startActivity(intent)
    }

    private fun wireProfileSection() {
        binding.btnActiveProfile.setOnClickListener { showActiveProfilePicker() }
        binding.btnProfileNew.setOnClickListener { showNewProfileDialog() }
        binding.btnProfileRename.setOnClickListener { showRenameProfileDialog() }
        binding.btnProfileDelete.setOnClickListener { showDeleteProfileDialog() }
    }

    private fun renderActiveProfileButton() {
        val (_, activeName) = profileStore.loadAll()
        binding.btnActiveProfile.text = activeName
    }

    private fun showActiveProfilePicker() {
        val (profiles, activeName) = profileStore.loadAll()
        val names = profiles.map { it.name }
        val currentIdx = names.indexOf(activeName).coerceAtLeast(0)
        MaterialAlertDialogBuilder(requireContext())
            .setTitle(R.string.settings_active_profile)
            .setSingleChoiceItems(names.toTypedArray(), currentIdx) { dlg, idx ->
                profileStore.setActive(names[idx])
                renderActiveProfileButton()
                dlg.dismiss()
            }
            .setNegativeButton(R.string.dialog_cancel, null)
            .show()
    }

    private fun showNewProfileDialog() {
        TextInputDialogs.show(
            context = requireContext(),
            titleRes = R.string.settings_new_profile_dialog,
            hintRes = R.string.settings_new_profile_dialog,
            validate = { name ->
                when {
                    name.isBlank() -> getString(R.string.settings_profile_name_required)
                    profileStore.loadAll().first.any { it.name == name } ->
                        getString(R.string.settings_profile_name_taken)
                    else -> null
                }
            },
        ) { name ->
            val (profiles, _) = profileStore.loadAll()
            val seed = profiles.firstOrNull() ?: return@show
            val copy = LayoutProfile(
                name = name,
                inGame = seed.inGame,
                uiMode = seed.uiMode,
                hotbarSwipeMode = seed.hotbarSwipeMode,
            )
            profileStore.saveAll(profiles + copy, activeName = name)
            renderActiveProfileButton()
        }
    }

    private fun showRenameProfileDialog() {
        val (_, activeName) = profileStore.loadAll()
        TextInputDialogs.show(
            context = requireContext(),
            titleRes = R.string.settings_rename_profile_dialog,
            hintRes = R.string.settings_rename_profile_dialog,
            prefill = activeName,
            validate = { newName ->
                val (profiles, current) = profileStore.loadAll()
                when {
                    newName.isBlank() -> getString(R.string.settings_profile_name_required)
                    newName == current -> null     // unchanged: just dismiss
                    profiles.any { it.name == newName } ->
                        getString(R.string.settings_profile_name_taken)
                    else -> null
                }
            },
        ) { newName ->
            val (profiles, current) = profileStore.loadAll()
            if (newName == current) return@show
            val updated = profiles.map { if (it.name == current) it.copy(name = newName) else it }
            profileStore.saveAll(updated, activeName = newName)
            renderActiveProfileButton()
        }
    }

    private fun showDeleteProfileDialog() {
        val (profiles, activeName) = profileStore.loadAll()
        if (profiles.size < 2) {
            MaterialAlertDialogBuilder(requireContext())
                .setMessage(R.string.settings_cannot_delete_last)
                .setPositiveButton(R.string.dialog_ok, null)
                .show()
            return
        }
        MaterialAlertDialogBuilder(requireContext())
            .setTitle(R.string.settings_delete_profile)
            .setMessage(getString(R.string.settings_delete_confirm, activeName))
            .setNegativeButton(R.string.dialog_cancel, null)
            .setPositiveButton(R.string.dialog_ok) { _, _ ->
                val remaining = profiles.filterNot { it.name == activeName }
                profileStore.saveAll(remaining, activeName = remaining.first().name)
                renderActiveProfileButton()
            }
            .show()
    }

    private fun wireHotbar() {
        binding.toggleHotbarMode.addOnButtonCheckedListener { _, checkedId, isChecked ->
            if (!isChecked) return@addOnButtonCheckedListener
            val mode = if (checkedId == R.id.btn_hotbar_precise) HotbarSwipeMode.Precise
            else HotbarSwipeMode.Relative
            settingsStore.update { it.copy(hotbarSwipeMode = mode) }
        }
    }

    private fun wireGestureSwitches() {
        // The <include>'s android:id (row_in_game_quick) overrides the
        // included layout root's own id (switch_row), so we can't
        // findViewById(R.id.switch_row) on it — the root IS the row.
        wireSwitchRow(
            row = binding.rowInGameQuick.root,
            switch = binding.rowInGameQuick.root.findViewById(R.id.switch_value),
            title = binding.rowInGameQuick.root.findViewById(R.id.switch_title),
            summary = binding.rowInGameQuick.root.findViewById(R.id.switch_summary),
            titleRes = R.string.settings_in_game_quick_clicks,
            summaryRes = R.string.settings_in_game_quick_clicks_summary,
            getValue = { settingsStore.current.inGameQuickClicks },
            setValue = { v -> settingsStore.update { it.copy(inGameQuickClicks = v) } },
        )
        wireSwitchRow(
            row = binding.rowUiQuick.root,
            switch = binding.rowUiQuick.root.findViewById(R.id.switch_value),
            title = binding.rowUiQuick.root.findViewById(R.id.switch_title),
            summary = binding.rowUiQuick.root.findViewById(R.id.switch_summary),
            titleRes = R.string.settings_ui_quick_clicks,
            summaryRes = R.string.settings_ui_quick_clicks_summary,
            getValue = { settingsStore.current.uiQuickClicks },
            setValue = { v -> settingsStore.update { it.copy(uiQuickClicks = v) } },
        )
    }

    private fun wireSwitchRow(
        row: View,
        switch: MaterialSwitch,
        title: TextView,
        summary: TextView,
        titleRes: Int,
        summaryRes: Int,
        getValue: () -> Boolean,
        setValue: (Boolean) -> Unit,
    ) {
        title.setText(titleRes)
        summary.setText(summaryRes)
        switch.isChecked = getValue()
        row.setOnClickListener {
            val newValue = !switch.isChecked
            switch.isChecked = newValue
            setValue(newValue)
        }
    }

    private fun wireVolumePickers() {
        wirePickerRow(
            row = binding.rowVolUp.root,
            title = binding.rowVolUp.root.findViewById(R.id.picker_title),
            value = binding.rowVolUp.root.findViewById(R.id.picker_value),
            titleRes = R.string.settings_volume_up,
            getValue = { settingsStore.current.volumeUpBinding },
            setValue = { v -> settingsStore.update { it.copy(volumeUpBinding = v) } },
        )
        wirePickerRow(
            row = binding.rowVolDown.root,
            title = binding.rowVolDown.root.findViewById(R.id.picker_title),
            value = binding.rowVolDown.root.findViewById(R.id.picker_value),
            titleRes = R.string.settings_volume_down,
            getValue = { settingsStore.current.volumeDownBinding },
            setValue = { v -> settingsStore.update { it.copy(volumeDownBinding = v) } },
        )
    }

    private fun wirePickerRow(
        row: View,
        title: TextView,
        value: TextView,
        titleRes: Int,
        getValue: () -> Int?,
        setValue: (Int?) -> Unit,
    ) {
        title.setText(titleRes)
        value.text = getString(ButtonBindingRegistry.labelResFor(getValue()))
        row.setOnClickListener { showBindingPicker(titleRes, getValue, setValue, value) }
    }

    private fun showBindingPicker(
        titleRes: Int,
        getCurrent: () -> Int?,
        setValue: (Int?) -> Unit,
        targetValueView: TextView,
    ) {
        val options = buildList<Pair<Int?, String>> {
            add(null to getString(R.string.binding_none))
            for (e in ButtonBindingRegistry.ALL) {
                add(e.buttonId to getString(e.labelResId))
            }
        }
        val labels = options.map { it.second }.toTypedArray()
        val currentIdx = options.indexOfFirst { it.first == getCurrent() }
            .coerceAtLeast(0)
        MaterialAlertDialogBuilder(requireContext())
            .setTitle(titleRes)
            .setSingleChoiceItems(labels, currentIdx) { dlg, idx ->
                val chosen = options[idx].first
                setValue(chosen)
                targetValueView.text = options[idx].second
                dlg.dismiss()
            }
            .setNegativeButton(R.string.dialog_cancel, null)
            .show()
    }

    private fun wireMarginSliders() {
        wireSliderRow(
            row = binding.rowLMargin.root,
            titleRes = R.string.settings_left_margin,
            getValue = { settingsStore.current.leftMarginOffsetDp },
            setValue = { v -> settingsStore.update { it.copy(leftMarginOffsetDp = v) } },
        )
        wireSliderRow(
            row = binding.rowRMargin.root,
            titleRes = R.string.settings_right_margin,
            getValue = { settingsStore.current.rightMarginOffsetDp },
            setValue = { v -> settingsStore.update { it.copy(rightMarginOffsetDp = v) } },
        )
    }

    private fun wireSliderRow(
        row: View,
        titleRes: Int,
        getValue: () -> Int,
        setValue: (Int) -> Unit,
    ) {
        val title = row.findViewById<TextView>(R.id.slider_title)
        val valueText = row.findViewById<TextView>(R.id.slider_value)
        val slider = row.findViewById<com.google.android.material.slider.Slider>(R.id.slider_value_slider)
        title.setText(titleRes)
        slider.value = getValue().toFloat().coerceIn(slider.valueFrom, slider.valueTo)
        valueText.text = getString(R.string.settings_margin_value_format, getValue())
        slider.addOnChangeListener { _, v, fromUser ->
            val intVal = v.toInt()
            valueText.text = getString(R.string.settings_margin_value_format, intVal)
            if (fromUser) setValue(intVal)
        }
    }

    // -------------------------------------------------------- render bind

    private fun render(s: AppSettings) {
        val checked = when (s.hotbarSwipeMode) {
            HotbarSwipeMode.Precise -> R.id.btn_hotbar_precise
            HotbarSwipeMode.Relative -> R.id.btn_hotbar_relative
        }
        binding.toggleHotbarMode.check(checked)
        binding.txtHotbarSummary.setText(
            when (s.hotbarSwipeMode) {
                HotbarSwipeMode.Precise -> R.string.settings_hotbar_mode_precise_summary
                HotbarSwipeMode.Relative -> R.string.settings_hotbar_mode_relative_summary
            },
        )

        binding.rowInGameQuick.root.findViewById<MaterialSwitch>(R.id.switch_value).isChecked =
            s.inGameQuickClicks
        binding.rowUiQuick.root.findViewById<MaterialSwitch>(R.id.switch_value).isChecked =
            s.uiQuickClicks

        binding.rowVolUp.root.findViewById<TextView>(R.id.picker_value).text =
            getString(ButtonBindingRegistry.labelResFor(s.volumeUpBinding))
        binding.rowVolDown.root.findViewById<TextView>(R.id.picker_value).text =
            getString(ButtonBindingRegistry.labelResFor(s.volumeDownBinding))

        renderActiveProfileButton()
    }
}
