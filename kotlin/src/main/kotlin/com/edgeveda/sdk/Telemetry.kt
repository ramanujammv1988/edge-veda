package com.edgeveda.sdk

import android.util.Log
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.Date

/**
 * Telemetry subsystem for structured logging and metrics collection.
 *
 * Provides [android.util.Log]-based logging with appropriate categories.
 * Integrates with runtime supervision components to collect performance metrics.
 *
 * Thread-safe via [Mutex] (Kotlin equivalent of Swift actor isolation).
 *
 * Example:
 * ```kotlin
 * val telemetry = Telemetry.instance
 * telemetry.logInferenceStart(requestId = "req-123")
 * telemetry.recordLatency(requestId = "req-123", latencyMs = 42.5)
 * telemetry.logBudgetViolation(type = BudgetViolationType.LATENCY, current = 50.0, limit = 40.0)
 * ```
 */
class Telemetry private constructor() {

    private val mutex = Mutex()

    // -------------------------------------------------------------------
    // Metrics Storage
    // -------------------------------------------------------------------

    private val latencyMetrics = mutableMapOf<String, LatencyMetric>()
    private val budgetViolations = mutableListOf<BudgetViolationRecord>()
    private val resourceSnapshots = mutableListOf<ResourceSnapshot>()

    // Configuration
    private var maxStoredMetrics = 1000
    private var maxStoredViolations = 100
    private var maxStoredSnapshots = 100

    companion object {
        // Log tags per category
        private const val TAG_INFERENCE = "EdgeVeda.Inference"
        private const val TAG_BUDGET = "EdgeVeda.Budget"
        private const val TAG_RESOURCES = "EdgeVeda.Resources"
        private const val TAG_SCHEDULER = "EdgeVeda.Scheduler"
        private const val TAG_POLICY = "EdgeVeda.Policy"

        /** Shared telemetry instance (singleton). */
        val instance: Telemetry by lazy { Telemetry() }
    }

    init {
        Log.i(TAG_INFERENCE, "Telemetry system initialized")
    }

    // -------------------------------------------------------------------
    // Configuration
    // -------------------------------------------------------------------

    /** Set maximum number of latency metrics to store in memory. */
    suspend fun setMaxStoredMetrics(count: Int) = mutex.withLock {
        maxStoredMetrics = count
        trimMetrics()
    }

    /** Set maximum number of budget violations to store. */
    suspend fun setMaxStoredViolations(count: Int) = mutex.withLock {
        maxStoredViolations = count
        trimViolations()
    }

    /** Set maximum number of resource snapshots to store. */
    suspend fun setMaxStoredSnapshots(count: Int) = mutex.withLock {
        maxStoredSnapshots = count
        trimSnapshots()
    }

    // -------------------------------------------------------------------
    // Inference Logging
    // -------------------------------------------------------------------

    /** Log the start of an inference request. */
    suspend fun logInferenceStart(requestId: String, modelName: String? = null) {
        if (modelName != null) {
            Log.i(TAG_INFERENCE, "Inference started: $requestId model=$modelName")
        } else {
            Log.i(TAG_INFERENCE, "Inference started: $requestId")
        }

        val metric = LatencyMetric(
            requestId = requestId,
            modelName = modelName,
            startTime = Date(),
            endTime = null,
            latencyMs = null
        )

        mutex.withLock {
            latencyMetrics[requestId] = metric
            trimMetrics()
        }
    }

    /** Log the completion of an inference request. */
    suspend fun logInferenceComplete(requestId: String, tokensGenerated: Int? = null) {
        if (tokensGenerated != null) {
            Log.i(TAG_INFERENCE, "Inference completed: $requestId tokens=$tokensGenerated")
        } else {
            Log.i(TAG_INFERENCE, "Inference completed: $requestId")
        }

        mutex.withLock {
            latencyMetrics[requestId]?.let { metric ->
                val endTime = Date()
                val latencyMs = metric.startTime?.let { start ->
                    (endTime.time - start.time).toDouble()
                }
                latencyMetrics[requestId] = metric.copy(
                    endTime = endTime,
                    latencyMs = latencyMs
                )
            }
        }
    }

