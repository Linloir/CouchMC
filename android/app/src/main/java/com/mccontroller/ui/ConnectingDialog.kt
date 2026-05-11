package com.mccontroller.ui

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import androidx.appcompat.app.AlertDialog
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.mccontroller.R
import com.mccontroller.databinding.DialogConnectingBinding

/**
 * Connection-progress modal. Single dialog re-skinned in place across
 * states — the user sees one continuous surface, never a brief disappear
 * + re-appear sequence.
 *
 * Two states:
 *   • Loading — spinner + "Connecting…" status + a primary Cancel button.
 *     Back-press / outside-touch dismissal blocked; the only way out is
 *     pressing Cancel (which calls [onCancel] so the host coroutine can
 *     stop its probe).
 *   • Failure — error icon + reason text + a primary Close button.
 *     Back-press / outside-touch now dismiss normally.
 *
 * Success doesn't need its own state — the caller simply [dismiss]es the
 * dialog before transitioning into ControllerActivity.
 */
class ConnectingDialog(
    context: Context,
    private val hostName: String,
    private val subtitle: String,
) {

    private val binding = DialogConnectingBinding.inflate(LayoutInflater.from(context))
    private val dialog: AlertDialog = MaterialAlertDialogBuilder(context)
        .setView(binding.root)
        .setCancelable(false)
        .create()

    /** Called when the user presses the action button in the loading state. */
    var onCancel: (() -> Unit)? = null

    init {
        binding.title.text = hostName
        binding.subtitle.text = subtitle
        showLoading(context)
    }

    fun show() {
        dialog.show()
    }

    fun dismiss() {
        if (dialog.isShowing) dialog.dismiss()
    }

    /** Returns to the loading visual after a failure → user-pressed-retry path. */
    fun showLoading(context: Context = binding.root.context) {
        binding.progress.visibility = View.VISIBLE
        binding.errorIcon.visibility = View.GONE
        binding.statusText.text = context.getString(R.string.home_connecting_label)
        binding.btnAction.setText(R.string.dialog_cancel)
        binding.btnAction.setOnClickListener { onCancel?.invoke() }
        dialog.setCancelable(false)
        dialog.setCanceledOnTouchOutside(false)
    }

    fun showFailure(reason: String) {
        val ctx = binding.root.context
        binding.progress.visibility = View.GONE
        binding.errorIcon.visibility = View.VISIBLE
        binding.statusText.text = ctx.getString(R.string.home_connect_failed_reason, reason)
        binding.btnAction.setText(R.string.dialog_close)
        binding.btnAction.setOnClickListener { dismiss() }
        dialog.setCancelable(true)
        dialog.setCanceledOnTouchOutside(true)
    }
}
