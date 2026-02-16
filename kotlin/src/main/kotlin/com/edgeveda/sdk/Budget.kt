package com.edgeveda.sdk

import java.util.Date

/**
 * Declarative compute budget contracts for on-device inference.
 *
 * An [EdgeVedaBudget] declares maximum resource limits that the [Scheduler]
 * enforces across concurrent workloads. Constraints are optional — set only
 * the ones you care about.
 *
 * Example:
 * ```kotlin
 * val budget = EdgeVedaBudget(
 *     p95LatencyMs = 2000,
 *     batteryDrainPerTenMinutes = 3.0,
 *     maxThermalLevel = 2,
 *     memoryCeilingMb = 1200
 * )
 * ```
 */
data class EdgeVedaBudget(
    /** Maximum p95 inference latency in milliseconds. Null to skip latency enforcement. */
    val p95LatencyMs: Int? = null,

    /** Maximum battery drain percentage per 10 minutes. Null to skip battery enforcement. */
    val batteryDrainPerTenMinutes: Double? = null,

    /** Maximum thermal level (0=nominal, 1=light, 2=moderate, 3=severe/critical). Null to skip. */
    val maxThermalLevel: Int? = null,

    /** Maximum memory RSS in megabytes. Null to skip memory enforcement. */
    val memoryCeilingMb: Int? = null,

    /** The adaptive profile, if created via [adaptive]. Null for explicit-value budgets. */
    val adaptiveProfile: BudgetProfile? = null
) {
    companion object {
        /**
         * Create an adaptive budget resolved against measured device performance after warm-up.
         *
         * Unlike explicit values, this stores the [profile] and lets the [Scheduler]
         * resolve concrete values after trackers have warmed up. Before resolution,
         * no budget enforcement occurs.
         */
        fun adaptive(profile: BudgetProfile): EdgeVedaBudget =
            EdgeVedaBudget(adaptiveProfile = profile)

        /**
         * Resolve an adaptive [profile] against a [baseline] to produce concrete budget values.
         *
         * Called internally by [Scheduler] after warm-up.
         */
        fun resolve(profile: BudgetProfile, baseline: MeasuredBaseline): EdgeVedaBudget {
            val resolvedP95: Int
            val resolvedDrain: Double?
            val resolvedThermal: Int

            when (profile) {
                BudgetProfile.CONSERVATIVE -> {
                    resolvedP95 = (baseline.measuredP95Ms * 2.0).toInt()
                    resolvedDrain = baseline.measuredDrainPerTenMin?.let { it * 0.6 }
                    resolvedThermal = if (baseline.currentThermalState < 1) 1 else baseline.currentThermalState
                }
                BudgetProfile.BALANCED -> {
                    resolvedP95 = (baseline.measuredP95Ms * 1.5).toInt()
                    resolvedDrain = baseline.measuredDrainPerTenMin?.let { it * 1.0 }
                    resolvedThermal = 1
                }
                BudgetProfile.PERFORMANCE -> {
                    resolvedP95 = (baseline.measuredP95Ms * 1.1).toInt()
                    resolvedDrain = baseline.measuredDrainPerTenMin?.let { it * 1.5 }
                    resolvedThermal = 3
                }
            }

            return EdgeVedaBudget(
                p95LatencyMs = resolvedP95,
                batteryDrainPerTenMinutes = resolvedDrain,
                maxThermalLevel = resolvedThermal,
                memoryCeilingMb = null // Memory is always observe-only
            )
        }
    }

    /**
     * Validate budget parameters for sanity.
     *
     * @return list of warnings for unrealistic values; empty means all OK.
     */
    fun validate(): List<String> {
        val warnings = mutableListOf<String>()

        p95LatencyMs?.let { p95 ->
            if (p95 < 500) {
                warnings.add(
                    "p95LatencyMs=$p95 is likely unrealistic for on-device LLM inference " +
                        "(typical: 1000-3000ms)"
                )
            }
        }

        batteryDrainPerTenMinutes?.let { drain ->
            if (drain < 0.5) {
                warnings.add(
                    "batteryDrainPerTenMinutes=$drain may be too restrictive for active inference"
                )
            }
        }

        memoryCeilingMb?.let { memory ->
            if (memory < 2000) {
                warnings.add(
                    "memoryCeilingMb=$memory may be too low for VLM workloads " +
                        "(typical RSS: 1500-2500MB including model + GPU buffers + image tensors). " +
                        "Consider setting to null to skip memory enforcement, or measure actual RSS " +
                        "after model load."
                )
            }
        }

        return warnings
    }

    override fun toString(): String {
        if (adaptiveProfile != null) {
            return "EdgeVedaBudget.adaptive(${adaptiveProfile.name.lowercase()})"
        }
        return "EdgeVedaBudget(p95LatencyMs=$p95LatencyMs, " +
            "batteryDrainPerTenMinutes=$batteryDrainPerTenMinutes, " +
            "maxThermalLevel=$maxThermalLevel, " +
            "memoryCeilingMb=$memoryCeilingMb)"
    }
}

