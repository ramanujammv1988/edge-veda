# Phase 4: Runtime Supervision - Implementation Plan

**Version:** 1.0  
**Created:** November 2, 2026  
**Status:** Planning Phase  
**Priority:** 🔴 HIGH (Next Major Milestone)

---

## Executive Summary

Phase 4 brings production-grade runtime management to all EdgeVeda platforms, achieving 100% feature parity with Flutter. This is the largest remaining implementation gap and will enable:

- **Declarative resource budgets** - p95 latency, battery drain, thermal, memory limits
- **Adaptive budget profiles** - Conservative, Balanced, Performance multipliers
- **Priority-based scheduling** - High/Low priority workload management
- **OS-aware runtime policies** - iOS thermal API, Android battery optimization
- **Production telemetry** - Performance metrics, diagnostics, and monitoring

**Timeline:** 8-12 weeks  
**Implementation Order:** Swift → Kotlin → React Native → Web

---

## Architecture Overview

### Core Components

```
┌─────────────────────────────────────────────────────────┐
│                     EdgeVeda SDK                         │
├─────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ ComputeBudget│  │  Scheduler   │  │RuntimePolicy │  │
│  │              │  │              │  │              │  │
│  │ • Budget     │  │ • TaskQueue  │  │ • Thermal    │  │
│  │ • Profile    │  │ • Priority   │  │ • Battery    │  │
│  │ • Baseline   │  │ • Violation  │  │ • Memory     │  │
│  │ • Violation  │  │ • Mitigation │  │ • Adaptive   │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
│         │                  │                  │         │
│         └──────────────────┼──────────────────┘         │
│                            │                            │
│                    ┌──────────────┐                     │
│                    │  Telemetry   │                     │
│                    │              │                     │
│                    │ • Metrics    │                     │
│                    │ • Diagnostics│                     │
│                    │ • Profiling  │                     │
│                    └──────────────┘                     │
└─────────────────────────────────────────────────────────┘
```

### Data Flow

```
App Code
   │
   ├─> setComputeBudget(budget) ──> Scheduler
   │                                    │
   ├─> scheduleTask(priority) ─────────┤
   │                                    │
   └─> setRuntimePolicy(policy) ────> RuntimePolicy
                                        │
                                        v
                            ┌──────────────────┐
                            │ Resource Monitor │
                            │                  │
                            │ • Latency        │
                            │ • Battery        │
                            │ • Thermal        │
                            │ • Memory         │
                            └──────────────────┘
                                        │
                                        v
                            ┌──────────────────┐
                            │Budget Enforcement│
                            │                  │
                            │ • Check Limits   │
                            │ • Emit Violation │
                            │ • Apply Mitigation│
                            └──────────────────┘
                                        │
                                        v
                            ┌──────────────────┐
                            │    Telemetry     │
                            └──────────────────┘
```

---

## API Design

### 1. ComputeBudget System

#### Core Types (Unified Across All Platforms)

```typescript
// Declarative resource budget
interface EdgeVedaBudget {
  p95LatencyMs?: number;              // Max p95 latency
  batteryDrainPerTenMinutes?: number; // Max battery % per 10min
  maxThermalLevel?: number;           // 0-3 (nominal to critical)
  memoryCeilingMb?: number;           // Max RSS in MB
  adaptiveProfile?: BudgetProfile;    // If created via adaptive()
}

// Adaptive profiles
enum BudgetProfile {
  CONSERVATIVE,  // p95×2.0, battery×0.6, thermal=1
  BALANCED,      // p95×1.5, battery×1.0, thermal=1
  PERFORMANCE    // p95×1.1, battery×1.5, thermal=3
}

// Device baseline measurement
interface MeasuredBaseline {
  measuredP95Ms: number;
  measuredDrainPerTenMin?: number;  // null if unavailable
  currentThermalState: number;      // 0-3 or -1
  currentRssMb: number;
  sampleCount: number;
  measuredAt: Date;
}

// Budget violation event
interface BudgetViolation {
  constraint: BudgetConstraint;
  currentValue: number;
  budgetValue: number;
  mitigation: string;
  timestamp: Date;
  mitigated: boolean;
  observeOnly: boolean;  // true for memory violations
}

enum BudgetConstraint {
  P95_LATENCY,
  BATTERY_DRAIN,
  THERMAL_LEVEL,
  MEMORY_CEILING
}
```

#### API Methods

```typescript
// Set compute budget
async setComputeBudget(budget: EdgeVedaBudget): Promise<void>

// Get current budget
async getComputeBudget(): Promise<EdgeVedaBudget | null>

// Create adaptive budget
static adaptiveBudget(profile: BudgetProfile): EdgeVedaBudget

// Get measured baseline (after warm-up)
async getMeasuredBaseline(): Promise<MeasuredBaseline | null>

// Listen for violations
onBudgetViolation(callback: (violation: BudgetViolation) => void): void
```

### 2. Scheduler System

#### Core Types

