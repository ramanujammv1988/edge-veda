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
import android.os.Debug
import android.os.Environment
import android.os.PowerManager
import android.os.StatFs
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
 *   MethodChannel "com.edgeveda.edge_veda/telemetry" — 17 methods (13 iOS-parity + 4 device_info)
 *   EventChannel  "com.edgeveda.edge_veda/thermal"   — PowerManager thermal listener (API 29+)
 *   EventChannel  "com.edgeveda.edge_veda/audio_capture" — AudioRecord 16kHz PCM float
 *   EventChannel  "com.edgeveda.edge_veda/memory_pressure" — ComponentCallbacks2 (Android-unique)
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

    // Permission request tracking
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var pendingPermissionType: String? = null // "microphone", "detective"

    companion object {
        private const val TAG = "EdgeVeda"
        private const val CHANNEL_TELEMETRY = "com.edgeveda.edge_veda/telemetry"
        private const val CHANNEL_THERMAL = "com.edgeveda.edge_veda/thermal"
        private const val CHANNEL_AUDIO_CAPTURE = "com.edgeveda.edge_veda/audio_capture"
        private const val CHANNEL_MEMORY_PRESSURE = "com.edgeveda.edge_veda/memory_pressure"

        private const val REQUEST_CODE_MICROPHONE = 9001
        private const val REQUEST_CODE_DETECTIVE = 9002

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

        // MethodChannel — telemetry (replaces old device_info channel)
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

        // EventChannel — memory pressure (Android-unique, kept)
        memoryPressureChannel = EventChannel(binding.binaryMessenger, CHANNEL_MEMORY_PRESSURE)
        memoryPressureChannel?.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                memoryEventSink = events
            }
            override fun onCancel(arguments: Any?) {
                memoryEventSink = null
            }
        })
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
    // MethodChannel handler — 17 methods
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

            // --- Existing device_info methods (4) ---
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
        pendingPermissionResult = result
        pendingPermissionType = "microphone"
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

        pendingPermissionResult = result
        pendingPermissionType = "detective"
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
        when (requestCode) {
            REQUEST_CODE_MICROPHONE -> {
                val granted = grantResults.isNotEmpty() &&
                        grantResults[0] == PackageManager.PERMISSION_GRANTED
                pendingPermissionResult?.success(granted)
                pendingPermissionResult = null
                pendingPermissionType = null
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
                    pendingPermissionResult?.success(
                        mapOf("photos" to photoStatus, "calendar" to calStatus)
                    )
                } else {
                    pendingPermissionResult?.success(
                        mapOf("photos" to "denied", "calendar" to "denied")
                    )
                }
                pendingPermissionResult = null
                pendingPermissionType = null
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
     * THERMAL_STATUS_NONE/LIGHT → 0 (nominal)
     * THERMAL_STATUS_MODERATE   → 1 (fair)
     * THERMAL_STATUS_SEVERE     → 2 (serious)
     * THERMAL_STATUS_CRITICAL+  → 3 (critical)
     */
    private fun mapThermalStatus(androidStatus: Int): Int {
        return when (androidStatus) {
            0, 1 -> 0  // NONE, LIGHT → nominal
            2 -> 1     // MODERATE → fair
            3 -> 2     // SEVERE → serious
            else -> 3  // CRITICAL, EMERGENCY, SHUTDOWN → critical
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
     * Flutter standard codec maps float[] → Float32List in Dart (matching iOS).
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

                captureThread = Thread({
                    val floatBuffer = FloatArray(CHUNK_SAMPLES)
                    while (isRecording) {
                        val read = audioRecord?.read(
                            floatBuffer, 0, CHUNK_SAMPLES, AudioRecord.READ_BLOCKING
                        ) ?: 0
                        if (read > 0 && isRecording) {
                            // Send as float[] — Flutter standard codec encodes
                            // float[] as FLOAT_ARRAY → Dart receives as Float32List
                            // (matching iOS FlutterStandardTypedData float32 behavior)
                            val chunk = if (read == CHUNK_SAMPLES) {
                                floatBuffer.clone()
                            } else {
                                floatBuffer.copyOfRange(0, read)
                            }
                            // Post to main thread for Flutter EventSink
                            android.os.Handler(android.os.Looper.getMainLooper()).post {
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
}
