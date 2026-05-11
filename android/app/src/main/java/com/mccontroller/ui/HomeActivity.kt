package com.mccontroller.ui

import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.EditText
import android.widget.PopupMenu
import androidx.activity.viewModels
import androidx.appcompat.app.AppCompatActivity
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.updatePadding
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
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
import com.mccontroller.databinding.ActivityHomeBinding
import com.mccontroller.databinding.DialogAddHostBinding
import com.mccontroller.net.ConnectivityProbe
import com.mccontroller.net.DiscoveryClient
import com.mccontroller.net.Protocol
import com.mccontroller.ui.adapter.HostListAdapter
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import java.util.regex.Pattern

/**
 * Main entry. Lists hosts (USB shortcut + saved + LAN-discovered),
 * connects on tap (after a TCP reachability probe), and offers a manual
 * "Add host" action. Settings live behind the toolbar cog.
 *
 * Designed around a ViewModel so the DiscoveryClient survives config
 * changes (e.g. dark-mode flip) without restarting the UDP socket.
 */
class HomeActivity : AppCompatActivity() {

    private lateinit var binding: ActivityHomeBinding
    private val viewModel: HomeViewModel by viewModels()
    private lateinit var adapter: HostListAdapter

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        binding = ActivityHomeBinding.inflate(layoutInflater)
        setContentView(binding.root)
        applyEdgeToEdgeInsets()

        adapter = HostListAdapter(
            onHostClick = ::onHostClick,
            onHostOverflow = ::onHostOverflow,
            onUsbClick = ::onUsbClick,
            isHostConnecting = { viewModel.connectingKey.value == it.key },
        )
        binding.list.adapter = adapter
        binding.list.layoutManager = LinearLayoutManager(this)
        binding.list.itemAnimator = null   // ListAdapter handles animations; suppress flicker

        binding.fabAdd.setOnClickListener { showAddHostDialog() }
        binding.toolbar.setOnMenuItemClickListener { item ->
            when (item.itemId) {
                R.id.action_settings -> {
                    startActivity(Intent(this, SettingsActivity::class.java))
                    true
                }
                else -> false
            }
        }