```typescript
// Task scheduling
interface TaskPriority {
  HIGH = "high",
  NORMAL = "normal",
  LOW = "low"
}

interface WorkloadId {
  VISION = "vision",
  TEXT = "text"
}

interface TaskHandle {
  id: string;
  priority: TaskPriority;
  workload: WorkloadId;
  status: TaskStatus;
}

enum TaskStatus {
  QUEUED,
  RUNNING,
  COMPLETED,
  CANCELLED,
  FAILED
}

interface QueueStatus {
  queuedTasks: number;
  runningTasks: number;
  completedTasks: number;
  highPriorityCount: number;
  normalPriorityCount: number;
  lowPriorityCount: number;
}
```

#### API Methods

```typescript
// Schedule a task
async scheduleTask(
  task: () => Promise<T>,
  priority: TaskPriority,
  workload: WorkloadId
): Promise<TaskHandle>

// Cancel task
async cancelTask(taskId: string): Promise<void>

// Get queue status
async getQueueStatus(): Promise<QueueStatus>

// Register workload priority
async registerWorkload(
  workload: WorkloadId,
  priority: WorkloadPriority
): Promise<void>
```

### 3. RuntimePolicy System

#### Core Types

```typescript
interface RuntimePolicy {
  throttleOnBattery: boolean;      // Reduce performance on battery
  adaptiveMemory: boolean;         // Auto-adjust memory usage
  thermalAware: boolean;           // Throttle on thermal pressure
  backgroundOptimization: boolean; // Optimize for background mode
}

interface RuntimePolicyOptions {
  // iOS-specific
  thermalStateMonitoring?: boolean;
  backgroundTaskSupport?: boolean;
  
  // Android-specific
  dozeOptimization?: boolean;
  batteryOptimization?: boolean;
  
  // Web-specific
  performanceObserver?: boolean;
  workerPooling?: boolean;
}
```

#### API Methods

```typescript
// Set runtime policy
async setRuntimePolicy(
  policy: RuntimePolicy,
  options?: RuntimePolicyOptions
): Promise<void>

// Get current policy
async getRuntimePolicy(): Promise<RuntimePolicy>

// Get OS-specific capabilities
async getRuntimeCapabilities(): Promise<RuntimeCapabilities>
```

### 4. Telemetry & Diagnostics

#### Core Types

```typescript
interface TelemetrySnapshot {
  // Performance metrics
  averageLatencyMs: number;
  p50LatencyMs: number;
  p95LatencyMs: number;
  p99LatencyMs: number;
  
  // Resource metrics
  currentRssMb: number;
  peakRssMb: number;
  batteryDrainRate?: number;  // % per 10min
  thermalState: number;        // 0-3
  
  // Task metrics
  totalTasks: number;
  completedTasks: number;
  failedTasks: number;
  averageQueueTime: number;
  
  // Violation metrics
  violationCount: number;
  violationsByType: Record<BudgetConstraint, number>;
  
  timestamp: Date;
}

interface DiagnosticInfo {
  sdkVersion: string;
  platform: string;
  osVersion: string;
  deviceModel: string;
  
  modelInfo: {
    name: string;
    parameterCount: number;
    quantization: string;
  };
  
  runtimeInfo: {
    currentBudget?: EdgeVedaBudget;
    currentPolicy: RuntimePolicy;
    schedulerStatus: QueueStatus;
  };
  
  lastError?: {
    message: string;
    timestamp: Date;
    stackTrace?: string;
  };
}
```

#### API Methods

```typescript
// Get telemetry snapshot
async getTelemetry(): Promise<TelemetrySnapshot>

// Get diagnostic info
async getDiagnosticInfo(): Promise<DiagnosticInfo>

// Get last error
async getLastError(): Promise<ErrorInfo | null>

// Enable debug mode
async enableDebugMode(enable: boolean): Promise<void>

// Export telemetry
async exportTelemetry(): Promise<string>  // JSON string
```

---

## Platform-Specific Implementation

### Swift (iOS/macOS) Implementation

#### File Structure

```
swift/Sources/EdgeVeda/
├── Budget.swift                 ✅ Already exists (Flutter reference)
├── Scheduler.swift              🆕 NEW
├── RuntimePolicy.swift          🆕 NEW
├── Telemetry.swift             🆕 NEW
├── ResourceMonitor.swift        🆕 NEW
├── LatencyTracker.swift         🆕 NEW
├── BatteryDrainTracker.swift    🆕 NEW
└── ThermalMonitor.swift         🆕 NEW
```

#### Key Implementation Details

**1. Scheduler.swift**

