import Foundation

/// Declarative compute budget contracts for on-device inference.
///
/// An `EdgeVedaBudget` declares maximum resource limits that the Scheduler
/// enforces across concurrent workloads. Constraints are optional -- set only
/// the ones you care about.
///
/// Example:
/// ```swift
/// let budget = EdgeVedaBudget(
///     p95LatencyMs: 2000,
///     batteryDrainPerTenMinutes: 3.0,
///     maxThermalLevel: 2,
///     memoryCeilingMb: 1200
/// )
/// ```
public struct EdgeVedaBudget: Sendable {
    /// Maximum p95 inference latency in milliseconds.
    ///
    /// Set to nil to skip latency enforcement.
    public let p95LatencyMs: Int?
    
    /// Maximum battery drain percentage per 10 minutes.
    ///
    /// E.g., 3.0 means max 3% drain per 10 minutes.
    /// Set to nil to skip battery enforcement.
    public let batteryDrainPerTenMinutes: Double?
    
    /// Maximum thermal level (0=nominal, 1=fair, 2=serious, 3=critical).
    ///
    /// Scheduler will degrade workloads to prevent exceeding this level.
    /// Set to nil to skip thermal enforcement (RuntimePolicy still runs).
    public let maxThermalLevel: Int?
    
    /// Maximum memory RSS in megabytes.
    ///
    /// Set to nil to skip memory enforcement.
    public let memoryCeilingMb: Int?
    
    /// The adaptive profile, if this budget was created via `EdgeVedaBudget.adaptive()`.
    /// Returns nil for budgets created with explicit values.
    public let adaptiveProfile: BudgetProfile?
    
    /// Creates a declarative budget with optional constraints.
    public init(
        p95LatencyMs: Int? = nil,
        batteryDrainPerTenMinutes: Double? = nil,
        maxThermalLevel: Int? = nil,
        memoryCeilingMb: Int? = nil
    ) {
        self.p95LatencyMs = p95LatencyMs
        self.batteryDrainPerTenMinutes = batteryDrainPerTenMinutes
        self.maxThermalLevel = maxThermalLevel
        self.memoryCeilingMb = memoryCeilingMb
        self.adaptiveProfile = nil
    }
    
    /// Create an adaptive budget that will be resolved against measured device
    /// performance after warm-up.
    ///
    /// Unlike the default initializer where you specify absolute values, this
    /// stores the `profile` and lets the Scheduler resolve concrete values after
    /// its trackers have warmed up. Before resolution, no budget enforcement occurs.
    ///
    /// See `BudgetProfile` for multiplier details.
    public static func adaptive(_ profile: BudgetProfile) -> EdgeVedaBudget {
        EdgeVedaBudget(
            p95LatencyMs: nil,
            batteryDrainPerTenMinutes: nil,
            maxThermalLevel: nil,
            memoryCeilingMb: nil,
            adaptiveProfile: profile
        )
    }
    
    /// Internal initializer for adaptive budgets with profile.
    private init(
        p95LatencyMs: Int?,
        batteryDrainPerTenMinutes: Double?,
        maxThermalLevel: Int?,
        memoryCeilingMb: Int?,
        adaptiveProfile: BudgetProfile?
    ) {
        self.p95LatencyMs = p95LatencyMs
        self.batteryDrainPerTenMinutes = batteryDrainPerTenMinutes
        self.maxThermalLevel = maxThermalLevel
        self.memoryCeilingMb = memoryCeilingMb
        self.adaptiveProfile = adaptiveProfile
    }
    
