package com.edgeveda.sdk

import android.app.ActivityManager
import android.content.Context
import android.os.Debug
import android.util.Log
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Monitors memory resource usage (RSS - Resident Set Size).
 *
 * Tracks the app's memory footprint for budget enforcement and telemetry.
 * Uses Android [Runtime] for Java heap and [Debug] for native heap measurement.
 *
 * Thread-safe via [Mutex] (Kotlin equivalent of Swift actor isolation).
 *
 * Example:
 * ```kotlin
 * val monitor = ResourceMonitor()
 * val currentMemory = monitor.currentRssMb()
 * val peakMemory = monitor.peakRssMb()
 * ```
 */
class ResourceMonitor(
    private val maxSamples: Int = 100
) {
    private val mutex = Mutex()
    private val samples = mutableListOf<Double>()
    private var _peakRssMb: Double = 0.0

    companion object {
        private const val TAG = "EdgeVeda.ResourceMonitor"
    }

    /**
     * Current RSS (Resident Set Size) in megabytes.
     *
     * Triggers a fresh memory sample before returning.
     */
    suspend fun currentRssMb(): Double = mutex.withLock {
        updateMemoryUsage()
        samples.lastOrNull() ?: 0.0
    }

    /** Peak RSS observed since monitoring started. */
    suspend fun peakRssMb(): Double = mutex.withLock { _peakRssMb }

    /** Average RSS over the sample window. */
    suspend fun averageRssMb(): Double = mutex.withLock {
        if (samples.isEmpty()) 0.0 else samples.sum() / samples.size
    }

    /** Number of samples collected. */
    suspend fun sampleCount(): Int = mutex.withLock { samples.size }

    /**
     * Manually trigger a memory usage update.
     *
     * Memory is automatically sampled when accessing [currentRssMb],
     * but this method allows explicit sampling for telemetry purposes.
     */
    suspend fun sample() = mutex.withLock {
        updateMemoryUsage()
    }

    /** Reset all samples and peak tracking. */
    suspend fun reset() = mutex.withLock {
        samples.clear()
        _peakRssMb = 0.0
    }

    // -----------------------------------------------------------------------
    // Private
    // -----------------------------------------------------------------------

    /** Must be called under [mutex] lock. */
    private fun updateMemoryUsage() {
        val rss = getResidentSetSize()
        samples.add(rss)

        if (rss > _peakRssMb) {
            _peakRssMb = rss
        }

        // Keep sliding window
        if (samples.size > maxSamples) {
            samples.removeFirst()
        }
    }

    /**
     * Get the current approximate resident set size in megabytes.
     *
     * On Android there is no direct equivalent of macOS `mach_task_basic_info`.
     * We approximate RSS by summing:
     * - Java heap usage: [Runtime.totalMemory] - [Runtime.freeMemory]
     * - Native heap usage: [Debug.getNativeHeapAllocatedSize]
     *
     * For a more precise PSS reading, use [getMemoryInfoFromContext] with
     * an [ActivityManager] (requires a [Context]).
     */
    private fun getResidentSetSize(): Double {
        return try {
            val runtime = Runtime.getRuntime()
            val javaHeapBytes = runtime.totalMemory() - runtime.freeMemory()
            val nativeHeapBytes = Debug.getNativeHeapAllocatedSize()
            val totalBytes = javaHeapBytes + nativeHeapBytes
            totalBytes.toDouble() / (1024.0 * 1024.0)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get memory info: ${e.message}")
            0.0
        }
    }
}