```swift
@available(iOS 15.0, macOS 12.0, *)
public actor Scheduler {
    private var taskQueue: PriorityQueue<ScheduledTask>
    private var activeTask: Task<Void, Never>?
    private var budget: EdgeVedaBudget?
    private var workloadRegistry: [WorkloadId: WorkloadPriority]
    
    private let latencyTracker: LatencyTracker
    private let batteryTracker: BatteryDrainTracker
    private let thermalMonitor: ThermalMonitor
    private let resourceMonitor: ResourceMonitor
    
    private var measureBaseline: MeasuredBaseline?
    private var warmUpComplete = false
    
    public init() {
        self.taskQueue = PriorityQueue()
        self.workloadRegistry = [:]
        self.latencyTracker = LatencyTracker()
        self.batteryTracker = BatteryDrainTracker()
        self.thermalMonitor = ThermalMonitor()
        self.resourceMonitor = ResourceMonitor()
    }
    
    public func setComputeBudget(_ budget: EdgeVedaBudget) {
        self.budget = budget
        
        // If adaptive profile, wait for warm-up
        if let profile = budget.adaptiveProfile {
            // Will be resolved after warm-up
            print("Adaptive budget set: \(profile). Warming up...")
        }
    }
    
    public func getComputeBudget() -> EdgeVedaBudget? {
        return budget
    }
    
    public func getMeasuredBaseline() -> MeasuredBaseline? {
        return measureBaseline
    }
    
    public func scheduleTask<T>(
        priority: TaskPriority,
        workload: WorkloadId,
        task: @escaping () async throws -> T
    ) async throws -> T {
        let taskId = UUID().uuidString
        let scheduledTask = ScheduledTask(
            id: taskId,
            priority: priority,
            workload: workload,
            execute: task
        )
        
        taskQueue.enqueue(scheduledTask)
        
        // Start processing if not already running
        if activeTask == nil {
            activeTask = Task {
                await processQueue()
            }
        }
        
        // Wait for completion
        return try await scheduledTask.completion.value
    }
    
    private func processQueue() async {
        while let task = taskQueue.dequeue() {
            do {
                let startTime = Date()
                
                // Check budget before execution
                try await checkBudgetConstraints()
                
                // Execute task
                let result = try await task.execute()
                
                // Record metrics
                let duration = Date().timeIntervalSince(startTime)
                await latencyTracker.record(duration * 1000) // Convert to ms
                
                // Update warm-up status
                if !warmUpComplete && latencyTracker.sampleCount >= 20 {
                    await completeWarmUp()
                }
                
                // Complete task
                task.completion.complete(with: .success(result))
            } catch {
                task.completion.complete(with: .failure(error))
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
            sampleCount: latencyTracker.sampleCount,
            measuredAt: Date()
        )
        
        self.measureBaseline = baseline
        
        // Resolve adaptive budget
        let resolvedBudget = EdgeVedaBudget.resolve(
            profile: profile,
            baseline: baseline
        )
        
        self.budget = resolvedBudget
        self.warmUpComplete = true
        
        print("Warm-up complete: \(baseline)")
        print("Resolved budget: \(resolvedBudget)")
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
        // Notify listeners via callback or async stream
        print("⚠️ Budget Violation: \(violation)")
    }
}
```

**2. Platform-Specific Integration**

```swift
// ThermalMonitor.swift
@available(iOS 15.0, macOS 12.0, *)
actor ThermalMonitor {
    private var currentState: ProcessInfo.ThermalState = .nominal
    
    init() {
        #if os(iOS) || os(macOS)
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.updateThermalState()
            }
        }
        #endif
        
        updateThermalState()
    }
    
    private func updateThermalState() {
        #if os(iOS) || os(macOS)
        currentState = ProcessInfo.processInfo.thermalState
        #endif
    }
    
    var currentLevel: Int {
        switch currentState {
        case .nominal: return 0
        case .fair: return 1
        case .serious: return 2
        case .critical: return 3
        @unknown default: return -1
        }
    }
}

// BatteryDrainTracker.swift
@available(iOS 15.0, macOS 12.0, *)
actor BatteryDrainTracker {
    private var samples: [(level: Float, timestamp: Date)] = []
    
    init() {
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        #endif
        
        startTracking()
    }
    
    private func startTracking() {
        Task {
            while true {
                recordSample()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }
    
    private func recordSample() {
        #if os(iOS)
        let level = UIDevice.current.batteryLevel
        if level >= 0 { // -1 means unavailable
            samples.append((level: level, timestamp: Date()))
            
            // Keep last 10 minutes of samples
            let cutoff = Date().addingTimeInterval(-600)
            samples.removeAll { $0.timestamp < cutoff }
        }
        #endif
    }
    
    var currentDrainRate: Double? {
        guard samples.count >= 2 else { return nil }
        
        let first = samples.first!
        let last = samples.last!
        
        let timeDiff = last.timestamp.timeIntervalSince(first.timestamp)
        guard timeDiff > 0 else { return nil }
        
        let levelDiff = first.level - last.level // Positive = draining
        let drainPerSecond = Double(levelDiff) / timeDiff
        let drainPerTenMin = drainPerSecond * 600 * 100 // Convert to %
        
        return max(0, drainPerTenMin)
    }
}
```

#### iOS-Specific Considerations

- **OSLog Integration**: Use `os_log` for structured logging
- **Thermal API**: Monitor `ProcessInfo.thermalStateDidChangeNotification`
- **Battery API**: Use `UIDevice.batteryLevel` and `batteryState`
- **Background Tasks**: Register background tasks with `BGTaskScheduler`
- **Metal Profiling**: Use MTLCaptureManager for GPU metrics

---

### Kotlin (Android) Implementation

#### File Structure

```
kotlin/src/main/kotlin/com/edgeveda/sdk/
├── Budget.kt                    🆕 NEW
├── Scheduler.kt                 🆕 NEW
├── RuntimePolicy.kt             🆕 NEW
├── Telemetry.kt                🆕 NEW
├── ResourceMonitor.kt           🆕 NEW
├── LatencyTracker.kt            🆕 NEW
├── BatteryDrainTracker.kt       🆕 NEW
└── ThermalMonitor.kt            🆕 NEW
```

