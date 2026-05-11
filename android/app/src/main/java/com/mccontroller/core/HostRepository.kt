package com.mccontroller.core

import com.mccontroller.R
import com.mccontroller.net.DiscoveryClient
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine

/**
 * Joins [HostStore] (saved) and [DiscoveryClient] (live) into the
 * ordered list of [HostListItem] the home-screen RecyclerView renders.
 *
 * Order:
 *   1. "Saved" header
 *   2. System hosts first (USB loopback), then user-saved hosts sorted by
 *      `lastConnectedAt` desc (nulls last), tie-broken by name.
 *   3. "On this network" header
 *   4. Discovered hosts not already in saved, sorted by name.
 *
 * Empty sections get an [HostListItem.Empty] placeholder.
 */
class HostRepository(
    private val store: HostStore,
    private val discovery: DiscoveryClient,
) {
    val items: Flow<List<HostListItem>> =
        combine(store.hosts, discovery.discovered) { saved, live ->
            buildList<HostListItem> {
                // --- Saved section ---
                add(HostListItem.Header(R.string.home_section_saved))
                val sortedSaved = saved.sortedWith(
                    // System hosts pin to the top; user hosts then sort by
                    // recency desc, then name.
                    compareByDescending<SavedHost> { it.isSystem }
                        .thenByDescending { it.lastConnectedAt ?: -1L }
                        .thenBy { it.name.lowercase() },
                )
                if (sortedSaved.isEmpty()) {
                    add(HostListItem.Empty(R.string.home_empty_saved, sectionKey = "saved"))
                } else {
                    for (h in sortedSaved) {
                        val liveMatch = live[HostKey(h.ip, h.port)]
                        add(HostListItem.Saved(h, liveMatch))
                    }
                }

                // --- Discovered (not already saved) section ---
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
}
