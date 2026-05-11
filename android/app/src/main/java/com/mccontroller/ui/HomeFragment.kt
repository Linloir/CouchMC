package com.mccontroller.ui

import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.EditText
import android.widget.PopupMenu
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import androidx.fragment.app.Fragment
import androidx.fragment.app.viewModels
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.viewModelScope
import androidx.recyclerview.widget.LinearLayoutManager
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.google.android.material.snackbar.Snackbar
import com.mccontroller.R
import com.mccontroller.core.HostListItem
import com.mccontroller.core.HostRepository
import com.mccontroller.core.HostStore
import com.mccontroller.core.SavedHost
import com.mccontroller.databinding.DialogAddHostBinding
import com.mccontroller.databinding.FragmentHomeBinding
import com.mccontroller.net.ConnectivityProbe
import com.mccontroller.net.DiscoveryClient
import com.mccontroller.net.Protocol
import com.mccontroller.ui.adapter.HostListAdapter
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.util.regex.Pattern

/**
 * Hosts the list of saved + discovered PCs. Tapping a card runs a TCP
 * reachability probe, then transitions into [ControllerActivity] on
 * success. The system USB entry is auto-seeded by [HostStore] — it can
 * be renamed and have its port changed but never deleted.
 *
 * Add-host action lives in the top-app-bar (trailing icon). Settings is
 * reachable through the bottom navigation bar on [MainActivity].
 */
class HomeFragment : Fragment() {

    private var _binding: FragmentHomeBinding? = null
    private val binding get() = _binding!!