#### Key Implementation Details

**1. Scheduler.kt**

```kotlin
class Scheduler(private val context: Context) {
    private val taskQueue = PriorityBlockingQueue<ScheduledTask>()
    private val executorService = Executors.newSingleThreadExecutor()
    private var budget: EdgeVedaBudget? = null
    private val workloadRegistry = mutableMapOf<WorkloadId, WorkloadPriority>()
    
    private val latencyTracker = LatencyTracker()
    private val batteryTracker = BatteryDrainTracker(context)
    private val thermalMonitor = ThermalMonitor(context)
    private val resourceMonitor = ResourceMonitor()
    
    private var measuredBaseline: MeasuredBaseline? = null
    private var warmUpComplete = false
    
    private val violationListeners = mutableListOf<(BudgetViolation) -> Unit>()
    
    suspend fun setComputeBudget(budget: EdgeVedaBudget) {
        this.budget = budget
        
        if (budget.adaptiveProfile != null) {
            Log.d(TAG, "Adaptive budget set: ${budget.adaptiveProfile}. Warming up...")
        }
    }
    
    fun getComputeBudget(): EdgeVedaBudget? = budget
    
    fun getMeasuredBaseline(): MeasuredBaseline? = measuredBaseline
    
    suspend fun <T> scheduleTask(
        priority: TaskPriority,
        workload: WorkloadId,
        task: suspend () -> T
    ): T = withContext(Dispatchers.Default) {
        val deferred = CompletableDeferred<T>()
        val scheduledTask = ScheduledTask(
            id = UUID.randomUUID().toString(),
            priority = priority,
            workload = workload,
            deferred = deferred,
            task = task
        )
        
        taskQueue.add(scheduledTask)
        processQueue()
        
        deferred.await()
    }
    
    private suspend fun processQueue() {
        while (taskQueue.isNotEmpty()) {
            val task = taskQueue.poll() ?: continue
            
            try {
                val startTime = System.currentTimeMillis()
                
                // Check budget constraints
                checkBudgetConstraints()
                
                // Execute task
                val result = task.task()
                
                // Record metrics
                val duration = System.currentTimeMillis() - startTime
                latencyTracker.record(duration.toDouble())
                
                // Update warm-up status
                if (!warmUpComplete && latencyTracker.sampleCount >= 20) {
                    completeWarmUp()
                }
                
                task.deferred.complete(result)
            } catch (e: Exception) {
                task.deferred.completeExceptionally(e)
            }
        }
    }
    
    private suspend fun completeWarmUp() {
        val budget = this.budget ?: return
        val profile = budget.adaptiveProfile ?: return
        
        val baseline = MeasuredBaseline(
            measuredP95Ms = latencyTracker.p95,
            measuredDrainPerTenMin = batteryTracker.currentDrainRate,
            currentThermalState = thermalMonitor.currentLevel,
            currentRssMb = resourceMonitor.currentRssMb,
            sampleCount = latencyTracker.sampleCount,
            measuredAt = System.currentTimeMillis()
        )
        
        this.measuredBaseline = baseline
        
        // Resolve adaptive budget
        val resolvedBudget = EdgeVedaBudget.resolve(profile, baseline)
        this.budget = resolvedBudget
        this.warmUpComplete = true
        
        Log.d(TAG, "Warm-up complete: $baseline")
        Log.d(TAG, "Resolved budget: $resolvedBudget")
    }
    
    private suspend fun checkBudgetConstraints() {
        val budget = this.budget ?: return
        if (!warmUpComplete) return
        
        // Check p95 latency
        budget.p95LatencyMs?.let { maxP95 ->
            val currentP95 = latencyTracker.p95
            if (currentP95 > maxP95) {
                handleViolation(
                    BudgetConstraint.P95_LATENCY,
                    currentP95,
                    maxP95.toDouble()
                )
            }
        }
        
        // Check battery drain
        budget.batteryDrainPerTenMinutes?.let { maxDrain ->
            batteryTracker.currentDrainRate?.let { currentDrain ->
                if (currentDrain > maxDrain) {
                    handleViolation(
                        BudgetConstraint.BATTERY_DRAIN,
                        currentDrain,
                        maxDrain
                    )
                }
            }
        }
        
        // Check thermal level
        budget.maxThermalLevel?.let { maxThermal ->
            val currentThermal = thermalMonitor.currentLevel
            if (currentThermal > maxThermal) {
                handleViolation(
                    BudgetConstraint.THERMAL_LEVEL,
                    currentThermal.toDouble(),
                    maxThermal.toDouble()
                )
            }
        }
        
        // Check memory ceiling (observe-only)
        budget.memoryCeilingMb?.let { maxMemory ->
            val currentMemory = resourceMonitor.currentRssMb
            if (currentMemory > maxMemory) {
                handleViolation(
                    BudgetConstraint.MEMORY_CEILING,
                    currentMemory,
                    maxMemory.toDouble()
                )
            }
        }
    }
    
    private fun handleViolation(
        constraint: BudgetConstraint,
        currentValue: Double,
        budgetValue: Double
    ) {
        val mitigation = attemptMitigation(constraint)
        
        val violation = BudgetViolation(
            constraint = constraint,
            currentValue = currentValue,
            budgetValue = budgetValue,
            mitigation = mitigation,
            timestamp = System.currentTimeMillis(),
            mitigated = false,
            observeOnly = constraint == BudgetConstraint.MEMORY_CEILING
        )
        
        emitViolation(violation)
    }
    
    private fun attemptMitigation(constraint: BudgetConstraint): String {
        return when (constraint) {
            BudgetConstraint.P95_LATENCY -> "Reduce inference frequency"
            BudgetConstraint.BATTERY_DRAIN -> "Lower model quality"
            BudgetConstraint.THERMAL_LEVEL -> "Pause high-priority workloads"
            BudgetConstraint.MEMORY_CEILING -> "Observe only - cannot reduce model memory"
        }
    }
    
    private fun emitViolation(violation: BudgetViolation) {
        Log.w(TAG, "⚠️ Budget Violation: $violation")
        violationListeners.forEach { it(violation) }
    }
    
    fun onBudgetViolation(listener: (BudgetViolation) -> Unit) {
        violationListeners.add(listener)
    }
    
    companion object {
        private const val TAG = "EdgeVeda.Scheduler"
    }
}
```

