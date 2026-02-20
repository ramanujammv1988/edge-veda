package com.edgeveda.edge_veda

import android.app.ActivityManager
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.res.Configuration
import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Edge Veda Flutter Plugin for Android
 *
 * Handles:
 * 1. Native library loading (System.loadLibrary)
 * 2. Android memory pressure via onTrimMemory
 * 3. Lifecycle events for background kill recovery
 * 4. Device info queries via MethodChannel
 */
class EdgeVedaPlugin : FlutterPlugin, ComponentCallbacks2, MethodChannel.MethodCallHandler {

    private var applicationContext: Context? = null
    private var memoryPressureChannel: EventChannel? = null
    private var memoryEventSink: EventChannel.EventSink? = null
    private var deviceInfoChannel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext

        // Register for memory callbacks
        binding.applicationContext.registerComponentCallbacks(this)

        // Set up EventChannel for memory pressure events to Dart
        memoryPressureChannel = EventChannel(
            binding.binaryMessenger,
            "com.edgeveda.edge_veda/memory_pressure"
        )
        memoryPressureChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                memoryEventSink = events
            }

            override fun onCancel(arguments: Any?) {
                memoryEventSink = null
            }
        })

        // Set up MethodChannel for device info queries
        deviceInfoChannel = MethodChannel(
            binding.binaryMessenger,
            "com.edgeveda.edge_veda/device_info"
        )
        deviceInfoChannel?.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext?.unregisterComponentCallbacks(this)
        applicationContext = null
        memoryPressureChannel?.setStreamHandler(null)
        memoryPressureChannel = null
        memoryEventSink = null
        deviceInfoChannel?.setMethodCallHandler(null)
        deviceInfoChannel = null
    }

    // MethodChannel.MethodCallHandler for device info

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getDeviceModel" -> {
                result.success(Build.MODEL)
            }
            "getChipName" -> {
                val chip = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    Build.SOC_MODEL
                } else {
                    Build.HARDWARE
                }
                result.success(chip)
            }
            "getTotalMemory" -> {
                val activityManager = applicationContext?.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                if (activityManager != null) {
                    val memInfo = ActivityManager.MemoryInfo()
                    activityManager.getMemoryInfo(memInfo)
                    result.success(memInfo.totalMem)
                } else {
                    result.success(0L)
                }
            }
            "hasNeuralEngine" -> {
                // Android doesn't have a direct Neural Engine equivalent;
                // NNAPI availability is a rough proxy but not guaranteed useful.
                result.success(false)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    // ComponentCallbacks2 interface for memory pressure

    override fun onTrimMemory(level: Int) {
        // Map Android trim levels to our memory pressure levels
        // TRIM_MEMORY_RUNNING_CRITICAL = 15 (highest pressure while running)
        // TRIM_MEMORY_RUNNING_LOW = 10
        // TRIM_MEMORY_RUNNING_MODERATE = 5
        // TRIM_MEMORY_UI_HIDDEN = 20 (app in background)
        // TRIM_MEMORY_BACKGROUND = 40
        // TRIM_MEMORY_MODERATE = 60
        // TRIM_MEMORY_COMPLETE = 80 (about to be killed)

        val pressureLevel = when {
            level >= ComponentCallbacks2.TRIM_MEMORY_COMPLETE -> "critical"
            level >= ComponentCallbacks2.TRIM_MEMORY_MODERATE -> "high"
            level >= ComponentCallbacks2.TRIM_MEMORY_BACKGROUND -> "medium"
            level >= ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN -> "background"
            level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL -> "running_critical"
            level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW -> "running_low"
            else -> "normal"
        }

        // Send to Dart via EventChannel
        memoryEventSink?.success(mapOf(
            "level" to level,
            "pressureLevel" to pressureLevel
        ))

        // Log for debugging
        android.util.Log.d("EdgeVeda", "onTrimMemory: level=$level ($pressureLevel)")
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        // Not needed for memory handling
    }

    override fun onLowMemory() {
        // Legacy callback - treat as critical
        memoryEventSink?.success(mapOf(
            "level" to ComponentCallbacks2.TRIM_MEMORY_COMPLETE,
            "pressureLevel" to "critical"
        ))
        android.util.Log.w("EdgeVeda", "onLowMemory called - critical pressure")
    }

    companion object {
        init {
            // Load native library when plugin class is loaded
            System.loadLibrary("edge_veda")
        }
    }
}
