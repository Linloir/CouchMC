package com.mccontroller.ui.adapter

import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.core.widget.ImageViewCompat
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.card.MaterialCardView
import com.mccontroller.R
import com.mccontroller.core.HostListItem

/**
 * Multi-view-type adapter for the home screen. Supported types:
 *
 *   • [HostListItem.Header] — section title (Saved / On this network)
 *   • [HostListItem.Empty]  — placeholder when a section has 0 rows
 *   • [HostListItem.UsbShortcut] — top-of-list quick-connect card
 *   • [HostListItem.Saved] — saved host row, with optional live indicator
 *   • [HostListItem.Discovered] — discovered-only host row
 *
 * Keyed DiffUtil on [HostListItem.key] keeps RecyclerView animations
 * stable across section reshuffles.
 */
class HostListAdapter(
    private val onHostClick: (HostListItem) -> Unit,
    private val onHostOverflow: (HostListItem, View) -> Unit,
    private val onUsbClick: () -> Unit,
    private val isHostConnecting: (HostListItem) -> Boolean,
) : ListAdapter<HostListItem, RecyclerView.ViewHolder>(DIFF) {

    override fun getItemViewType(position: Int): Int = when (getItem(position)) {
        is HostListItem.Header -> TYPE_HEADER
        is HostListItem.Empty -> TYPE_EMPTY
        is HostListItem.UsbShortcut -> TYPE_USB
        is HostListItem.Saved -> TYPE_HOST
        is HostListItem.Discovered -> TYPE_HOST
    }

    override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): RecyclerView.ViewHolder {
        val inflater = LayoutInflater.from(parent.context)
        return when (viewType) {
            TYPE_HEADER -> HeaderViewHolder(inflater.inflate(R.layout.item_section_header, parent, false))
            TYPE_EMPTY -> EmptyViewHolder(inflater.inflate(R.layout.item_empty, parent, false))
            else -> HostViewHolder(inflater.inflate(R.layout.item_host, parent, false))
        }
    }

    override fun onBindViewHolder(holder: RecyclerView.ViewHolder, position: Int) {
        when (val item = getItem(position)) {
            is HostListItem.Header -> (holder as HeaderViewHolder).bind(item)
            is HostListItem.Empty -> (holder as EmptyViewHolder).bind(item)
            is HostListItem.UsbShortcut -> (holder as HostViewHolder).bindUsb(item)
            is HostListItem.Saved -> (holder as HostViewHolder).bindSaved(item)
            is HostListItem.Discovered -> (holder as HostViewHolder).bindDiscovered(item)
        }
    }

    // -- ViewHolders ----------------------------------------------------------

    private class HeaderViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val title: TextView = view as TextView
        fun bind(item: HostListItem.Header) {
            title.setText(item.titleResId)
        }
    }

    private class EmptyViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val message: TextView = view as TextView
        fun bind(item: HostListItem.Empty) {
            message.setText(item.messageResId)
        }
    }

    private inner class HostViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val card: MaterialCardView = view as MaterialCardView
        private val icon: ImageView = view.findViewById(R.id.host_icon)
        private val name: TextView = view.findViewById(R.id.host_name)
        private val subtitle: TextView = view.findViewById(R.id.host_subtitle)
        private val statusRow: LinearLayout = view.findViewById(R.id.host_status_row)
        private val statusDot: ImageView = view.findViewById(R.id.host_status_dot)
        private val statusLabel: TextView = view.findViewById(R.id.host_status_label)
        private val overflow: ImageButton = view.findViewById(R.id.host_overflow)
        private val progress: ProgressBar = view.findViewById(R.id.host_progress)

        fun bindUsb(item: HostListItem.UsbShortcut) {
            val ctx = card.context
            icon.setImageResource(R.drawable.ic_usb)
            name.text = ctx.getString(R.string.home_usb_label)
            subtitle.text = ctx.getString(R.string.home_usb_subtitle)
            statusRow.visibility = View.GONE
            overflow.visibility = View.GONE
            progress.visibility = if (isHostConnecting(item)) View.VISIBLE else View.GONE
            card.setOnClickListener { onUsbClick() }
            card.setOnLongClickListener(null)
        }

        fun bindSaved(item: HostListItem.Saved) {
            val ctx = card.context
            icon.setImageResource(R.drawable.ic_computer)
            name.text = item.name
            subtitle.text = ctx.getString(R.string.addhost_ip) +
                ": ${item.ip} · ${ctx.getString(R.string.addhost_port)} ${item.port}"
            applyStatusBadge(item.live?.let { live ->
                StatusInfo(
                    online = true,
                    busy = live.busy,
                    mcForeground = live.mcInForeground,
                )
            })
            overflow.visibility = View.VISIBLE
            progress.visibility = if (isHostConnecting(item)) View.VISIBLE else View.GONE
            card.setOnClickListener { onHostClick(item) }
            overflow.setOnClickListener { v -> onHostOverflow(item, v) }
        }

        fun bindDiscovered(item: HostListItem.Discovered) {
            val ctx = card.context
            icon.setImageResource(R.drawable.ic_computer)
            name.text = item.name
            subtitle.text = ctx.getString(R.string.addhost_ip) +
                ": ${item.ip} · ${ctx.getString(R.string.addhost_port)} ${item.port}"
            applyStatusBadge(
                StatusInfo(
                    online = true,
                    busy = item.discovered.busy,
                    mcForeground = item.discovered.mcInForeground,
                ),
            )
            overflow.visibility = View.GONE
            progress.visibility = if (isHostConnecting(item)) View.VISIBLE else View.GONE
            card.setOnClickListener { onHostClick(item) }
            overflow.setOnClickListener(null)
        }

        private fun applyStatusBadge(info: StatusInfo?) {
            val ctx = card.context
            if (info == null) {
                statusRow.visibility = View.GONE
                return
            }
            statusRow.visibility = View.VISIBLE
            val (dotColor, statusText) = when {
                info.busy -> R.color.status_busy to ctx.getString(R.string.home_host_status_busy)
                info.online -> R.color.status_online to ctx.getString(R.string.home_host_status_idle)
                else -> R.color.status_offline to ctx.getString(R.string.home_host_status_offline)
            }
            ImageViewCompat.setImageTintList(
                statusDot,
                android.content.res.ColorStateList.valueOf(ContextCompat.getColor(ctx, dotColor)),
            )
            val mcText = if (info.mcForeground) {
                ctx.getString(R.string.home_host_mc_foreground)
            } else {
                ctx.getString(R.string.home_host_mc_background)
            }
            statusLabel.text = "$statusText · $mcText"
        }
    }

    private data class StatusInfo(
        val online: Boolean,
        val busy: Boolean,
        val mcForeground: Boolean,
    )

    companion object {
        private const val TYPE_HEADER = 0
        private const val TYPE_EMPTY = 1
        private const val TYPE_USB = 2
        private const val TYPE_HOST = 3

        private val DIFF = object : DiffUtil.ItemCallback<HostListItem>() {
            override fun areItemsTheSame(a: HostListItem, b: HostListItem) = a.key == b.key
            override fun areContentsTheSame(a: HostListItem, b: HostListItem) = a == b
        }
    }
}
