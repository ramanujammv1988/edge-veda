import Foundation

#if os(iOS) || os(macOS)
import os.log
#endif

/// Telemetry subsystem for structured logging and metrics collection.
///
/// Provides OSLog-based logging with appropriate categories and privacy controls.
/// Integrates with runtime supervision components to collect performance metrics.
///
/// Example:
/// ```swift
/// let telemetry = Telemetry.shared
/// telemetry.logInferenceStart(requestId: "req-123")
/// telemetry.recordLatency(requestId: "req-123", latencyMs: 42.5)
/// telemetry.logBudgetViolation(type: .latency, current: 50.0, limit: 40.0)
/// ```
@available(iOS 15.0, macOS 12.0, *)
public actor Telemetry {
    
    // MARK: - Singleton
    
    /// Shared telemetry instance.
    public static let shared = Telemetry()
    
    // MARK: - Loggers
    
    #if os(iOS) || os(macOS)
    private let inferenceLogger = Logger(subsystem: "com.edgeveda.sdk", category: "Inference")
    private let budgetLogger = Logger(subsystem: "com.edgeveda.sdk", category: "Budget")
    private let resourceLogger = Logger(subsystem: "com.edgeveda.sdk", category: "Resources")
    private let schedulerLogger = Logger(subsystem: "com.edgeveda.sdk", category: "Scheduler")
    private let policyLogger = Logger(subsystem: "com.edgeveda.sdk", category: "Policy")
    #endif
    
    // MARK: - Metrics Storage
    
    private var latencyMetrics: [String: LatencyMetric] = [:]
    private var budgetViolations: [BudgetViolationRecord] = []
    private var resourceSnapshots: [ResourceSnapshot] = []
    
    // Configuration
    private var maxStoredMetrics = 1000
    private var maxStoredViolations = 100
    private var maxStoredSnapshots = 100
    
    private init() {
        #if os(iOS) || os(macOS)
        inferenceLogger.info("Telemetry system initialized")
        #endif
    }
    
    // MARK: - Configuration
    
    /// Set maximum number of metrics to store in memory.
    public func setMaxStoredMetrics(_ count: Int) {
        self.maxStoredMetrics = count
        trimMetrics()
    }
    
    /// Set maximum number of budget violations to store.
    public func setMaxStoredViolations(_ count: Int) {
        self.maxStoredViolations = count
        trimViolations()
    }
    
    /// Set maximum number of resource snapshots to store.
    public func setMaxStoredSnapshots(_ count: Int) {
        self.maxStoredSnapshots = count
        trimSnapshots()
    }
    
    // MARK: - Inference Logging
    
    /// Log the start of an inference request.
    public func logInferenceStart(requestId: String, modelName: String? = nil) {
        #if os(iOS) || os(macOS)
        if let model = modelName {
            inferenceLogger.info("Inference started: \(requestId, privacy: .public) model=\(model, privacy: .public)")
        } else {
            inferenceLogger.info("Inference started: \(requestId, privacy: .public)")
        }
        #endif
        
        let metric = LatencyMetric(
            requestId: requestId,
            modelName: modelName,
            startTime: Date(),
            endTime: nil,
            latencyMs: nil
        )
        latencyMetrics[requestId] = metric
        trimMetrics()
    }
    
    /// Log the completion of an inference request.
    public func logInferenceComplete(requestId: String, tokensGenerated: Int? = nil) {
        #if os(iOS) || os(macOS)
        if let tokens = tokensGenerated {
            inferenceLogger.info("Inference completed: \(requestId, privacy: .public) tokens=\(tokens)")
        } else {
            inferenceLogger.info("Inference completed: \(requestId, privacy: .public)")
        }
        #endif
        
        if var metric = latencyMetrics[requestId] {
            metric.endTime = Date()
            if let start = metric.startTime, let end = metric.endTime {
                metric.latencyMs = end.timeIntervalSince(start) * 1000.0
            }
            latencyMetrics[requestId] = metric
        }
    }
    
    /// Log an inference error.
    public func logInferenceError(requestId: String, error: String) {
        #if os(iOS) || os(macOS)
        inferenceLogger.error("Inference failed: \(requestId, privacy: .public) error=\(error, privacy: .public)")
        #endif
    }
    
    /// Record latency for a completed request.
    public func recordLatency(requestId: String, latencyMs: Double) {
        #if os(iOS) || os(macOS)
        inferenceLogger.debug("Latency recorded: \(requestId, privacy: .public) latency=\(latencyMs)ms")
        #endif
        
        if var metric = latencyMetrics[requestId] {
            metric.latencyMs = latencyMs
            latencyMetrics[requestId] = metric
        }
    }
    
    // MARK: - Budget Logging
    
    /// Log a budget violation.
    public func logBudgetViolation(
        type: BudgetViolationType,
        current: Double,
        limit: Double,
        severity: ViolationSeverity = .warning
    ) {
        #if os(iOS) || os(macOS)
        let message = "Budget violation: \(type.rawValue) current=\(current) limit=\(limit) severity=\(severity.rawValue)"
        
        switch severity {
        case .info:
            budgetLogger.info("\(message, privacy: .public)")
        case .warning:
            budgetLogger.warning("\(message, privacy: .public)")
        case .critical:
            budgetLogger.error("\(message, privacy: .public)")
        }
        #endif
        
        let record = BudgetViolationRecord(
            timestamp: Date(),
            type: type,
            current: current,
            limit: limit,
            severity: severity
        )
        budgetViolations.append(record)
        trimViolations()
    }
    
    /// Log budget enforcement action.
    public func logBudgetEnforcement(action: String, reason: String) {
        #if os(iOS) || os(macOS)
        budgetLogger.info("Budget enforcement: \(action, privacy: .public) reason=\(reason, privacy: .public)")
        #endif
    }
    
    /// Log measured baseline update.
    public func logBaselineUpdate(
        p50: Double,
        p95: Double,
        p99: Double,
        sampleCount: Int
    ) {
        #if os(iOS) || os(macOS)
        budgetLogger.info("Baseline updated: p50=\(p50)ms p95=\(p95)ms p99=\(p99)ms samples=\(sampleCount)")
        #endif
    }
    
    // MARK: - Resource Logging
    
    /// Log current resource usage.
    public func logResourceUsage(
        memoryMb: Double,
        batteryLevel: Double? = nil,
        thermalLevel: Int = 0
    ) {
        #if os(iOS) || os(macOS)
        if let battery = batteryLevel {
            resourceLogger.debug("Resources: memory=\(memoryMb)MB battery=\(Int(battery * 100))% thermal=\(thermalLevel)")
        } else {
            resourceLogger.debug("Resources: memory=\(memoryMb)MB thermal=\(thermalLevel)")
        }
        #endif
        
        let snapshot = ResourceSnapshot(
            timestamp: Date(),
            memoryMb: memoryMb,
            batteryLevel: batteryLevel,
            thermalLevel: thermalLevel
        )
        resourceSnapshots.append(snapshot)
        trimSnapshots()
    }
    
    /// Log memory pressure event.
    public func logMemoryPressure(current: Double, peak: Double, available: Double?) {
        #if os(iOS) || os(macOS)
        if let avail = available {
            resourceLogger.warning("Memory pressure: current=\(current)MB peak=\(peak)MB available=\(avail)MB")
        } else {
            resourceLogger.warning("Memory pressure: current=\(current)MB peak=\(peak)MB")
        }
        #endif
    }
    
    /// Log thermal state change.
    public func logThermalStateChange(from: Int, to: Int) {
        #if os(iOS) || os(macOS)
        resourceLogger.info("Thermal state changed: \(from) -> \(to)")
        #endif
    }
    
    /// Log battery drain rate.
    public func logBatteryDrain(drainRate: Double, currentLevel: Double) {
        #if os(iOS) || os(macOS)
        resourceLogger.info("Battery drain: rate=\(drainRate)%/10min level=\(Int(currentLevel * 100))%")
        #endif
    }
    
    // MARK: - Scheduler Logging
    
    /// Log task scheduling.
    public func logTaskScheduled(taskId: String, priority: String) {
        #if os(iOS) || os(macOS)
        schedulerLogger.debug("Task scheduled: \(taskId, privacy: .public) priority=\(priority, privacy: .public)")
        #endif
    }
    
    /// Log task execution start.
    public func logTaskStarted(taskId: String) {
        #if os(iOS) || os(macOS)
        schedulerLogger.debug("Task started: \(taskId, privacy: .public)")
        #endif
    }
    
    /// Log task completion.
    public func logTaskCompleted(taskId: String, durationMs: Double) {
        #if os(iOS) || os(macOS)
        schedulerLogger.debug("Task completed: \(taskId, privacy: .public) duration=\(durationMs)ms")
        #endif
    }
    
    /// Log task cancellation.
    public func logTaskCancelled(taskId: String, reason: String) {
        #if os(iOS) || os(macOS)
        schedulerLogger.info("Task cancelled: \(taskId, privacy: .public) reason=\(reason, privacy: .public)")
        #endif
    }
    
    /// Log queue status.
    public func logQueueStatus(pending: Int, running: Int, priority: String) {
        #if os(iOS) || os(macOS)
        schedulerLogger.debug("Queue status: pending=\(pending) running=\(running) priority=\(priority, privacy: .public)")
        #endif
    }
    
    // MARK: - Policy Logging
    
    /// Log policy change.
    public func logPolicyChange(from: String, to: String) {
        #if os(iOS) || os(macOS)
        policyLogger.info("Policy changed: \(from, privacy: .public) -> \(to, privacy: .public)")
        #endif
    }
    
    /// Log throttle decision.
    public func logThrottleDecision(shouldThrottle: Bool, factor: Double, reasons: [String]) {
        #if os(iOS) || os(macOS)
        if shouldThrottle {
            let reasonStr = reasons.joined(separator: ", ")
            policyLogger.warning("Throttling applied: factor=\(factor) reasons=\(reasonStr, privacy: .public)")
        } else {
            policyLogger.debug("No throttling needed")
        }
        #endif
    }
    
    /// Log policy enforcement action.
    public func logPolicyEnforcement(action: String, context: String) {
        #if os(iOS) || os(macOS)
        policyLogger.info("Policy enforcement: \(action, privacy: .public) context=\(context, privacy: .public)")
        #endif
    }
    
    // MARK: - Metrics Retrieval
    
    /// Get all stored latency metrics.
    public func getLatencyMetrics() -> [LatencyMetric] {
        return Array(latencyMetrics.values)
    }
    
    /// Get latency metrics for a specific request.
    public func getLatencyMetric(requestId: String) -> LatencyMetric? {
        return latencyMetrics[requestId]
    }
    
    /// Get all budget violations.
    public func getBudgetViolations() -> [BudgetViolationRecord] {
        return budgetViolations
    }
    
    /// Get recent budget violations (last N).
    public func getRecentViolations(count: Int) -> [BudgetViolationRecord] {
        let startIndex = max(0, budgetViolations.count - count)
        return Array(budgetViolations[startIndex...])
    }
    
    /// Get all resource snapshots.
    public func getResourceSnapshots() -> [ResourceSnapshot] {
        return resourceSnapshots
    }
    
    /// Get recent resource snapshots (last N).
    public func getRecentSnapshots(count: Int) -> [ResourceSnapshot] {
        let startIndex = max(0, resourceSnapshots.count - count)
        return Array(resourceSnapshots[startIndex...])
    }
    
    /// Get aggregated latency statistics.
    public func getLatencyStats() -> LatencyStats? {
        let latencies = latencyMetrics.values.compactMap { $0.latencyMs }
        guard !latencies.isEmpty else { return nil }
        
        let sorted = latencies.sorted()
        let count = Double(sorted.count)
        
        return LatencyStats(
            count: sorted.count,
            min: sorted.first ?? 0,
            max: sorted.last ?? 0,
            mean: sorted.reduce(0, +) / count,
            p50: sorted[Int(count * 0.5)],
            p95: sorted[Int(count * 0.95)],
            p99: sorted[Int(count * 0.99)]
        )
    }
    
    // MARK: - Cleanup
    
    /// Clear all stored metrics.
    public func clearMetrics() {
        latencyMetrics.removeAll()
        budgetViolations.removeAll()
        resourceSnapshots.removeAll()
        
        #if os(iOS) || os(macOS)
        inferenceLogger.info("All metrics cleared")
        #endif
    }
    
    /// Clear metrics older than specified duration.
    public func clearOldMetrics(olderThan duration: TimeInterval) {
        let cutoff = Date().addingTimeInterval(-duration)
        
        latencyMetrics = latencyMetrics.filter { _, metric in
            guard let start = metric.startTime else { return false }
            return start > cutoff
        }
        
        budgetViolations = budgetViolations.filter { $0.timestamp > cutoff }
        resourceSnapshots = resourceSnapshots.filter { $0.timestamp > cutoff }
        
        #if os(iOS) || os(macOS)
        inferenceLogger.info("Cleared metrics older than \(duration)s")
        #endif
    }
    
    // MARK: - Private Methods
    
    private func trimMetrics() {
        if latencyMetrics.count > maxStoredMetrics {
            let toRemove = latencyMetrics.count - maxStoredMetrics
            let oldestKeys = latencyMetrics
                .sorted { $0.value.startTime ?? Date.distantPast < $1.value.startTime ?? Date.distantPast }
                .prefix(toRemove)
                .map { $0.key }
            
            for key in oldestKeys {
                latencyMetrics.removeValue(forKey: key)
            }
        }
    }
    
    private func trimViolations() {
        if budgetViolations.count > maxStoredViolations {
            let toRemove = budgetViolations.count - maxStoredViolations
            budgetViolations.removeFirst(toRemove)
        }
    }
    
    private func trimSnapshots() {
        if resourceSnapshots.count > maxStoredSnapshots {
            let toRemove = resourceSnapshots.count - maxStoredSnapshots
            resourceSnapshots.removeFirst(toRemove)
        }
    }
}

