package com.edgeveda.sdk

import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.util.Log
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.UUID

/**
 * Monitors device thermal state for budget enforcement.
 *
 * Tracks thermal pressure levels (0-3) using Android [PowerManager] API (API 29+).
 * Thermal monitoring helps prevent device overheating and throttling.
 *
 * Thermal Levels:
 * - 0: None / Nominal (normal operation)
 * - 1: Light / Fair (slight thermal pressure)
 * - 2: Moderate / Serious (significant thermal pressure, recommend throttling)
 * - 3: Severe / Critical (severe thermal pressure, must throttle)
 * - -1: Unavailable (platform doesn't support thermal monitoring or API < 29)
 *
 * Thread-safe via [Mutex] (Kotlin equivalent of Swift actor isolation).
 *
 * Example:
 * ```kotlin
 * val monitor = ThermalMonitor(context)
 * val level = monitor.currentLevel()
 * if (level >= 2) {
 *     // Throttle inference workload
 * }
 * ```
 */
class ThermalMonitor(
    private val context: Context? = null
) {
    private val mutex = Mutex()
    private var _currentLevel: Int = -1
    private val stateChangeListeners = mutableMapOf<String, (Int) -> Unit>()
    private var thermalStatusListener: Any? = null // Holds the OnThermalStatusChangedListener ref

    companion object {
        private const val TAG = "EdgeVeda.ThermalMonitor"
    }

    init {
        if (context != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                if (powerManager != null) {
                    // Get initial thermal status
                    _currentLevel = mapThermalStatus(powerManager.currentThermalStatus)

                    // Register for thermal status changes (API 29+)
                    val listener = PowerManager.OnThermalStatusChangedListener { status ->
                        val newLevel = mapThermalStatus(status)
                        handleThermalStateChange(newLevel)
                    }
                    powerManager.addThermalStatusListener(listener)
                    thermalStatusListener = listener

                    Log.i(TAG, "ThermalMonitor initialized. Current level: $_currentLevel")
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to initialize thermal monitoring: ${e.message}")
                _currentLevel = -1
            }
        } else {
            Log.i(TAG, "ThermalMonitor: thermal API unavailable (requires API 29+)")
        }
    }

    // -----------------------------------------------------------------------
    // Public Properties
    // -----------------------------------------------------------------------

    /** Current thermal level (0-3, or -1 if unavailable). */
    suspend fun currentLevel(): Int = mutex.withLock { _currentLevel }

    /** Human-readable thermal state name. */
    suspend fun currentStateName(): String = mutex.withLock {
        thermalLevelName(_currentLevel)
    }

    /** Whether thermal monitoring is supported on this device. */
    val isSupported: Boolean
        get() = context != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q

    /**
     * Check if current thermal state requires throttling.
     *
     * Returns true if thermal level is 2 (moderate/serious) or higher.
     */
    suspend fun shouldThrottle(): Boolean = mutex.withLock { _currentLevel >= 2 }

    /**
     * Check if current thermal state is critical.
     *
     * Returns true if thermal level is 3 (severe/critical).
     */
    suspend fun isCritical(): Boolean = mutex.withLock { _currentLevel >= 3 }

    // -----------------------------------------------------------------------
    // Listener Management
    // -----------------------------------------------------------------------

    /**
     * Register a callback for thermal state changes.
     *
     * @param callback Called when thermal state changes with the new level.
     * @return Listener ID to use for removal via [removeListener].
     */
    suspend fun onThermalStateChange(callback: (Int) -> Unit): String = mutex.withLock {
        val id = UUID.randomUUID().toString()
        stateChangeListeners[id] = callback
        id
    }

    /** Remove a thermal state change listener. */
    suspend fun removeListener(id: String) = mutex.withLock {
        stateChangeListeners.remove(id)
    }

    // -----------------------------------------------------------------------
    // Cleanup
    // -----------------------------------------------------------------------

    /**
     * Unregister the system thermal listener.
     *
     * Call when the monitor is no longer needed to avoid leaks.
     */
    fun destroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && context != null) {
            try {
                val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
                val listener = thermalStatusListener as? PowerManager.OnThermalStatusChangedListener
                if (powerManager != null && listener != null) {
                    powerManager.removeThermalStatusListener(listener)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Error removing thermal listener: ${e.message}")
            }
        }
        thermalStatusListener = null
    }

    // -----------------------------------------------------------------------
    // Private
    // -----------------------------------------------------------------------

    private fun handleThermalStateChange(newLevel: Int) {
        val previousLevel = _currentLevel
        _currentLevel = newLevel

        if (previousLevel != newLevel) {
            Log.i(TAG, "Thermal state changed: ${thermalLevelName(previousLevel)} → ${thermalLevelName(newLevel)}")

            // Notify listeners (snapshot to avoid ConcurrentModificationException)
            val listeners = synchronized(stateChangeListeners) {
                stateChangeListeners.values.toList()
            }
            for (listener in listeners) {
                try {
                    listener(newLevel)
                } catch (e: Exception) {
                    Log.w(TAG, "Error in thermal listener callback: ${e.message}")
                }
            }
        }
    }

    /**
     * Map Android [PowerManager] thermal status constants to our 0-3 level scheme.
     *
     * Android constants (API 29+):
     * - THERMAL_STATUS_NONE (0) → 0 (nominal)
     * - THERMAL_STATUS_LIGHT (1) → 1 (fair)
     * - THERMAL_STATUS_MODERATE (2) → 2 (serious)
     * - THERMAL_STATUS_SEVERE (3) → 3 (critical)
     * - THERMAL_STATUS_CRITICAL (4) → 3 (critical)
     * - THERMAL_STATUS_EMERGENCY (5) → 3 (critical)
     * - THERMAL_STATUS_SHUTDOWN (6) → 3 (critical)
     */
    private fun mapThermalStatus(status: Int): Int {
        return when {
            status <= 0 -> 0  // NONE → nominal
            status == 1 -> 1  // LIGHT → fair
            status == 2 -> 2  // MODERATE → serious
            status >= 3 -> 3  // SEVERE/CRITICAL/EMERGENCY/SHUTDOWN → critical
            else -> -1
        }
    }

    private fun thermalLevelName(level: Int): String {
        return when (level) {
            0 -> "nominal"
            1 -> "fair"
            2 -> "serious"
            3 -> "critical"
            else -> "unavailable"
        }
    }
}