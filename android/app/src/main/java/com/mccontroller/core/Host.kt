package com.mccontroller.core

/**
 * A host the user has manually saved or previously connected to.
 *
 * Persisted via [HostStore]. `lastConnectedAt` drives the
 * "recently used → top of list" sort. `id` is a stable UUID so renames
 * don't break references.
 *
 * The special id [SYSTEM_USB_ID] marks the auto-seeded loopback entry
 * for `adb reverse` USB mode. That entry can be renamed and have its
 * port changed, but cannot be deleted — see [HostStore.delete] and the
 * adapter overflow menu's gating logic.
 */
data class SavedHost(
    val id: String,
    val name: String,
    val ip: String,
    val port: Int,
    val lastConnectedAt: Long?,
) {
    /** True if this is the auto-provided 127.0.0.1 USB shortcut. */
    val isSystem: Boolean get() = id == SYSTEM_USB_ID

    companion object {
        /** Stable id for the auto-seeded USB-loopback entry. */
        const val SYSTEM_USB_ID = "system-usb"
    }
}

/** Source channel that surfaced a discovered host. */
enum class DiscoverySource { UdpBroadcast, Mdns }

/**
 * A host learned from the network (UDP broadcast or mDNS). Ephemeral —
 * lives only while we keep seeing announces. The home repository merges
 * these with [SavedHost] entries by `(ip, port)`.
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
