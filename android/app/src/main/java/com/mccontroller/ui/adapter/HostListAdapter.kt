package com.mccontroller.ui.adapter

import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.ImageButton
import android.widget.ImageView
import android.widget.ProgressBar
import android.widget.TextView
import androidx.core.content.ContextCompat
import androidx.recyclerview.widget.DiffUtil
import androidx.recyclerview.widget.ListAdapter
import androidx.recyclerview.widget.RecyclerView
import com.google.android.material.card.MaterialCardView
import com.mccontroller.R
import com.mccontroller.core.HostListItem
import com.mccontroller.core.SavedHost

/**
 * Multi-view-type adapter for the home screen. Supported types:
 *
 *   • [HostListItem.Header] — section title (Saved / On this network)
 *   • [HostListItem.Empty]  — placeholder when a section has 0 rows
 *   • [HostListItem.Saved] / [HostListItem.Discovered] — host card
 *
 * Card visual is owned here (per-host gradient avatar, status pill,
 * meta line). DiffUtil on [HostListItem.key] keeps animations stable.
 */
class HostListAdapter(
    private val onHostClick: (HostListItem) -> Unit,
    private val onHostOverflow: (HostListItem, View) -> Unit,
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
        private val avatar: View = view.findViewById(R.id.host_avatar)
        private val icon: ImageView = view.findViewById(R.id.host_icon)
        private val name: TextView = view.findViewById(R.id.host_name)
        private val subtitle: TextView = view.findViewById(R.id.host_subtitle)
        private val meta: TextView = view.findViewById(R.id.host_meta)
        private val statusPill: TextView = view.findViewById(R.id.host_status_pill)
        private val overflow: ImageButton = view.findViewById(R.id.host_overflow)
        private val progress: ProgressBar = view.findViewById(R.id.host_progress)

        fun bindSaved(item: HostListItem.Saved) {
            val saved = item.saved
            applyAvatar(saved)
            name.text = saved.name
            subtitle.text = "${saved.ip} · ${saved.port}"
            meta.text = buildMetaText(item.live, saved.lastConnectedAt, card.context)
            applyStatus(item.live)
            overflow.visibility = View.VISIBLE
            progress.visibility = if (isHostConnecting(item)) View.VISIBLE else View.GONE
            card.setOnClickListener { onHostClick(item) }
            overflow.setOnClickListener { v -> onHostOverflow(item, v) }
        }

        fun bindDiscovered(item: HostListItem.Discovered) {
            val ip = item.ip; val port = item.port
            applyAvatarColor(item.name)
            icon.setImageResource(R.drawable.ic_computer)
            name.text = item.name
            subtitle.text = "$ip · $port"
            meta.text = buildMetaText(item.discovered, null, card.context)
            applyStatus(item.discovered)
            overflow.visibility = View.GONE
            progress.visibility = if (isHostConnecting(item)) View.VISIBLE else View.GONE
            card.setOnClickListener { onHostClick(item) }
            overflow.setOnClickListener(null)
        }

        // ---- helpers ----

        private fun applyAvatar(saved: SavedHost) {
            applyAvatarColor(saved.name)
            icon.setImageResource(
                if (saved.isSystem) R.drawable.ic_usb else R.drawable.ic_computer,
            )
        }

        private fun applyAvatarColor(seed: String) {
            val (c1, c2) = avatarGradientFor(seed)
            val drawable = GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                intArrayOf(c1, c2),
            ).apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = card.context.resources.displayMetrics.density * 14f
            }
            avatar.background = drawable
        }

        private fun applyStatus(live: com.mccontroller.core.DiscoveredHost?) {
            val ctx = card.context
            when {
                live == null -> {
                    statusPill.setText(R.string.home_host_status_offline)
                    statusPill.setTextColor(ContextCompat.getColor(ctx, R.color.status_offline))
                    statusPill.setBackgroundResource(R.drawable.status_pill_bg_offline)
                }
                live.busy -> {
                    statusPill.setText(R.string.home_host_status_busy)
                    statusPill.setTextColor(ContextCompat.getColor(ctx, R.color.status_busy))
                    statusPill.setBackgroundResource(R.drawable.status_pill_bg_busy)
                }
                else -> {
                    statusPill.setText(R.string.home_host_status_idle)
                    statusPill.setTextColor(ContextCompat.getColor(ctx, R.color.status_online))
                    statusPill.setBackgroundResource(R.drawable.status_pill_bg_online)
                }
            }
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

        /**
         * Two-stop HSL gradient derived from a name hash. Produces a
         * stable, distinctive avatar swatch per host without requiring
         * the user to pick colours. Saturation + lightness fixed; only
         * the hue varies — keeps swatches in the same visual family.
         */
        private fun avatarGradientFor(seed: String): Pair<Int, Int> {
            val h = (seed.hashCode().toLong() and 0xffffffffL).toFloat()
            val hue = (h % 360f + 360f) % 360f
            val c1 = hslToRgb(hue, 0.66f, 0.58f)
            val c2 = hslToRgb((hue + 28f) % 360f, 0.74f, 0.46f)
            return c1 to c2
        }

        private fun hslToRgb(h: Float, s: Float, l: Float): Int {
            val c = (1 - Math.abs(2 * l - 1)) * s
            val hp = h / 60f
            val x = c * (1 - Math.abs(hp % 2 - 1))
            val (r, g, b) = when {
                hp < 1 -> Triple(c, x, 0f)
                hp < 2 -> Triple(x, c, 0f)
                hp < 3 -> Triple(0f, c, x)
                hp < 4 -> Triple(0f, x, c)
                hp < 5 -> Triple(x, 0f, c)
                else -> Triple(c, 0f, x)
            }
            val m = l - c / 2f
            return Color.rgb(
                ((r + m) * 255).toInt().coerceIn(0, 255),
                ((g + m) * 255).toInt().coerceIn(0, 255),
                ((b + m) * 255).toInt().coerceIn(0, 255),
            )
        }

        private fun buildMetaText(
            live: com.mccontroller.core.DiscoveredHost?,
            lastConnectedAt: Long?,
            ctx: android.content.Context,
        ): String {
            val parts = mutableListOf<String>()
            if (live != null) {
                parts += if (live.mcInForeground) {
                    ctx.getString(R.string.home_host_mc_foreground)
                } else {
                    ctx.getString(R.string.home_host_mc_background)
                }
            }
            if (lastConnectedAt != null) {
                parts += ctx.getString(
                    R.string.home_host_last_connected,
                    formatRelativeTime(ctx, lastConnectedAt),
                )
            }
            return parts.joinToString(" · ")
        }

        /** Lightweight relative-time formatter. */
        private fun formatRelativeTime(ctx: android.content.Context, then: Long): String {
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