**2. Platform-Specific Integration**

```kotlin
// ThermalMonitor.kt
class ThermalMonitor(private val context: Context) {
    private var currentLevel: Int = 0
    
    init {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            currentLevel = powerManager.currentThermalStatus
            
            // Register for thermal status updates
            val thermalCallback = object : PowerManager.OnThermalStatusChangedListener {
                override fun onThermalStatusChanged(status: Int) {
                    currentLevel = status
                }
            }
            powerManager.addThermalStatusListener(thermalCallback)
        }
    }
    
    fun getCurrentLevel(): Int = currentLevel
}

// BatteryDrainTracker.kt
class BatteryDrainTracker(private val context: Context) {
    private val samples = mutableListOf<BatterySample>()
    
    init {
        startTracking()
    }
    
    private fun startTracking() {
        val handler = Handler(Looper.getMainLooper())
        handler.post(object : Runnable {
            override fun run() {
                recordSample()
                handler.postDelayed(this, 60_000) // Every minute
            }
        })
    }
    
    private fun recordSample() {
        val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        val level = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
        
        if (level >= 0) {
            samples.add(BatterySample(level, System.currentTimeMillis()))
            
            // Keep last 10 minutes of samples
            val cutoff = System.currentTimeMillis() - 600_000
            samples.removeAll { it.timestamp < cutoff }
        }
    }
    
    val currentDrainRate: Double?
        get() {
            if (samples.size < 2) return null
            
            val first = samples.first()
            val last = samples.last()
            
            val timeDiff = (last.timestamp - first.timestamp) / 1000.0 // seconds
            if (timeDiff <= 0) return null
            
            val levelDiff = (first.level - last.level).toDouble() // Positive = draining
            val drainPerSecond = levelDiff / timeDiff
            val drainPerTenMin = drainPerSecond * 600
            
            return maxOf(0.0, drainPerTenMin)
        }
    
    private data class BatterySample(val level: Int, val timestamp: Long)
}
```

#### Android-Specific Considerations

- **JobScheduler**: Use for background task management
- **Doze Mode**: Handle app standby and optimization
- **Thermal API**: Requires Android 10+ (API 29)
- **BatteryManager**: Track battery capacity and drain
- **WorkManager**: For deferred/periodic tasks

---

### React Native (Cross-Platform) Implementation

#### File Structure

```
react-native/src/
├── Budget.ts                    🆕 NEW
├── Scheduler.ts                 🆕 NEW
├── RuntimePolicy.ts             🆕 NEW
├── Telemetry.ts                🆕 NEW
```

#### Key Implementation Details

**1. Budget.ts**

