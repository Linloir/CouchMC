package com.mccontroller.ui.adapter

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.core.widget.ImageViewCompat
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.card.MaterialCardView
import com.google.android.material.color.MaterialColors
import com.mccontroller.R
import com.mccontroller.core.DiscoveredHost
import com.mccontroller.core.HostListItem

/**
 * Multi-view-type adapter for the home screen. Section types:
 *
 *   • [HostListItem.Header] — section title
 *   • [HostListItem.Empty]  — placeholder when a section has 0 rows
 *   • [HostListItem.Saved] / [HostListItem.Discovered] — host card
 *
 * Card visual is four rows:
 *   1. Name + trailing overflow icon (M3 secondary-action surface).
 *   2. IP · port description.
 *   3. Status row: coloured dot + matching-coloured word.
 *   4. Last-connected line (or "Not connected yet").
 *
 * Tapping the overflow opens a [android.widget.PopupMenu] with the
 * applicable actions (rename / change port / forget). System-USB hosts
 * omit "Forget" since they're permanently provided by [HostStore].
 */
class HostListAdapter(
    private val onHostClick: (HostListItem) -> Unit,
    private val onHostMenu: (HostListItem, View) -> Unit,
    private val isHostConnecting: (HostListItem) -> Boolean,
) : ListAdapter<HostListItem, RecyclerView.ViewHolder>(DIFF) {

    override fun getItemViewType(position: Int): Int = when (getItem(position)) {
        is HostListItem.Header -> TYPE_HEADER
        is HostListItem.Empty -> TYPE_EMPTY
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
            is HostListItem.Saved -> (holder as HostViewHolder).bindSaved(item)
            is HostListItem.Discovered -> (holder as HostViewHolder).bindDiscovered(item)
        }
    }

    // -- ViewHolders ----------------------------------------------------------

    private class HeaderViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val title: TextView = view as TextView
        fun bind(item: HostListItem.Header) { title.setText(item.titleResId) }
    }

    private class EmptyViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val message: TextView = view as TextView
        fun bind(item: HostListItem.Empty) { message.setText(item.messageResId) }
    }

    private inner class HostViewHolder(view: View) : RecyclerView.ViewHolder(view) {
        private val card: MaterialCardView = view as MaterialCardView
        private val name: TextView = view.findViewById(R.id.host_name)
        private val description: TextView = view.findViewById(R.id.host_description)
        private val statusDot: ImageView = view.findViewById(R.id.host_status_dot)
        private val statusLabel: TextView = view.findViewById(R.id.host_status_label)
        private val lastConnected: TextView = view.findViewById(R.id.host_last_connected)
        private val overflow: ImageButton = view.findViewById(R.id.host_overflow)
        private val progress: ProgressBar = view.findViewById(R.id.host_progress)

        fun bindSaved(item: HostListItem.Saved) {
            val saved = item.saved
            val ctx = card.context
            name.text = saved.name
            description.text = "${saved.ip} · ${saved.port}"
            applyStatus(item.live, isSystem = saved.isSystem, ctx)
            lastConnected.text = lastConnectedText(saved.lastConnectedAt, ctx)
            progress.visibility = if (isHostConnecting(item)) View.VISIBLE else View.GONE
            card.setOnClickListener { onHostClick(item) }
            overflow.visibility = View.VISIBLE
            overflow.setOnClickListener { onHostMenu(item, it) }
        }

        fun bindDiscovered(item: HostListItem.Discovered) {
            val ctx = card.context
            name.text = item.name
            description.text = "${item.ip} · ${item.port}"
            applyStatus(item.discovered, isSystem = false, ctx)
            lastConnected.text = lastConnectedText(null, ctx)
            progress.visibility = if (isHostConnecting(item)) View.VISIBLE else View.GONE
            card.setOnClickListener { onHostClick(item) }
            // Discovered-but-not-saved hosts don't have an overflow menu —
            // the only useful action would be "save", which a future
            // iteration can wire in. Tapping the card connects directly.
            overflow.visibility = View.GONE
            overflow.setOnClickListener(null)
        }

        /**
         * Paints the dot + word for a host's connection status.
         *
         *   • system USB → primary-coloured "USB" (always-shown shortcut)
         *   • busy → amber "In use"
         *   • live + not busy → green "Available"
         *   • no live record → gray "Offline"
         */
        private fun applyStatus(live: DiscoveredHost?, isSystem: Boolean, ctx: Context) {
            val (labelRes, colour) = when {
                isSystem -> R.string.home_host_status_usb to
                    MaterialColors.getColor(card, com.google.android.material.R.attr.colorPrimary)
                live == null -> R.string.home_host_status_offline to
                    ContextCompat.getColor(ctx, R.color.status_offline)
                live.busy -> R.string.home_host_status_busy to
                    ContextCompat.getColor(ctx, R.color.status_busy)
                else -> R.string.home_host_status_idle to
                    ContextCompat.getColor(ctx, R.color.status_online)
            }
            statusLabel.setText(labelRes)
            statusLabel.setTextColor(colour)
            ImageViewCompat.setImageTintList(
                statusDot,
                android.content.res.ColorStateList.valueOf(colour),
            )
        }
    }

    companion object {
        private const val TYPE_HEADER = 0
        private const val TYPE_EMPTY = 1
        private const val TYPE_HOST = 2

        private val DIFF = object : DiffUtil.ItemCallback<HostListItem>() {
            override fun areItemsTheSame(a: HostListItem, b: HostListItem) = a.key == b.key
            override fun areContentsTheSame(a: HostListItem, b: HostListItem) = a == b
        }

        private fun lastConnectedText(lastConnectedAt: Long?, ctx: Context): String =
            if (lastConnectedAt == null) ctx.getString(R.string.home_meta_never_used)
            else ctx.getString(
                R.string.home_meta_last_used,
                formatRelativeTime(ctx, lastConnectedAt),
            )

        private fun formatRelativeTime(ctx: Context, then: Long): String {
            val delta = (System.currentTimeMillis() - then).coerceAtLeast(0L)
            val sec = delta / 1000
            return when {
                sec < 60 -> ctx.getString(R.string.time_just_now)
                sec < 3600 -> ctx.getString(R.string.time_min_ago, (sec / 60).toInt())
                sec < 86_400 -> ctx.getString(R.string.time_hr_ago, (sec / 3600).toInt())
                sec < 86_400 * 7 -> ctx.getString(R.string.time_day_ago, (sec / 86_400).toInt())
                else -> ctx.getString(R.string.time_long_ago)
            }
        }
    }
}
