package com.edgeveda.sdk

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.util.Log
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Runtime policy configuration for adaptive behavior.
 *
 * RuntimePolicy defines how the SDK should adapt its behavior based on
 * device state, battery level, thermal conditions, and execution context.
 *
 * Thread-safe via [Mutex] in [RuntimePolicyEnforcer].
 *
 * Example:
 * ```kotlin
 * val policy = RuntimePolicy(
 *     throttleOnBattery = true,
 *     adaptiveMemory = true,
 *     thermalAware = true,
 *     backgroundOptimization = false
 * )
 * enforcer.setPolicy(policy)
 * ```
 */
data class RuntimePolicy(
    /** Reduce performance when device is on battery power. */
    val throttleOnBattery: Boolean = true,

    /** Automatically adjust memory usage based on available memory. */
    val adaptiveMemory: Boolean = true,

    /** Throttle workload based on thermal pressure. */
    val thermalAware: Boolean = true,

    /** Optimize for background execution mode. */
    val backgroundOptimization: Boolean = false,

    /** Platform-specific options. */
    val options: RuntimePolicyOptions = RuntimePolicyOptions()
) {
    companion object {
        /** Conservative policy: Prioritize battery life and device health. */
        val CONSERVATIVE = RuntimePolicy(
            throttleOnBattery = true,
            adaptiveMemory = true,
            thermalAware = true,
            backgroundOptimization = true
        )

        /** Balanced policy: Balance performance and resource usage. */
        val BALANCED = RuntimePolicy(
            throttleOnBattery = true,
            adaptiveMemory = true,
            thermalAware = true,
            backgroundOptimization = false
        )

        /** Performance policy: Prioritize inference speed. */
        val PERFORMANCE = RuntimePolicy(
            throttleOnBattery = false,
            adaptiveMemory = false,
            thermalAware = false,
            backgroundOptimization = false
        )

        /** Default policy (same as balanced). */
        val DEFAULT = BALANCED
    }

    override fun toString(): String =
        "RuntimePolicy(throttleOnBattery=$throttleOnBattery, adaptiveMemory=$adaptiveMemory, " +
            "thermalAware=$thermalAware, backgroundOptimization=$backgroundOptimization)"
}

/**
 * Platform-specific runtime policy options.
 */
data class RuntimePolicyOptions(
    /** Enable thermal state monitoring (Android API 29+). */
    val thermalStateMonitoring: Boolean = true,

    /** Support background task execution. */
    val backgroundTaskSupport: Boolean = false,

    /** Enable performance observer APIs (Web). */
    val performanceObserver: Boolean = true,

    /** Enable worker pooling for concurrent tasks (Web). */
    val workerPooling: Boolean = true
)

/**
 * Runtime capabilities available on the current platform.
 *
 * Use [detect] to query the device for available monitoring APIs.
 */
data class RuntimeCapabilities(
    /** Thermal monitoring is available (PowerManager, API 29+). */
    val hasThermalMonitoring: Boolean,

    /** Battery monitoring is available (BatteryManager). */
    val hasBatteryMonitoring: Boolean,

    /** Memory monitoring is available. */
    val hasMemoryMonitoring: Boolean,

    /** Background task support is available. */
    val hasBackgroundTasks: Boolean,

    /** Current platform name. */
    val platform: String,

    /** Operating system version string. */
    val osVersion: String,

    /** Device model identifier. */
    val deviceModel: String
) {
    companion object {
        /**
         * Detect runtime capabilities for the current Android device.
         *
         * @param context Optional Android context for richer capability detection.
         */
        fun detect(context: Context? = null): RuntimeCapabilities {
            val hasThermalMonitoring = Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
            val hasBatteryMonitoring = context != null
            val hasMemoryMonitoring = true // Always available via Runtime + Debug
            val hasBackgroundTasks = true  // Android services

            val osVersion = "Android ${Build.VERSION.RELEASE} (API ${Build.VERSION.SDK_INT})"
            val deviceModel = "${Build.MANUFACTURER} ${Build.MODEL}"

            return RuntimeCapabilities(
                hasThermalMonitoring = hasThermalMonitoring,
                hasBatteryMonitoring = hasBatteryMonitoring,
                hasMemoryMonitoring = hasMemoryMonitoring,
                hasBackgroundTasks = hasBackgroundTasks,
                platform = "Android",
                osVersion = osVersion,
                deviceModel = deviceModel
            )
        }
    }
}

/**
 * Policy enforcement engine that applies runtime policies.
 *
 * Evaluates current device state (thermal, battery, memory) against the
 * active [RuntimePolicy] and provides throttle recommendations.
 *
 * Thread-safe via [Mutex] (Kotlin equivalent of Swift actor isolation).
 *
 * Example:
 * ```kotlin
 * val enforcer = RuntimePolicyEnforcer(context, policy = RuntimePolicy.BALANCED)
 * val recommendation = enforcer.shouldThrottle()
 * if (recommendation.shouldThrottle) {
 *     // Apply throttle factor to workload
 * }
 * ```
 */
