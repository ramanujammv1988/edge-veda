package com.edgeveda.sdk.examples

import com.edgeveda.sdk.*
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlin.random.Random

/**
 * Phase 4 — Runtime Supervision demo for Android/Kotlin.
 *
 * Demonstrates the declarative budget system, adaptive profiles, runtime
 * policies, scheduler priority queues, latency tracking, resource monitoring,
 * thermal monitoring, battery drain tracking, and telemetry.
 *
 * Usage:
 * ```kotlin
 * // In an Android Activity or ViewModel:
 * lifecycleScope.launch {
 *     RuntimeSupervisionExample.run(applicationContext)
 * }
 * ```
 */
object RuntimeSupervisionExample {

    suspend fun run(context: android.content.Context? = null) {
        println("EdgeVeda Kotlin SDK — Runtime Supervision (Phase 4)")
        println("====================================================\n")

        // ─────────────────────────────────────────────────────
        // 1. Declarative Compute Budgets
        // ─────────────────────────────────────────────────────
        println("1. Declarative Compute Budgets")
        println("───────────────────────────────")

        // Explicit budget with hard limits
        val explicitBudget = EdgeVedaBudget(
            p95LatencyMs = 2000.0,
            batteryDrainPerTenMinutes = 3.0,
            maxThermalLevel = 2,
            memoryCeilingMb = 1200.0
        )
        println("Explicit budget:  $explicitBudget")

        // Validate — will warn about memory ceiling
        val warnings = explicitBudget.validate()
        if (warnings.isNotEmpty()) {
            println("Warnings:")
            for (w in warnings) println("  ⚠️  $w")
        }
        println()

        // ─────────────────────────────────────────────────────
        // 2. Adaptive Budget Profiles
        // ─────────────────────────────────────────────────────
        println("2. Adaptive Budget Profiles")
        println("───────────────────────────")
        for (profile in BudgetProfile.entries) {
            val budget = EdgeVedaBudget.adaptive(profile)
            println("  .${profile.name}  →  $budget")
        }
        println()

        // Resolve a profile against a simulated baseline
        val baseline = MeasuredBaseline(
            measuredP95Ms = 1500.0,
            measuredDrainPerTenMin = 2.0,
            currentThermalState = 0,
            currentRssMb = 1800.0,
            sampleCount = 25,
            measuredAt = System.currentTimeMillis()
        )
        println("Measured baseline:  $baseline")

        for (profile in BudgetProfile.entries) {
            val resolved = EdgeVedaBudget.resolve(profile, baseline)
            println("  .${profile.name} resolved →  $resolved")
        }
        println()

        // ─────────────────────────────────────────────────────
        // 3. Budget Violations
        // ─────────────────────────────────────────────────────
        println("3. Budget Violation Events")
        println("──────────────────────────")

        val violation = BudgetViolation(
            constraint = BudgetConstraint.P95_LATENCY,
            currentValue = 2500.0,
            budgetValue = 2000.0,
            mitigation = "Reduced vision FPS 30→15",
            timestamp = System.currentTimeMillis(),
            mitigated = true
        )
        println("  $violation")

        val memViolation = BudgetViolation(
            constraint = BudgetConstraint.MEMORY_CEILING,
            currentValue = 2100.0,
            budgetValue = 1200.0,
            mitigation = "Observe-only: QoS cannot reduce model RSS",
            timestamp = System.currentTimeMillis(),
            mitigated = false,
            observeOnly = true
        )
        println("  $memViolation")
        println()

        // ─────────────────────────────────────────────────────
        // 4. Runtime Policy
        // ─────────────────────────────────────────────────────
        println("4. Runtime Policy")
        println("─────────────────")

        val capabilities = if (context != null) {
            RuntimeCapabilities.detect(context)
        } else {
            RuntimeCapabilities(
                hasThermalMonitoring = false,
                hasBatteryMonitoring = false,
                hasMemoryPressureNotifications = true
            )
        }
        println("  Capabilities: $capabilities")

        val policies = listOf(
            RuntimePolicy.CONSERVATIVE,
            RuntimePolicy.BALANCED,
            RuntimePolicy.PERFORMANCE
        )
        for (policy in policies) {
            println("  ${policy.name}: $policy")
        }

        // Custom policy
        val customPolicy = RuntimePolicy(
            name = "background-sync",
            options = RuntimePolicyOptions(
                throttleOnBattery = true,
                adaptiveMemory = true,
                backgroundOptimization = true
            )
        )
        println("  Custom: $customPolicy")
        println()

        // RuntimePolicyEnforcer (requires context for full functionality)
        val thermalMonitor = ThermalMonitor(context)
        val batteryTracker = BatteryDrainTracker(context)
        val resourceMonitor = ResourceMonitor()

        val enforcer = RuntimePolicyEnforcer(
            context = context,
            policy = RuntimePolicy.BALANCED,
            thermalMonitor = thermalMonitor,
            batteryTracker = batteryTracker,
            resourceMonitor = resourceMonitor
        )

        val throttle = enforcer.shouldThrottle()
        println("  Throttle recommendation: $throttle")
        println("  Priority multiplier: ${enforcer.getPriorityMultiplier()}")
        println()

        // ─────────────────────────────────────────────────────
        // 5. Latency Tracker
        // ─────────────────────────────────────────────────────
        println("5. Latency Tracker")
        println("──────────────────")

        val latencyTracker = LatencyTracker()

        // Simulate 30 inference latency samples
        for (i in 0 until 30) {
            latencyTracker.record(Random.nextDouble(800.0, 2200.0))
        }

        val count = latencyTracker.sampleCount()
        val p50 = latencyTracker.p50()
        val p95 = latencyTracker.p95()
        val p99 = latencyTracker.p99()
        val avg = latencyTracker.average()

        println("  Samples: $count")
        println("  p50=${p50?.let { "%.0f".format(it) } ?: "n/a"}ms  " +
                "p95=${p95?.let { "%.0f".format(it) } ?: "n/a"}ms  " +
                "p99=${p99?.let { "%.0f".format(it) } ?: "n/a"}ms")
        println("  average=${avg?.let { "%.0f".format(it) } ?: "n/a"}ms")
        println()

        // ─────────────────────────────────────────────────────
        // 6. Resource Monitor
        // ─────────────────────────────────────────────────────
        println("6. Resource Monitor (Memory RSS)")
        println("────────────────────────────────")

        for (i in 0 until 5) {
            resourceMonitor.sample()
        }

        val currentRss = resourceMonitor.currentRssMb()
        val peakRss = resourceMonitor.peakRssMb()
        val avgRss = resourceMonitor.averageRssMb()
        val rssSamples = resourceMonitor.sampleCount()

        println("  Current RSS: ${"%.1f".format(currentRss)} MB")
        println("  Peak RSS:    ${"%.1f".format(peakRss)} MB")
        println("  Average RSS: ${"%.1f".format(avgRss)} MB")
        println("  Samples:     $rssSamples")
        println()

        // ─────────────────────────────────────────────────────
        // 7. Thermal Monitor
        // ─────────────────────────────────────────────────────
        println("7. Thermal Monitor")
        println("──────────────────")

        val thermalLevel = thermalMonitor.currentLevel()
        val thermalName = thermalMonitor.currentStateName()
        val shouldThrottle = thermalMonitor.shouldThrottle()
        val isCritical = thermalMonitor.isCritical()

        println("  Supported: ${thermalMonitor.isSupported}")
        println("  Level: $thermalLevel ($thermalName)")
        println("  Should throttle: $shouldThrottle")
        println("  Is critical:     $isCritical")

        // Register a thermal listener
        val listenerId = thermalMonitor.onThermalStateChange { level ->
            println("  🌡️  Thermal state changed → level $level")
        }
        println("  Listener registered: ${listenerId.take(8)}…")
        thermalMonitor.removeListener(listenerId)
        println()

        // ─────────────────────────────────────────────────────
        // 8. Battery Drain Tracker
        // ─────────────────────────────────────────────────────
        println("8. Battery Drain Tracker")
        println("────────────────────────")

        val batterySupported = batteryTracker.isSupported
        println("  Supported: $batterySupported")

        if (batterySupported) {
            batteryTracker.recordSample()
            val level = batteryTracker.currentBatteryLevel()
            if (level != null) {
                println("  Battery level: ${"%.0f".format(level * 100)}%")
            }
            val drain = batteryTracker.currentDrainRate()
            if (drain != null) {
                println("  Drain rate: ${"%.2f".format(drain)}% / 10 min")
            } else {
                println("  Drain rate: accumulating samples…")
            }
        } else {
            println("  (Battery monitoring unavailable — no Context provided)")
        }
        println()

        // ─────────────────────────────────────────────────────
        // 9. Scheduler (priority queue)
        // ─────────────────────────────────────────────────────
        println("9. Scheduler — Priority Task Queue")
        println("───────────────────────────────────")

        val scheduler = Scheduler(
            latencyTracker = latencyTracker,
            batteryTracker = batteryTracker,
            thermalMonitor = thermalMonitor,
            resourceMonitor = resourceMonitor
        )

        // Set a compute budget
        scheduler.setComputeBudget(EdgeVedaBudget.adaptive(BudgetProfile.BALANCED))

        // Schedule tasks at different priorities
        val highResult = scheduler.scheduleTask<String>(
            priority = TaskPriority.HIGH,
            workload = WorkloadId.TEXT
        ) {
            delay(10)
            "high-priority result"
        }

        val normalResult = scheduler.scheduleTask<String>(
            priority = TaskPriority.NORMAL,
            workload = WorkloadId.TEXT
        ) {
            "normal-priority result"
        }

        val lowResult = scheduler.scheduleTask<String>(
            priority = TaskPriority.LOW,
            workload = WorkloadId.VISION
        ) {
            "low-priority result"
        }

        println("  HIGH   → $highResult")
        println("  NORMAL → $normalResult")
        println("  LOW    → $lowResult")

        val queueStatus = scheduler.getQueueStatus()
        println("  Queue status: $queueStatus")

        // Register budget violation listener
        val violationListenerId = scheduler.onBudgetViolation { v ->
            println("  ⚠️  Budget violation: ${v.constraint} " +
                    "(current=${v.currentValue}, budget=${v.budgetValue})")
        }
        println("  Violation listener: ${violationListenerId.take(8)}…")
        scheduler.removeViolationListener(violationListenerId)
        println()

        // ─────────────────────────────────────────────────────
        // 10. Telemetry
        // ─────────────────────────────────────────────────────
        println("10. Telemetry — Structured Logging & Metrics")
        println("─────────────────────────────────────────────")

        val telemetry = Telemetry.instance

        telemetry.logInferenceStart("req-001", "gemma-2b")
        telemetry.logInferenceComplete("req-001", tokensGenerated = 42)
        telemetry.recordLatency("req-001", p95 ?: 1500.0)
        telemetry.logResourceUsage(
            memoryMb = currentRss,
            batteryLevel = batteryTracker.currentBatteryLevel(),
            thermalLevel = thermalLevel
        )
        telemetry.logBudgetViolation(
            type = BudgetViolationType.P95_LATENCY,
            current = 2500.0,
            limit = 2000.0,
            severity = ViolationSeverity.WARNING
        )

        val latencyMetrics = telemetry.getLatencyMetrics()
        println("  Latency metrics: ${latencyMetrics.size} entries")

        val latencyStats = telemetry.getLatencyStats()
        if (latencyStats != null) {
            println("  Stats: p50=${"%.0f".format(latencyStats.p50)}ms, " +
                    "p95=${"%.0f".format(latencyStats.p95)}ms, " +
                    "avg=${"%.0f".format(latencyStats.average)}ms")
        }

        val violations = telemetry.getRecentViolations(5)
        println("  Recent violations: ${violations.size}")

        val snapshots = telemetry.getRecentSnapshots(5)
        println("  Recent snapshots: ${snapshots.size}")

        telemetry.clearMetrics()
        println("  Metrics cleared.")
        println()

        // Clean up
        thermalMonitor.destroy()
        batteryTracker.destroy()
        enforcer.destroy()

        // ─────────────────────────────────────────────────────
        // Summary
        // ─────────────────────────────────────────────────────
        println("====================================================")
        println("Phase 4 Runtime Supervision — all components active")
        println("  ✅ ComputeBudget (declarative + adaptive)")
        println("  ✅ BudgetProfile (CONSERVATIVE / BALANCED / PERFORMANCE)")
        println("  ✅ MeasuredBaseline + budget resolution")
        println("  ✅ BudgetViolation events")
        println("  ✅ RuntimePolicy (CONSERVATIVE / BALANCED / PERFORMANCE / custom)")
        println("  ✅ RuntimePolicyEnforcer (throttle, priority multiplier)")
        println("  ✅ LatencyTracker (percentiles)")
        println("  ✅ ResourceMonitor (RSS, peak, average)")
        println("  ✅ ThermalMonitor (level, listeners)")
        println("  ✅ BatteryDrainTracker (drain rate, platform-aware)")
        println("  ✅ Scheduler (priority queue, budget violations)")
        println("  ✅ Telemetry (inference logs, latency stats, resource snapshots)")
        println("====================================================")
    }
}