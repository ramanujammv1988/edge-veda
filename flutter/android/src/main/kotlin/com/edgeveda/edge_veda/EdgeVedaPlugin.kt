package com.edgeveda.edge_veda

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/**
 * Edge Veda Flutter Plugin for Android
 *
 * Handles:
 * 1. Native library loading (System.loadLibrary)
 * 2. Android memory pressure via onTrimMemory
 * 3. Lifecycle events for background kill recovery
 * 4. MethodChannel APIs for Dart to interact with the JNI NativeEdgeVeda layer
 * 5. Audio capture via EventChannel wrapping AudioRecord
 */
class EdgeVedaPlugin : FlutterPlugin, MethodCallHandler, ComponentCallbacks2, ActivityAware, PluginRegistry.RequestPermissionsResultListener {

    private var applicationContext: Context? = null
    private var activity: Activity? = null
    private lateinit var channel: MethodChannel
    private lateinit var telemetryChannel: MethodChannel
    private var memoryPressureChannel: EventChannel? = null
    private var memoryEventSink: EventChannel.EventSink? = null
    private var audioCaptureChannel: EventChannel? = null
    
    private var permissionResultListener: Result? = null
    private val nativeEngine = NativeEdgeVeda()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext

        // Register for MethodChannel calls from Dart
        channel = MethodChannel(binding.binaryMessenger, "com.edgeveda.edge_veda")
        channel.setMethodCallHandler(this)

        // Telemetry channel for iOS/macOS parity
        telemetryChannel = MethodChannel(binding.binaryMessenger, "com.edgeveda.edge_veda/telemetry")
        telemetryChannel.setMethodCallHandler(this)

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

        // Set up EventChannel for audio capture
        audioCaptureChannel = EventChannel(
            binding.binaryMessenger,
            "com.edgeveda.edge_veda/audio_capture"
        )
        audioCaptureChannel?.setStreamHandler(AudioCaptureHandler())
    }

    // ActivityAware Implementation
    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        if (requestCode == 1001) {
            val granted = grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED
            permissionResultListener?.success(granted)
            permissionResultListener = null
            return true
        }
        return false
    }
    
    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${Build.VERSION.RELEASE}")
            }
            "getEdgeVedaVersion" -> {
                val version = nativeEngine.getVersionNative()
                result.success(version)
            }
            "requestMicrophonePermission" -> {
                if (activity == null) {
                    result.error("NO_ACTIVITY", "Activity is null", null)
                    return
                }
                if (ContextCompat.checkSelfPermission(activity!!, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
                    result.success(true)
                } else {
                    permissionResultListener = result
                    ActivityCompat.requestPermissions(activity!!, arrayOf(Manifest.permission.RECORD_AUDIO), 1001)
                }
            }
            // Stub audio session tools (expected by whisper_session.dart)
            "configureVoicePipelineAudio", "resetAudioSession" -> {
                result.success(true) 
            }
            "getDeviceMemoryInfo" -> {
                if (applicationContext == null) {
                    result.error("CONTEXT_MISSING", "Application context is null", null)
                    return
                }
                
                val activityManager = applicationContext?.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                if (activityManager != null) {
                    val memoryInfo = ActivityManager.MemoryInfo()
                    activityManager.getMemoryInfo(memoryInfo)
                    
                    val infoMap = mapOf(
                        "totalMem" to memoryInfo.totalMem,
                        "availMem" to memoryInfo.availMem,
                        "lowMemory" to memoryInfo.lowMemory,
                        "threshold" to memoryInfo.threshold
                    )
                    result.success(infoMap)
                } else {
                    result.error("SERVICE_UNAVAILABLE", "Could not get ActivityManager", null)
                }
            }
            "initContext" -> {
                val modelPath = call.argument<String>("modelPath") ?: ""
                val threads = call.argument<Int>("numThreads") ?: 4
                val contextSize = call.argument<Int>("contextSize") ?: 2048
                val batchSize = call.argument<Int>("batchSize") ?: 512
                
                if (modelPath.isEmpty()) {
                    result.error("INVALID_ARGUMENT", "modelPath cannot be empty", null)
                    return
                }
                
                val ctxPtr = nativeEngine.initContextNative(modelPath, threads, contextSize, batchSize)
                if (ctxPtr == 0L) {
                    result.error("INIT_FAILED", "Failed to initialize native context.", null)
                } else {
                    result.success(ctxPtr)
                }
            }
            "freeContext" -> {
                val ctxPtr = call.argument<Long>("contextPtr") ?: 0L
                if (ctxPtr != 0L) {
                    nativeEngine.freeContextNative(ctxPtr)
                }
                result.success(null)
            }
            "generate" -> {
                val ctxPtr = call.argument<Long>("contextPtr") ?: 0L
                val prompt = call.argument<String>("prompt") ?: ""
                val maxTokens = call.argument<Int>("maxTokens") ?: 512
                
                if (ctxPtr == 0L || prompt.isEmpty()) {
                    result.error("INVALID_ARGUMENT", "contextPtr and prompt cannot be empty", null)
                    return
                }
                
                val output = nativeEngine.generateNative(ctxPtr, prompt, maxTokens)
                result.success(output)
            }
            "getAvailableMemory" -> {
                val activityManager = applicationContext?.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                if (activityManager != null) {
                    val memoryInfo = ActivityManager.MemoryInfo()
                    activityManager.getMemoryInfo(memoryInfo)
                    result.success(memoryInfo.availMem)
                } else {
                    result.success(0L)
                }
            }
            "getThermalState" -> {
                // Android does not have direct thermal state API equivalent to iOS
                // Return -1 (unknown) per TelemetryService convention
                result.success(-1)
            }
            "getBatteryLevel" -> {
                result.success(-1.0)
            }
            "getBatteryState" -> {
                result.success(0)
            }
            "getMemoryRSS" -> {
                // Use Debug.getNativeHeapAllocatedSize() as rough RSS proxy
                result.success(android.os.Debug.getNativeHeapAllocatedSize())
            }
            "getFreeDiskSpace" -> {
                result.success(-1L)
            }
            "isLowPowerMode" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    val powerManager = applicationContext?.getSystemService(Context.POWER_SERVICE) as? android.os.PowerManager
                    result.success(powerManager?.isPowerSaveMode ?: false)
                } else {
                    result.success(false)
                }
            }
            else -> {
                // If the swift/obj-c delegates other system tools, swallow Unimplemented to avoid random crashes on boot.
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        telemetryChannel.setMethodCallHandler(null)
        applicationContext?.unregisterComponentCallbacks(this)
        applicationContext = null
        memoryPressureChannel?.setStreamHandler(null)
        memoryPressureChannel = null
        memoryEventSink = null
        audioCaptureChannel?.setStreamHandler(null)
        audioCaptureChannel = null
    }

    // ComponentCallbacks2 interface for memory pressure

    override fun onTrimMemory(level: Int) {
        val pressureLevel = when {
            level >= ComponentCallbacks2.TRIM_MEMORY_COMPLETE -> "critical"
            level >= ComponentCallbacks2.TRIM_MEMORY_MODERATE -> "high"
            level >= ComponentCallbacks2.TRIM_MEMORY_BACKGROUND -> "medium"
            level >= ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN -> "background"
            level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL -> "running_critical"
            level >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW -> "running_low"
            else -> "normal"
        }

        memoryEventSink?.success(mapOf(
            "level" to level,
            "pressureLevel" to pressureLevel
        ))
    }

    override fun onConfigurationChanged(newConfig: Configuration) {}

    override fun onLowMemory() {
        memoryEventSink?.success(mapOf(
            "level" to ComponentCallbacks2.TRIM_MEMORY_COMPLETE,
            "pressureLevel" to "critical"
        ))
    }

    companion object {
        init {
            // Load native library when plugin class is loaded
            System.loadLibrary("edge_veda")
        }
    }
}

