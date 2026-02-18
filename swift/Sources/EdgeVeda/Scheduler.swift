import Foundation

#if os(iOS) || os(macOS)
import os.log
#endif

/// Priority-based task scheduler with budget enforcement.
///
/// The Scheduler manages concurrent inference workloads, enforces ComputeBudget
/// constraints, and emits BudgetViolation events when limits are exceeded.
///
/// Example:
/// ```swift
/// let scheduler = Scheduler()
/// await scheduler.setComputeBudget(EdgeVedaBudget.adaptive(.balanced))
///
/// // Schedule high-priority task
/// let result = try await scheduler.scheduleTask(
///     priority: .high,
///     workload: .text
/// ) {
///     try await edgeVeda.generate(prompt)
/// }
/// ```
@available(iOS 15.0, macOS 12.0, *)
public actor Scheduler {
    // MARK: - Properties
    
    private var taskQueue: PriorityQueue<ScheduledTask>
    private var activeTask: Task<Void, Never>?
    private var budget: EdgeVedaBudget?
    private var workloadRegistry: [WorkloadId: WorkloadPriority]
    
    private let latencyTracker: LatencyTracker
    private let batteryTracker: BatteryDrainTracker
    private let thermalMonitor: ThermalMonitor
    private let resourceMonitor: ResourceMonitor
    
    private var measuredBaseline: MeasuredBaseline?
    private var warmUpComplete = false
    private let warmUpThreshold = 20 // samples needed
    
    private var violationListeners: [UUID: @Sendable (BudgetViolation) -> Void] = [:]
    
    #if os(iOS) || os(macOS)
    private let logger = Logger(subsystem: "com.edgeveda.sdk", category: "Scheduler")
    #endif
    
    // MARK: - Initialization
    
    public init() {
        self.taskQueue = PriorityQueue()
        self.workloadRegistry = [:]
        self.latencyTracker = LatencyTracker()
        self.batteryTracker = BatteryDrainTracker()
        self.thermalMonitor = ThermalMonitor()
        self.resourceMonitor = ResourceMonitor()
    }
    
    // MARK: - Budget Management
    
    /// Set the compute budget for task execution.
    ///
    /// If the budget uses an adaptive profile, it will be resolved after warm-up
    /// (20+ task samples). Until then, no budget enforcement occurs.
    public func setComputeBudget(_ budget: EdgeVedaBudget) {
        self.budget = budget
        
        if let profile = budget.adaptiveProfile {
            #if os(iOS) || os(macOS)
            logger.info("Adaptive budget set: \(profile.rawValue). Warming up...")
            #else
            print("Adaptive budget set: \(profile.rawValue). Warming up...")
            #endif
        }
    }
    
    /// Get the current compute budget.
    public func getComputeBudget() -> EdgeVedaBudget? {
        return budget
    }
    
    /// Get the measured baseline after warm-up completes.
    ///
    /// Returns nil if warm-up hasn't completed yet.
    public func getMeasuredBaseline() -> MeasuredBaseline? {
        return measuredBaseline
    }
    
    // MARK: - Task Scheduling
    
    /// Schedule a task with the specified priority.
    ///
    /// Tasks are queued and executed in priority order. High-priority tasks
    /// run before normal and low-priority tasks.
    ///
    /// - Parameters:
    ///   - priority: Task priority (high, normal, or low)
    ///   - workload: Workload type (text or vision)
    ///   - task: Async closure to execute
    /// - Returns: Result of the task execution
    /// - Throws: Any error from task execution or budget violations
    public func scheduleTask<T>(
        priority: TaskPriority,
        workload: WorkloadId,
        task: @escaping () async throws -> T
    ) async throws -> T {
        let taskId = UUID().uuidString
        let taskHandle = TaskHandle(
            id: taskId,
            priority: priority,
            workload: workload,
            status: .queued
        )
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let scheduledTask = ScheduledTask(
                handle: taskHandle,
                execute: {
                    let result = try await task()
                    return result as Any
                },
                continuation: { result in
                    continuation.resume(returning: result as! T)
                },
                continuationError: { error in
                    continuation.resume(throwing: error)
                }
            )
            
            taskQueue.enqueue(scheduledTask)
            
            // Start processing if not already running
            if activeTask == nil {
                activeTask = Task {
                    await processQueue()
                }
            }
        }
    }
    
    /// Cancel a scheduled task.
    ///
    /// Only queued tasks can be cancelled. Running tasks cannot be cancelled.
    public func cancelTask(_ taskId: String) async {
        taskQueue.removeTask(withId: taskId)
    }
    
    /// Get current queue status.
    public func getQueueStatus() async -> QueueStatus {
        return QueueStatus(
            queuedTasks: taskQueue.count,
            runningTasks: activeTask != nil ? 1 : 0,
            completedTasks: await latencyTracker.sampleCount,
            highPriorityCount: taskQueue.countByPriority(.high),
            normalPriorityCount: taskQueue.countByPriority(.normal),
            lowPriorityCount: taskQueue.countByPriority(.low)
        )
    }
    
    // MARK: - Workload Management
    
    /// Register a workload with its priority for degradation policy.
    public func registerWorkload(
        _ workload: WorkloadId,
        priority: WorkloadPriority
    ) {
        workloadRegistry[workload] = priority
    }
    
    // MARK: - Violation Callbacks
    
    /// Register a callback for budget violation events.
    ///
    /// - Parameter callback: Called when a budget constraint is violated
    /// - Returns: UUID to use for removing the listener
    @discardableResult
    public func onBudgetViolation(
        _ callback: @escaping @Sendable (BudgetViolation) -> Void
    ) -> UUID {
        let id = UUID()
        violationListeners[id] = callback
        return id
    }
    
    /// Remove a budget violation listener.
    public func removeViolationListener(_ id: UUID) {
        violationListeners.removeValue(forKey: id)
    }
    
    // MARK: - Private Methods
    
    private func processQueue() async {
        while let task = taskQueue.dequeue() {
            let startTime = Date()
            
            do {
                // Check budget before execution
                try await checkBudgetConstraints()
                
                // Execute task
                let result = try await task.execute()
                
                // Record metrics
                let duration = Date().timeIntervalSince(startTime)
                await latencyTracker.record(duration * 1000) // Convert to ms
                
                // Update warm-up status
                let currentSampleCount = await latencyTracker.sampleCount
                if !warmUpComplete && currentSampleCount >= 20 {
                    await completeWarmUp()
                }
                
                // Complete task
                task.continuation(result)
            } catch {
                task.continuationError(error)
            }
        }
        
        activeTask = nil
    }
    
    private func completeWarmUp() async {
        guard let budget = budget, let profile = budget.adaptiveProfile else {
            return
        }
        
        let baseline = MeasuredBaseline(
            measuredP95Ms: await latencyTracker.p95,
            measuredDrainPerTenMin: await batteryTracker.currentDrainRate,
            currentThermalState: await thermalMonitor.currentLevel,
            currentRssMb: await resourceMonitor.currentRssMb,
            sampleCount: await latencyTracker.sampleCount,
            measuredAt: Date()
        )
        
        self.measuredBaseline = baseline
        
        // Resolve adaptive budget
        let resolvedBudget = EdgeVedaBudget.resolve(
            profile: profile,
            baseline: baseline
        )
        
        self.budget = resolvedBudget
        self.warmUpComplete = true
        
        #if os(iOS) || os(macOS)
        logger.info("Warm-up complete: \(baseline.description)")
        logger.info("Resolved budget: \(resolvedBudget.description)")
        #else
        print("Warm-up complete: \(baseline)")
        print("Resolved budget: \(resolvedBudget)")
        #endif
    }
    
    private func checkBudgetConstraints() async throws {
        guard let budget = budget, warmUpComplete else {
            return
        }
        
        // Check p95 latency
        if let maxP95 = budget.p95LatencyMs {
            let currentP95 = await latencyTracker.p95
            if currentP95 > Double(maxP95) {
                await handleViolation(
                    constraint: .p95Latency,
                    currentValue: currentP95,
                    budgetValue: Double(maxP95)
                )
            }
        }
        
        // Check battery drain
        if let maxDrain = budget.batteryDrainPerTenMinutes {
            if let currentDrain = await batteryTracker.currentDrainRate {
                if currentDrain > maxDrain {
                    await handleViolation(
                        constraint: .batteryDrain,
                        currentValue: currentDrain,
                        budgetValue: maxDrain
                    )
                }
            }
        }
        
        // Check thermal level
        if let maxThermal = budget.maxThermalLevel {
            let currentThermal = await thermalMonitor.currentLevel
            if currentThermal > maxThermal {
                await handleViolation(
                    constraint: .thermalLevel,
                    currentValue: Double(currentThermal),
                    budgetValue: Double(maxThermal)
                )
            }
        }
        
        // Check memory ceiling (observe-only)
        if let maxMemory = budget.memoryCeilingMb {
            let currentMemory = await resourceMonitor.currentRssMb
            if currentMemory > Double(maxMemory) {
                await handleViolation(
                    constraint: .memoryCeiling,
                    currentValue: currentMemory,
                    budgetValue: Double(maxMemory)
                )
            }
        }
    }
    
    private func handleViolation(
        constraint: BudgetConstraint,
        currentValue: Double,
        budgetValue: Double
    ) async {
        let mitigation = attemptMitigation(constraint: constraint)
        
        let violation = BudgetViolation(
            constraint: constraint,
            currentValue: currentValue,
            budgetValue: budgetValue,
            mitigation: mitigation,
            timestamp: Date(),
            mitigated: false, // Will be checked next cycle
            observeOnly: constraint == .memoryCeiling
        )
        
        // Emit violation event
        await emitViolation(violation)
    }
    
    private func attemptMitigation(constraint: BudgetConstraint) -> String {
        switch constraint {
        case .p95Latency:
            return "Reduce inference frequency"
        case .batteryDrain:
            return "Lower model quality"
        case .thermalLevel:
            return "Pause high-priority workloads"
        case .memoryCeiling:
            return "Observe only - cannot reduce model memory"
        }
    }
    
    private func emitViolation(_ violation: BudgetViolation) async {
        #if os(iOS) || os(macOS)
        logger.warning("⚠️ Budget Violation: \(violation.description)")
        #else
        print("⚠️ Budget Violation: \(violation)")
        #endif
        
        for listener in violationListeners.values {
            listener(violation)
        }
    }
}