// ---------------------------------------------------------------------------
// BudgetProfile
// ---------------------------------------------------------------------------

/**
 * Adaptive budget profile expressing intent as multipliers on measured device baseline.
 *
 * Instead of hard-coding absolute values, profiles multiply the actual measured
 * performance of THIS device with THIS model. The [Scheduler] resolves profile
 * multipliers against [MeasuredBaseline] after warm-up.
 */
enum class BudgetProfile {
    /**
     * Generous headroom: p95×2.0, battery×0.6 (strict), thermal=1 (light).
     * Best for background/secondary workloads where stability matters more than speed.
     */
    CONSERVATIVE,

    /**
     * Moderate headroom: p95×1.5, battery×1.0 (match baseline), thermal=1 (light).
     * Good default for most apps.
     */
    BALANCED,

    /**
     * Tight headroom: p95×1.1, battery×1.5 (generous), thermal=3 (allow critical).
     * For latency-sensitive apps willing to trade battery/thermal for speed.
     */
    PERFORMANCE
}

// ---------------------------------------------------------------------------
// MeasuredBaseline
// ---------------------------------------------------------------------------

/**
 * Snapshot of actual device performance measured during warm-up.
 *
 * The [Scheduler] builds this after its [LatencyTracker] and [BatteryDrainTracker]
 * have collected sufficient data.
 */
data class MeasuredBaseline(
    /** Measured p95 inference latency in milliseconds. */
    val measuredP95Ms: Double,

    /** Measured battery drain rate per 10 minutes (percentage). Null if unavailable. */
    val measuredDrainPerTenMin: Double? = null,

    /** Current thermal state at time of measurement (0-3, or -1 if unknown). */
    val currentThermalState: Int,

    /** Current process RSS in megabytes at time of measurement. */
    val currentRssMb: Double,

    /** Number of latency samples collected during warm-up. */
    val sampleCount: Int,

    /** When this baseline was captured. */
    val measuredAt: Date
) {
    override fun toString(): String {
        val drainStr = measuredDrainPerTenMin?.let { String.format("%.1f", it) } ?: "n/a"
        return "MeasuredBaseline(p95=${String.format("%.0f", measuredP95Ms)}ms, " +
            "drain=${drainStr}%/10min, thermal=$currentThermalState, " +
            "rss=${String.format("%.0f", currentRssMb)}MB, samples=$sampleCount)"
    }
}

// ---------------------------------------------------------------------------
// BudgetViolation
// ---------------------------------------------------------------------------

/**
 * Emitted when the [Scheduler] cannot satisfy a declared budget constraint
 * even after attempting mitigation.
 */
data class BudgetViolation(
    /** Which constraint was violated. */
    val constraint: BudgetConstraint,

    /** Current measured value that exceeds the budget. */
    val currentValue: Double,

    /** Declared budget value that was exceeded. */
    val budgetValue: Double,

    /** What mitigation was attempted (e.g., "degrade vision to minimal"). */
    val mitigation: String,

    /** When the violation was detected. */
    val timestamp: Date,

    /** Whether the mitigation was successful (constraint now satisfied). */
    val mitigated: Boolean,

    /** Whether this violation is observe-only (no QoS mitigation possible). */
    val observeOnly: Boolean = false
) {
    override fun toString(): String {
        val observeStr = if (observeOnly) "observeOnly=true, " else ""
        return "BudgetViolation(${constraint}: current=$currentValue, budget=$budgetValue, " +
            "${observeStr}mitigated=$mitigated, mitigation=$mitigation)"
    }
}

// ---------------------------------------------------------------------------
// BudgetConstraint
// ---------------------------------------------------------------------------

/** Which budget constraint was violated. */
enum class BudgetConstraint {
    /** p95 inference latency exceeded the declared maximum. */
    P95_LATENCY,

    /** Battery drain rate exceeded the declared maximum per 10 minutes. */
    BATTERY_DRAIN,

    /** Thermal level exceeded the declared maximum. */
    THERMAL_LEVEL,

    /** Memory RSS exceeded the declared ceiling. */
    MEMORY_CEILING
}

// ---------------------------------------------------------------------------
// WorkloadPriority
// ---------------------------------------------------------------------------

/**
 * Priority level for a registered workload.
 *
 * Higher-priority workloads are degraded **last** when the scheduler needs
 * to reduce resource usage to satisfy budget constraints.
 */
enum class WorkloadPriority {
    /** Low priority — degraded first when budget is at risk. */
    LOW,

    /** High priority — maintained as long as possible. */
    HIGH
}

// ---------------------------------------------------------------------------
// WorkloadId
// ---------------------------------------------------------------------------

/** Unique identifier for each workload type managed by the scheduler. */
enum class WorkloadId {
    /** Vision inference (VisionWorker). */
    VISION,

    /** Text/chat inference (StreamingWorker via ChatSession). */
    TEXT
}