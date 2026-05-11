package com.mccontroller.core

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/**
 * Persistent CRUD for [SavedHost] entries, backed by SharedPreferences
 * with a single JSON-blob value (same pattern as [ProfileStore]).
 *
 * The store exposes a [StateFlow] so the home screen can observe live
 * updates whenever a host is added / renamed / forgotten.
 *
 * Thread-safe: all mutations go through `synchronized(this)` and the
 * StateFlow emits afterwards.
 */
class HostStore(ctx: Context) {

    private val prefs = ctx.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private val _hosts = MutableStateFlow(loadAll())
    val hosts: StateFlow<List<SavedHost>> = _hosts

    /** Insert if `(ip, port)` doesn't exist; otherwise update name only. */
    @Synchronized
    fun upsert(name: String, ip: String, port: Int): SavedHost {
        val current = _hosts.value
        val existing = current.firstOrNull { it.ip == ip && it.port == port }
        val updated = if (existing != null) {
            existing.copy(name = name.ifBlank { existing.name })
        } else {
            SavedHost(
                id = UUID.randomUUID().toString(),
                name = name.ifBlank { "$ip:$port" },
                ip = ip,
                port = port,
                lastConnectedAt = null,
            )
        }
        val next = current.filterNot { it.id == updated.id } + updated
        persist(next)
        _hosts.value = next
        return updated
    }

    /** Update `lastConnectedAt` to push the host to the top of the recents list. */
    @Synchronized
    fun markConnected(id: String) {
        val next = _hosts.value.map {
            if (it.id == id) it.copy(lastConnectedAt = System.currentTimeMillis()) else it
        }
        persist(next)
        _hosts.value = next
    }

    @Synchronized
    fun rename(id: String, newName: String) {
        if (newName.isBlank()) return
        val next = _hosts.value.map {
            if (it.id == id) it.copy(name = newName) else it
        }
        persist(next)
        _hosts.value = next
    }

    @Synchronized
    fun delete(id: String) {
        val next = _hosts.value.filterNot { it.id == id }
        persist(next)
        _hosts.value = next
    }

    private fun loadAll(): List<SavedHost> {
        val raw = prefs.getString(KEY_BLOB, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            buildList {
                for (i in 0 until arr.length()) {
                    val o = arr.getJSONObject(i)
                    add(
                        SavedHost(
                            id = o.optString("id", UUID.randomUUID().toString()),
                            name = o.optString("name"),
                            ip = o.optString("ip"),
                            port = o.optInt("port", 34555),
                            lastConnectedAt = if (o.has("last")) o.optLong("last") else null,
                        ),
                    )
                }
            }
        } catch (_: Exception) {
            // Corrupted blob — recover by starting fresh; user just re-adds.
            emptyList()
        }
    }

    private fun persist(list: List<SavedHost>) {
        val arr = JSONArray()
        for (h in list) {
            val o = JSONObject().apply {
                put("id", h.id)
                put("name", h.name)
                put("ip", h.ip)
                put("port", h.port)
                h.lastConnectedAt?.let { put("last", it) }
            }
            arr.put(o)
        }
        prefs.edit().putString(KEY_BLOB, arr.toString()).apply()
    }

    companion object {
        private const val PREFS = "hosts_v1"
        private const val KEY_BLOB = "blob"

        @Volatile private var instance: HostStore? = null

        fun get(ctx: Context): HostStore =
            instance ?: synchronized(this) {
                instance ?: HostStore(ctx).also { instance = it }
            }
    }
}
