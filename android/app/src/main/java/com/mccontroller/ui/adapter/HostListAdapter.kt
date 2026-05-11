package com.mccontroller.ui.adapter

import android.content.Context
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
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
import com.mccontroller.core.DiscoveredHost
import com.mccontroller.core.HostListItem
import com.mccontroller.core.SavedHost

/**
 * Multi-view-type adapter for the home screen. Sections:
 *
 *   • [HostListItem.Header] — section title (Saved / On this network)
 *   • [HostListItem.Empty]  — placeholder when a section has 0 rows
 *   • [HostListItem.Saved] / [HostListItem.Discovered] — host card
 *
 * Card visual matches the iOS-leaning design the user picked from a
 * reference screenshot: big bold title, descriptor subtitle, meta line
 * with clock glyph, and a 3-column tinted-icon stats footer
 * (Address / Port / Minecraft).
 *
 * Long-press a card → context menu (rename / change-port / forget),
 * since there's no persistent overflow icon to clutter the surface.
 */
class HostListAdapter(
    private val onHostClick: (HostListItem) -> Unit,
    private val onHostLongPress: (HostListItem, View) -> Unit,
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
        private val subtitle: TextView = view.findViewById(R.id.host_subtitle)
        private val meta: TextView = view.findViewById(R.id.host_meta)
        private val statusPill: LinearLayout = view.findViewById(R.id.host_status_pill)
        private val statusIcon: ImageView = view.findViewById(R.id.host_status_icon)
        private val statusLabel: TextView = view.findViewById(R.id.host_status_label)
        private val statAddressValue: TextView = view.findViewById(R.id.stat_address_value)
        private val statPortValue: TextView = view.findViewById(R.id.stat_port_value)
        private val statMcValue: TextView = view.findViewById(R.id.stat_mc_value)
        private val progress: ProgressBar = view.findViewById(R.id.host_progress)

        fun bindSaved(item: HostListItem.Saved) {
            val saved = item.saved
            val ctx = card.context
            name.text = saved.name
            subtitle.setText(
                if (saved.isSystem) R.string.home_descriptor_usb
                else R.string.home_descriptor_saved,
            )
            meta.text = metaTextFor(item.live, saved.lastConnectedAt, ctx)
            applyStatus(item.live)
            applyStats(saved.ip, saved.port, item.live, ctx)
            progress.visibility = if (isHostConnecting(item)) View.VISIBLE else View.GONE
            card.setOnClickListener { onHostClick(item) }
            card.setOnLongClickListener {
                onHostLongPress(item, card); true
            }
        }

        fun bindDiscovered(item: HostListItem.Discovered) {
            val ctx = card.context
            name.text = item.name
            subtitle.setText(R.string.home_descriptor_discovered)
            meta.text = metaTextFor(item.discovered, null, ctx)
            applyStatus(item.discovered)
            applyStats(item.ip, item.port, item.discovered, ctx)
            progress.visibility = if (isHostConnecting(item)) View.VISIBLE else View.GONE
            card.setOnClickListener { onHostClick(item) }
            // Long-press still works to "save" the discovered host (handled
            // in the fragment's onHostLongPress for Discovered items, if
            // we expose that later). For now, no menu — just click.
            card.setOnLongClickListener(null)
        }

        // ---- helpers ----

        private fun applyStatus(live: DiscoveredHost?) {
            val ctx = card.context
            val (label, color, bg) = when {
                live == null -> Triple(R.string.home_host_status_offline, R.color.status_offline, R.drawable.status_pill_bg_offline)
                live.busy -> Triple(R.string.home_host_status_busy, R.color.status_busy, R.drawable.status_pill_bg_busy)
                else -> Triple(R.string.home_host_status_idle, R.color.status_online, R.drawable.status_pill_bg_online)
            }
            statusPill.setBackgroundResource(bg)
            statusLabel.setText(label)
            val colour = ContextCompat.getColor(ctx, color)
            statusLabel.setTextColor(colour)
            ImageViewCompat.setImageTintList(statusIcon, android.content.res.ColorStateList.valueOf(colour))
        }

        private fun applyStats(ip: String, port: Int, live: DiscoveredHost?, ctx: Context) {
            statAddressValue.text = ip
            statPortValue.text = port.toString()
            statMcValue.setText(
                when {
                    live == null -> R.string.home_stat_mc_unknown
                    live.mcInForeground -> R.string.home_stat_mc_running
                    else -> R.string.home_stat_mc_idle
                },
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

        private fun metaTextFor(
            live: DiscoveredHost?,
            lastConnectedAt: Long?,
            ctx: Context,
        ): String = when {
            live != null -> ctx.getString(R.string.home_meta_seen_just_now)
            lastConnectedAt != null -> ctx.getString(
                R.string.home_meta_last_used,
                formatRelativeTime(ctx, lastConnectedAt),
            )
            else -> ctx.getString(R.string.home_meta_never_used)
        }

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