    /** Log an inference error. */
    fun logInferenceError(requestId: String, error: String) {
        Log.e(TAG_INFERENCE, "Inference failed: $requestId error=$error")
    }

    /** Record latency for a completed request. */
    suspend fun recordLatency(requestId: String, latencyMs: Double) {
        Log.d(TAG_INFERENCE, "Latency recorded: $requestId latency=${latencyMs}ms")

        mutex.withLock {
            latencyMetrics[requestId]?.let { metric ->
                latencyMetrics[requestId] = metric.copy(latencyMs = latencyMs)
            }
        }
    }

    // -------------------------------------------------------------------
    // Budget Logging
    // -------------------------------------------------------------------

    /** Log a budget violation. */
    suspend fun logBudgetViolation(
        type: BudgetViolationType,
        current: Double,
        limit: Double,
        severity: ViolationSeverity = ViolationSeverity.WARNING
    ) {
        val message = "Budget violation: ${type.value} current=$current limit=$limit severity=${severity.value}"

        when (severity) {
            ViolationSeverity.INFO -> Log.i(TAG_BUDGET, message)
            ViolationSeverity.WARNING -> Log.w(TAG_BUDGET, message)
            ViolationSeverity.CRITICAL -> Log.e(TAG_BUDGET, message)
        }

        val record = BudgetViolationRecord(
            timestamp = Date(),
            type = type,
            current = current,
            limit = limit,
            severity = severity
        )

        mutex.withLock {
            budgetViolations.add(record)
            trimViolations()
        }
    }

    /** Log budget enforcement action. */
    fun logBudgetEnforcement(action: String, reason: String) {
        Log.i(TAG_BUDGET, "Budget enforcement: $action reason=$reason")
    }

    /** Log measured baseline update. */
    fun logBaselineUpdate(p50: Double, p95: Double, p99: Double, sampleCount: Int) {
        Log.i(TAG_BUDGET, "Baseline updated: p50=${p50}ms p95=${p95}ms p99=${p99}ms samples=$sampleCount")
    }

    // -------------------------------------------------------------------
    // Resource Logging
    // -------------------------------------------------------------------

    /** Log current resource usage. */
    suspend fun logResourceUsage(
        memoryMb: Double,
        batteryLevel: Double? = null,
        thermalLevel: Int = 0
    ) {
        if (batteryLevel != null) {
            Log.d(TAG_RESOURCES, "Resources: memory=${memoryMb}MB battery=${(batteryLevel * 100).toInt()}% thermal=$thermalLevel")
        } else {
            Log.d(TAG_RESOURCES, "Resources: memory=${memoryMb}MB thermal=$thermalLevel")
        }

        val snapshot = ResourceSnapshot(
            timestamp = Date(),
            memoryMb = memoryMb,
            batteryLevel = batteryLevel,
            thermalLevel = thermalLevel
        )

        mutex.withLock {
            resourceSnapshots.add(snapshot)
            trimSnapshots()
        }
    }

    /** Log memory pressure event. */
    fun logMemoryPressure(current: Double, peak: Double, available: Double? = null) {
        if (available != null) {
            Log.w(TAG_RESOURCES, "Memory pressure: current=${current}MB peak=${peak}MB available=${available}MB")
        } else {
            Log.w(TAG_RESOURCES, "Memory pressure: current=${current}MB peak=${peak}MB")
        }
    }

    /** Log thermal state change. */
    fun logThermalStateChange(from: Int, to: Int) {
        Log.i(TAG_RESOURCES, "Thermal state changed: $from -> $to")
    }

    /** Log battery drain rate. */
    fun logBatteryDrain(drainRate: Double, currentLevel: Double) {
        Log.i(TAG_RESOURCES, "Battery drain: rate=${drainRate}%/10min level=${(currentLevel * 100).toInt()}%")
    }

    // -------------------------------------------------------------------
    // Scheduler Logging
    // -------------------------------------------------------------------

