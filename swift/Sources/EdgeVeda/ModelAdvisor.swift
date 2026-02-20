import Foundation
#if canImport(Metal)
import Metal
#endif

// MARK: - DeviceProfile

/// Snapshot of the device's hardware capabilities relevant to on-device inference.
public struct DeviceProfile: Sendable {
    /// Whether a Metal GPU is available (iOS/macOS)
    public let hasMetal: Bool

    /// Estimated GPU memory in megabytes (from MTLDevice.recommendedMaxWorkingSetSize, or 0)
    public let estimatedGpuMemoryMb: Int64

    /// Total physical memory in megabytes (from ProcessInfo.physicalMemory)
    public let totalMemoryMb: Int64

    /// A conservative estimate of memory available for model use (total × 0.5)
    public let availableForModelMb: Int64

    /// Number of logical CPU cores
    public let processorCount: Int

    /// Hardware model string (e.g. "iPhone16,2")
    public let deviceModel: String
}

// MARK: - Device Capability Detection

/// Detects the current device's hardware capabilities relevant to on-device inference.
///
/// - Returns: A `DeviceProfile` describing the device's memory, GPU, and CPU capabilities.
@available(iOS 15.0, macOS 12.0, *)
public func detectDeviceCapabilities() -> DeviceProfile {
    let totalBytes = ProcessInfo.processInfo.physicalMemory
    let totalMb = Int64(totalBytes / (1024 * 1024))

    var gpuMb: Int64 = 0
    var hasMetal = false
    #if canImport(Metal)
    if let device = MTLCreateSystemDefaultDevice() {
        hasMetal = true
        gpuMb = Int64(device.recommendedMaxWorkingSetSize / (1024 * 1024))
    }
    #endif

    var systemInfo = utsname()
    uname(&systemInfo)
    let deviceModel = withUnsafePointer(to: &systemInfo.machine) {
        $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
    }

    return DeviceProfile(
        hasMetal: hasMetal,
        estimatedGpuMemoryMb: gpuMb,
        totalMemoryMb: totalMb,
        availableForModelMb: totalMb / 2,
        processorCount: ProcessInfo.processInfo.processorCount,
        deviceModel: deviceModel
    )
}

// MARK: - Model Memory Estimation

/// Estimate total runtime memory a model needs (download size + 10% overhead).
///
/// - Parameter model: The `DownloadableModelInfo` to estimate memory for.
/// - Returns: Estimated runtime memory in bytes.
@available(iOS 15.0, macOS 12.0, *)
public func estimateModelMemory(_ model: DownloadableModelInfo) -> Int64 {
    return Int64(Double(model.sizeBytes) * 1.1)
}

// MARK: - Model Recommendation

/// Return models from a list that fit within the device's memory budget, sorted largest first.
///
/// - Vision and mmproj models require Metal; they are excluded when `hasMetal` is false.
/// - Budget = `availableForModelMb × 0.7` (30% headroom for OS and other processes).
///
/// - Parameters:
///   - profile: Device profile from `detectDeviceCapabilities()`.
///   - models: Candidate models to filter and rank.
/// - Returns: Filtered and sorted array of models that fit the device's budget.
@available(iOS 15.0, macOS 12.0, *)
public func recommendModels(
    profile: DeviceProfile,
    from models: [DownloadableModelInfo]
) -> [DownloadableModelInfo] {
    let budgetBytes = Int64(Double(profile.availableForModelMb * 1024 * 1024) * 0.7)

    return models
        .filter { model in
            let required = estimateModelMemory(model)
            let modelType = model.modelType ?? .text
            if modelType == .vision || modelType == .mmproj {
                return profile.hasMetal && required <= budgetBytes
            }
            return required <= budgetBytes
        }
        .sorted { $0.sizeBytes > $1.sizeBytes }
}