```typescript
export interface EdgeVedaBudget {
  p95LatencyMs?: number;
  batteryDrainPerTenMinutes?: number;
  maxThermalLevel?: number;
  memoryCeilingMb?: number;
  adaptiveProfile?: BudgetProfile;
}

export enum BudgetProfile {
  CONSERVATIVE = 'conservative',
  BALANCED = 'balanced',
  PERFORMANCE = 'performance',
}

export interface MeasuredBaseline {
  measuredP95Ms: number;
  measuredDrainPerTenMin?: number;
  currentThermalState: number;
  currentRssMb: number;
  sampleCount: number;
  measuredAt: Date;
}

export interface BudgetViolation {
  constraint: BudgetConstraint;
  currentValue: number;
  budgetValue: number;
  mitigation: string;
  timestamp: Date;
  mitigated: boolean;
  observeOnly: boolean;
}

export enum BudgetConstraint {
  P95_LATENCY = 'p95_latency',
  BATTERY_DRAIN = 'battery_drain',
  THERMAL_LEVEL = 'thermal_level',
  MEMORY_CEILING = 'memory_ceiling',
}

export class Budget {
  static adaptive(profile: BudgetProfile): EdgeVedaBudget {
    return {
      adaptiveProfile: profile,
    };
  }
  
  static resolve(profile: BudgetProfile, baseline: MeasuredBaseline): EdgeVedaBudget {
    let resolvedP95: number;
    let resolvedDrain: number | undefined;
    let resolvedThermal: number;
    
    switch (profile) {
      case BudgetProfile.CONSERVATIVE:
        resolvedP95 = Math.round(baseline.measuredP95Ms * 2.0);
        resolvedDrain = baseline.measuredDrainPerTenMin 
          ? baseline.measuredDrainPerTenMin * 0.6 
          : undefined;
        resolvedThermal = baseline.currentThermalState < 1 ? 1 : baseline.currentThermalState;
        break;
        
      case BudgetProfile.BALANCED:
        resolvedP95 = Math.round(baseline.measuredP95Ms * 1.5);
        resolvedDrain = baseline.measuredDrainPerTenMin;
        resolvedThermal = 1;
        break;
        
      case BudgetProfile.PERFORMANCE:
        resolvedP95 = Math.round(baseline.measuredP95Ms * 1.1);
        resolvedDrain = baseline.measuredDrainPerTenMin 
          ? baseline.measuredDrainPerTenMin * 1.5 
          : undefined;
        resolvedThermal = 3;
        break;
    }
    
    return {
      p95LatencyMs: resolvedP95,
      batteryDrainPerTenMinutes: resolvedDrain,
      maxThermalLevel: resolvedThermal,
      memoryCeilingMb: undefined, // Always observe-only
    };
  }
}
```

**2. Native Module Integration**

React Native delegates to native iOS/Android implementations:

```typescript
// EdgeVeda.ts - Add Phase 4 methods
export class EdgeVedaSDK {
  // Existing methods...
  
  async setComputeBudget(budget: EdgeVedaBudget): Promise<void> {
    await NativeEdgeVeda.setComputeBudget(budget);
  }
  
  async getComputeBudget(): Promise<EdgeVedaBudget | null> {
    return await NativeEdgeVeda.getComputeBudget();
  }
  
  async getMeasuredBaseline(): Promise<MeasuredBaseline | null> {
    return await NativeEdgeVeda.getMeasuredBaseline();
  }
  
  onBudgetViolation(callback: (violation: BudgetViolation) => void): void {
    const subscription = eventEmitter.addListener('budgetViolation', callback);
    // Return unsubscribe function
    return () => subscription.remove();
  }
  
  async getTelemetry(): Promise<TelemetrySnapshot> {
    return await NativeEdgeVeda.getTelemetry();
  }
  
  async setRuntimePolicy(policy: RuntimePolicy): Promise<void> {
    await NativeEdgeVeda.setRuntimePolicy(policy);
  }
}
```

#### React Native Considerations

- **Delegate to Native**: Most implementation in Swift/Kotlin
- **Event Emitters**: Use for violation callbacks
- **TypeScript Types**: Match Swift/Kotlin exactly
- **Platform Detection**: Conditionally access platform features

---

### Web (Browser) Implementation

#### File Structure

```
web/src/
├── Budget.ts                    🆕 NEW
├── Scheduler.ts                 🆕 NEW
├── RuntimePolicy.ts             🆕 NEW
├── Telemetry.ts                🆕 NEW
├── PerformanceMonitor.ts        🆕 NEW
```

#### Key Implementation Details

**1. Web Scheduler**

