package com.mccontroller.net

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.util.Log
import com.mccontroller.core.DiscoveredHost
import com.mccontroller.core.DiscoverySource
import com.mccontroller.core.HostKey
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetSocketAddress

/**
 * Listens for PC-server discovery announcements on the LAN. Two parallel
 * channels per [docs/discovery.md](../../../../../../docs/discovery.md):
 *
 *   1. **UDP broadcast** on `0.0.0.0:34556` — primary, payload format
 *      `MCCT v1 msg=ANNOUNCE flags tcpPort nameLen name`.
 *   2. **mDNS / DNS-SD** for `_mccontroller._tcp.local.` via [NsdManager]
 *      — secondary, complements UDP on routers that drop broadcast.
 *
 * Both channels feed into the same `discovered` map keyed by `(ip, port)`.
 * A GC coroutine drops entries whose `lastSeenAt` is older than
 * [STALE_AFTER_MS] so vanished hosts disappear from the UI.
 *
 * Acquires a [WifiManager.MulticastLock] while running; some OEMs would
 * otherwise drop broadcast UDP under power-save.
 */
class DiscoveryClient(private val ctx: Context) {

    private val _discovered = MutableStateFlow<Map<HostKey, DiscoveredHost>>(emptyMap())
    val discovered: StateFlow<Map<HostKey, DiscoveredHost>> = _discovered

    private var udpSocket: DatagramSocket? = null
    private var multicastLock: WifiManager.MulticastLock? = null
    private var nsdManager: NsdManager? = null
    private var nsdListener: NsdManager.DiscoveryListener? = null
    private val runningJobs = mutableListOf<Job>()

    fun start(scope: CoroutineScope) {
        if (runningJobs.isNotEmpty()) return
        acquireMulticastLock()
        runningJobs += scope.launch(Dispatchers.IO) { runUdpListener() }
        runningJobs += scope.launch(Dispatchers.IO) { runGarbageCollector() }
        runningJobs += scope.launch(Dispatchers.Main) { runMdnsDiscovery() }
    }

    fun stop() {
        runningJobs.forEach { it.cancel() }
        runningJobs.clear()
        try { udpSocket?.close() } catch (_: Exception) {}
        udpSocket = null
        stopMdnsDiscovery()
        releaseMulticastLock()
    }

    // -------------------------------------------------------------- UDP

    private suspend fun runUdpListener() {
        val socket = try {
            DatagramSocket(null).apply {
                reuseAddress = true
                broadcast = true
                soTimeout = 1000          // periodic wakeup → cooperative cancel
                bind(InetSocketAddress(DISCOVERY_PORT))
            }
        } catch (e: Exception) {
            Log.w(TAG, "UDP discovery bind failed", e)
            return
        }
        udpSocket = socket

        val buf = ByteArray(512)
        val pkt = DatagramPacket(buf, buf.size)
        while (currentScopeActive()) {
            try {
                socket.receive(pkt)
                val host = parseAnnouncement(
                    buf,
                    pkt.length,
                    sourceIp = pkt.address?.hostAddress ?: continue,
                    source = DiscoverySource.UdpBroadcast,
                )
                if (host != null) put(host)
            } catch (_: java.net.SocketTimeoutException) {
                /* expected — loop and check cancellation */
            } catch (e: Exception) {
                if (!currentScopeActive()) break
                Log.w(TAG, "UDP discovery recv error", e)
                delay(500)
            }
        }
    }

    /**
     * Parse a single datagram into a [DiscoveredHost]. Returns null on
     * any structural rejection (wrong magic, unsupported version, short
     * payload). See `docs/discovery.md` § "Channel A — wire format".
     */
    private fun parseAnnouncement(
        buf: ByteArray,
        len: Int,
        sourceIp: String,
        source: DiscoverySource,
    ): DiscoveredHost? {
        if (len < 11) return null
        if (buf[0] != 'M'.code.toByte() ||
            buf[1] != 'C'.code.toByte() ||
            buf[2] != 'C'.code.toByte() ||
            buf[3] != 'T'.code.toByte()
        ) return null
        val ver = buf[4].toInt() and 0xff
        if (ver != PROTOCOL_VERSION) return null
        val msg = buf[5].toInt() and 0xff
        if (msg != MSG_ANNOUNCE) return null
        val flags = buf[6].toInt() and 0xff
        val tcpPort = ((buf[7].toInt() and 0xff) shl 8) or (buf[8].toInt() and 0xff)
        val nameLen = ((buf[9].toInt() and 0xff) shl 8) or (buf[10].toInt() and 0xff)
        if (11 + nameLen > len) return null
        val name = if (nameLen > 0) String(buf, 11, nameLen, Charsets.UTF_8) else sourceIp

        return DiscoveredHost(
            ip = sourceIp,
            port = tcpPort,
            name = name,
            mcInForeground = (flags and FLAG_MC_FOREGROUND) != 0,
            acceptsUdp = (flags and FLAG_ACCEPTS_UDP) != 0,
            busy = (flags and FLAG_BUSY) != 0,
            source = source,
            lastSeenAt = System.currentTimeMillis(),
        )
    }

