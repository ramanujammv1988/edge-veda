package com.edgeveda.sdk

import android.app.ActivityManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build

/**
 * Snapshot of the Android device's hardware capabilities for on-device inference.
 *
 * @property hasVulkan Whether Vulkan GPU acceleration is available
 * @property totalMemoryMb Total physical RAM in megabytes
 * @property availableForModelMb Conservative estimate of memory available for a model (total × 0.5)
 * @property processorCount Number of logical CPU cores
 * @property deviceModel "${Build.MANUFACTURER} ${Build.MODEL}"
 * @property androidVersion Android SDK version (e.g. 34 for Android 14)
 */
data class DeviceProfile(
    val hasVulkan: Boolean,
    val totalMemoryMb: Long,
    val availableForModelMb: Long,
    val processorCount: Int,
    val deviceModel: String,
    val androidVersion: Int
)

/**
 * Detect the current device's hardware capabilities.
 *
 * Queries [ActivityManager] for RAM and [PackageManager] for the Vulkan
 * hardware level feature flag.
 *
 * @param context Application or Activity context
 * @return [DeviceProfile] snapshot of the device's current capabilities
 */
fun detectDeviceCapabilities(context: Context): DeviceProfile {
    val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    val memInfo = ActivityManager.MemoryInfo()
    am.getMemoryInfo(memInfo)
    val totalMb = memInfo.totalMem / (1024 * 1024)

    val hasVulkan = context.packageManager
        .hasSystemFeature(PackageManager.FEATURE_VULKAN_HARDWARE_LEVEL)

    return DeviceProfile(
        hasVulkan           = hasVulkan,
        totalMemoryMb       = totalMb,
        availableForModelMb = totalMb / 2,
        processorCount      = Runtime.getRuntime().availableProcessors(),
        deviceModel         = "${Build.MANUFACTURER} ${Build.MODEL}",
        androidVersion      = Build.VERSION.SDK_INT
    )
}

/**
 * Estimate total runtime memory a model needs (download size + 10% overhead).
 *
 * @param model Model descriptor
 * @return Estimated bytes required at runtime
 */
fun estimateModelMemory(model: DownloadableModelInfo): Long =
    (model.sizeBytes * 1.1).toLong()

/**
 * Return models from [models] that fit within the device's memory budget, largest first.
 *
 * Budget = availableForModelMb × 0.7 (30% headroom for OS and other processes).
 * Vision and mmproj models require Vulkan; they are excluded when
 * [DeviceProfile.hasVulkan] is false.
 *
 * @param profile Device profile from [detectDeviceCapabilities]
 * @param models Candidate models to filter and rank
 * @return Filtered and sorted list of recommended models
 */
fun recommendModels(
    profile: DeviceProfile,
    models: List<DownloadableModelInfo>
): List<DownloadableModelInfo> {
    val budgetBytes = (profile.availableForModelMb * 1024L * 1024L * 0.7).toLong()

    return models
        .filter { model ->
            val required = estimateModelMemory(model)
            val type = model.modelType ?: ModelType.TEXT
            if (type == ModelType.VISION || type == ModelType.MMPROJ) {
                profile.hasVulkan && required <= budgetBytes
            } else {
                required <= budgetBytes
            }
        }
        .sortedByDescending { it.sizeBytes }
}
