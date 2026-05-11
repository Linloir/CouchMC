package com.mccontroller.core

/**
 * A host the user has manually saved or previously connected to.
 *
 * Persisted via [HostStore]. `lastConnectedAt` is what drives the
 * "recently used → top of list" sort. `id` is a stable UUID so renames
 * don't break references.
 */
data class SavedHost(
    val id: String,
    val name: String,
    val ip: String,
    val port: Int,
    val lastConnectedAt: Long?,
)

/** Source channel that surfaced a discovered host. */
enum class DiscoverySource { UdpBroadcast, Mdns }

/**
 * A host learned from the network (UDP broadcast or mDNS). Ephemeral —
 * lives only while we keep seeing announces. The home repository merges
 * these with [SavedHost] entries by `(ip, port)` so a saved host that's
 * also live on the network is shown as one row.
 */
data class DiscoveredHost(
    val ip: String,
    val port: Int,
    val name: String,
    val mcInForeground: Boolean,
    val acceptsUdp: Boolean,
    val busy: Boolean,
    val source: DiscoverySource,
    val lastSeenAt: Long,
)

/** Equality key for matching a saved host to a discovered one. */
data class HostKey(val ip: String, val port: Int)

/**
 * UI-ready row for the home screen list. The repository emits a flat
 * list of these in the order the adapter should render. Headers and
 * empty-state placeholders are list items so RecyclerView's DiffUtil
 * can animate section changes (e.g. discovery turning from empty to
 * populated) cleanly.
 */
sealed class HostListItem {
    /** Stable diff key. */
    abstract val key: String

    data class Header(val titleResId: Int) : HostListItem() {
        override val key get() = "header_$titleResId"
    }

    data class Empty(val messageResId: Int, val sectionKey: String) : HostListItem() {
        override val key get() = "empty_$sectionKey"
    }

    /** USB / 127.0.0.1 quick-connect card. Always at the top of the list. */
    object UsbShortcut : HostListItem() {
        override val key get() = "usb_shortcut"
    }

    /** Section: a saved host (may or may not also be currently discovered). */
    data class Saved(
        val saved: SavedHost,
        val live: DiscoveredHost?,
    ) : HostListItem() {
        override val key get() = "saved_${saved.id}"
        val ip get() = saved.ip
        val port get() = saved.port
        val name get() = saved.name
    }

    /** Section: a discovered host that is NOT already saved. */
    data class Discovered(val discovered: DiscoveredHost) : HostListItem() {
        override val key get() = "discovered_${discovered.ip}_${discovered.port}"
        val ip get() = discovered.ip
        val port get() = discovered.port
        val name get() = discovered.name
    }
}