    // ------------------------------------------------------------- mDNS

    private fun runMdnsDiscovery() {
        nsdManager = ctx.getSystemService(Context.NSD_SERVICE) as? NsdManager
        val mgr = nsdManager ?: return
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onDiscoveryStopped(serviceType: String) {}
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.w(TAG, "mDNS start failed: $errorCode")
            }
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
            override fun onServiceFound(info: NsdServiceInfo) {
                resolveService(info)
            }
            override fun onServiceLost(info: NsdServiceInfo) {
                // Don't immediately purge — UDP heartbeat may still keep
                // the host alive. The GC handles disappearance.
            }
        }
        nsdListener = listener
        try {
            mgr.discoverServices(MDNS_SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
        } catch (e: Exception) {
            Log.w(TAG, "mDNS discoverServices threw", e)
        }
    }

    private fun resolveService(info: NsdServiceInfo) {
        val mgr = nsdManager ?: return
        val resolveListener = object : NsdManager.ResolveListener {
            override fun onResolveFailed(svc: NsdServiceInfo, errorCode: Int) {
                Log.w(TAG, "mDNS resolve failed: $errorCode for ${svc.serviceName}")
            }
            override fun onServiceResolved(svc: NsdServiceInfo) {
                val ip = svc.host?.hostAddress ?: return
                val port = svc.port
                val name = svc.serviceName ?: ip
                val attrs = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    svc.attributes
                } else null
                fun txtBool(key: String, default: Boolean = false): Boolean {
                    val v = attrs?.get(key)?.let { String(it, Charsets.UTF_8) } ?: return default
                    return v == "1"
                }
                put(
                    DiscoveredHost(
                        ip = ip,
                        port = port,
                        name = name,
                        mcInForeground = txtBool("mc"),
                        acceptsUdp = txtBool("udp", default = true),
                        busy = txtBool("busy", default = false),
                        source = DiscoverySource.Mdns,
                        lastSeenAt = System.currentTimeMillis(),
                    ),
                )
            }
        }
        try {
            mgr.resolveService(info, resolveListener)
        } catch (e: Exception) {
            Log.w(TAG, "mDNS resolveService threw", e)
        }
    }

    private fun stopMdnsDiscovery() {
        val mgr = nsdManager ?: return
        val listener = nsdListener ?: return
        try {
            mgr.stopServiceDiscovery(listener)
        } catch (_: Exception) {}
        nsdListener = null
        nsdManager = null
    }

    // ---------------------------------------------------------- bookkeeping

    private fun put(host: DiscoveredHost) {
        _discovered.value = _discovered.value.toMutableMap().apply {
            // Prefer UDP-sourced data over mDNS for the same host (UDP
            // carries the live MC-foreground flag fresh every second;
            // mDNS TXT-record updates are batched).
            val existing = get(HostKey(host.ip, host.port))
            if (existing == null ||
                existing.source == DiscoverySource.Mdns ||
                host.source == DiscoverySource.UdpBroadcast
            ) {
                put(HostKey(host.ip, host.port), host)
            } else {
                // Keep the existing UDP record, just bump the seen timestamp.
                put(HostKey(host.ip, host.port), existing.copy(lastSeenAt = host.lastSeenAt))
            }
        }
    }

    private suspend fun runGarbageCollector() {
        while (currentScopeActive()) {
            delay(1000)
            val now = System.currentTimeMillis()
            val filtered = _discovered.value.filterValues { now - it.lastSeenAt < STALE_AFTER_MS }
            if (filtered.size != _discovered.value.size) {
                _discovered.value = filtered
            }
        }
    }

    private fun currentScopeActive(): Boolean =
        runningJobs.any { it.isActive }

    // ------------------------------------------------------ multicast lock

    private fun acquireMulticastLock() {
        try {
            val wifi = ctx.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
            multicastLock = wifi?.createMulticastLock("mc_controller_discovery")?.apply {
                setReferenceCounted(false)
                acquire()
            }
        } catch (e: Exception) {
            Log.w(TAG, "MulticastLock acquire failed (continuing anyway)", e)
        }
    }

    private fun releaseMulticastLock() {
        try {
            multicastLock?.takeIf { it.isHeld }?.release()
        } catch (_: Exception) {}
        multicastLock = null
    }

    companion object {
        private const val TAG = "DiscoveryClient"
        private const val DISCOVERY_PORT = 34556
        private const val PROTOCOL_VERSION = 0x01
        private const val MSG_ANNOUNCE = 0x01
        private const val FLAG_MC_FOREGROUND = 0x01
        private const val FLAG_ACCEPTS_UDP = 0x02
        private const val FLAG_BUSY = 0x04
        private const val MDNS_SERVICE_TYPE = "_mccontroller._tcp."
        const val STALE_AFTER_MS = 5_000L
    }
}

// Internal helper hoisted out so withContext callers don't have to construct it inline.
@Suppress("RedundantSuspendModifier")
private suspend fun <T> ioOf(block: () -> T): T = withContext(Dispatchers.IO) { block() }