        viewModel.start(this)

        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                combine(viewModel.items, viewModel.connectingKey) { items, _ -> items }
                    .collect { adapter.submitList(it) }
            }
        }
    }

    override fun onDestroy() {
        // ViewModel handles teardown via onCleared.
        super.onDestroy()
    }

    private fun applyEdgeToEdgeInsets() {
        ViewCompat.setOnApplyWindowInsetsListener(binding.appBar) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            v.updatePadding(top = bars.top)
            insets
        }
        ViewCompat.setOnApplyWindowInsetsListener(binding.list) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            // List bottom inset = system nav inset + extra for FAB clearance
            v.updatePadding(
                left = bars.left + dp(16),
                right = bars.right + dp(16),
                bottom = bars.bottom + dp(96),
            )
            insets
        }
        ViewCompat.setOnApplyWindowInsetsListener(binding.fabAdd) { v, insets ->
            val bars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
            (v.layoutParams as android.view.ViewGroup.MarginLayoutParams).apply {
                bottomMargin = bars.bottom + dp(16)
                rightMargin = bars.right + dp(16)
            }
            v.requestLayout()
            insets
        }
    }

    // -------------------------------------------------------------- click handlers

    private fun onUsbClick() {
        connectAndLaunch(
            ip = "127.0.0.1",
            port = Protocol.DEFAULT_PORT,
            isUsbMode = true,
            savedHostId = null,
            keyForBusyIndicator = HostListItem.UsbShortcut.key,
            displayName = getString(R.string.home_usb_label),
        )
    }

    private fun onHostClick(item: HostListItem) {
        val (ip, port, savedId, name) = when (item) {
            is HostListItem.Saved -> HostTarget(item.ip, item.port, item.saved.id, item.name)
            is HostListItem.Discovered -> HostTarget(item.ip, item.port, null, item.name)
            else -> return
        }
        connectAndLaunch(
            ip = ip,
            port = port,
            isUsbMode = false,
            savedHostId = savedId,
            keyForBusyIndicator = item.key,
            displayName = name,
        )
    }

    private fun onHostOverflow(item: HostListItem, anchor: View) {
        val saved = (item as? HostListItem.Saved)?.saved ?: return
        val popup = PopupMenu(this, anchor)
        popup.menu.add(0, MENU_RENAME, 0, R.string.hostmenu_rename)
        popup.menu.add(0, MENU_REMOVE, 1, R.string.hostmenu_remove)
        popup.setOnMenuItemClickListener {
            when (it.itemId) {
                MENU_RENAME -> { showRenameDialog(saved); true }
                MENU_REMOVE -> { showRemoveDialog(saved); true }
                else -> false
            }
        }
        popup.show()
    }

    // --------------------------------------------------------------- connection

    private fun connectAndLaunch(
        ip: String,
        port: Int,
        isUsbMode: Boolean,
        savedHostId: String?,
        keyForBusyIndicator: String,
        displayName: String,
    ) {
        if (viewModel.connectingKey.value != null) return       // de-bounce double taps
        viewModel.connectingKey.value = keyForBusyIndicator

        lifecycleScope.launch {
            val msg = getString(R.string.home_connecting, displayName)
            val bar = Snackbar.make(binding.root, msg, Snackbar.LENGTH_INDEFINITE).also { it.show() }

            val result = ConnectivityProbe.probe(ip, port)
            bar.dismiss()
            viewModel.connectingKey.value = null

            when (result) {
                ConnectivityProbe.Result.Ok -> {
                    val intent = Intent(this@HomeActivity, ControllerActivity::class.java).apply {
                        putExtra(ControllerActivity.EXTRA_IP, ip)
                        putExtra(ControllerActivity.EXTRA_PORT, port)
                        putExtra(ControllerActivity.EXTRA_USB_MODE, isUsbMode)
                        savedHostId?.let { putExtra(ControllerActivity.EXTRA_SAVED_HOST_ID, it) }
                    }
                    startActivity(intent)
                }
                is ConnectivityProbe.Result.Failed -> {
                    Snackbar.make(
                        binding.root,
                        getString(R.string.home_connect_failed, displayName),
                        Snackbar.LENGTH_LONG,
                    ).show()
                }
            }
        }
    }

    // -------------------------------------------------------------- dialogs

    private fun showAddHostDialog() {
        val dlgBinding = DialogAddHostBinding.inflate(layoutInflater)
        val dlg = MaterialAlertDialogBuilder(this)
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
        val edit = EditText(this).apply {
            setText(host.name)
            setSelection(text.length)
        }
        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.hostmenu_rename)
            .setView(edit)
            .setNegativeButton(R.string.dialog_cancel, null)
            .setPositiveButton(R.string.dialog_ok) { _, _ ->
                viewModel.hostStore.rename(host.id, edit.text.toString().trim())
            }
            .show()
    }

    private fun showRemoveDialog(host: SavedHost) {
        MaterialAlertDialogBuilder(this)
            .setTitle(R.string.hostmenu_remove)
            .setMessage(getString(R.string.hostmenu_remove_confirm, host.name))
            .setNegativeButton(R.string.hostmenu_remove_no, null)
            .setPositiveButton(R.string.hostmenu_remove_yes) { _, _ ->
                viewModel.hostStore.delete(host.id)
            }
            .show()
    }

    // -------------------------------------------------------------- helpers

    private data class HostTarget(val ip: String, val port: Int, val savedId: String?, val name: String)

    private fun dp(v: Int): Int = (v * resources.displayMetrics.density).toInt()

    companion object {
        private const val MENU_RENAME = 1
        private const val MENU_REMOVE = 2

        private val IPV4 = Pattern.compile(
            "^(25[0-5]|2[0-4]\\d|[01]?\\d?\\d)" +
                "(\\.(25[0-5]|2[0-4]\\d|[01]?\\d?\\d)){3}$",
        )

        private fun isValidIpv4(s: String): Boolean = IPV4.matcher(s).matches()
    }
}

/**
 * Holds the DiscoveryClient + HostRepository across config changes so
 * the UDP listener doesn't tear down on dark-mode flips. Exposes the
 * combined item stream and a single "host currently connecting" key.
 *
 * The discovery socket is created lazily on first [start] so unit tests
 * that don't need it (or that haven't called start) don't open ports.
 */
class HomeViewModel : ViewModel() {

    lateinit var hostStore: HostStore
        private set
    private var discovery: DiscoveryClient? = null

    val connectingKey: MutableStateFlow<String?> = MutableStateFlow(null)

    private val readyFlag = MutableStateFlow(false)

    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    val items: StateFlow<List<HostListItem>> =
        readyFlag.flatMapLatest { ready ->
            if (!ready) flow<List<HostListItem>> { emit(emptyList()) }
            else HostRepository(hostStore, discovery!!).items
        }.stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    fun start(host: AppCompatActivity) {
        if (readyFlag.value) return
        hostStore = HostStore.get(host.applicationContext)
        discovery = DiscoveryClient(host.applicationContext).also { it.start(viewModelScope) }
        readyFlag.value = true
    }

    override fun onCleared() {
        discovery?.stop()
        super.onCleared()
    }
}
