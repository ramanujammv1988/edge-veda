import Foundation

#if os(iOS)
import UIKit
import os.log
#endif

/// Tracks battery drain rate for budget enforcement.
///
/// Monitors battery level changes over time to calculate drain rate as percentage
/// per 10 minutes. Uses UIDevice battery monitoring API on iOS.
///
/// Drain Rate Calculation:
/// - Samples battery level every minute
/// - Maintains sliding window of last 10 minutes
/// - Calculates rate: (initial% - current%) / time * 600 seconds
///
/// Example:
/// ```swift
/// let tracker = BatteryDrainTracker()
/// if let drainRate = await tracker.currentDrainRate {
///     print("Battery draining at \(drainRate)% per 10 minutes")
/// }
/// ```
@available(iOS 15.0, macOS 12.0, *)
actor BatteryDrainTracker {
    #if os(iOS)
    private let logger = Logger(subsystem: "com.edgeveda.sdk", category: "BatteryDrainTracker")
    #endif
    
    /// Individual battery level sample with timestamp.
    private struct BatterySample {
        let level: Float      // Battery level 0.0-1.0
        let timestamp: Date   // When sample was taken
    }
    
    private var samples: [BatterySample] = []
    private var isTracking = false
    private var trackingTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    init() {
        #if os(iOS)
        // Enable battery monitoring
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        logger.info("BatteryDrainTracker initialized. Battery monitoring: \(UIDevice.current.isBatteryMonitoringEnabled)")
        #endif
        
        // Start tracking automatically
        startTracking()
    }
    
    deinit {
        stopTracking()
        
        #if os(iOS)
        // Disable battery monitoring when done
        UIDevice.current.isBatteryMonitoringEnabled = false
        #endif
    }
    
    // MARK: - Public Properties
    
    /// Current battery drain rate in percentage per 10 minutes.
    ///
    /// Returns nil if:
    /// - Battery monitoring is unavailable
    /// - Not enough samples collected (need at least 2)
    /// - Platform doesn't support battery monitoring
    var currentDrainRate: Double? {
        #if os(iOS)
        guard samples.count >= 2 else {
            return nil
        }
        
        let first = samples.first!
        let last = samples.last!
        
        // Calculate time difference in seconds
        let timeDiff = last.timestamp.timeIntervalSince(first.timestamp)
        guard timeDiff > 0 else {
            return nil
        }
        
        // Calculate level difference (positive = draining)
        let levelDiff = first.level - last.level
        
        // Calculate drain per second, then scale to 10 minutes
        let drainPerSecond = Double(levelDiff) / timeDiff
        let drainPerTenMinutes = drainPerSecond * 600.0 * 100.0 // Convert to percentage
        
        return max(0, drainPerTenMinutes)
        #else
        return nil
        #endif
    }
    
    /// Average battery drain rate over available samples.
    var averageDrainRate: Double? {
        #if os(iOS)
        guard samples.count >= 3 else {
            return currentDrainRate
        }
        
        // Calculate multiple intervals and average them
        var rates: [Double] = []
        for i in 0..<(samples.count - 1) {
            let first = samples[i]
            let second = samples[i + 1]
            
            let timeDiff = second.timestamp.timeIntervalSince(first.timestamp)
            guard timeDiff > 0 else { continue }
            
            let levelDiff = first.level - second.level
            let drainPerSecond = Double(levelDiff) / timeDiff
            let drainPerTenMinutes = drainPerSecond * 600.0 * 100.0
            
            if drainPerTenMinutes >= 0 {
                rates.append(drainPerTenMinutes)
            }
        }
        
        guard !rates.isEmpty else { return nil }
        return rates.reduce(0.0, +) / Double(rates.count)
        #else
        return nil
        #endif
    }
    
    /// Current battery level (0.0-1.0), or nil if unavailable.
    var currentBatteryLevel: Float? {
        #if os(iOS)
        let level = UIDevice.current.batteryLevel
        return level >= 0 ? level : nil
        #else
        return nil
        #endif
    }
    
    /// Number of samples collected.
    var sampleCount: Int {
        return samples.count
    }
    
    /// Whether battery monitoring is supported on this platform.
    nonisolated var isSupported: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }
    
    // MARK: - Public Methods
    
    /// Manually record a battery sample.
    ///
    /// Normally samples are recorded automatically every minute,
    /// but this can be used to force an immediate sample.
    func recordSample() {
        #if os(iOS)
        let level = UIDevice.current.batteryLevel
        
        // Battery level -1.0 means monitoring unavailable
        guard level >= 0 else {
            logger.warning("Battery level unavailable")
            return
        }
        
        let sample = BatterySample(level: level, timestamp: Date())
        samples.append(sample)
        
        // Keep last 10 minutes of samples (max 11 samples at 1-minute intervals)
        let cutoff = Date().addingTimeInterval(-600)
        samples.removeAll { $0.timestamp < cutoff }
        
        logger.debug("Recorded battery sample: \(level * 100)% (\(self.samples.count) samples)")
        #endif
    }
    
    /// Reset all collected samples.
    func reset() {
        samples.removeAll()
        
        #if os(iOS)
        logger.info("Battery drain tracker reset")
        #endif
    }
    
    // MARK: - Private Methods
    
    private func startTracking() {
        guard !isTracking else { return }
        
        isTracking = true
        
        // Record initial sample
        recordSample()
        
        // Start periodic sampling task
        trackingTask = Task {
            while isTracking && !Task.isCancelled {
                // Wait 60 seconds (60 billion nanoseconds)
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                
                // Record sample
                await recordSample()
            }
        }
        
        #if os(iOS)
        logger.info("Battery drain tracking started")
        #endif
    }
    
    private func stopTracking() {
        isTracking = false
        trackingTask?.cancel()
        trackingTask = nil
        
        #if os(iOS)
        logger.info("Battery drain tracking stopped")
        #endif
    }
}