```typescript
export class Scheduler {
  private taskQueue: PriorityQueue<ScheduledTask> = new PriorityQueue();
  private budget?: EdgeVedaBudget;
  private latencyTracker = new LatencyTracker();
  private performanceMonitor = new PerformanceMonitor();
  
  private measuredBaseline?: MeasuredBaseline;
  private warmUpComplete = false;
  
  private violationListeners: Array<(v: BudgetViolation) => void> = [];
  
  async setComputeBudget(budget: EdgeVedaBudget): Promise<void> {
    this.budget = budget;
    
    if (budget.adaptiveProfile) {
      console.log(`Adaptive budget set: ${budget.adaptiveProfile}. Warming up...`);
    }
  }
  
  getComputeBudget(): EdgeVedaBudget | undefined {
    return this.budget;
  }
  
  getMeasuredBaseline(): MeasuredBaseline | undefined {
    return this.measuredBaseline;
  }
  
  async scheduleTask<T>(
    priority: TaskPriority,
    workload: WorkloadId,
    task: () => Promise<T>
  ): Promise<T> {
    const taskId = crypto.randomUUID();
    
    return new Promise((resolve, reject) => {
      const scheduledTask: ScheduledTask = {
        id: taskId,
        priority,
        workload,
        execute: task,
        resolve,
        reject,
      };
      
      this.taskQueue.enqueue(scheduledTask);
      this.processQueue();
    });
  }
  
  private async processQueue(): Promise<void> {
    while (!this.taskQueue.isEmpty()) {
      const task = this.taskQueue.dequeue();
      if (!task) continue;
      
      try {
        const startTime = performance.now();
        
        // Check budget constraints
        await this.checkBudgetConstraints();
        
        // Execute task
        const result = await task.execute();
        
        // Record metrics
        const duration = performance.now() - startTime;
        this.latencyTracker.record(duration);
        
        // Update warm-up status
        if (!this.warmUpComplete && this.latencyTracker.sampleCount >= 20) {
          await this.completeWarmUp();
        }
        
        task.resolve(result);
      } catch (error) {
        task.reject(error);
      }
    }
  }
  
  private async completeWarmUp(): Promise<void> {
    if (!this.budget?.adaptiveProfile) return;
    
    const baseline: MeasuredBaseline = {
      measuredP95Ms: this.latencyTracker.p95,
      measuredDrainPerTenMin: undefined, // Not available in browser
      currentThermalState: -1, // Not available in browser
      currentRssMb: this.performanceMonitor.currentMemoryMb,
      sampleCount: this.latencyTracker.sampleCount,
      measuredAt: new Date(),
    };
    
    this.measuredBaseline = baseline;
    
    // Resolve adaptive budget
    this.budget = Budget.resolve(this.budget.adaptiveProfile, baseline);
    this.warmUpComplete = true;
    
    console.log('Warm-up complete:', baseline);
    console.log('Resolved budget:', this.budget);
  }
  
  private async checkBudgetConstraints(): Promise<void> {
    if (!this.budget || !this.warmUpComplete) return;
    
    // Check p95 latency
    if (this.budget.p95LatencyMs !== undefined) {
      const currentP95 = this.latencyTracker.p95;
      if (currentP95 > this.budget.p95LatencyMs) {
        this.handleViolation(
          BudgetConstraint.P95_LATENCY,
          currentP95,
          this.budget.p95LatencyMs
        );
      }
    }
    
    // Check memory ceiling (observe-only)
    if (this.budget.memoryCeilingMb !== undefined) {
      const currentMemory = this.performanceMonitor.currentMemoryMb;
      if (currentMemory > this.budget.memoryCeilingMb) {
        this.handleViolation(
          BudgetConstraint.MEMORY_CEILING,
          currentMemory,
          this.budget.memoryCeilingMb
        );
      }
    }
    
    // Battery and thermal not available in browser
  }
  
  private handleViolation(
    constraint: BudgetConstraint,
    currentValue: number,
    budgetValue: number
  ): void {
    const mitigation = this.attemptMitigation(constraint);
    
    const violation: BudgetViolation = {
      constraint,
      currentValue,
      budgetValue,
      mitigation,
      timestamp: new Date(),
      mitigated: false,
      observeOnly: constraint === BudgetConstraint.MEMORY_CEILING,
    };
    
    this.emitViolation(violation);
  }
  
  private attemptMitigation(constraint: BudgetConstraint): string {
    switch (constraint) {
      case BudgetConstraint.P95_LATENCY:
        return 'Reduce inference frequency';
      case BudgetConstraint.MEMORY_CEILING:
        return 'Observe only - cannot reduce model memory';
      default:
        return 'No mitigation available';
    }
  }
  
  private emitViolation(violation: BudgetViolation): void {
    console.warn('⚠️ Budget Violation:', violation);
    this.violationListeners.forEach(listener => listener(violation));
  }
  
  onBudgetViolation(listener: (violation: BudgetViolation) => void): () => void {
    this.violationListeners.push(listener);
    return () => {
      const index = this.violationListeners.indexOf(listener);
      if (index > -1) {
        this.violationListeners.splice(index, 1);
      }
    };
  }
}
```

**2. Performance Monitor**

```typescript
// PerformanceMonitor.ts
export class PerformanceMonitor {
  get currentMemoryMb(): number {
    if ('memory' in performance) {
      const memory = (performance as any).memory;
      return memory.usedJSHeapSize / (1024 * 1024);
    }
    return 0;
  }
  
  get peakMemoryMb(): number {
    if ('memory' in performance) {
      const memory = (performance as any).memory;
      return memory.jsHeapSizeLimit / (1024 * 1024);
    }
    return 0;
  }
}
```

#### Web-Specific Considerations

- **No Battery/Thermal API**: Browser security limits access
- **Performance API**: Use for timing and memory metrics
- **Service Workers**: For background processing
- **IndexedDB**: Store telemetry data locally
- **Limited OS Integration**: Cannot access system-level APIs

---

## Implementation Roadmap

### Month 1: Foundation & Swift (Weeks 1-4)

**Week 1: Architecture & Design**
- [ ] Finalize unified API design
- [ ] Review Flutter Budget.swift implementation
- [ ] Create detailed type definitions for all platforms
- [ ] Set up testing infrastructure

**Week 2: Swift Core Implementation**
- [ ] Implement Scheduler.swift with task queue
- [ ] Implement LatencyTracker.swift (p50, p95, p99)
- [ ] Implement ResourceMonitor.swift (memory RSS)
- [ ] Add warm-up logic and baseline measurement

**Week 3: Swift Platform Integration**
- [ ] Implement ThermalMonitor.swift (iOS thermal API)
- [ ] Implement BatteryDrainTracker.swift (UIDevice battery)
- [ ] Implement RuntimePolicy.swift with iOS policies
- [ ] Implement Telemetry.swift with OSLog integration

**Week 4: Swift Testing & Polish**
- [ ] Unit tests for all components (80%+ coverage)
- [ ] Integration tests with EdgeVeda SDK
- [ ] Performance benchmarking
- [ ] Update Swift example app with Phase 4 demo