// MARK: - Supporting Types

private struct ScheduledTask {
    let handle: TaskHandle
    let execute: () async throws -> Any
    let continuation: (Any) -> Void
    let continuationError: (Error) -> Void
}

/// Handle for a scheduled task.
public struct TaskHandle: Sendable {
    public let id: String
    public let priority: TaskPriority
    public let workload: WorkloadId
    public var status: TaskStatus
    
    public init(id: String, priority: TaskPriority, workload: WorkloadId, status: TaskStatus) {
        self.id = id
        self.priority = priority
        self.workload = workload
        self.status = status
    }
}

/// Task priority levels.
public enum TaskPriority: Int, Sendable, Comparable {
    case low = 0
    case normal = 1
    case high = 2
    
    public static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// Task execution status.
public enum TaskStatus: String, Sendable {
    case queued
    case running
    case completed
    case cancelled
    case failed
}

/// Queue status snapshot.
public struct QueueStatus: Sendable {
    public let queuedTasks: Int
    public let runningTasks: Int
    public let completedTasks: Int
    public let highPriorityCount: Int
    public let normalPriorityCount: Int
    public let lowPriorityCount: Int
    
    public init(
        queuedTasks: Int,
        runningTasks: Int,
        completedTasks: Int,
        highPriorityCount: Int,
        normalPriorityCount: Int,
        lowPriorityCount: Int
    ) {
        self.queuedTasks = queuedTasks
        self.runningTasks = runningTasks
        self.completedTasks = completedTasks
        self.highPriorityCount = highPriorityCount
        self.normalPriorityCount = normalPriorityCount
        self.lowPriorityCount = lowPriorityCount
    }
}

// MARK: - PriorityQueue

private struct PriorityQueue<T> {
    private var tasks: [ScheduledTask] = []
    
    var count: Int {
        return tasks.count
    }
    
    var isEmpty: Bool {
        return tasks.isEmpty
    }
    
    mutating func enqueue(_ task: ScheduledTask) {
        tasks.append(task)
        tasks.sort { $0.handle.priority > $1.handle.priority }
    }
    
    mutating func dequeue() -> ScheduledTask? {
        guard !tasks.isEmpty else { return nil }
        return tasks.removeFirst()
    }
    
    mutating func removeTask(withId id: String) {
        tasks.removeAll { $0.handle.id == id }
    }
    
    func countByPriority(_ priority: TaskPriority) -> Int {
        return tasks.filter { $0.handle.priority == priority }.count
    }
}