class RuntimePolicyEnforcer(
    private val context: Context? = null,
    policy: RuntimePolicy = RuntimePolicy.DEFAULT,
    private val thermalMonitor: ThermalMonitor = ThermalMonitor(context),
    private val batteryTracker: BatteryDrainTracker = BatteryDrainTracker(context),
    private val resourceMonitor: ResourceMonitor = ResourceMonitor()
) {
    private val mutex = Mutex()
    private var currentPolicy: RuntimePolicy = policy

    companion object {
        private const val TAG = "EdgeVeda.PolicyEnforcer"
    }

    init {
        Log.i(
            TAG,
            "RuntimePolicyEnforcer initialized: throttleOnBattery=${policy.throttleOnBattery}, " +
                "thermalAware=${policy.thermalAware}"
        )
    }

    // -------------------------------------------------------------------
    // Policy Management
    // -------------------------------------------------------------------

    /** Set the runtime policy. */
    suspend fun setPolicy(policy: RuntimePolicy) = mutex.withLock {
        currentPolicy = policy
        Log.i(TAG, "Runtime policy updated: $policy")
    }

    /** Get the current runtime policy. */
    suspend fun getPolicy(): RuntimePolicy = mutex.withLock { currentPolicy }

    /** Get runtime capabilities for the current platform. */
    fun getCapabilities(): RuntimeCapabilities = RuntimeCapabilities.detect(context)

    // -------------------------------------------------------------------
    // Policy Enforcement
    // -------------------------------------------------------------------

    /**
     * Check if workload should be throttled based on current policy and device state.
     *
     * Evaluates thermal pressure, battery level, and memory usage against
     * the active policy to produce a [ThrottleRecommendation].
     */
    suspend fun shouldThrottle(): ThrottleRecommendation {
        val policy = mutex.withLock { currentPolicy }

        val reasons = mutableListOf<String>()
        var shouldThrottle = false
        var suggestedFactor = 1.0

        // Check thermal state
        if (policy.thermalAware) {
            val thermalLevel = thermalMonitor.currentLevel()
            if (thermalLevel >= 2) { // Serious or critical
                shouldThrottle = true
                reasons.add("Thermal pressure (level $thermalLevel)")
                suggestedFactor *= 0.5 // Reduce by 50%
            } else if (thermalLevel == 1) { // Fair
                suggestedFactor *= 0.8 // Reduce by 20%
            }
        }

        // Check battery state
        if (policy.throttleOnBattery) {
            val batteryLevel = batteryTracker.currentBatteryLevel()
            if (batteryLevel != null) {
                if (batteryLevel < 0.2f) { // Below 20%
                    shouldThrottle = true
                    reasons.add("Low battery (${(batteryLevel * 100).toInt()}%)")
                    suggestedFactor *= 0.6 // Reduce by 40%
                } else if (batteryLevel < 0.5f) { // Below 50%
                    suggestedFactor *= 0.9 // Reduce by 10%
                }
            }
        }

        // Check memory pressure
        if (policy.adaptiveMemory) {
            val currentMemory = resourceMonitor.currentRssMb()
            val peakMemory = resourceMonitor.peakRssMb()

            if (peakMemory > 0 && currentMemory > peakMemory * 0.9) { // Near peak
                shouldThrottle = true
                reasons.add("High memory usage (${currentMemory.toInt()}MB)")
                suggestedFactor *= 0.7 // Reduce by 30%
            }
        }

        return ThrottleRecommendation(
            shouldThrottle = shouldThrottle,
            throttleFactor = suggestedFactor,
            reasons = reasons
        )
    }

    /**
     * Check if background optimizations should be applied.
     *
     * On Android, checks if the app importance indicates a background state.
     */
    suspend fun shouldOptimizeForBackground(): Boolean {
        val policy = mutex.withLock { currentPolicy }
        if (!policy.backgroundOptimization) return false

        // On Android, check process importance if context is available
        if (context != null) {
            try {
                val activityManager =
                    context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                if (activityManager != null) {
                    val runningProcesses = activityManager.runningAppProcesses
                    val myProcess = runningProcesses?.find { it.pid == android.os.Process.myPid() }
                    if (myProcess != null) {
                        return myProcess.importance > ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to check background state: ${e.message}")
            }
        }

        return false
    }

    /**
     * Get suggested workload priority adjustment based on current policy.
     *
     * @return Multiplier for workload priority (0.0-2.0).
     */
    suspend fun getPriorityMultiplier(): Double {
        val throttle = shouldThrottle()

        if (throttle.shouldThrottle) {
            return throttle.throttleFactor
        }

        val policy = mutex.withLock { currentPolicy }

        // If performance policy and no throttling needed, boost priority
        if (!policy.throttleOnBattery && !policy.thermalAware) {
            return 1.2 // 20% boost
        }

        return 1.0
    }

    /**
     * Clean up resources held by the enforcer.
     *
     * Releases thermal monitor and battery tracker resources.
     */
    fun destroy() {
        thermalMonitor.destroy()
        batteryTracker.destroy()
    }
}

/**
 * Throttle recommendation based on current device state.
 */
data class ThrottleRecommendation(
    /** Whether workload should be throttled. */
    val shouldThrottle: Boolean,

    /** Suggested throttle factor (0.0-1.0, where 1.0 = no throttling). */
    val throttleFactor: Double,

    /** Human-readable reasons for throttling. */
    val reasons: List<String>
) {
    override fun toString(): String {
        return if (shouldThrottle) {
            "Throttle by ${((1.0 - throttleFactor) * 100).toInt()}%: ${reasons.joinToString(", ")}"
        } else {
            "No throttling needed"
        }
    }
}