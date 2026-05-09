package com.mccontroller.input

import com.mccontroller.core.ControllerSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicInteger

/**
 * Buffers raw look deltas in atomic counters and flushes them on a fixed
 * interval (8ms ≈ 125Hz). The touch thread never blocks on IO; the flush
 * coroutine reads-and-resets the accumulators each tick.
 *
 * Zero deltas are skipped so we don't spam the PC with idle traffic when
 * the finger is still or lifted.
 */
class LookAccumulator(
    private val session: ControllerSession,
    private val flushIntervalMs: Long = DEFAULT_INTERVAL_MS,
) {
    private val dxAcc = AtomicInteger(0)
    private val dyAcc = AtomicInteger(0)
    private var job: Job? = null

    fun start(scope: CoroutineScope) {
        if (job?.isActive == true) return
        job = scope.launch(Dispatchers.Default) {
            while (isActive) {
                delay(flushIntervalMs)
                val dx = dxAcc.getAndSet(0)
                val dy = dyAcc.getAndSet(0)
                if (dx != 0 || dy != 0) {
                    val sdx = dx.coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                    val sdy = dy.coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt()).toShort()
                    session.sendLookDelta(sdx, sdy)
                }
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
        dxAcc.set(0)
        dyAcc.set(0)
    }

    fun add(dx: Int, dy: Int) {
        if (dx != 0) dxAcc.addAndGet(dx)
        if (dy != 0) dyAcc.addAndGet(dy)
    }

    companion object {
        const val DEFAULT_INTERVAL_MS = 8L  // ~125Hz, matches PC server expectations
    }
}
