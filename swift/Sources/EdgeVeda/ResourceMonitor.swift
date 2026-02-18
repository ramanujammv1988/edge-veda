import Foundation

#if os(iOS) || os(macOS)
import os.log
#endif

/// Monitors memory resource usage (RSS - Resident Set Size).
///
/// Tracks the app's memory footprint for budget enforcement and telemetry.
/// RSS represents the actual physical memory used by the process.
///
/// Example:
/// ```swift
/// let monitor = ResourceMonitor()
/// let currentMemory = await monitor.currentRssMb
/// let peakMemory = await monitor.peakRssMb
/// ```
@available(iOS 15.0, macOS 12.0, *)
actor ResourceMonitor {
    private var samples: [Double] = []
    private let maxSamples = 100
    private var _peakRssMb: Double = 0.0
    
    #if os(iOS) || os(macOS)
    private let logger = Logger(subsystem: "com.edgeveda.sdk", category: "ResourceMonitor")
    #endif
    
    // MARK: - Initialization
    
    init() {
        // Take initial sample
        updateMemoryUsage()
    }
    
    // MARK: - Public Properties
    
    /// Current RSS (Resident Set Size) in megabytes.
    var currentRssMb: Double {
        updateMemoryUsage()
        return samples.last ?? 0.0
    }
    
    /// Peak RSS observed since monitoring started.
    var peakRssMb: Double {
        return _peakRssMb
    }
    
    /// Average RSS over the sample window.
    var averageRssMb: Double {
        guard !samples.isEmpty else { return 0.0 }
        return samples.reduce(0.0, +) / Double(samples.count)
    }
    
    /// Number of samples collected.
    var sampleCount: Int {
        return samples.count
    }
    
    // MARK: - Public Methods
    
    /// Manually trigger a memory usage update.
    ///
    /// Memory is automatically sampled when accessing currentRssMb,
    /// but this method allows explicit sampling for telemetry purposes.
    func sample() {
        updateMemoryUsage()
    }
    
    /// Reset all samples and peak tracking.
    func reset() {
        samples.removeAll()
        _peakRssMb = 0.0
    }
    
    // MARK: - Private Methods
    
    private func updateMemoryUsage() {
        let rss = getResidentSetSize()
        samples.append(rss)
        
        // Update peak
        if rss > _peakRssMb {
            _peakRssMb = rss
        }
        
        // Keep sliding window
        if samples.count > maxSamples {
            samples.removeFirst()
        }
    }
    
    /// Get the current resident set size in megabytes.
    private func getResidentSetSize() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }
        
        guard result == KERN_SUCCESS else {
            #if os(iOS) || os(macOS)
            logger.error("Failed to get memory info: \(result)")
            #else
            print("Failed to get memory info: \(result)")
            #endif
            return 0.0
        }
        
        // Convert bytes to megabytes
        let rssBytes = Double(info.resident_size)
        let rssMb = rssBytes / (1024.0 * 1024.0)
        
        return rssMb
    }
}

