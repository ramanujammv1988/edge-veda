package com.edgeveda.edge_veda

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.content.ComponentCallbacks2
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.database.Cursor
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.os.Debug
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.StatFs
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import android.provider.CalendarContract
import android.provider.MediaStore
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry
import java.io.BufferedReader
import java.io.File
import java.io.FileReader
import java.util.Calendar

/**
 * Edge Veda Flutter Plugin for Android — Full iOS Parity
 *
 * Channels:
 *   MethodChannel "com.edgeveda.edge_veda/telemetry" — 25 methods (13 iOS-parity + 4 device_info + 5 TTS + 3 SpeechRecognizer)
 *   EventChannel  "com.edgeveda.edge_veda/thermal"   — PowerManager thermal listener (API 29+)
 *   EventChannel  "com.edgeveda.edge_veda/audio_capture" — AudioRecord 16kHz PCM float
 *   EventChannel  "com.edgeveda.edge_veda/memory_pressure" — ComponentCallbacks2 (Android-unique)
 *   EventChannel  "com.edgeveda.edge_veda/tts_events" — TextToSpeech utterance progress events
 *   EventChannel  "com.edgeveda.edge_veda/speech_recognition" — SpeechRecognizer results for fallback STT
 */
class EdgeVedaPlugin : FlutterPlugin, ComponentCallbacks2, MethodChannel.MethodCallHandler,
    ActivityAware, PluginRegistry.RequestPermissionsResultListener {

    private var applicationContext: Context? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    // Channels
    private var telemetryChannel: MethodChannel? = null
    private var thermalEventChannel: EventChannel? = null
    private var audioCaptureEventChannel: EventChannel? = null
    private var memoryPressureChannel: EventChannel? = null

    // Event sinks
    private var memoryEventSink: EventChannel.EventSink? = null

    // Stream handlers (need references for cleanup)
    private var thermalStreamHandler: ThermalStreamHandler? = null
    private var audioCaptureStreamHandler: AudioCaptureStreamHandler? = null
    private var ttsEventChannel: EventChannel? = null
    private var ttsStreamHandler: TtsStreamHandler? = null
    private var speechRecognitionEventChannel: EventChannel? = null
    private var speechRecognizerStreamHandler: SpeechRecognizerStreamHandler? = null

    // Permission request tracking — keyed by request code to prevent race conditions.
    // Concurrent requests for different permission types are handled independently.
    private val pendingPermissions = mutableMapOf<Int, MethodChannel.Result>()

    companion object {
        private const val TAG = "EdgeVeda"
        private const val CHANNEL_TELEMETRY = "com.edgeveda.edge_veda/telemetry"
        private const val CHANNEL_THERMAL = "com.edgeveda.edge_veda/thermal"
        private const val CHANNEL_AUDIO_CAPTURE = "com.edgeveda.edge_veda/audio_capture"
        private const val CHANNEL_MEMORY_PRESSURE = "com.edgeveda.edge_veda/memory_pressure"
        private const val CHANNEL_TTS_EVENTS = "com.edgeveda.edge_veda/tts_events"
        private const val CHANNEL_SPEECH_RECOGNITION = "com.edgeveda.edge_veda/speech_recognition"

        private const val REQUEST_CODE_MICROPHONE = 9001
        private const val REQUEST_CODE_DETECTIVE = 9002
        private const val REQUEST_CODE_WRITE_STORAGE = 9003

        init {
            System.loadLibrary("edge_veda")
        }
    }

    // =========================================================================
    // FlutterPlugin lifecycle
    // =========================================================================

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        binding.applicationContext.registerComponentCallbacks(this)

        // MethodChannel — telemetry
        telemetryChannel = MethodChannel(binding.binaryMessenger, CHANNEL_TELEMETRY)
        telemetryChannel?.setMethodCallHandler(this)

        // EventChannel — thermal state changes
        thermalStreamHandler = ThermalStreamHandler(binding.applicationContext)
        thermalEventChannel = EventChannel(binding.binaryMessenger, CHANNEL_THERMAL)
        thermalEventChannel?.setStreamHandler(thermalStreamHandler)

        // EventChannel — audio capture
        audioCaptureStreamHandler = AudioCaptureStreamHandler()
        audioCaptureEventChannel = EventChannel(binding.binaryMessenger, CHANNEL_AUDIO_CAPTURE)
        audioCaptureEventChannel?.setStreamHandler(audioCaptureStreamHandler)

        // EventChannel — memory pressure (Android-unique)
        memoryPressureChannel = EventChannel(binding.binaryMessenger, CHANNEL_MEMORY_PRESSURE)
        memoryPressureChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                memoryEventSink = events
            }
            override fun onCancel(arguments: Any?) {
                memoryEventSink = null
            }
        })

        // EventChannel — TTS events
        ttsStreamHandler = TtsStreamHandler(binding.applicationContext)
        ttsEventChannel = EventChannel(binding.binaryMessenger, CHANNEL_TTS_EVENTS)
        ttsEventChannel?.setStreamHandler(ttsStreamHandler)

        // EventChannel — speech recognition (SpeechRecognizer fallback)
        speechRecognizerStreamHandler = SpeechRecognizerStreamHandler()
        speechRecognitionEventChannel = EventChannel(binding.binaryMessenger, CHANNEL_SPEECH_RECOGNITION)
        speechRecognitionEventChannel?.setStreamHandler(speechRecognizerStreamHandler)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext?.unregisterComponentCallbacks(this)
        applicationContext = null

        telemetryChannel?.setMethodCallHandler(null)
        telemetryChannel = null

        thermalStreamHandler?.dispose()
        thermalEventChannel?.setStreamHandler(null)
        thermalEventChannel = null
        thermalStreamHandler = null

        audioCaptureStreamHandler?.dispose()
        audioCaptureEventChannel?.setStreamHandler(null)
        audioCaptureEventChannel = null
        audioCaptureStreamHandler = null

        memoryPressureChannel?.setStreamHandler(null)
        memoryPressureChannel = null
        memoryEventSink = null

        ttsStreamHandler?.dispose()
        ttsEventChannel?.setStreamHandler(null)
        ttsEventChannel = null
        ttsStreamHandler = null

        speechRecognizerStreamHandler?.dispose()
        speechRecognitionEventChannel?.setStreamHandler(null)
        speechRecognitionEventChannel = null
        speechRecognizerStreamHandler = null
    }

    // =========================================================================
    // ActivityAware — needed for permission requests
    // =========================================================================

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activity = null
        activityBinding = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activity = null
        activityBinding = null
    }

    // =========================================================================
    // MethodChannel handler — 25 methods
    // =========================================================================

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // --- iOS-parity telemetry methods (13) ---
            "getThermalState" -> result.success(getThermalState())
            "getBatteryLevel" -> result.success(getBatteryLevel())
            "getBatteryState" -> result.success(getBatteryState())
            "getMemoryRSS" -> result.success(getMemoryRSS())
            "getAvailableMemory" -> result.success(getAvailableMemory())
            "getFreeDiskSpace" -> result.success(getFreeDiskSpace())
            "isLowPowerMode" -> result.success(isLowPowerMode())
            "requestMicrophonePermission" -> requestMicrophonePermission(result)
            "checkDetectivePermissions" -> result.success(checkDetectivePermissions())
            "requestDetectivePermissions" -> requestDetectivePermissions(result)
            "getPhotoInsights" -> getPhotoInsights(result)
            "getCalendarInsights" -> getCalendarInsights(result)
            "shareFile" -> shareFile(call, result)
            "saveFileToDownloads" -> saveFileToDownloads(call, result)

            // --- Device info methods (4) ---
            "getDeviceModel" -> result.success(Build.MODEL)
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
            "hasNeuralEngine" -> result.success(false)
            "getGpuBackend" -> {
                val ctx = applicationContext
                if (ctx != null) {
                    // ggml-vulkan requires Vulkan 1.2+; check actual API version
                    val vulkan12 = (1 shl 22) or (2 shl 12) // VK_MAKE_API_VERSION(0,1,2,0)
                    val hasVulkan12 = ctx.packageManager
                        .hasSystemFeature(PackageManager.FEATURE_VULKAN_HARDWARE_VERSION, vulkan12)
                    result.success(if (hasVulkan12) "Vulkan" else "CPU")
                } else {
                    result.success("CPU")
                }
            }

            // --- TTS methods (5) ---
            "tts_speak" -> {
                val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                val text = args["text"] as? String ?: ""
                val voiceId = args["voiceId"] as? String
                val rate = (args["rate"] as? Number)?.toFloat()
                val pitch = (args["pitch"] as? Number)?.toFloat()
                val volume = (args["volume"] as? Number)?.toFloat()
                ttsStreamHandler?.speak(text, voiceId, rate, pitch, volume)
                result.success(true)
            }
            "tts_stop" -> {
                ttsStreamHandler?.stop()
                result.success(true)
            }
            "tts_pause" -> {
                // Android TextToSpeech has no native pause — no-op
                result.success(true)
            }
            "tts_resume" -> {
                // Android TextToSpeech has no native resume — no-op
                result.success(true)
            }
            "tts_voices" -> {
                result.success(ttsStreamHandler?.getVoices() ?: emptyList<Map<String, Any>>())
            }

            // --- SpeechRecognizer methods (3) ---
            "speechRecognizer_isAvailable" -> {
                val ctx = applicationContext
                result.success(ctx != null && SpeechRecognizer.isRecognitionAvailable(ctx))
            }
            "speechRecognizer_start" -> {
                speechRecognizerStreamHandler?.startListening(applicationContext)
                result.success(true)
            }
            "speechRecognizer_stop" -> {
                speechRecognizerStreamHandler?.stopListening()
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    // =========================================================================
    // Telemetry method implementations
    // =========================================================================

    /**
     * Thermal state: 0=nominal, 1=fair, 2=serious, 3=critical.
     * Returns -1 on API < 29.
     */
    private fun getThermalState(): Int {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return -1
        val pm = applicationContext?.getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return -1
        return mapThermalStatus(pm.currentThermalStatus)
    }

    /** Battery level as 0.0 to 1.0. Returns -1.0 on error. */
    private fun getBatteryLevel(): Double {
        val bm = applicationContext?.getSystemService(Context.BATTERY_SERVICE) as? BatteryManager
            ?: return -1.0
        val level = bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        return if (level >= 0) level / 100.0 else -1.0
    }

    /** Battery state: 0=unknown, 1=unplugged, 2=charging, 3=full. */
    private fun getBatteryState(): Int {
        val intentFilter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        val batteryStatus = applicationContext?.registerReceiver(null, intentFilter)
        val status = batteryStatus?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        return when (status) {
            BatteryManager.BATTERY_STATUS_CHARGING -> 2
            BatteryManager.BATTERY_STATUS_FULL -> 3
            BatteryManager.BATTERY_STATUS_DISCHARGING,
            BatteryManager.BATTERY_STATUS_NOT_CHARGING -> 1
            else -> 0
        }
    }

    /** Process RSS in bytes. Reads /proc/self/status VmRSS, fallback to Debug heap. */
    private fun getMemoryRSS(): Long {
        try {
            BufferedReader(FileReader("/proc/self/status")).use { reader ->
                var line: String?
                while (reader.readLine().also { line = it } != null) {
                    if (line!!.startsWith("VmRSS:")) {
                        val kbStr = line!!.replace("VmRSS:", "").replace("kB", "").trim()
                        val kb = kbStr.toLongOrNull() ?: 0L
                        return kb * 1024 // convert kB to bytes
                    }
                }
            }
        } catch (_: Exception) {
            // Fall through to fallback
        }
        return Debug.getNativeHeapAllocatedSize()
    }

    /** Available memory in bytes via ActivityManager. */
    private fun getAvailableMemory(): Long {
        val am = applicationContext?.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            ?: return 0L
        val memInfo = ActivityManager.MemoryInfo()
        am.getMemoryInfo(memInfo)
        return memInfo.availMem
    }

    /** Free disk space in bytes. Returns -1 on error. */
    private fun getFreeDiskSpace(): Long {
        return try {
            val stat = StatFs(Environment.getDataDirectory().path)
            stat.availableBytes
        } catch (_: Exception) {
            -1L
        }
    }

    /** Whether power save (battery saver) mode is enabled. */
    private fun isLowPowerMode(): Boolean {
        val pm = applicationContext?.getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return false
        return pm.isPowerSaveMode
    }

    // =========================================================================
    // Permission methods
    // =========================================================================

    /** Request RECORD_AUDIO permission. Returns true if granted. */
    private fun requestMicrophonePermission(result: MethodChannel.Result) {
        val ctx = applicationContext ?: run { result.success(false); return }
        if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO)
            == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        val act = activity ?: run { result.success(false); return }
        // Reject any already-pending microphone request to avoid leaking its Result
        pendingPermissions.remove(REQUEST_CODE_MICROPHONE)?.error(
            "CANCELLED", "Superseded by a new microphone permission request", null
        )
        pendingPermissions[REQUEST_CODE_MICROPHONE] = result
        ActivityCompat.requestPermissions(
            act, arrayOf(Manifest.permission.RECORD_AUDIO), REQUEST_CODE_MICROPHONE
        )
    }

    /** Check photo and calendar permission status. */
    private fun checkDetectivePermissions(): Map<String, String> {
        val ctx = applicationContext ?: return mapOf("photos" to "denied", "calendar" to "denied")
        val photoPerm = getPhotoPermissionStatus(ctx)
        val calPerm = if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.READ_CALENDAR)
            == PackageManager.PERMISSION_GRANTED
        ) "granted" else "notDetermined"
        return mapOf("photos" to photoPerm, "calendar" to calPerm)
    }

    /** Request photo + calendar permissions. */
    private fun requestDetectivePermissions(result: MethodChannel.Result) {
        val act = activity ?: run {
            result.success(mapOf("photos" to "denied", "calendar" to "denied"))
            return
        }
        val ctx = applicationContext ?: run {
            result.success(mapOf("photos" to "denied", "calendar" to "denied"))
            return
        }

        val permsNeeded = mutableListOf<String>()
        if (getPhotoPermissionStatus(ctx) != "granted") {
            permsNeeded.add(getPhotoPermissionName())
        }
        if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.READ_CALENDAR)
            != PackageManager.PERMISSION_GRANTED
        ) {
            permsNeeded.add(Manifest.permission.READ_CALENDAR)
        }

        if (permsNeeded.isEmpty()) {
            result.success(mapOf("photos" to "granted", "calendar" to "granted"))
            return
        }

        // Reject any already-pending detective request to avoid leaking its Result
        pendingPermissions.remove(REQUEST_CODE_DETECTIVE)?.error(
            "CANCELLED", "Superseded by a new detective permission request", null
        )
        pendingPermissions[REQUEST_CODE_DETECTIVE] = result
        ActivityCompat.requestPermissions(act, permsNeeded.toTypedArray(), REQUEST_CODE_DETECTIVE)
    }

    /** Determine the correct photo permission name by API level. */
    private fun getPhotoPermissionName(): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_IMAGES
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
    }

    /** Check current photo permission status. */
    private fun getPhotoPermissionStatus(ctx: Context): String {
        val perm = getPhotoPermissionName()
        return if (ContextCompat.checkSelfPermission(ctx, perm)
            == PackageManager.PERMISSION_GRANTED
        ) "granted" else "notDetermined"
    }

    // =========================================================================
    // Permission result callback
    // =========================================================================

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ): Boolean {
        val pendingResult = pendingPermissions.remove(requestCode) ?: return false
        when (requestCode) {
            REQUEST_CODE_MICROPHONE -> {
                val granted = grantResults.isNotEmpty() &&
                        grantResults[0] == PackageManager.PERMISSION_GRANTED
                pendingResult.success(granted)
                return true
            }
            REQUEST_CODE_DETECTIVE -> {
                val ctx = applicationContext
                if (ctx != null) {
                    val photoStatus = getPhotoPermissionStatus(ctx)
                    val calStatus = if (ContextCompat.checkSelfPermission(
                            ctx, Manifest.permission.READ_CALENDAR
                        ) == PackageManager.PERMISSION_GRANTED
                    ) "granted" else "denied"
                    pendingResult.success(
                        mapOf("photos" to photoStatus, "calendar" to calStatus)
                    )
                } else {
                    pendingResult.success(
                        mapOf("photos" to "denied", "calendar" to "denied")
                    )
                }
                return true
            }
            REQUEST_CODE_WRITE_STORAGE -> {
                val granted = grantResults.isNotEmpty() &&
                        grantResults[0] == PackageManager.PERMISSION_GRANTED
                val filePath = pendingSaveFilePath
                pendingSaveFilePath = null
                if (granted && filePath != null) {
                    doSaveFileToDownloads(filePath, pendingResult)
                } else {
                    pendingResult.error("PERMISSION_DENIED", "Storage permission denied", null)
                }
                return true
            }
        }
        return false
    }

    // =========================================================================
    // Photo Insights — MediaStore query
    // =========================================================================

    private fun getPhotoInsights(result: MethodChannel.Result) {
        val ctx = applicationContext ?: run { result.success(emptyPhotoInsights()); return }

        // Check permission
        if (ContextCompat.checkSelfPermission(ctx, getPhotoPermissionName())
            != PackageManager.PERMISSION_GRANTED
        ) {
            result.success(emptyPhotoInsights())
            return
        }

        try {
            val thirtyDaysAgo = System.currentTimeMillis() - (30L * 24 * 60 * 60 * 1000)
            val uri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            val projection = arrayOf(
                MediaStore.Images.Media.DATE_TAKEN,
                MediaStore.Images.Media.LATITUDE,
                MediaStore.Images.Media.LONGITUDE
            )
            val selection = "${MediaStore.Images.Media.DATE_TAKEN} > ?"
            val selectionArgs = arrayOf(thirtyDaysAgo.toString())
            val sortOrder = "${MediaStore.Images.Media.DATE_TAKEN} DESC"

            val dayOfWeekCounts = mutableMapOf(
                "Sun" to 0, "Mon" to 0, "Tue" to 0, "Wed" to 0,
                "Thu" to 0, "Fri" to 0, "Sat" to 0
            )
            val hourOfDayCounts = mutableMapOf<String, Int>()
            val locationClusters = mutableMapOf<String, MutableMap<String, Any>>()
            var totalPhotos = 0
            var photosWithLocation = 0
            val samplePhotos = mutableListOf<Map<String, Any?>>()
            val calendar = Calendar.getInstance()
            val dayNames = arrayOf("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")

            val cursor: Cursor? = ctx.contentResolver.query(
                uri, projection, selection, selectionArgs, sortOrder
            )
            cursor?.use {
                val dateCol = it.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_TAKEN)
                @Suppress("DEPRECATION")
                val latCol = it.getColumnIndex(MediaStore.Images.Media.LATITUDE)
                @Suppress("DEPRECATION")
                val lonCol = it.getColumnIndex(MediaStore.Images.Media.LONGITUDE)

                while (it.moveToNext()) {
                    totalPhotos++
                    val dateTaken = it.getLong(dateCol)
                    calendar.timeInMillis = dateTaken

                    // Day of week (Calendar.SUNDAY=1..Calendar.SATURDAY=7)
                    val dow = calendar.get(Calendar.DAY_OF_WEEK)
                    val dayName = dayNames[dow - 1]
                    dayOfWeekCounts[dayName] = (dayOfWeekCounts[dayName] ?: 0) + 1

                    // Hour of day
                    val hour = calendar.get(Calendar.HOUR_OF_DAY).toString()
                    hourOfDayCounts[hour] = (hourOfDayCounts[hour] ?: 0) + 1

                    // Location
                    var hasLocation = false
                    var lat = 0.0
                    var lon = 0.0
                    if (latCol >= 0 && lonCol >= 0) {
                        lat = it.getDouble(latCol)
                        lon = it.getDouble(lonCol)
                        if (lat != 0.0 || lon != 0.0) {
                            hasLocation = true
                            photosWithLocation++
                            // Cluster by rounded coords (0.01 degree ~ 1km)
                            val clusterKey = "${String.format("%.2f", lat)},${String.format("%.2f", lon)}"
                            val cluster = locationClusters.getOrPut(clusterKey) {
                                mutableMapOf("lat" to lat, "lon" to lon, "count" to 0)
                            }
                            cluster["count"] = (cluster["count"] as Int) + 1
                        }
                    }

                    // Sample photos (first 10)
                    if (samplePhotos.size < 10) {
                        samplePhotos.add(mapOf(
                            "timestamp" to dateTaken,
                            "hasLocation" to hasLocation,
                            "lat" to if (hasLocation) lat else null,
                            "lon" to if (hasLocation) lon else null
                        ))
                    }
                }
            }

            // Top locations (sorted by count, top 5)
            val topLocations = locationClusters.values
                .sortedByDescending { it["count"] as Int }
                .take(5)
                .map { mapOf("lat" to it["lat"], "lon" to it["lon"], "count" to it["count"]) }

            result.success(mapOf(
                "totalPhotos" to totalPhotos,
                "dayOfWeekCounts" to dayOfWeekCounts,
                "hourOfDayCounts" to hourOfDayCounts,
                "topLocations" to topLocations,
                "photosWithLocation" to photosWithLocation,
                "samplePhotos" to samplePhotos
            ))
        } catch (e: Exception) {
            Log.e(TAG, "getPhotoInsights failed", e)
            result.success(emptyPhotoInsights())
        }
    }

    private fun emptyPhotoInsights(): Map<String, Any> = mapOf(
        "totalPhotos" to 0,
        "dayOfWeekCounts" to emptyMap<String, Int>(),
        "hourOfDayCounts" to emptyMap<String, Int>(),
        "topLocations" to emptyList<Map<String, Any>>(),
        "photosWithLocation" to 0,
        "samplePhotos" to emptyList<Map<String, Any>>()
    )

    // =========================================================================
    // Calendar Insights — CalendarContract query
    // =========================================================================

    private fun getCalendarInsights(result: MethodChannel.Result) {
        val ctx = applicationContext ?: run { result.success(emptyCalendarInsights()); return }

        if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.READ_CALENDAR)
            != PackageManager.PERMISSION_GRANTED
        ) {
            result.success(emptyCalendarInsights())
            return
        }

        try {
            val now = System.currentTimeMillis()
            val thirtyDaysAgo = now - (30L * 24 * 60 * 60 * 1000)

            val uri = CalendarContract.Events.CONTENT_URI
            val projection = arrayOf(
                CalendarContract.Events.DTSTART,
                CalendarContract.Events.DTEND,
                CalendarContract.Events.TITLE,
                CalendarContract.Events.DURATION
            )
            val selection = "${CalendarContract.Events.DTSTART} > ? AND ${CalendarContract.Events.DTSTART} < ?"
            val selectionArgs = arrayOf(thirtyDaysAgo.toString(), now.toString())
            val sortOrder = "${CalendarContract.Events.DTSTART} DESC"

            val dayOfWeekCounts = mutableMapOf(
                "Sun" to 0, "Mon" to 0, "Tue" to 0, "Wed" to 0,
                "Thu" to 0, "Fri" to 0, "Sat" to 0
            )
            val hourOfDayCounts = mutableMapOf<String, Int>()
            val meetingMinutesPerWeekday = mutableMapOf(
                "Sun" to 0.0, "Mon" to 0.0, "Tue" to 0.0, "Wed" to 0.0,
                "Thu" to 0.0, "Fri" to 0.0, "Sat" to 0.0
            )
            var totalEvents = 0
            var totalDurationMinutes = 0L
            val sampleEvents = mutableListOf<Map<String, Any>>()
            val calendar = Calendar.getInstance()
            val dayNames = arrayOf("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat")

            val cursor: Cursor? = ctx.contentResolver.query(
                uri, projection, selection, selectionArgs, sortOrder
            )
            cursor?.use {
                val startCol = it.getColumnIndexOrThrow(CalendarContract.Events.DTSTART)
                val endCol = it.getColumnIndex(CalendarContract.Events.DTEND)
                val titleCol = it.getColumnIndex(CalendarContract.Events.TITLE)

                while (it.moveToNext()) {
                    totalEvents++
                    val dtStart = it.getLong(startCol)
                    val dtEnd = if (endCol >= 0 && !it.isNull(endCol)) it.getLong(endCol) else dtStart
                    val title = if (titleCol >= 0) (it.getString(titleCol) ?: "") else ""

                    calendar.timeInMillis = dtStart
                    val dow = calendar.get(Calendar.DAY_OF_WEEK)
                    val dayName = dayNames[dow - 1]

                    // Day of week count
                    dayOfWeekCounts[dayName] = (dayOfWeekCounts[dayName] ?: 0) + 1

                    // Hour of day count
                    val hour = calendar.get(Calendar.HOUR_OF_DAY).toString()
                    hourOfDayCounts[hour] = (hourOfDayCounts[hour] ?: 0) + 1

                    // Duration in minutes
                    val durationMs = if (dtEnd > dtStart) dtEnd - dtStart else 30L * 60 * 1000
                    val durationMin = (durationMs / (60 * 1000)).toInt()
                    totalDurationMinutes += durationMin

                    // Meeting minutes per weekday
                    meetingMinutesPerWeekday[dayName] =
                        (meetingMinutesPerWeekday[dayName] ?: 0.0) + durationMin

                    // Sample events (first 10)
                    if (sampleEvents.size < 10) {
                        val truncatedTitle = if (title.length > 50) title.substring(0, 50) else title
                        sampleEvents.add(mapOf(
                            "startTimestamp" to dtStart,
                            "endTimestamp" to dtEnd,
                            "title" to truncatedTitle,
                            "durationMinutes" to durationMin
                        ))
                    }
                }
            }

            val avgDuration = if (totalEvents > 0) (totalDurationMinutes / totalEvents).toInt() else 0

            result.success(mapOf(
                "totalEvents" to totalEvents,
                "dayOfWeekCounts" to dayOfWeekCounts,
                "hourOfDayCounts" to hourOfDayCounts,
                "meetingMinutesPerWeekday" to meetingMinutesPerWeekday,
                "averageDurationMinutes" to avgDuration,
                "sampleEvents" to sampleEvents
            ))
        } catch (e: Exception) {
            Log.e(TAG, "getCalendarInsights failed", e)
            result.success(emptyCalendarInsights())
        }
    }

    private fun emptyCalendarInsights(): Map<String, Any> = mapOf(
        "totalEvents" to 0,
        "dayOfWeekCounts" to emptyMap<String, Int>(),
        "hourOfDayCounts" to emptyMap<String, Int>(),
        "meetingMinutesPerWeekday" to emptyMap<String, Double>(),
        "averageDurationMinutes" to 0,
        "sampleEvents" to emptyList<Map<String, Any>>()
    )

    // =========================================================================
    // Share File — Intent.ACTION_SEND with FileProvider
    // =========================================================================

    private fun shareFile(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val mimeType = call.argument<String>("mimeType") ?: "application/octet-stream"
        if (path == null) {
            result.success(false)
            return
        }

        try {
            val ctx = applicationContext ?: run { result.success(false); return }
            val file = File(path)
            if (!file.exists()) {
                result.success(false)
                return
            }

            val uri: Uri = FileProvider.getUriForFile(
                ctx,
                "${ctx.packageName}.fileprovider",
                file
            )

            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = mimeType
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            ctx.startActivity(Intent.createChooser(shareIntent, "Share").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "shareFile failed", e)
            result.success(false)
        }
    }

    // =========================================================================
    // Save File to Downloads — MediaStore (API 29+) or direct copy
    // =========================================================================

    // Stash the source path so we can resume after the permission grant.
    private var pendingSaveFilePath: String? = null

    private fun saveFileToDownloads(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path == null) {
            result.error("INVALID_ARG", "Missing 'path' argument", null)
            return
        }

        val sourceFile = File(path)
        if (!sourceFile.exists()) {
            result.error("FILE_NOT_FOUND", "File not found", path)
            return
        }

        val ctx = applicationContext ?: run {
            result.error("NO_CONTEXT", "Application context unavailable", null)
            return
        }

        // API < 29 requires WRITE_EXTERNAL_STORAGE at runtime
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.WRITE_EXTERNAL_STORAGE)
                != PackageManager.PERMISSION_GRANTED
            ) {
                val act = activity ?: run {
                    result.error("NO_ACTIVITY", "No activity for permission request", null)
                    return
                }
                pendingSaveFilePath = path
                pendingPermissions.remove(REQUEST_CODE_WRITE_STORAGE)?.error(
                    "CANCELLED", "Superseded by a new save request", null
                )
                pendingPermissions[REQUEST_CODE_WRITE_STORAGE] = result
                ActivityCompat.requestPermissions(
                    act,
                    arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
                    REQUEST_CODE_WRITE_STORAGE
                )
                return
            }
        }

        doSaveFileToDownloads(path, result)
    }

    private fun doSaveFileToDownloads(path: String, result: MethodChannel.Result) {
        val sourceFile = File(path)
        val ctx = applicationContext ?: run {
            result.error("NO_CONTEXT", "Application context unavailable", null)
            return
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                // API 29+: Use MediaStore (no WRITE_EXTERNAL_STORAGE needed)
                val values = android.content.ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, sourceFile.name)
                    put(MediaStore.Downloads.MIME_TYPE, "application/octet-stream")
                    put(MediaStore.Downloads.IS_PENDING, 1)
                }

                val resolver = ctx.contentResolver
                val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                if (uri == null) {
                    result.error("SAVE_FAILED", "Failed to create MediaStore entry", null)
                    return
                }

                resolver.openOutputStream(uri)?.use { output ->
                    sourceFile.inputStream().use { input ->
                        input.copyTo(output)
                    }
                }

                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                resolver.update(uri, values, null, null)

                val savedPath = "${Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)}/${sourceFile.name}"
                result.success(savedPath)
            } else {
                // API < 29: Copy directly to Downloads folder
                val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                if (!downloadsDir.exists()) downloadsDir.mkdirs()
                val destFile = File(downloadsDir, sourceFile.name)
                sourceFile.inputStream().use { input ->
                    destFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
                result.success(destFile.absolutePath)
            }
        } catch (e: Exception) {
            Log.e(TAG, "saveFileToDownloads failed", e)
            result.error("SAVE_FAILED", e.message, null)
        }
    }

    // =========================================================================
    // ComponentCallbacks2 — memory pressure (Android-unique)
    // =========================================================================

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
        Log.d(TAG, "onTrimMemory: level=$level ($pressureLevel)")
    }

    override fun onConfigurationChanged(newConfig: Configuration) {}

    override fun onLowMemory() {
        memoryEventSink?.success(mapOf(
            "level" to ComponentCallbacks2.TRIM_MEMORY_COMPLETE,
            "pressureLevel" to "critical"
        ))
        Log.w(TAG, "onLowMemory called — critical pressure")
    }

    // =========================================================================
    // Thermal State Mapping
    // =========================================================================

    /**
     * Map Android thermal status (0-6) to iOS-compatible (0-3).
     * THERMAL_STATUS_NONE/LIGHT -> 0 (nominal)
     * THERMAL_STATUS_MODERATE   -> 1 (fair)
     * THERMAL_STATUS_SEVERE     -> 2 (serious)
     * THERMAL_STATUS_CRITICAL+  -> 3 (critical)
     */
    private fun mapThermalStatus(androidStatus: Int): Int {
        return when (androidStatus) {
            0, 1 -> 0  // NONE, LIGHT -> nominal
            2 -> 1     // MODERATE -> fair
            3 -> 2     // SEVERE -> serious
            else -> 3  // CRITICAL, EMERGENCY, SHUTDOWN -> critical
        }
    }

    // =========================================================================
    // Inner class: ThermalStreamHandler
    // =========================================================================

    /**
     * Listens for thermal state changes via PowerManager (API 29+).
     * Emits maps with "thermalState" (int) and "timestamp" (double ms).
     */
    inner class ThermalStreamHandler(private val context: Context) : EventChannel.StreamHandler {
        private var eventSink: EventChannel.EventSink? = null
        private var listener: Any? = null  // PowerManager.OnThermalStatusChangedListener (API 29+)

        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            eventSink = events

            // Emit current state immediately
            val currentState = getThermalState()
            events?.success(mapOf(
                "thermalState" to currentState,
                "timestamp" to System.currentTimeMillis().toDouble()
            ))

            // Register listener for API 29+
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                registerThermalListener()
            }
        }

        override fun onCancel(arguments: Any?) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                unregisterThermalListener()
            }
            eventSink = null
        }

        @RequiresApi(Build.VERSION_CODES.Q)
        private fun registerThermalListener() {
            val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
            val thermalListener = PowerManager.OnThermalStatusChangedListener { status ->
                eventSink?.success(mapOf(
                    "thermalState" to mapThermalStatus(status),
                    "timestamp" to System.currentTimeMillis().toDouble()
                ))
            }
            listener = thermalListener
            pm.addThermalStatusListener(thermalListener)
        }

        @RequiresApi(Build.VERSION_CODES.Q)
        private fun unregisterThermalListener() {
            val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return
            val thermalListener = listener as? PowerManager.OnThermalStatusChangedListener ?: return
            pm.removeThermalStatusListener(thermalListener)
            listener = null
        }

        fun dispose() {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                unregisterThermalListener()
            }
            eventSink = null
        }
    }

    // =========================================================================
    // Inner class: AudioCaptureStreamHandler
    // =========================================================================

    /**
     * Captures 16kHz mono PCM float audio via AudioRecord.
     * Emits FloatArray chunks of ~300ms (4800 samples).
     * Flutter standard codec maps float[] -> Float32List in Dart (matching iOS).
     */
    inner class AudioCaptureStreamHandler : EventChannel.StreamHandler {
        private var eventSink: EventChannel.EventSink? = null
        private var audioRecord: AudioRecord? = null
        @Volatile private var isRecording = false
        private var captureThread: Thread? = null

        private val SAMPLE_RATE = 16000
        private val CHUNK_SAMPLES = 4800  // ~300ms at 16kHz

        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            eventSink = events
            startCapture()
        }

        override fun onCancel(arguments: Any?) {
            stopCapture()
            eventSink = null
        }

        private fun startCapture() {
            val ctx = applicationContext ?: return
            if (ContextCompat.checkSelfPermission(ctx, Manifest.permission.RECORD_AUDIO)
                != PackageManager.PERMISSION_GRANTED
            ) {
                eventSink?.error("PERMISSION_DENIED", "RECORD_AUDIO permission not granted", null)
                return
            }

            val bufferSize = AudioRecord.getMinBufferSize(
                SAMPLE_RATE,
                AudioFormat.CHANNEL_IN_MONO,
                AudioFormat.ENCODING_PCM_FLOAT
            )
            if (bufferSize == AudioRecord.ERROR || bufferSize == AudioRecord.ERROR_BAD_VALUE) {
                eventSink?.error("AUDIO_FORMAT_UNAVAILABLE", "Cannot create AudioRecord", null)
                return
            }

            try {
                audioRecord = AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_FLOAT,
                    bufferSize * 2
                )

                if (audioRecord?.state != AudioRecord.STATE_INITIALIZED) {
                    eventSink?.error("AUDIO_ERROR", "AudioRecord failed to initialize", null)
                    audioRecord?.release()
                    audioRecord = null
                    return
                }

                isRecording = true
                audioRecord?.startRecording()

                // Hoist Handler allocation out of the capture loop to avoid
                // per-chunk object creation and reduce GC pressure.
                val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

                captureThread = Thread({
                    val floatBuffer = FloatArray(CHUNK_SAMPLES)
                    // Pre-allocate a send buffer to avoid clone()/copyOfRange()
                    // on the hot path when full chunks are read.
                    val sendBuffer = FloatArray(CHUNK_SAMPLES)
                    while (isRecording) {
                        val read = audioRecord?.read(
                            floatBuffer, 0, CHUNK_SAMPLES, AudioRecord.READ_BLOCKING
                        ) ?: 0
                        if (read > 0 && isRecording) {
                            // Copy into pre-allocated send buffer (or allocate
                            // only for partial reads which are rare)
                            val chunk = if (read == CHUNK_SAMPLES) {
                                floatBuffer.copyInto(sendBuffer)
                                sendBuffer.copyOf()
                            } else {
                                floatBuffer.copyOfRange(0, read)
                            }
                            mainHandler.post {
                                eventSink?.success(chunk)
                            }
                        }
                    }
                }, "EdgeVeda-AudioCapture")
                captureThread?.start()

            } catch (e: Exception) {
                Log.e(TAG, "AudioCapture start failed", e)
                eventSink?.error("AUDIO_EXCEPTION", e.message, null)
                audioRecord?.release()
                audioRecord = null
            }
        }

        private fun stopCapture() {
            isRecording = false
            try {
                captureThread?.join(1000)
            } catch (_: InterruptedException) {}
            captureThread = null

            try {
                audioRecord?.stop()
            } catch (_: Exception) {}
            audioRecord?.release()
            audioRecord = null
        }

        fun dispose() {
            stopCapture()
            eventSink = null
        }
    }

    // =========================================================================
    // Inner class: TtsStreamHandler
    // =========================================================================

    /**
     * Text-to-Speech using android.speech.tts.TextToSpeech.
     * Implements EventChannel.StreamHandler to emit TTS events matching the
     * Dart TtsEvent format: {"type": "start"|"finish"|"cancel"|"wordBoundary",
     * "start": int, "length": int, "text": string}.
     *
     * Design notes:
     * - Pause/Resume: Android TTS has no native pause/resume. These are no-ops.
     * - Word boundaries: onRangeStart() requires API 26+ (minSdk is 24).
     *   On API 24-25 word boundary events won't fire — Dart handles gracefully.
     * - Init is async: If speak() arrives before onInit(SUCCESS), the request
     *   is queued and executed once init completes. On onInit(ERROR), a cancel
     *   event is emitted so the Dart Completer resolves.
     * - Rate mapping: iOS default rate = 0.5, Android default = 1.0.
     *   Dart rate is multiplied by 2.0 to match.
     */
    inner class TtsStreamHandler(private val context: Context) : EventChannel.StreamHandler {
        private var eventSink: EventChannel.EventSink? = null
        private var tts: TextToSpeech? = null
        private var ttsReady = false
        private val mainHandler = Handler(Looper.getMainLooper())

        // Queued speak request if TTS not yet initialized
        private var pendingSpeak: (() -> Unit)? = null

        // Track the text being spoken for word boundary events
        private var currentText: String = ""

        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            eventSink = events
            initTts()
        }

        override fun onCancel(arguments: Any?) {
            eventSink = null
        }

        private fun initTts() {
            if (tts != null) return
            tts = TextToSpeech(context) { status ->
                if (status == TextToSpeech.SUCCESS) {
                    ttsReady = true
                    setupListener()
                    // Execute any queued speak request
                    pendingSpeak?.invoke()
                    pendingSpeak = null
                } else {
                    Log.e(TAG, "TTS init failed with status=$status")
                    ttsReady = false
                    // Emit cancel so Dart Completer resolves
                    mainHandler.post {
                        eventSink?.success(mapOf("type" to "cancel"))
                    }
                    pendingSpeak = null
                }
            }
        }

        private fun setupListener() {
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {
                    mainHandler.post {
                        eventSink?.success(mapOf("type" to "start"))
                    }
                }

                override fun onDone(utteranceId: String?) {
                    mainHandler.post {
                        eventSink?.success(mapOf("type" to "finish"))
                    }
                }

                @Deprecated("Deprecated in API level 21")
                override fun onError(utteranceId: String?) {
                    mainHandler.post {
                        eventSink?.success(mapOf("type" to "cancel"))
                    }
                }

                override fun onError(utteranceId: String?, errorCode: Int) {
                    mainHandler.post {
                        eventSink?.success(mapOf("type" to "cancel"))
                    }
                }

                override fun onStop(utteranceId: String?, interrupted: Boolean) {
                    mainHandler.post {
                        eventSink?.success(mapOf("type" to "cancel"))
                    }
                }

                override fun onRangeStart(utteranceId: String?, start: Int, end: Int, frame: Int) {
                    // API 26+ only
                    val length = end - start
                    val word = if (start >= 0 && end <= currentText.length && start < end) {
                        currentText.substring(start, end)
                    } else {
                        ""
                    }
                    mainHandler.post {
                        eventSink?.success(mapOf(
                            "type" to "wordBoundary",
                            "start" to start,
                            "length" to length,
                            "text" to word
                        ))
                    }
                }
            })
        }

        fun speak(text: String, voiceId: String?, rate: Float?, pitch: Float?, volume: Float?) {
            if (text.isEmpty()) return

            // Ensure TTS is initialized
            if (tts == null) {
                initTts()
            }

            if (!ttsReady) {
                // Queue the speak request for when TTS init completes
                pendingSpeak = { doSpeak(text, voiceId, rate, pitch, volume) }
            } else {
                doSpeak(text, voiceId, rate, pitch, volume)
            }
        }

        private fun doSpeak(text: String, voiceId: String?, rate: Float?, pitch: Float?, volume: Float?) {
            val engine = tts ?: return
            currentText = text

            // Voice selection
            if (!voiceId.isNullOrEmpty()) {
                val voices = try { engine.voices } catch (_: Exception) { null }
                val voice = voices?.firstOrNull { it.name == voiceId }
                if (voice != null) {
                    engine.voice = voice
                }
            }

            // Rate: Dart sends 0.0-1.0 (iOS scale), Android default is 1.0
            // Map by multiplying by 2.0 so Dart 0.5 → Android 1.0
            engine.setSpeechRate((rate ?: 0.5f) * 2.0f)

            // Pitch: 0.5-2.0 on both platforms, direct pass-through
            engine.setPitch(pitch ?: 1.0f)

            // Speak with utterance ID for progress tracking
            val params = android.os.Bundle()
            if (volume != null) {
                params.putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, volume)
            }
            engine.speak(text, TextToSpeech.QUEUE_FLUSH, params, "ev_tts_utterance")
        }

        fun stop() {
            tts?.stop()
        }

        fun getVoices(): List<Map<String, Any>> {
            val engine = tts ?: return emptyList()
            if (!ttsReady) return emptyList()

            val voices: Set<Voice> = try {
                engine.voices ?: return emptyList()
            } catch (_: Exception) {
                return emptyList()
            }

            return voices
                .filter { !it.isNetworkConnectionRequired }
                .map { voice ->
                    val quality = if (voice.quality >= 400) 3 else 2
                    mapOf(
                        "id" to voice.name,
                        "name" to voice.name,
                        "language" to voice.locale.toLanguageTag(),
                        "quality" to quality
                    )
                }
                .sortedBy { it["language"] as String }
        }

        fun dispose() {
            tts?.stop()
            tts?.shutdown()
            tts = null
            ttsReady = false
            pendingSpeak = null
            currentText = ""
            eventSink = null
        }
    }

    // =========================================================================
    // Inner class: SpeechRecognizerStreamHandler
    // =========================================================================

    /**
     * Fallback STT using Android's built-in SpeechRecognizer.
     *
     * Implements EventChannel.StreamHandler to emit recognition events.
     * Used as an automatic fallback when Whisper inference repeatedly
     * times out on low-end devices.
     *
     * Key behaviors:
     * - EXTRA_PREFER_OFFLINE = true for privacy parity with Whisper
     * - Auto-restart on ERROR_NO_MATCH / ERROR_SPEECH_TIMEOUT (continuous listening)
     * - Auto-restart after final result (continuous listening)
     * - SpeechRecognizer must be created/destroyed on main thread
     *
     * Events emitted: ready, speechStart, speechEnd, result, error
     */
    inner class SpeechRecognizerStreamHandler : EventChannel.StreamHandler {
        private var eventSink: EventChannel.EventSink? = null
        private var speechRecognizer: SpeechRecognizer? = null
        private val mainHandler = Handler(Looper.getMainLooper())
        @Volatile private var isListening = false
        // Flag to track if we were asked to stop — prevents auto-restart races
        private var stopRequested = false

        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            eventSink = events
        }

        override fun onCancel(arguments: Any?) {
            stopListening()
            eventSink = null
        }

        fun startListening(context: Context?) {
            val ctx = context ?: return
            stopRequested = false

            mainHandler.post {
                try {
                    // Always create a fresh recognizer to avoid stale state
                    speechRecognizer?.destroy()
                    speechRecognizer = SpeechRecognizer.createSpeechRecognizer(ctx)
                    speechRecognizer?.setRecognitionListener(createListener())
                    doStartListening()
                } catch (e: Exception) {
                    Log.e(TAG, "SpeechRecognizer start failed", e)
                    eventSink?.success(mapOf(
                        "type" to "error",
                        "errorCode" to -1,
                        "message" to (e.message ?: "Failed to start SpeechRecognizer")
                    ))
                }
            }
        }

        private fun doStartListening() {
            if (stopRequested) return
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-US")
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            }
            isListening = true
            speechRecognizer?.startListening(intent)
        }

        fun stopListening() {
            stopRequested = true
            isListening = false
            mainHandler.post {
                try {
                    speechRecognizer?.stopListening()
                    speechRecognizer?.cancel()
                    speechRecognizer?.destroy()
                } catch (_: Exception) {}
                speechRecognizer = null
            }
        }

        private fun createListener(): RecognitionListener {
            return object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {
                    mainHandler.post {
                        eventSink?.success(mapOf("type" to "ready"))
                    }
                }

                override fun onBeginningOfSpeech() {
                    mainHandler.post {
                        eventSink?.success(mapOf("type" to "speechStart"))
                    }
                }

                override fun onEndOfSpeech() {
                    mainHandler.post {
                        eventSink?.success(mapOf("type" to "speechEnd"))
                    }
                }

                override fun onResults(results: Bundle?) {
                    val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    val scores = results?.getFloatArray(SpeechRecognizer.CONFIDENCE_SCORES)
                    val text = matches?.firstOrNull() ?: ""
                    val confidence = scores?.firstOrNull()?.toDouble() ?: 0.0
                    if (text.isNotEmpty()) {
                        mainHandler.post {
                            eventSink?.success(mapOf(
                                "type" to "result",
                                "text" to text,
                                "confidence" to confidence,
                                "isFinal" to true
                            ))
                        }
                    }
                    // Auto-restart for continuous listening
                    if (isListening && !stopRequested) {
                        mainHandler.postDelayed({ doStartListening() }, 100)
                    }
                }

                override fun onPartialResults(partialResults: Bundle?) {
                    val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    val text = matches?.firstOrNull() ?: ""
                    if (text.isNotEmpty()) {
                        mainHandler.post {
                            eventSink?.success(mapOf(
                                "type" to "result",
                                "text" to text,
                                "confidence" to 0.0,
                                "isFinal" to false
                            ))
                        }
                    }
                }

                override fun onError(error: Int) {
                    val message = when (error) {
                        SpeechRecognizer.ERROR_NO_MATCH -> "No speech detected"
                        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "Speech input timed out"
                        SpeechRecognizer.ERROR_AUDIO -> "Audio recording error"
                        SpeechRecognizer.ERROR_CLIENT -> "Client-side error"
                        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Missing RECORD_AUDIO permission"
                        SpeechRecognizer.ERROR_NETWORK -> "Network error"
                        SpeechRecognizer.ERROR_NETWORK_TIMEOUT -> "Network timeout"
                        SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "Recognizer busy"
                        SpeechRecognizer.ERROR_SERVER -> "Server error"
                        else -> "Unknown error ($error)"
                    }

                    mainHandler.post {
                        eventSink?.success(mapOf(
                            "type" to "error",
                            "errorCode" to error,
                            "message" to message
                        ))
                    }

                    // Auto-restart on transient errors (continuous listening)
                    val isTransient = error == SpeechRecognizer.ERROR_NO_MATCH ||
                            error == SpeechRecognizer.ERROR_SPEECH_TIMEOUT
                    if (isTransient && isListening && !stopRequested) {
                        mainHandler.postDelayed({ doStartListening() }, 300)
                    }
                }

                override fun onRmsChanged(rmsdB: Float) {
                    // Not forwarded — too noisy for EventChannel
                }

                override fun onBufferReceived(buffer: ByteArray?) {
                    // Not used
                }

                override fun onEvent(eventType: Int, params: Bundle?) {
                    // Not used
                }
            }
        }

        fun dispose() {
            stopListening()
            eventSink = null
        }
    }
}
