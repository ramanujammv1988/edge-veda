import Foundation

#if os(iOS) || os(macOS)
import os.log
#endif

/// Runtime policy configuration for adaptive behavior.
///
/// RuntimePolicy defines how the SDK should adapt its behavior based on
/// device state, battery level, thermal conditions, and execution context.
///
/// Example:
/// ```swift
/// let policy = RuntimePolicy(
///     throttleOnBattery: true,
///     adaptiveMemory: true,
///     thermalAware: true,
///     backgroundOptimization: false
/// )
/// await scheduler.setRuntimePolicy(policy)
/// ```
@available(iOS 15.0, macOS 12.0, *)
public struct RuntimePolicy: Sendable {
    /// Reduce performance when device is on battery power.
    public let throttleOnBattery: Bool
    
    /// Automatically adjust memory usage based on available memory.
    public let adaptiveMemory: Bool
    
    /// Throttle workload based on thermal pressure.
    public let thermalAware: Bool
    
    /// Optimize for background execution mode.
    public let backgroundOptimization: Bool
    
    /// Platform-specific options.
    public let options: RuntimePolicyOptions
    
    public init(
        throttleOnBattery: Bool = true,
        adaptiveMemory: Bool = true,
        thermalAware: Bool = true,
        backgroundOptimization: Bool = false,
        options: RuntimePolicyOptions = RuntimePolicyOptions()
    ) {
        self.throttleOnBattery = throttleOnBattery
        self.adaptiveMemory = adaptiveMemory
        self.thermalAware = thermalAware
        self.backgroundOptimization = backgroundOptimization
        self.options = options
    }
    
    // MARK: - Predefined Policies
    
    /// Conservative policy: Prioritize battery life and device health.
    public static let conservative = RuntimePolicy(
        throttleOnBattery: true,
        adaptiveMemory: true,
        thermalAware: true,
        backgroundOptimization: true
    )
    
    /// Balanced policy: Balance performance and resource usage.
    public static let balanced = RuntimePolicy(
        throttleOnBattery: true,
        adaptiveMemory: true,
        thermalAware: true,
        backgroundOptimization: false
    )
    
    /// Performance policy: Prioritize inference speed.
    public static let performance = RuntimePolicy(
        throttleOnBattery: false,
        adaptiveMemory: false,
        thermalAware: false,
        backgroundOptimization: false
    )
    
    /// Default policy (same as balanced).
    public static let `default` = RuntimePolicy.balanced
}

// MARK: - CustomStringConvertible

@available(iOS 15.0, macOS 12.0, *)
extension RuntimePolicy: CustomStringConvertible {
    public var description: String {
        return "RuntimePolicy(throttleOnBattery: \(throttleOnBattery), adaptiveMemory: \(adaptiveMemory), thermalAware: \(thermalAware), backgroundOptimization: \(backgroundOptimization))"
    }
}

/// Platform-specific runtime policy options.
@available(iOS 15.0, macOS 12.0, *)
public struct RuntimePolicyOptions: Sendable {
    /// Enable thermal state monitoring (iOS/macOS).
    public let thermalStateMonitoring: Bool
    
    /// Support background task execution (iOS).
    public let backgroundTaskSupport: Bool
    
    /// Enable performance observer APIs (Web).
    public let performanceObserver: Bool
    
    /// Enable worker pooling for concurrent tasks (Web).
    public let workerPooling: Bool
    
    public init(
        thermalStateMonitoring: Bool = true,
        backgroundTaskSupport: Bool = false,
        performanceObserver: Bool = true,
        workerPooling: Bool = true
    ) {
        self.thermalStateMonitoring = thermalStateMonitoring
        self.backgroundTaskSupport = backgroundTaskSupport
        self.performanceObserver = performanceObserver
        self.workerPooling = workerPooling
    }
}

