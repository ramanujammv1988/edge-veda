package com.edgeveda.sdk

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Tracks inference latency and calculates percentiles.
 *
 * Maintains a sliding window of latency samples for calculating
 * p50, p95, and p99 metrics used in budget enforcement.
 *
 * Thread-safe via [Mutex] (Kotlin equivalent of Swift actor isolation).
 */
class LatencyTracker(
    private val maxSamples: Int = 100
) {
    private val mutex = Mutex()
    private val samples = mutableListOf<Double>()

    /** Total number of samples recorded. */
    suspend fun sampleCount(): Int = mutex.withLock { samples.size }

    /** Record a latency sample in milliseconds. */
    suspend fun record(latencyMs: Double) = mutex.withLock {
        samples.add(latencyMs)
        if (samples.size > maxSamples) {
            samples.removeFirst()
        }
    }

    /** Get the 50th percentile (median) latency. */
    suspend fun p50(): Double = mutex.withLock { percentile(0.50) }

    /** Get the 95th percentile latency. */
    suspend fun p95(): Double = mutex.withLock { percentile(0.95) }

    /** Get the 99th percentile latency. */
    suspend fun p99(): Double = mutex.withLock { percentile(0.99) }

    /** Get the average latency. */
    suspend fun average(): Double = mutex.withLock {
        if (samples.isEmpty()) 0.0 else samples.sum() / samples.size
    }

    /** Get the minimum latency. */
    suspend fun min(): Double = mutex.withLock {
        samples.minOrNull() ?: 0.0
    }

    /** Get the maximum latency. */
    suspend fun max(): Double = mutex.withLock {
        samples.maxOrNull() ?: 0.0
    }

    /** Calculate a specific percentile (internal, must be called under lock). */
    private fun percentile(p: Double): Double {
        if (samples.isEmpty()) return 0.0
        val sorted = samples.sorted()
        val index = (sorted.size * p).toInt().coerceAtMost(sorted.size - 1)
        return sorted[index]
    }

    /** Reset all samples. */
    suspend fun reset() = mutex.withLock {
        samples.clear()
    }
}