// MARK: - Supporting Types

/// Latency metric for a single inference request.
public struct LatencyMetric: Sendable {
    public let requestId: String
    public let modelName: String?
    public let startTime: Date?
    public var endTime: Date?
    public var latencyMs: Double?
    
    public init(requestId: String, modelName: String?, startTime: Date?, endTime: Date?, latencyMs: Double?) {
        self.requestId = requestId
        self.modelName = modelName
        self.startTime = startTime
        self.endTime = endTime
        self.latencyMs = latencyMs
    }
}

/// Budget violation record.
public struct BudgetViolationRecord: Sendable {
    public let timestamp: Date
    public let type: BudgetViolationType
    public let current: Double
    public let limit: Double
    public let severity: ViolationSeverity
    
    public init(timestamp: Date, type: BudgetViolationType, current: Double, limit: Double, severity: ViolationSeverity) {
        self.timestamp = timestamp
        self.type = type
        self.current = current
        self.limit = limit
        self.severity = severity
    }
}

/// Resource usage snapshot.
public struct ResourceSnapshot: Sendable {
    public let timestamp: Date
    public let memoryMb: Double
    public let batteryLevel: Double?
    public let thermalLevel: Int
    
    public init(timestamp: Date, memoryMb: Double, batteryLevel: Double?, thermalLevel: Int) {
        self.timestamp = timestamp
        self.memoryMb = memoryMb
        self.batteryLevel = batteryLevel
        self.thermalLevel = thermalLevel
    }
}

/// Aggregated latency statistics.
public struct LatencyStats: Sendable {
    public let count: Int
    public let min: Double
    public let max: Double
    public let mean: Double
    public let p50: Double
    public let p95: Double
    public let p99: Double
    
    public init(count: Int, min: Double, max: Double, mean: Double, p50: Double, p95: Double, p99: Double) {
        self.count = count
        self.min = min
        self.max = max
        self.mean = mean
        self.p50 = p50
        self.p95 = p95
        self.p99 = p99
    }
    
    public var description: String {
        return "LatencyStats(count=\(count), min=\(String(format: "%.2f", min))ms, max=\(String(format: "%.2f", max))ms, mean=\(String(format: "%.2f", mean))ms, p50=\(String(format: "%.2f", p50))ms, p95=\(String(format: "%.2f", p95))ms, p99=\(String(format: "%.2f", p99))ms)"
    }
}

/// Budget violation type.
public enum BudgetViolationType: String, Sendable {
    case latency = "latency"
    case memory = "memory"
    case battery = "battery"
    case thermal = "thermal"
}

/// Violation severity level.
public enum ViolationSeverity: String, Sendable {
    case info = "info"
    case warning = "warning"
    case critical = "critical"
}