    /// Resolve an adaptive `profile` against a `baseline` to produce concrete
    /// budget values.
    ///
    /// Called internally by Scheduler after warm-up. Not typically called
    /// by application code.
    public static func resolve(
        profile: BudgetProfile,
        baseline: MeasuredBaseline
    ) -> EdgeVedaBudget {
        let resolvedP95: Int
        let resolvedDrain: Double?
        let resolvedThermal: Int
        
        switch profile {
        case .conservative:
            resolvedP95 = Int((baseline.measuredP95Ms * 2.0).rounded())
            resolvedDrain = baseline.measuredDrainPerTenMin.map { $0 * 0.6 }
            resolvedThermal = baseline.currentThermalState < 1 ? 1 : baseline.currentThermalState
            
        case .balanced:
            resolvedP95 = Int((baseline.measuredP95Ms * 1.5).rounded())
            resolvedDrain = baseline.measuredDrainPerTenMin.map { $0 * 1.0 }
            resolvedThermal = 1
            
        case .performance:
            resolvedP95 = Int((baseline.measuredP95Ms * 1.1).rounded())
            resolvedDrain = baseline.measuredDrainPerTenMin.map { $0 * 1.5 }
            resolvedThermal = 3
        }
        
        return EdgeVedaBudget(
            p95LatencyMs: resolvedP95,
            batteryDrainPerTenMinutes: resolvedDrain,
            maxThermalLevel: resolvedThermal,
            memoryCeilingMb: nil // Memory is always observe-only
        )
    }
    
    /// Validate budget parameters for sanity.
    ///
    /// Returns a list of warnings for unrealistic values. An empty array means
    /// all parameters are within reasonable bounds.
    public func validate() -> [String] {
        var warnings: [String] = []
        
        if let p95 = p95LatencyMs, p95 < 500 {
            warnings.append(
                "p95LatencyMs=\(p95) is likely unrealistic for on-device LLM inference " +
                "(typical: 1000-3000ms)"
            )
        }
        
        if let drain = batteryDrainPerTenMinutes, drain < 0.5 {
            warnings.append(
                "batteryDrainPerTenMinutes=\(drain) may be too restrictive for active inference"
            )
        }
        
        if let memory = memoryCeilingMb, memory < 2000 {
            warnings.append(
                "memoryCeilingMb=\(memory) may be too low for VLM workloads " +
                "(typical RSS: 1500-2500MB including model + Metal buffers + image tensors). " +
                "Consider setting to nil to skip memory enforcement, or measure actual RSS " +
                "after model load."
            )
        }
        
        return warnings
    }
}

extension EdgeVedaBudget: CustomStringConvertible {
    public var description: String {
        if let profile = adaptiveProfile {
            return "EdgeVedaBudget.adaptive(.\(profile))"
        }
        
        let p95Str = p95LatencyMs.map { String($0) } ?? "nil"
        let drainStr = batteryDrainPerTenMinutes.map { String($0) } ?? "nil"
        let thermalStr = maxThermalLevel.map { String($0) } ?? "nil"
        let memoryStr = memoryCeilingMb.map { String($0) } ?? "nil"
        
        return """
        EdgeVedaBudget(p95LatencyMs=\(p95Str), \
        batteryDrainPerTenMinutes=\(drainStr), \
        maxThermalLevel=\(thermalStr), \
        memoryCeilingMb=\(memoryStr))
        """
    }
}

// MARK: - BudgetProfile

/// Adaptive budget profile expressing intent as multipliers on measured device baseline.
///
/// Instead of hardcoding absolute values, profiles multiply the actual measured
/// performance of THIS device with THIS model. The Scheduler resolves profile
/// multipliers against `MeasuredBaseline` after warm-up.
public enum BudgetProfile: String, Sendable, CaseIterable {
    /// Generous headroom: p95 x2.0, battery x0.6 (strict), thermal = 1 (Fair).
    /// Best for background/secondary workloads where stability matters more than speed.
    case conservative
    
    /// Moderate headroom: p95 x1.5, battery x1.0 (match baseline), thermal = 1 (Fair).
    /// Good default for most apps.
    case balanced
    
    /// Tight headroom: p95 x1.1, battery x1.5 (generous), thermal = 3 (allow critical).
    /// For latency-sensitive apps willing to trade battery/thermal for speed.
    case performance
}

// MARK: - MeasuredBaseline

/// Snapshot of actual device performance measured during warm-up.
///
/// The Scheduler builds this after its LatencyTracker and BatteryDrainTracker
/// have collected sufficient data. Use `Scheduler.measuredBaseline` to access it.
public struct MeasuredBaseline: Sendable {
    /// Measured p95 inference latency in milliseconds.
    public let measuredP95Ms: Double
    
    /// Measured battery drain rate per 10 minutes (percentage).
    /// Nil if battery data was insufficient (e.g., plugged in, simulator).
    public let measuredDrainPerTenMin: Double?
    
    /// Current thermal state at time of measurement (0-3, or -1 if unknown).
    public let currentThermalState: Int
    