### Month 2: Kotlin & React Native (Weeks 5-8)

**Week 5: Kotlin Core Implementation**
- [ ] Port Scheduler to Kotlin with coroutines
- [ ] Port LatencyTracker, ResourceMonitor
- [ ] Implement adaptive budget resolution
- [ ] Add budget violation handling

**Week 6: Kotlin Platform Integration**
- [ ] Implement ThermalMonitor (Android 10+ API)
- [ ] Implement BatteryDrainTracker (BatteryManager)
- [ ] Implement RuntimePolicy with Doze/JobScheduler
- [ ] Add Telemetry with Android logging

**Week 7: React Native Bridge**
- [ ] Create TypeScript type definitions
- [ ] Implement iOS native module methods
- [ ] Implement Android native module methods
- [ ] Add event emitters for violations

**Week 8: React Native Testing**
- [ ] Unit tests for TypeScript layer
- [ ] Integration tests (iOS + Android)
- [ ] Update React Native example app
- [ ] Performance validation

### Month 3: Web & Final Polish (Weeks 9-12)

**Week 9: Web Implementation**
- [ ] Implement Web Scheduler with Worker
- [ ] Implement PerformanceMonitor
- [ ] Implement Web-specific Telemetry
- [ ] Handle browser limitations gracefully

**Week 10: Web Testing & Integration**
- [ ] Unit tests for Web implementation
- [ ] Browser compatibility testing
- [ ] Performance profiling
- [ ] Update Web example

**Week 11: Documentation & Examples**
- [ ] Complete API documentation for all platforms
- [ ] Write usage guides and best practices
- [ ] Create comprehensive examples
- [ ] Performance tuning guide

**Week 12: Final Validation**
- [ ] Cross-platform integration testing
- [ ] Performance benchmarking (all platforms)
- [ ] Security audit
- [ ] Release preparation

---

## Success Criteria

### Functional Requirements

- [x] ComputeBudget API implemented on all platforms
- [ ] Adaptive budget profiles (Conservative, Balanced, Performance)
- [ ] Measured baseline after warm-up (20+ samples)
- [ ] Budget violation detection and events
- [ ] Scheduler with priority queuing
- [ ] RuntimePolicy with OS-specific integration
- [ ] Telemetry snapshot and diagnostics
- [ ] Resource monitoring (latency, battery, thermal, memory)

### Performance Requirements

- [ ] Scheduler overhead < 5% vs direct execution
- [ ] Budget check latency < 10ms
- [ ] Memory overhead < 50MB for monitoring
- [ ] Warm-up completes within 2 minutes of usage

### Platform Parity

- [ ] Swift: Full iOS/macOS integration
- [ ] Kotlin: Full Android integration (API 24+)
- [ ] React Native: Native bridge working on both platforms
- [ ] Web: Browser-compatible implementation

### Quality Requirements

- [ ] Unit test coverage ≥ 80% for all components
- [ ] Integration tests passing on all platforms
- [ ] Documentation complete with examples
- [ ] Example apps demonstrate all features
- [ ] Performance validated against benchmarks

---

## Risk Mitigation

### Technical Risks

**Risk**: Adaptive budget calculation unstable on some devices
- **Mitigation**: Extensive device testing, fallback to static budgets
- **Owner**: Platform leads

**Risk**: Thermal/battery APIs unavailable on older devices
- **Mitigation**: Graceful degradation, feature detection
- **Owner**: Platform leads

**Risk**: React Native bridge overhead affects performance
- **Mitigation**: Batch operations, optimize event emission
- **Owner**: React Native lead

### Schedule Risks

**Risk**: Implementation takes longer than estimated
- **Mitigation**: Incremental delivery, prioritize core features first
- **Owner**: Project manager

**Risk**: Testing reveals platform-specific bugs
- **Mitigation**: Buffer time in Month 3, continuous testing
- **Owner**: QA lead

---

## Dependencies

### Internal

- Flutter Budget.swift (reference implementation) ✅
- Core EdgeVeda SDK on all platforms ✅
- Platform hardening complete ✅

### External

- iOS: iOS 15+, Xcode 14+
- Android: API 24+, SDK 33+
- React Native: 0.71+
- Web: ES2020+, modern browsers

---

## Deliverables

### Code

- [ ] Swift implementation (7 new files)
- [ ] Kotlin implementation (7 new files)
- [ ] React Native TypeScript + native bridges
- [ ] Web TypeScript implementation
- [ ] Unit tests (all platforms)
- [ ] Integration tests (all platforms)

### Documentation

- [ ] API reference (all platforms)
- [ ] Usage guides and tutorials
- [ ] Best practices document
- [ ] Performance tuning guide
- [ ] Migration guide for existing apps

### Examples

- [ ] Swift example with budget demo
- [ ] Kotlin example with budget demo
- [ ] React Native example
- [ ] Web demo application

---

## Next Steps

1. **Review this plan** with the team
2. **Approve API design** and get consensus
3. **Set up project tracking** (Jira/GitHub issues)
4. **Assign platform leads** for each implementation
5. **Begin Week 1** with architecture finalization

**Ready to proceed?** Once approved, we can start with Swift implementation (Month 1, Week 1).
