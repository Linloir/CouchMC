package com.mccontroller.core

import com.mccontroller.R
import com.mccontroller.net.DiscoveryClient
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.combine

/**
 * Joins [HostStore] (saved) and [DiscoveryClient] (live) into the
 * ordered list of [HostListItem] the home-screen RecyclerView renders.
 *
 * The third input — [systemUsbReachable] — is the result of a periodic
 * TCP probe of the loopback host (driven by HomeViewModel). When that
 * flag is `true` we synthesise a [DiscoveredHost] for the system USB
 * entry so it lights up green like any other live host. When the flag
 * is `false` the system entry shows the "Offline" gray. While the flag
 * is `null` (haven't probed yet) the system entry has no live record,
 * so the status reads "Offline" briefly until the first probe lands.
 *
 * Order:
 *   1. "Saved" header
 *   2. System hosts pinned first, then user hosts by `lastConnectedAt`
 *      desc, tie-broken by name.
 *   3. "On this network" header
 *   4. Discovered (non-saved) hosts, sorted by name.
 */
class HostRepository(
    private val store: HostStore,
    private val discovery: DiscoveryClient,
    private val systemUsbReachable: MutableStateFlow<Boolean?>,
) {
    val items: Flow<List<HostListItem>> =
        combine(store.hosts, discovery.discovered, systemUsbReachable) { saved, live, usbUp ->
            buildList<HostListItem> {
                add(HostListItem.Header(R.string.home_section_saved))
                val sortedSaved = saved.sortedWith(
                    compareByDescending<SavedHost> { it.isSystem }
                        .thenByDescending { it.lastConnectedAt ?: -1L }
                        .thenBy { it.name.lowercase() },
                )
                if (sortedSaved.isEmpty()) {
                    add(HostListItem.Empty(R.string.home_empty_saved, sectionKey = "saved"))
                } else {
                    for (h in sortedSaved) {
                        val liveMatch = if (h.isSystem) {
                            if (usbUp == true) synthesiseSystemLive(h) else null
                        } else {
                            live[HostKey(h.ip, h.port)]
                        }
                        add(HostListItem.Saved(h, liveMatch))
                    }
                }

                add(HostListItem.Header(R.string.home_section_discovered))
                val savedKeys = saved.map { HostKey(it.ip, it.port) }.toHashSet()
                val newcomers = live.values
                    .filter { HostKey(it.ip, it.port) !in savedKeys }
                    .sortedBy { it.name.lowercase() }
                if (newcomers.isEmpty()) {
                    add(HostListItem.Empty(R.string.home_empty_discovered, sectionKey = "discovered"))
                } else {
                    for (h in newcomers) add(HostListItem.Discovered(h))
                }
            }
        }

    /**
     * Treat a reachable USB loopback host as a live discovered host so
     * the adapter can paint the green-dot "Available" status without a
     * separate code path. MC-foreground info isn't available locally so
     * we leave it false.
     */
    private fun synthesiseSystemLive(host: SavedHost): DiscoveredHost = DiscoveredHost(
        ip = host.ip,
        port = host.port,
        name = host.name,
        mcInForeground = false,
        acceptsUdp = false,
        busy = false,
        source = DiscoverySource.UdpBroadcast,
        lastSeenAt = System.currentTimeMillis(),
    )
}
