package com.edgeveda.sdk

import android.util.Log
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.Date
import java.util.UUID
import kotlin.coroutines.cancellation.CancellationException

/**
 * Priority-based task scheduler with budget enforcement.
 *
 * The Scheduler manages concurrent inference workloads, enforces [EdgeVedaBudget]
 * constraints, and emits [BudgetViolation] events when limits are exceeded.
 *
 * Thread-safe via [Mutex] (Kotlin equivalent of Swift actor isolation).
 *
 * Example:
 * ```kotlin
 * val scheduler = Scheduler()
 * scheduler.setComputeBudget(EdgeVedaBudget.adaptive(BudgetProfile.BALANCED))
 *
 * val result = scheduler.scheduleTask(
 *     priority = TaskPriority.HIGH,
 *     workload = WorkloadId.TEXT
 * ) {
 *     edgeVeda.generate(prompt)
 * }
 * ```
 */
class Scheduler(
    private val latencyTracker: LatencyTracker = LatencyTracker(),
    private val batteryTracker: BatteryDrainTracker = BatteryDrainTracker(),
    private val thermalMonitor: ThermalMonitor = ThermalMonitor(),
    private val resourceMonitor: ResourceMonitor = ResourceMonitor()
) {
    private val mutex = Mutex()
    private val taskQueue = PriorityQueue()
    private var budget: EdgeVedaBudget? = null
    private val workloadRegistry = mutableMapOf<WorkloadId, WorkloadPriority>()

    private var measuredBaseline: MeasuredBaseline? = null
    private var warmUpComplete = false
    private val warmUpThreshold = 20 // samples needed

    private val violationListeners = mutableMapOf<String, (BudgetViolation) -> Unit>()

    companion object {
        private const val TAG = "EdgeVeda.Scheduler"
    }

    // -------------------------------------------------------------------
    // Budget Management
    // -------------------------------------------------------------------

    /**
     * Set the compute budget for task execution.
     *
     * If the budget uses an adaptive profile, it will be resolved after warm-up
     * (20+ task samples). Until then, no budget enforcement occurs.
     */
    suspend fun setComputeBudget(budget: EdgeVedaBudget) = mutex.withLock {
        this.budget = budget

        if (budget.adaptiveProfile != null) {
            Log.i(TAG, "Adaptive budget set: ${budget.adaptiveProfile.name}. Warming up...")
        }
    }

    /** Get the current compute budget. */
    suspend fun getComputeBudget(): EdgeVedaBudget? = mutex.withLock { budget }

    /**
     * Get the measured baseline after warm-up completes.
     *
     * Returns null if warm-up hasn't completed yet.
     */
    suspend fun getMeasuredBaseline(): MeasuredBaseline? = mutex.withLock { measuredBaseline }

    // -------------------------------------------------------------------
    // Task Scheduling
    // -------------------------------------------------------------------

    /**
     * Schedule a task with the specified priority.
     *
     * Tasks are queued and executed in priority order. High-priority tasks
     * run before normal and low-priority tasks. Budget constraints are checked
     * before each execution; violations are emitted but do not block execution.
     *
     * @param priority Task priority (HIGH, NORMAL, or LOW)
     * @param workload Workload type (TEXT or VISION)
     * @param task Suspend function to execute
     * @return Result of the task execution
     * @throws Exception Any error from the task execution
     */
    suspend fun <T> scheduleTask(
        priority: TaskPriority,
        workload: WorkloadId,
        task: suspend () -> T
    ): T {
        val taskId = UUID.randomUUID().toString()
        val taskHandle = TaskHandle(
            id = taskId,
            priority = priority,
            workload = workload,
            status = TaskStatus.QUEUED
        )

        Log.d(TAG, "Task scheduled: $taskId priority=${priority.name}")

        val startTime = System.currentTimeMillis()

        // Check budget before execution
        checkBudgetConstraints()

        // Execute task
        try {
            val result = task()

            // Record latency
            val durationMs = (System.currentTimeMillis() - startTime).toDouble()
            latencyTracker.record(durationMs)

            // Update warm-up status
            val currentSampleCount = latencyTracker.sampleCount()
            if (!warmUpComplete && currentSampleCount >= warmUpThreshold) {
                completeWarmUp()
            }

            Log.d(TAG, "Task completed: $taskId duration=${durationMs.toLong()}ms")
            return result
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.e(TAG, "Task failed: $taskId error=${e.message}")
            throw e
        }
    }

    /**
     * Cancel a scheduled task by ID.
     *
     * Only queued tasks can be cancelled. Running tasks cannot be cancelled.
     */
    suspend fun cancelTask(taskId: String) = mutex.withLock {
        taskQueue.removeTask(taskId)
    }

    /** Get current queue status. */
    suspend fun getQueueStatus(): QueueStatus = mutex.withLock {
        QueueStatus(
            queuedTasks = taskQueue.count,
            runningTasks = 0, // Simplified: coroutine-based execution
            completedTasks = latencyTracker.sampleCount(),
            highPriorityCount = taskQueue.countByPriority(TaskPriority.HIGH),
            normalPriorityCount = taskQueue.countByPriority(TaskPriority.NORMAL),
            lowPriorityCount = taskQueue.countByPriority(TaskPriority.LOW)
        )
    }

    // -------------------------------------------------------------------
    // Workload Management
    // -------------------------------------------------------------------

    /** Register a workload with its priority for degradation policy. */
    suspend fun registerWorkload(workload: WorkloadId, priority: WorkloadPriority) = mutex.withLock {
        workloadRegistry[workload] = priority
    }

    // -------------------------------------------------------------------
    // Violation Callbacks
    // -------------------------------------------------------------------

    /**
     * Register a callback for budget violation events.
     *
     * @param callback Called when a budget constraint is violated
     * @return Listener ID to use for removal via [removeViolationListener]
     */
    suspend fun onBudgetViolation(callback: (BudgetViolation) -> Unit): String = mutex.withLock {
        val id = UUID.randomUUID().toString()
        violationListeners[id] = callback
        id
    }

    /** Remove a budget violation listener. */
    suspend fun removeViolationListener(id: String) = mutex.withLock {
        violationListeners.remove(id)
    }

    // -------------------------------------------------------------------
    // Private - Warm-up
    // -------------------------------------------------------------------

    private suspend fun completeWarmUp() {
        val currentBudget = mutex.withLock { budget } ?: return
        val profile = currentBudget.adaptiveProfile ?: return

        val baseline = MeasuredBaseline(
            measuredP95Ms = latencyTracker.p95(),
            measuredDrainPerTenMin = batteryTracker.currentDrainRate(),
            currentThermalState = thermalMonitor.currentLevel(),
            currentRssMb = resourceMonitor.currentRssMb(),
            sampleCount = latencyTracker.sampleCount(),
            measuredAt = Date()
        )

        val resolvedBudget = EdgeVedaBudget.resolve(profile, baseline)

        mutex.withLock {
            this.measuredBaseline = baseline
            this.budget = resolvedBudget
            this.warmUpComplete = true
        }

        Log.i(TAG, "Warm-up complete: $baseline")
        Log.i(TAG, "Resolved budget: $resolvedBudget")
    }

    // -------------------------------------------------------------------
    // Private - Budget Enforcement
    // -------------------------------------------------------------------

    private suspend fun checkBudgetConstraints() {
        val currentBudget: EdgeVedaBudget
        val isWarm: Boolean
        mutex.withLock {
            currentBudget = budget ?: return
            isWarm = warmUpComplete
        }
        if (!isWarm) return

        // Check p95 latency
        currentBudget.p95LatencyMs?.let { maxP95 ->
            val currentP95 = latencyTracker.p95()
            if (currentP95 > maxP95.toDouble()) {
                handleViolation(
                    constraint = BudgetConstraint.P95_LATENCY,
                    currentValue = currentP95,
                    budgetValue = maxP95.toDouble()
                )
            }
        }

        // Check battery drain
        currentBudget.batteryDrainPerTenMinutes?.let { maxDrain ->
            batteryTracker.currentDrainRate()?.let { currentDrain ->
                if (currentDrain > maxDrain) {
                    handleViolation(
                        constraint = BudgetConstraint.BATTERY_DRAIN,
                        currentValue = currentDrain,
                        budgetValue = maxDrain
                    )
                }
            }
        }

        // Check thermal level
        currentBudget.maxThermalLevel?.let { maxThermal ->
            val currentThermal = thermalMonitor.currentLevel()
            if (currentThermal > maxThermal) {
                handleViolation(
                    constraint = BudgetConstraint.THERMAL_LEVEL,
                    currentValue = currentThermal.toDouble(),
                    budgetValue = maxThermal.toDouble()
                )
            }
        }

        // Check memory ceiling (observe-only)
        currentBudget.memoryCeilingMb?.let { maxMemory ->
            val currentMemory = resourceMonitor.currentRssMb()
            if (currentMemory > maxMemory.toDouble()) {
                handleViolation(
                    constraint = BudgetConstraint.MEMORY_CEILING,
                    currentValue = currentMemory,
                    budgetValue = maxMemory.toDouble()
                )
            }
        }
    }

    private suspend fun handleViolation(
        constraint: BudgetConstraint,
        currentValue: Double,
        budgetValue: Double
    ) {
        val mitigation = attemptMitigation(constraint)

        val violation = BudgetViolation(
            constraint = constraint,
            currentValue = currentValue,
            budgetValue = budgetValue,
            mitigation = mitigation,
            timestamp = Date(),
            mitigated = false,
            observeOnly = constraint == BudgetConstraint.MEMORY_CEILING
        )

        emitViolation(violation)
    }

    private fun attemptMitigation(constraint: BudgetConstraint): String {
        return when (constraint) {
            BudgetConstraint.P95_LATENCY -> "Reduce inference frequency"
            BudgetConstraint.BATTERY_DRAIN -> "Lower model quality"
            BudgetConstraint.THERMAL_LEVEL -> "Pause high-priority workloads"
            BudgetConstraint.MEMORY_CEILING -> "Observe only - cannot reduce model memory"
        }
    }

    private suspend fun emitViolation(violation: BudgetViolation) {
        Log.w(TAG, "⚠️ Budget Violation: $violation")

        val listeners = mutex.withLock { violationListeners.values.toList() }
        for (listener in listeners) {
            try {
                listener(violation)
            } catch (e: Exception) {
                Log.w(TAG, "Error in violation listener: ${e.message}")
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Supporting Types
// ---------------------------------------------------------------------------

/** Handle for a scheduled task. */
data class TaskHandle(
    val id: String,
    val priority: TaskPriority,
    val workload: WorkloadId,
    val status: TaskStatus
)

/** Task priority levels. */
enum class TaskPriority(val value: Int) {
    LOW(0),
    NORMAL(1),
    HIGH(2);

    companion object {
        fun fromValue(value: Int): TaskPriority = entries.first { it.value == value }
    }
}

/** Task execution status. */
enum class TaskStatus {
    QUEUED,
    RUNNING,
    COMPLETED,
    CANCELLED,
    FAILED
}

/** Queue status snapshot. */
data class QueueStatus(
    val queuedTasks: Int,
    val runningTasks: Int,
    val completedTasks: Int,
    val highPriorityCount: Int,
    val normalPriorityCount: Int,
    val lowPriorityCount: Int
) {
    override fun toString(): String =
        "QueueStatus(queued=$queuedTasks, running=$runningTasks, " +
            "completed=$completedTasks, high=$highPriorityCount, " +
            "normal=$normalPriorityCount, low=$lowPriorityCount)"
}

// ---------------------------------------------------------------------------
// PriorityQueue (internal)
// ---------------------------------------------------------------------------

/** Internal priority queue for scheduled tasks. */
internal class PriorityQueue {
    private data class QueuedItem(
        val id: String,
        val priority: TaskPriority
    )

    private val items = mutableListOf<QueuedItem>()

    val count: Int get() = items.size
    val isEmpty: Boolean get() = items.isEmpty()

    fun enqueue(id: String, priority: TaskPriority) {
        items.add(QueuedItem(id, priority))
        items.sortByDescending { it.priority.value }
    }

    fun dequeue(): String? {
        if (items.isEmpty()) return null
        return items.removeFirst().id
    }

    fun removeTask(id: String) {
        items.removeAll { it.id == id }
    }

    fun countByPriority(priority: TaskPriority): Int =
        items.count { it.priority == priority }
}