package com.mccontroller.core

import com.mccontroller.R
import com.mccontroller.net.Protocol

/**
 * Catalogue of all [Protocol.ButtonId] values plus their display strings.
 * Used by the volume-key binding picker in Settings, and anywhere else
 * that needs to render "what button is this?" in user-facing UI.
 *
 * Order in [ALL] is the order options appear in the picker — grouped by
 * conceptual category (mouse → movement → world → menu → hotbar).
 */
object ButtonBindingRegistry {

    data class Entry(val buttonId: Int, val labelResId: Int)

    val ALL: List<Entry> = listOf(
        Entry(Protocol.ButtonId.MOUSE_LEFT.toInt() and 0xff, R.string.binding_mouse_left),
        Entry(Protocol.ButtonId.MOUSE_RIGHT.toInt() and 0xff, R.string.binding_mouse_right),

        Entry(Protocol.ButtonId.JUMP.toInt() and 0xff, R.string.binding_jump),
        Entry(Protocol.ButtonId.SNEAK.toInt() and 0xff, R.string.binding_sneak),
        Entry(Protocol.ButtonId.SPRINT.toInt() and 0xff, R.string.binding_sprint),

        Entry(Protocol.ButtonId.INVENTORY.toInt() and 0xff, R.string.binding_inventory),
        Entry(Protocol.ButtonId.DROP.toInt() and 0xff, R.string.binding_drop),
        Entry(Protocol.ButtonId.SWAP_HAND.toInt() and 0xff, R.string.binding_swap_hand),
        Entry(Protocol.ButtonId.ESC.toInt() and 0xff, R.string.binding_esc),

        Entry(Protocol.ButtonId.HOTBAR_1.toInt() and 0xff, R.string.binding_hotbar_1),
        Entry(Protocol.ButtonId.HOTBAR_2.toInt() and 0xff, R.string.binding_hotbar_2),
        Entry(Protocol.ButtonId.HOTBAR_3.toInt() and 0xff, R.string.binding_hotbar_3),
        Entry(Protocol.ButtonId.HOTBAR_4.toInt() and 0xff, R.string.binding_hotbar_4),
        Entry(Protocol.ButtonId.HOTBAR_5.toInt() and 0xff, R.string.binding_hotbar_5),
        Entry(Protocol.ButtonId.HOTBAR_6.toInt() and 0xff, R.string.binding_hotbar_6),
        Entry(Protocol.ButtonId.HOTBAR_7.toInt() and 0xff, R.string.binding_hotbar_7),
        Entry(Protocol.ButtonId.HOTBAR_8.toInt() and 0xff, R.string.binding_hotbar_8),
        Entry(Protocol.ButtonId.HOTBAR_9.toInt() and 0xff, R.string.binding_hotbar_9),
    )

    fun labelResFor(buttonId: Int?): Int =
        if (buttonId == null) R.string.binding_none
        else ALL.firstOrNull { it.buttonId == buttonId }?.labelResId ?: R.string.binding_none
}