    /// Current process RSS in megabytes at time of measurement.
    public let currentRssMb: Double
    
    /// Number of latency samples collected during warm-up.
    public let sampleCount: Int
    
    /// When this baseline was captured.
    public let measuredAt: Date
    
    public init(
        measuredP95Ms: Double,
        measuredDrainPerTenMin: Double? = nil,
        currentThermalState: Int,
        currentRssMb: Double,
        sampleCount: Int,
        measuredAt: Date
    ) {
        self.measuredP95Ms = measuredP95Ms
        self.measuredDrainPerTenMin = measuredDrainPerTenMin
        self.currentThermalState = currentThermalState
        self.currentRssMb = currentRssMb
        self.sampleCount = sampleCount
        self.measuredAt = measuredAt
    }
}

extension MeasuredBaseline: CustomStringConvertible {
    public var description: String {
        let drainStr = measuredDrainPerTenMin.map { String(format: "%.1f", $0) } ?? "n/a"
        return """
        MeasuredBaseline(p95=\(String(format: "%.0f", measuredP95Ms))ms, \
        drain=\(drainStr)%/10min, thermal=\(currentThermalState), \
        rss=\(String(format: "%.0f", currentRssMb))MB, samples=\(sampleCount))
        """
    }
}

// MARK: - BudgetViolation

/// Emitted when the Scheduler cannot satisfy a declared budget constraint
/// even after attempting mitigation.
public struct BudgetViolation: Sendable {
    /// Which constraint was violated.
    public let constraint: BudgetConstraint
    
    /// Current measured value that exceeds the budget.
    public let currentValue: Double
    
    /// Declared budget value that was exceeded.
    public let budgetValue: Double
    
    /// What mitigation was attempted (e.g., "degrade vision to minimal").
    public let mitigation: String
    
    /// When the violation was detected.
    public let timestamp: Date
    
    /// Whether the mitigation was successful (constraint now satisfied).
    public let mitigated: Bool
    
    /// Whether this violation is observe-only (no QoS mitigation possible).
    ///
    /// Memory ceiling violations are observe-only because QoS knob changes
    /// (fps, resolution, tokens) cannot reduce model memory footprint.
    public let observeOnly: Bool
    
    public init(
        constraint: BudgetConstraint,
        currentValue: Double,
        budgetValue: Double,
        mitigation: String,
        timestamp: Date,
        mitigated: Bool,
        observeOnly: Bool = false
    ) {
        self.constraint = constraint
        self.currentValue = currentValue
        self.budgetValue = budgetValue
        self.mitigation = mitigation
        self.timestamp = timestamp
        self.mitigated = mitigated
        self.observeOnly = observeOnly
    }
}

extension BudgetViolation: CustomStringConvertible {
    public var description: String {
        let observeStr = observeOnly ? "observeOnly=true, " : ""
        return """
        BudgetViolation(\(constraint): current=\(currentValue), budget=\(budgetValue), \
        \(observeStr)mitigated=\(mitigated), mitigation=\(mitigation))
        """
    }
}

// MARK: - BudgetConstraint

/// Which budget constraint was violated.
public enum BudgetConstraint: String, Sendable, CaseIterable {
    /// p95 inference latency exceeded the declared maximum.
    case p95Latency
    
    /// Battery drain rate exceeded the declared maximum per 10 minutes.
    case batteryDrain
    
    /// Thermal level exceeded the declared maximum.
    case thermalLevel
    
    /// Memory RSS exceeded the declared ceiling.
    case memoryCeiling
}

// MARK: - WorkloadPriority

/// Priority level for a registered workload.
///
/// Higher-priority workloads are degraded **last** when the scheduler needs
/// to reduce resource usage to satisfy budget constraints.
public enum WorkloadPriority: String, Sendable, CaseIterable {
    /// Low priority -- degraded first when budget is at risk.
    case low
    
    /// High priority -- maintained as long as possible.
    case high
}

// MARK: - WorkloadId

/// Unique identifier for each workload type managed by the scheduler.
public enum WorkloadId: String, Sendable, CaseIterable {
    /// Vision inference (VisionWorker).
    case vision
    
    /// Text/chat inference (StreamingWorker via ChatSession).
    case text
}