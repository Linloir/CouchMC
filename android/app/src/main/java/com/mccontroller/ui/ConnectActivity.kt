package com.mccontroller.ui

import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.AdapterView
import android.widget.ArrayAdapter
import androidx.appcompat.app.AppCompatActivity
import com.mccontroller.core.ProfileStore
import com.mccontroller.databinding.ActivityConnectBinding
import com.mccontroller.net.Protocol

/**
 * Entry screen: enter PC IP/port, choose a saved layout profile, optionally
 * jump into the layout editor, then connect via WiFi or USB.
 *
 * The "USB" button auto-fills 127.0.0.1 because adb reverse forwards
 * localhost over the USB cable.
 */
class ConnectActivity : AppCompatActivity() {

    private lateinit var binding: ActivityConnectBinding
    private lateinit var profileStore: ProfileStore

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityConnectBinding.inflate(layoutInflater)
        setContentView(binding.root)

        profileStore = ProfileStore(this)

        val prefs = getSharedPreferences(PREFS, MODE_PRIVATE)
        binding.edtIp.setText(prefs.getString(KEY_LAST_IP, ""))

        binding.btnConnectWifi.setOnClickListener {
            val ip = binding.edtIp.text?.toString()?.trim().orEmpty()
            if (ip.isBlank()) {
                binding.txtStatus.text = "Please enter PC IP address"
                return@setOnClickListener
            }
            prefs.edit().putString(KEY_LAST_IP, ip).apply()
            launchController(ip, parsePort(), isUsbMode = false)
        }

        binding.btnConnectUsb.setOnClickListener {
            launchController("127.0.0.1", parsePort(), isUsbMode = true)
        }

        binding.btnEditLayout.setOnClickListener {
            startActivity(Intent(this, LayoutEditorActivity::class.java))
        }
    }

    override fun onResume() {
        super.onResume()
        // Refresh profile list each time we return (e.g., from editor).
        refreshProfileSpinner()
    }

    private fun refreshProfileSpinner() {
        val (profiles, activeName) = profileStore.loadAll()
        val names = profiles.map { it.name }
        val adapter = ArrayAdapter(
            this,
            android.R.layout.simple_spinner_dropdown_item,
            names,
        )
        binding.spinnerProfile.adapter = adapter
        val activeIdx = names.indexOf(activeName).coerceAtLeast(0)
        binding.spinnerProfile.setSelection(activeIdx, false)

        binding.spinnerProfile.onItemSelectedListener = object : AdapterView.OnItemSelectedListener {
            override fun onItemSelected(parent: AdapterView<*>?, view: View?, position: Int, id: Long) {
                val name = names.getOrNull(position) ?: return
                profileStore.setActive(name)
            }
            override fun onNothingSelected(parent: AdapterView<*>?) {}
        }
    }

    private fun parsePort(): Int =
        binding.edtPort.text?.toString()?.trim()?.toIntOrNull() ?: Protocol.DEFAULT_PORT

    private fun launchController(ip: String, port: Int, isUsbMode: Boolean) {
        val intent = Intent(this, ControllerActivity::class.java).apply {
            putExtra(EXTRA_IP, ip)
            putExtra(EXTRA_PORT, port)
            putExtra(EXTRA_USB_MODE, isUsbMode)
        }
        startActivity(intent)
    }

    companion object {
        const val EXTRA_IP = "ip"
        const val EXTRA_PORT = "port"
        const val EXTRA_USB_MODE = "usbMode"
        private const val PREFS = "connect"
        private const val KEY_LAST_IP = "last_ip"
    }
}