    /** Log task scheduling. */
    fun logTaskScheduled(taskId: String, priority: String) {
        Log.d(TAG_SCHEDULER, "Task scheduled: $taskId priority=$priority")
    }

    /** Log task execution start. */
    fun logTaskStarted(taskId: String) {
        Log.d(TAG_SCHEDULER, "Task started: $taskId")
    }

    /** Log task completion. */
    fun logTaskCompleted(taskId: String, durationMs: Double) {
        Log.d(TAG_SCHEDULER, "Task completed: $taskId duration=${durationMs}ms")
    }

    /** Log task cancellation. */
    fun logTaskCancelled(taskId: String, reason: String) {
        Log.i(TAG_SCHEDULER, "Task cancelled: $taskId reason=$reason")
    }

    /** Log queue status. */
    fun logQueueStatus(pending: Int, running: Int, priority: String) {
        Log.d(TAG_SCHEDULER, "Queue status: pending=$pending running=$running priority=$priority")
    }

    // -------------------------------------------------------------------
    // Policy Logging
    // -------------------------------------------------------------------

    /** Log policy change. */
    fun logPolicyChange(from: String, to: String) {
        Log.i(TAG_POLICY, "Policy changed: $from -> $to")
    }

    /** Log throttle decision. */
    fun logThrottleDecision(shouldThrottle: Boolean, factor: Double, reasons: List<String>) {
        if (shouldThrottle) {
            Log.w(TAG_POLICY, "Throttling applied: factor=$factor reasons=${reasons.joinToString(", ")}")
        } else {
            Log.d(TAG_POLICY, "No throttling needed")
        }
    }

    /** Log policy enforcement action. */
    fun logPolicyEnforcement(action: String, context: String) {
        Log.i(TAG_POLICY, "Policy enforcement: $action context=$context")
    }

    // -------------------------------------------------------------------
    // Metrics Retrieval
    // -------------------------------------------------------------------

    /** Get all stored latency metrics. */
    suspend fun getLatencyMetrics(): List<LatencyMetric> = mutex.withLock {
        latencyMetrics.values.toList()
    }

    /** Get latency metric for a specific request. */
    suspend fun getLatencyMetric(requestId: String): LatencyMetric? = mutex.withLock {
        latencyMetrics[requestId]
    }

    /** Get all budget violations. */
    suspend fun getBudgetViolations(): List<BudgetViolationRecord> = mutex.withLock {
        budgetViolations.toList()
    }

    /** Get recent budget violations (last N). */
    suspend fun getRecentViolations(count: Int): List<BudgetViolationRecord> = mutex.withLock {
        val startIndex = maxOf(0, budgetViolations.size - count)
        budgetViolations.subList(startIndex, budgetViolations.size).toList()
    }

    /** Get all resource snapshots. */
    suspend fun getResourceSnapshots(): List<ResourceSnapshot> = mutex.withLock {
        resourceSnapshots.toList()
    }

    /** Get recent resource snapshots (last N). */
    suspend fun getRecentSnapshots(count: Int): List<ResourceSnapshot> = mutex.withLock {
        val startIndex = maxOf(0, resourceSnapshots.size - count)
        resourceSnapshots.subList(startIndex, resourceSnapshots.size).toList()
    }

    /** Get aggregated latency statistics, or null if no completed metrics. */
    suspend fun getLatencyStats(): LatencyStats? = mutex.withLock {
        val latencies = latencyMetrics.values.mapNotNull { it.latencyMs }
        if (latencies.isEmpty()) return@withLock null

        val sorted = latencies.sorted()
        val count = sorted.size.toDouble()

        LatencyStats(
            count = sorted.size,
            min = sorted.first(),
            max = sorted.last(),
            mean = sorted.sum() / count,
            p50 = sorted[(count * 0.5).toInt().coerceAtMost(sorted.size - 1)],
            p95 = sorted[(count * 0.95).toInt().coerceAtMost(sorted.size - 1)],
            p99 = sorted[(count * 0.99).toInt().coerceAtMost(sorted.size - 1)]
        )
    }

