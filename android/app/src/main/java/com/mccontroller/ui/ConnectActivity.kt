package com.mccontroller.ui

import android.content.Intent
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.mccontroller.databinding.ActivityConnectBinding
import com.mccontroller.net.Protocol

/**
 * Entry screen: enter PC IP/port, choose WiFi or USB mode, then launch the
 * controller activity. The "USB" button auto-fills 127.0.0.1 because adb
 * reverse forwards localhost over the USB cable.
 */
class ConnectActivity : AppCompatActivity() {

    private lateinit var binding: ActivityConnectBinding

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        binding = ActivityConnectBinding.inflate(layoutInflater)
        setContentView(binding.root)

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