/**
 * Handles Microphone Audio Capture streaming 16kHz float32 PCM over EventChannel
 */
class AudioCaptureHandler : EventChannel.StreamHandler {
    private var _eventSink: EventChannel.EventSink? = null
    private var audioRecord: AudioRecord? = null
    private var isRecording = false
    private var recordingThread: Thread? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        _eventSink = events
        startRecording()
    }

    override fun onCancel(arguments: Any?) {
        stopRecording()
        _eventSink = null
    }

    private fun startRecording() {
        val sampleRate = 16000
        val channelConfig = AudioFormat.CHANNEL_IN_MONO
        val audioFormat = AudioFormat.ENCODING_PCM_FLOAT
        val minBufferSize = AudioRecord.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        
        if (minBufferSize == AudioRecord.ERROR || minBufferSize == AudioRecord.ERROR_BAD_VALUE) {
            _eventSink?.error("AUDIO_ERROR", "Could not get min buffer size or hardware unsupported.", null)
            return
        }

        try {
            audioRecord = AudioRecord(
                MediaRecorder.AudioSource.MIC,
                sampleRate,
                channelConfig,
                audioFormat,
                minBufferSize * 4 // Give a larger buffer so reading thread never misses bytes
            )

            if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                _eventSink?.error("AUDIO_ERROR", "Failed to initialize AudioRecord", null)
                return
            }

            audioRecord?.startRecording()
            isRecording = true

            recordingThread = Thread {
                // Read ~100ms chunks (1600 floats = 6400 bytes)
                val bufferSize = sampleRate / 10 
                val audioData = FloatArray(bufferSize)

                while (isRecording) {
                    val readSize = audioRecord?.read(audioData, 0, bufferSize, AudioRecord.READ_BLOCKING) ?: 0
                    if (readSize > 0) {
                        val dataToSend = audioData.copyOf(readSize)
                        // Route safely back to main thread
                        Handler(Looper.getMainLooper()).post {
                            _eventSink?.success(dataToSend)
                        }
                    } else if (readSize < 0) {
                        Handler(Looper.getMainLooper()).post {
                            _eventSink?.error("AUDIO_ERROR", "Error reading audio data: \$readSize", null)
                        }
                        break
                    }
                }
            }
            recordingThread?.start()
        } catch (e: SecurityException) {
            _eventSink?.error("SECURITY_EXCEPTION", "Microphone permission not granted (SecurityException)", e.message)
        } catch (e: Exception) {
            _eventSink?.error("AUDIO_EXCEPTION", "Failed to start recording stream", e.message)
        }
    }

    private fun stopRecording() {
        isRecording = false
        recordingThread?.join(500)
        recordingThread = null
        try {
            audioRecord?.stop()
        } catch (e: Exception) {
            // Ignored
        }
        audioRecord?.release()
        audioRecord = null
    }
}