    // -------------------------------------------------------------------
    // Cleanup
    // -------------------------------------------------------------------

    /** Clear all stored metrics. */
    suspend fun clearMetrics() = mutex.withLock {
        latencyMetrics.clear()
        budgetViolations.clear()
        resourceSnapshots.clear()
        Log.i(TAG_INFERENCE, "All metrics cleared")
    }

    /** Clear metrics older than specified duration in milliseconds. */
    suspend fun clearOldMetrics(olderThanMs: Long) = mutex.withLock {
        val cutoff = Date(System.currentTimeMillis() - olderThanMs)

        val keysToRemove = latencyMetrics.entries
            .filter { (_, metric) -> metric.startTime == null || metric.startTime.before(cutoff) }
            .map { it.key }
        for (key in keysToRemove) {
            latencyMetrics.remove(key)
        }

        budgetViolations.removeAll { it.timestamp.before(cutoff) }
        resourceSnapshots.removeAll { it.timestamp.before(cutoff) }

        Log.i(TAG_INFERENCE, "Cleared metrics older than ${olderThanMs}ms")
    }

    // -------------------------------------------------------------------
    // Private - Trimming
    // -------------------------------------------------------------------

    /** Must be called under [mutex] lock. */
    private fun trimMetrics() {
        if (latencyMetrics.size > maxStoredMetrics) {
            val toRemove = latencyMetrics.size - maxStoredMetrics
            val oldestKeys = latencyMetrics.entries
                .sortedBy { it.value.startTime?.time ?: 0L }
                .take(toRemove)
                .map { it.key }
            for (key in oldestKeys) {
                latencyMetrics.remove(key)
            }
        }
    }

    /** Must be called under [mutex] lock. */
    private fun trimViolations() {
        if (budgetViolations.size > maxStoredViolations) {
            val toRemove = budgetViolations.size - maxStoredViolations
            repeat(toRemove) { budgetViolations.removeFirst() }
        }
    }

    /** Must be called under [mutex] lock. */
    private fun trimSnapshots() {
        if (resourceSnapshots.size > maxStoredSnapshots) {
            val toRemove = resourceSnapshots.size - maxStoredSnapshots
            repeat(toRemove) { resourceSnapshots.removeFirst() }
        }
    }
}

// ---------------------------------------------------------------------------
// Supporting Types
// ---------------------------------------------------------------------------

/** Latency metric for a single inference request. */
data class LatencyMetric(
    val requestId: String,
    val modelName: String?,
    val startTime: Date?,
    val endTime: Date?,
    val latencyMs: Double?
)

/** Budget violation record. */
data class BudgetViolationRecord(
    val timestamp: Date,
    val type: BudgetViolationType,
    val current: Double,
    val limit: Double,
    val severity: ViolationSeverity
)

/** Resource usage snapshot. */
data class ResourceSnapshot(
    val timestamp: Date,
    val memoryMb: Double,
    val batteryLevel: Double?,
    val thermalLevel: Int
)

/** Aggregated latency statistics. */
data class LatencyStats(
    val count: Int,
    val min: Double,
    val max: Double,
    val mean: Double,
    val p50: Double,
    val p95: Double,
    val p99: Double
) {
    override fun toString(): String =
        "LatencyStats(count=$count, min=${"%.2f".format(min)}ms, max=${"%.2f".format(max)}ms, " +
            "mean=${"%.2f".format(mean)}ms, p50=${"%.2f".format(p50)}ms, " +
            "p95=${"%.2f".format(p95)}ms, p99=${"%.2f".format(p99)}ms)"
}

/** Budget violation type. */
enum class BudgetViolationType(val value: String) {
    LATENCY("latency"),
    MEMORY("memory"),
    BATTERY("battery"),
    THERMAL("thermal")
}

/** Violation severity level. */
enum class ViolationSeverity(val value: String) {
    INFO("info"),
    WARNING("warning"),
    CRITICAL("critical")
}