/// Runtime capabilities available on the current platform.
@available(iOS 15.0, macOS 12.0, *)
public struct RuntimeCapabilities: Sendable {
    /// Thermal monitoring is available.
    public let hasThermalMonitoring: Bool
    
    /// Battery monitoring is available.
    public let hasBatteryMonitoring: Bool
    
    /// Memory monitoring is available.
    public let hasMemoryMonitoring: Bool
    
    /// Background task support is available.
    public let hasBackgroundTasks: Bool
    
    /// Current platform name.
    public let platform: String
    
    /// Operating system version.
    public let osVersion: String
    
    /// Device model identifier.
    public let deviceModel: String
    
    public init(
        hasThermalMonitoring: Bool,
        hasBatteryMonitoring: Bool,
        hasMemoryMonitoring: Bool,
        hasBackgroundTasks: Bool,
        platform: String,
        osVersion: String,
        deviceModel: String
    ) {
        self.hasThermalMonitoring = hasThermalMonitoring
        self.hasBatteryMonitoring = hasBatteryMonitoring
        self.hasMemoryMonitoring = hasMemoryMonitoring
        self.hasBackgroundTasks = hasBackgroundTasks
        self.platform = platform
        self.osVersion = osVersion
        self.deviceModel = deviceModel
    }
    
    /// Get runtime capabilities for the current platform.
    public static func detect() -> RuntimeCapabilities {
        #if os(iOS)
        let platform = "iOS"
        let hasBatteryMonitoring = true
        let hasBackgroundTasks = true
        #elseif os(macOS)
        let platform = "macOS"
        let hasBatteryMonitoring = false
        let hasBackgroundTasks = false
        #else
        let platform = "Unknown"
        let hasBatteryMonitoring = false
        let hasBackgroundTasks = false
        #endif
        
        #if os(iOS) || os(macOS)
        let hasThermalMonitoring = true
        let hasMemoryMonitoring = true
        #else
        let hasThermalMonitoring = false
        let hasMemoryMonitoring = false
        #endif
        
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        
        #if os(iOS)
        let deviceModel = UIDevice.current.model
        #else
        let deviceModel = "Mac"
        #endif
        
        return RuntimeCapabilities(
            hasThermalMonitoring: hasThermalMonitoring,
            hasBatteryMonitoring: hasBatteryMonitoring,
            hasMemoryMonitoring: hasMemoryMonitoring,
            hasBackgroundTasks: hasBackgroundTasks,
            platform: platform,
            osVersion: osVersion,
            deviceModel: deviceModel
        )
    }
}

