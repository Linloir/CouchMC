package com.mccontroller.ui

import android.content.Context
import android.text.InputType
import android.view.LayoutInflater
import androidx.annotation.StringRes
import com.google.android.material.dialog.MaterialAlertDialogBuilder
import com.mccontroller.R
import com.mccontroller.databinding.DialogTextInputBinding

/**
 * Shared single-text-field MaterialAlertDialog used for renames, the
 * port-edit dialog, and the "New profile name" prompt. Centralised so
 * every text-input dialog in the app uses the same Material 3 outlined
 * text field; raw [android.widget.EditText] looked out of place on a
 * theme that's otherwise fully M3.
 *
 * The validation hook ([validate]) returns a non-null error string to
 * keep the dialog open with that string painted under the field, or
 * null to accept and close.
 */
object TextInputDialogs {

    fun show(
        context: Context,
        @StringRes titleRes: Int,
        @StringRes hintRes: Int,
        prefill: String = "",
        inputType: Int = InputType.TYPE_CLASS_TEXT,
        @StringRes positiveRes: Int = R.string.dialog_ok,
        validate: (String) -> String? = { null },
        onConfirm: (String) -> Unit,
    ) {
        val binding = DialogTextInputBinding.inflate(LayoutInflater.from(context))
        binding.til.setHint(hintRes)
        binding.edt.inputType = inputType
        binding.edt.setText(prefill)
        binding.edt.setSelection(binding.edt.text?.length ?: 0)

        val dialog = MaterialAlertDialogBuilder(context)
            .setTitle(titleRes)
            .setView(binding.root)
            .setNegativeButton(R.string.dialog_cancel, null)
            .setPositiveButton(positiveRes, null)   // wired below so we can keep dialog open on validation failure
            .create()

        dialog.setOnShowListener {
            dialog.getButton(androidx.appcompat.app.AlertDialog.BUTTON_POSITIVE)
                .setOnClickListener {
                    val value = binding.edt.text?.toString()?.trim().orEmpty()
                    val err = validate(value)
                    if (err == null) {
                        onConfirm(value)
                        dialog.dismiss()
                    } else {
                        binding.til.error = err
                    }
                }
            // Live-clear the error when the user starts typing again.
            binding.edt.doAfterTextChanged { binding.til.error = null }
        }
        dialog.show()
    }

    // ----- tiny extension to avoid pulling in the whole core-ktx TextWatcher dependency -----
    private inline fun com.google.android.material.textfield.TextInputEditText.doAfterTextChanged(
        crossinline block: (String) -> Unit,
    ) {
        addTextChangedListener(object : android.text.TextWatcher {
            override fun beforeTextChanged(s: CharSequence?, start: Int, count: Int, after: Int) {}
            override fun onTextChanged(s: CharSequence?, start: Int, before: Int, count: Int) {}
            override fun afterTextChanged(s: android.text.Editable?) { block(s?.toString().orEmpty()) }
        })
    }
}
