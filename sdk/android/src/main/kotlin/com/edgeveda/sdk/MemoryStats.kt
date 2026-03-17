package com.edgeveda.sdk

/**
 * Memory usage statistics from the native engine.
 */
data class MemoryStats(
    val currentBytes: Long,
    val peakBytes: Long,
    val limitBytes: Long,
    val modelBytes: Long,
    val contextBytes: Long,
) {
    val usagePercent: Double get() = if (limitBytes > 0) currentBytes.toDouble() / limitBytes else 0.0
    val isHighPressure: Boolean get() = usagePercent > 0.8
}