/// Policy enforcement engine that applies runtime policies.
@available(iOS 15.0, macOS 12.0, *)
public actor RuntimePolicyEnforcer {
    private var currentPolicy: RuntimePolicy
    private let thermalMonitor: ThermalMonitor
    private let batteryTracker: BatteryDrainTracker
    private let resourceMonitor: ResourceMonitor
    
    #if os(iOS) || os(macOS)
    private let logger = Logger(subsystem: "com.edgeveda.sdk", category: "RuntimePolicyEnforcer")
    #endif
    
    // MARK: - Initialization
    
    public init(policy: RuntimePolicy = .default) {
        self.currentPolicy = policy
        self.thermalMonitor = ThermalMonitor()
        self.batteryTracker = BatteryDrainTracker()
        self.resourceMonitor = ResourceMonitor()
        
        #if os(iOS) || os(macOS)
        logger.info("RuntimePolicyEnforcer initialized with policy: throttleOnBattery=\(policy.throttleOnBattery), thermalAware=\(policy.thermalAware)")
        #endif
    }
    
    // MARK: - Policy Management
    
    /// Set the runtime policy.
    public func setPolicy(_ policy: RuntimePolicy) {
        self.currentPolicy = policy
        
        #if os(iOS) || os(macOS)
        logger.info("Runtime policy updated: \(policy)")
        #endif
    }
    
    /// Get the current runtime policy.
    public func getPolicy() -> RuntimePolicy {
        return currentPolicy
    }
    
    /// Get runtime capabilities for the current platform.
    public func getCapabilities() -> RuntimeCapabilities {
        return RuntimeCapabilities.detect()
    }
    
    // MARK: - Policy Enforcement
    
    /// Check if workload should be throttled based on current policy and device state.
    ///
    /// Returns a throttle recommendation with reason.
    public func shouldThrottle() async -> ThrottleRecommendation {
        var reasons: [String] = []
        var shouldThrottle = false
        var suggestedFactor = 1.0
        
        // Check thermal state
        if currentPolicy.thermalAware {
            let thermalLevel = await thermalMonitor.currentLevel
            if thermalLevel >= 2 { // Serious or critical
                shouldThrottle = true
                reasons.append("Thermal pressure (level \(thermalLevel))")
                suggestedFactor *= 0.5 // Reduce by 50%
            } else if thermalLevel == 1 { // Fair
                suggestedFactor *= 0.8 // Reduce by 20%
            }
        }
        
        // Check battery state (iOS only)
        if currentPolicy.throttleOnBattery {
            #if os(iOS)
            if let batteryLevel = await batteryTracker.currentBatteryLevel {
                if batteryLevel < 0.2 { // Below 20%
                    shouldThrottle = true
                    reasons.append("Low battery (\(Int(batteryLevel * 100))%)")
                    suggestedFactor *= 0.6 // Reduce by 40%
                } else if batteryLevel < 0.5 { // Below 50%
                    suggestedFactor *= 0.9 // Reduce by 10%
                }
            }
            #endif
        }
        
        // Check memory pressure
        if currentPolicy.adaptiveMemory {
            let currentMemory = await resourceMonitor.currentRssMb
            let peakMemory = await resourceMonitor.peakRssMb
            
            if currentMemory > peakMemory * 0.9 { // Near peak
                shouldThrottle = true
                reasons.append("High memory usage (\(Int(currentMemory))MB)")
                suggestedFactor *= 0.7 // Reduce by 30%
            }
        }
        
        return ThrottleRecommendation(
            shouldThrottle: shouldThrottle,
            throttleFactor: suggestedFactor,
            reasons: reasons
        )
    }
    
    /// Check if background optimizations should be applied.
    public func shouldOptimizeForBackground() async -> Bool {
        guard currentPolicy.backgroundOptimization else {
            return false
        }
        
        #if os(iOS)
        // Check if app is in background
        return await MainActor.run {
            UIApplication.shared.applicationState == .background
        }
        #else
        return false
        #endif
    }
    
    /// Get suggested workload priority adjustment based on current policy.
    ///
    /// Returns a multiplier for workload priority (0.0-2.0).
    public func getPriorityMultiplier() async -> Double {
        let throttle = await shouldThrottle()
        
        if throttle.shouldThrottle {
            return throttle.throttleFactor
        }
        
        // If performance policy and no throttling needed, boost priority
        if !currentPolicy.throttleOnBattery && !currentPolicy.thermalAware {
            return 1.2 // 20% boost
        }
        
        return 1.0
    }
}

/// Throttle recommendation based on current device state.
public struct ThrottleRecommendation: Sendable {
    /// Whether workload should be throttled.
    public let shouldThrottle: Bool
    
    /// Suggested throttle factor (0.0-1.0, where 1.0 = no throttling).
    public let throttleFactor: Double
    
    /// Human-readable reasons for throttling.
    public let reasons: [String]
    
    public init(shouldThrottle: Bool, throttleFactor: Double, reasons: [String]) {
        self.shouldThrottle = shouldThrottle
        self.throttleFactor = throttleFactor
        self.reasons = reasons
    }
    
    public var description: String {
        if shouldThrottle {
            return "Throttle by \(Int((1.0 - throttleFactor) * 100))%: \(reasons.joined(separator: ", "))"
        } else {
            return "No throttling needed"
        }
    }
}

#if os(iOS)
import UIKit
#endif