    private val viewModel: HomeViewModel by viewModels()
    private lateinit var adapter: HostListAdapter

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?,
    ): View {
        _binding = FragmentHomeBinding.inflate(inflater, container, false)
        return binding.root
    }

    override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
        super.onViewCreated(view, savedInstanceState)
        applyEdgeToEdgeInsets()

        adapter = HostListAdapter(
            onHostClick = ::onHostClick,
            onHostOverflow = ::onHostOverflow,
            isHostConnecting = { viewModel.connectingKey.value == it.key },
        )
        binding.list.adapter = adapter
        binding.list.layoutManager = LinearLayoutManager(requireContext())
        binding.list.itemAnimator = null

        binding.toolbar.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                R.id.action_add_host -> { showAddHostDialog(); true }
                else -> false
            }
        }

        viewModel.start(requireActivity().applicationContext)

        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                combine(viewModel.items, viewModel.connectingKey) { items, _ -> items }
                    .collect { adapter.submitList(it) }
            }
        }
    }

    override fun onDestroyView() {
        super.onDestroyView()
        _binding = null
    }

    private fun applyEdgeToEdgeInsets() {
        // The bottom nav owns the bottom inset (see MainActivity). We only
        // pad the top of the app bar so the toolbar isn't behind the
        // status bar / camera notch.
        ViewCompat.setOnApplyWindowInsetsListener(binding.appBar) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.updatePadding(top = bars.top)
            insets
        }
        ViewCompat.setOnApplyWindowInsetsListener(binding.list) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.updatePadding(
                left = bars.left,
                right = bars.right,
                bottom = dp(8),
            )
            insets
        }
    }

    // -------------------------------------------------------------- click handlers

    private fun onHostClick(item: HostListItem) {
        val target = when (item) {
            is HostListItem.Saved -> HostTarget(item.ip, item.port, item.saved.id, item.name, item.saved.isSystem)
            is HostListItem.Discovered -> HostTarget(item.ip, item.port, null, item.name, isUsb = false)
            else -> return
        }
        connectAndLaunch(target, key = item.key)
    }

    private fun onHostOverflow(item: HostListItem, anchor: View) {
        val saved = (item as? HostListItem.Saved)?.saved ?: return
        val popup = PopupMenu(requireContext(), anchor)
        popup.menu.add(0, MENU_RENAME, 0, R.string.hostmenu_rename)
        if (!saved.isSystem) popup.menu.add(0, MENU_PORT, 1, R.string.addhost_port)
        if (!saved.isSystem) popup.menu.add(0, MENU_REMOVE, 2, R.string.hostmenu_remove)
        else popup.menu.add(0, MENU_PORT, 1, R.string.addhost_port)
        popup.setOnMenuItemClickListener {
            when (it.itemId) {
                MENU_RENAME -> { showRenameDialog(saved); true }
                MENU_PORT -> { showEditPortDialog(saved); true }
                MENU_REMOVE -> { showRemoveDialog(saved); true }
                else -> false
            }
        }
        popup.show()
    }

    // --------------------------------------------------------------- connection

    private fun connectAndLaunch(target: HostTarget, key: String) {
        if (viewModel.connectingKey.value != null) return
        viewModel.connectingKey.value = key

        viewLifecycleOwner.lifecycleScope.launch {
            val msg = getString(R.string.home_connecting, target.name)
            val bar = Snackbar.make(binding.root, msg, Snackbar.LENGTH_INDEFINITE).also { it.show() }

            val result = ConnectivityProbe.probe(target.ip, target.port)
            bar.dismiss()
            viewModel.connectingKey.value = null

            when (result) {
                ConnectivityProbe.Result.Ok -> {
                    val intent = Intent(requireContext(), ControllerActivity::class.java).apply {
                        putExtra(ControllerActivity.EXTRA_IP, target.ip)
                        putExtra(ControllerActivity.EXTRA_PORT, target.port)
                        putExtra(ControllerActivity.EXTRA_USB_MODE, target.isUsb)
                        target.savedId?.let { putExtra(ControllerActivity.EXTRA_SAVED_HOST_ID, it) }
                    }
                    startActivity(intent)
                }
                is ConnectivityProbe.Result.Failed -> {
                    Snackbar.make(
                        binding.root,
                        getString(R.string.home_connect_failed, target.name),
                        Snackbar.LENGTH_LONG,
                    ).show()
                }
            }
        }
    }

    // -------------------------------------------------------------- dialogs

    private fun showAddHostDialog() {
        val dlgBinding = DialogAddHostBinding.inflate(layoutInflater)
        val dlg = MaterialAlertDialogBuilder(requireContext())
            .setTitle(R.string.addhost_title)
            .setView(dlgBinding.root)
            .setNegativeButton(R.string.addhost_cancel, null)
            .setPositiveButton(R.string.addhost_save, null)
            .create()

        dlg.setOnShowListener {
            dlg.getButton(androidx.appcompat.app.AlertDialog.BUTTON_POSITIVE).setOnClickListener {
                val ip = dlgBinding.edtIp.text?.toString()?.trim().orEmpty()
                val portStr = dlgBinding.edtPort.text?.toString()?.trim().orEmpty()
                val port = portStr.toIntOrNull()
                if (!isValidIpv4(ip)) {
                    dlgBinding.tilIp.error = getString(R.string.addhost_invalid_ip); return@setOnClickListener
                }
                if (port == null || port !in 1..65535) {
                    dlgBinding.tilPort.error = getString(R.string.addhost_invalid_port); return@setOnClickListener
                }
                val name = dlgBinding.edtName.text?.toString()?.trim().orEmpty()
                viewModel.hostStore.upsert(name, ip, port)
                dlg.dismiss()
            }
        }
        dlg.show()
    }

    private fun showRenameDialog(host: SavedHost) {
        val edit = EditText(requireContext()).apply {
            setText(host.name)
            setSelection(text.length)
        }
        MaterialAlertDialogBuilder(requireContext())
            .setTitle(R.string.hostmenu_rename)
            .setView(edit)
            .setNegativeButton(R.string.dialog_cancel, null)
            .setPositiveButton(R.string.dialog_ok) { _, _ ->
                viewModel.hostStore.rename(host.id, edit.text.toString().trim())
            }
            .show()
    }

    private fun showEditPortDialog(host: SavedHost) {
        val edit = EditText(requireContext()).apply {
            inputType = android.text.InputType.TYPE_CLASS_NUMBER
            setText(host.port.toString())
            setSelection(text.length)
        }
        MaterialAlertDialogBuilder(requireContext())
            .setTitle(R.string.addhost_port)
            .setView(edit)
            .setNegativeButton(R.string.dialog_cancel, null)
            .setPositiveButton(R.string.dialog_ok) { _, _ ->
                val port = edit.text.toString().trim().toIntOrNull() ?: return@setPositiveButton
                if (port !in 1..65535) return@setPositiveButton
                // Re-save with same name + ip + new port. For the system USB
                // host this also gives the user a way to track a non-default
                // PC port; the singleton-id semantics keep it pinned.
                viewModel.hostStore.changePort(host.id, port)
            }
            .show()
    }

    private fun showRemoveDialog(host: SavedHost) {
        if (host.isSystem) return
        MaterialAlertDialogBuilder(requireContext())
            .setTitle(R.string.hostmenu_remove)
            .setMessage(getString(R.string.hostmenu_remove_confirm, host.name))
            .setNegativeButton(R.string.hostmenu_remove_no, null)
            .setPositiveButton(R.string.hostmenu_remove_yes) { _, _ ->
                viewModel.hostStore.delete(host.id)
            }
            .show()
    }

    // -------------------------------------------------------------- helpers

    private data class HostTarget(
        val ip: String,
        val port: Int,
        val savedId: String?,
        val name: String,
        val isUsb: Boolean,
    )

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    companion object {
        private const val MENU_RENAME = 1
        private const val MENU_PORT = 2
        private const val MENU_REMOVE = 3

        private val IPV4 = Pattern.compile(
            "^(25[0-5]|2[0-4]\\d|[01]?\\d?\\d)" +
                "(\\.(25[0-5]|2[0-4]\\d|[01]?\\d?\\d)){3}$",
        )

        private fun isValidIpv4(s: String): Boolean = IPV4.matcher(s).matches()
    }
}

/**
 * Survives config changes so the DiscoveryClient keeps running across
 * a dark-mode flip. Exposes the merged item stream + which host is
 * currently being probed.
 */
class HomeViewModel : ViewModel() {

    lateinit var hostStore: HostStore
        private set
    private var discovery: DiscoveryClient? = null

    val connectingKey: MutableStateFlow<String?> = MutableStateFlow(null)

    private val readyFlag = MutableStateFlow(false)

    @OptIn(ExperimentalCoroutinesApi::class)
    val items: StateFlow<List<HostListItem>> =
        readyFlag.flatMapLatest { ready ->
            if (!ready) flow<List<HostListItem>> { emit(emptyList()) }
            else HostRepository(hostStore, discovery!!).items
        }.stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    fun start(appContext: android.content.Context) {
        if (readyFlag.value) return
        hostStore = HostStore.get(appContext)
        discovery = DiscoveryClient(appContext).also { it.start(viewModelScope) }
        readyFlag.value = true
    }

    override fun onCleared() {
        discovery?.stop()
        super.onCleared()
    }
}
