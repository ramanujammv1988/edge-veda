package com.edgeveda.sdk

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Tracks battery drain rate for budget enforcement.
 *
 * Monitors battery level changes over time to calculate drain rate as percentage
 * per 10 minutes. Uses Android [BatteryManager] via sticky broadcast for battery
 * level readings.
 *
 * Drain Rate Calculation:
 * - Samples battery level every 60 seconds
 * - Maintains sliding window of last 10 minutes
 * - Calculates rate: (initial% - current%) / time × 600 seconds
 *
 * Thread-safe via [Mutex] (Kotlin equivalent of Swift actor isolation).
 *
 * Example:
 * ```kotlin
 * val tracker = BatteryDrainTracker(context)
 * val drainRate = tracker.currentDrainRate()
 * if (drainRate != null) {
 *     println("Battery draining at $drainRate% per 10 minutes")
 * }
 * ```
 */
class BatteryDrainTracker(
    private val context: Context? = null
) {
    private val mutex = Mutex()
    private val samples = mutableListOf<BatterySample>()
    private var isTracking = false
    private var trackingJob: Job? = null
    private val scope = CoroutineScope(Dispatchers.Default + SupervisorJob())

    companion object {
        private const val TAG = "EdgeVeda.BatteryDrain"
        private const val SAMPLE_INTERVAL_MS = 60_000L       // 60 seconds
        private const val WINDOW_DURATION_MS = 600_000L      // 10 minutes
        private const val MAX_SAMPLES = 11                    // ~10 min at 1-min intervals
    }

    /** Individual battery level sample with timestamp. */
    private data class BatterySample(
        val level: Float,       // Battery level 0.0-1.0
        val timestamp: Long     // System.currentTimeMillis()
    )

    init {
        startTracking()
        Log.i(TAG, "BatteryDrainTracker initialized. Context available: ${context != null}")
    }

    // -------------------------------------------------------------------
    // Public Properties
    // -------------------------------------------------------------------

    /**
     * Current battery drain rate in percentage per 10 minutes.
     *
     * Returns null if:
     * - Battery monitoring is unavailable (no Context)
     * - Not enough samples collected (need at least 2)
     */
    suspend fun currentDrainRate(): Double? = mutex.withLock {
        if (samples.size < 2) return@withLock null

        val first = samples.first()
        val last = samples.last()

        val timeDiffMs = last.timestamp - first.timestamp
        if (timeDiffMs <= 0) return@withLock null

        // Level difference (positive = draining)
        val levelDiff = first.level - last.level

        // Drain per millisecond → scale to 10 minutes (600,000ms) → percentage
        val drainPerMs = levelDiff.toDouble() / timeDiffMs
        val drainPerTenMinutes = drainPerMs * 600_000.0 * 100.0

        return@withLock if (drainPerTenMinutes >= 0) drainPerTenMinutes else 0.0
    }

    /**
     * Average battery drain rate over available sample intervals.
     *
     * Calculates drain rate for each consecutive pair of samples,
     * then averages the non-negative rates.
     */
    suspend fun averageDrainRate(): Double? = mutex.withLock {
        if (samples.size < 3) {
            // Fall back to simple calculation
            return@withLock computeSimpleDrainRate()
        }

        val rates = mutableListOf<Double>()
        for (i in 0 until samples.size - 1) {
            val first = samples[i]
            val second = samples[i + 1]

            val timeDiffMs = second.timestamp - first.timestamp
            if (timeDiffMs <= 0) continue

            val levelDiff = first.level - second.level
            val drainPerMs = levelDiff.toDouble() / timeDiffMs
            val drainPerTenMinutes = drainPerMs * 600_000.0 * 100.0

            if (drainPerTenMinutes >= 0) {
                rates.add(drainPerTenMinutes)
            }
        }

        if (rates.isEmpty()) return@withLock null
        return@withLock rates.sum() / rates.size
    }

    /**
     * Current battery level (0.0-1.0), or null if unavailable.
     */
    suspend fun currentBatteryLevel(): Float? = mutex.withLock {
        getBatteryLevel()
    }

    /** Number of samples collected. */
    suspend fun sampleCount(): Int = mutex.withLock { samples.size }

    /** Whether battery monitoring is supported (requires Context). */
    val isSupported: Boolean
        get() = context != null

    // -------------------------------------------------------------------
    // Public Methods
    // -------------------------------------------------------------------

    /**
     * Manually record a battery sample.
     *
     * Normally samples are recorded automatically every 60 seconds,
     * but this can be used to force an immediate sample.
     */
    suspend fun recordSample() = mutex.withLock {
        recordSampleInternal()
    }

    /** Reset all collected samples. */
    suspend fun reset() = mutex.withLock {
        samples.clear()
        Log.i(TAG, "Battery drain tracker reset")
    }

    /**
     * Stop tracking and release resources.
     *
     * Call when the tracker is no longer needed.
     */
    fun destroy() {
        isTracking = false
        trackingJob?.cancel()
        trackingJob = null
        scope.cancel()
        Log.i(TAG, "Battery drain tracking stopped")
    }

    // -------------------------------------------------------------------
    // Private
    // -------------------------------------------------------------------

    private fun startTracking() {
        if (isTracking) return
        isTracking = true

        // Record initial sample asynchronously on the tracker's own scope
        scope.launch {
            mutex.withLock { recordSampleInternal() }
        }

        // Start periodic sampling
        trackingJob = scope.launch {
            while (isActive && isTracking) {
                delay(SAMPLE_INTERVAL_MS)
                mutex.withLock { recordSampleInternal() }
            }
        }

        Log.i(TAG, "Battery drain tracking started")
    }

    /** Must be called under [mutex] lock. */
    private fun recordSampleInternal() {
        val level = getBatteryLevel()
        if (level == null || level < 0f) {
            Log.w(TAG, "Battery level unavailable")
            return
        }

        val sample = BatterySample(level = level, timestamp = System.currentTimeMillis())
        samples.add(sample)

        // Trim to sliding window (10 minutes)
        val cutoff = System.currentTimeMillis() - WINDOW_DURATION_MS
        samples.removeAll { it.timestamp < cutoff }

        Log.d(TAG, "Recorded battery sample: ${(level * 100).toInt()}% (${samples.size} samples)")
    }

    /** Simple drain rate from first/last sample. Must be called under lock. */
    private fun computeSimpleDrainRate(): Double? {
        if (samples.size < 2) return null

        val first = samples.first()
        val last = samples.last()

        val timeDiffMs = last.timestamp - first.timestamp
        if (timeDiffMs <= 0) return null

        val levelDiff = first.level - last.level
        val drainPerMs = levelDiff.toDouble() / timeDiffMs
        val drainPerTenMinutes = drainPerMs * 600_000.0 * 100.0

        return if (drainPerTenMinutes >= 0) drainPerTenMinutes else 0.0
    }

    /**
     * Get current battery level (0.0-1.0) using Android sticky broadcast.
     *
     * Uses [Intent.ACTION_BATTERY_CHANGED] sticky broadcast which does not
     * require registering a BroadcastReceiver.
     */
    private fun getBatteryLevel(): Float? {
        val ctx = context ?: return null
        return try {
            val batteryStatus: Intent? = IntentFilter(Intent.ACTION_BATTERY_CHANGED).let { filter ->
                ctx.registerReceiver(null, filter)
            }

            if (batteryStatus == null) return null

            val level = batteryStatus.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
            val scale = batteryStatus.getIntExtra(BatteryManager.EXTRA_SCALE, -1)

            if (level >= 0 && scale > 0) {
                level.toFloat() / scale.toFloat()
            } else {
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get battery level: ${e.message}")
            null
        }
    }
}