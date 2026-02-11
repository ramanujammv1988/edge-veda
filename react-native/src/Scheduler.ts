/**
 * Edge Veda SDK - Scheduler
 * Priority-based task scheduler with budget enforcement.
 *
 * The Scheduler manages concurrent inference workloads, enforces EdgeVedaBudget
 * constraints, and emits BudgetViolation events when limits are exceeded.
 *
 * JavaScript is single-threaded in React Native, so no mutex is needed.
 * Async/await provides the same sequential guarantees as Kotlin's Mutex.
 *
 * @example
 * ```typescript
 * const scheduler = new Scheduler();
 * scheduler.setComputeBudget(Budget.adaptive(BudgetProfile.BALANCED));
 *
 * const result = await scheduler.scheduleTask(
 *   TaskPriority.HIGH,
 *   WorkloadId.TEXT,
 *   () => edgeVeda.generate(prompt)
 * );
 * ```
 */

import {
  type EdgeVedaBudget,
  type MeasuredBaseline,
  type BudgetViolation,
  BudgetProfile,
  BudgetConstraint,
  WorkloadPriority,
  WorkloadId,
  Budget,
} from './Budget';
import { LatencyTracker } from './LatencyTracker';
import { BatteryDrainTracker } from './BatteryDrainTracker';
import { ThermalMonitor } from './ThermalMonitor';
import { ResourceMonitor } from './ResourceMonitor';

// =============================================================================
// Supporting Types
// =============================================================================

/** Task priority levels. */
export enum TaskPriority {
  LOW = 0,
  NORMAL = 1,
  HIGH = 2,
}

/** Task execution status. */
export enum TaskStatus {
  QUEUED = 'queued',
  RUNNING = 'running',
  COMPLETED = 'completed',
  CANCELLED = 'cancelled',
  FAILED = 'failed',
}

/** Handle for a scheduled task. */
export interface TaskHandle {
  /** Unique task identifier. */
  id: string;
  /** Task priority. */
  priority: TaskPriority;
  /** Workload type. */
  workload: WorkloadId;
  /** Current status. */
  status: TaskStatus;
}

/** Queue status snapshot. */
export interface QueueStatus {
  /** Number of tasks currently queued. */
  queuedTasks: number;
  /** Number of tasks currently running. */
  runningTasks: number;
  /** Total number of completed tasks. */
  completedTasks: number;
  /** Number of high-priority tasks in queue. */
  highPriorityCount: number;
  /** Number of normal-priority tasks in queue. */
  normalPriorityCount: number;
  /** Number of low-priority tasks in queue. */
  lowPriorityCount: number;
}

// =============================================================================
// Internal PriorityQueue
// =============================================================================

interface QueuedItem {
  id: string;
  priority: TaskPriority;
}

class PriorityQueue {
  private items: QueuedItem[] = [];

  get count(): number {
    return this.items.length;
  }

  get isEmpty(): boolean {
    return this.items.length === 0;
  }

  enqueue(id: string, priority: TaskPriority): void {
    this.items.push({ id, priority });
    // Sort descending by priority value (HIGH=2 first)
    this.items.sort((a, b) => b.priority - a.priority);
  }

  dequeue(): string | undefined {
    if (this.items.length === 0) return undefined;
    return this.items.shift()!.id;
  }

  removeTask(id: string): void {
    this.items = this.items.filter((item) => item.id !== id);
  }

  countByPriority(priority: TaskPriority): number {
    return this.items.filter((item) => item.priority === priority).length;
  }
}

// =============================================================================
// UUID Helper
// =============================================================================

let _nextId = 0;

function generateTaskId(): string {
  _nextId += 1;
  const timestamp = Date.now().toString(36);
  const random = Math.random().toString(36).substring(2, 8);
  return `task_${timestamp}_${random}_${_nextId}`;
}

// =============================================================================
// Scheduler
// =============================================================================

/**
 * Priority-based task scheduler with budget enforcement.
 *
 * Manages concurrent inference workloads, enforces EdgeVedaBudget constraints,
 * and emits BudgetViolation events when limits are exceeded.
 *
 * Single-threaded JS means no mutex is needed — the API matches Swift/Kotlin
 * for cross-platform consistency.
 */
export class Scheduler {
  private readonly latencyTracker: LatencyTracker;
  private readonly batteryTracker: BatteryDrainTracker;
  private readonly thermalMonitor: ThermalMonitor;
  private readonly resourceMonitor: ResourceMonitor;

  private readonly taskQueue = new PriorityQueue();
  private budget: EdgeVedaBudget | undefined;
  private readonly workloadRegistry = new Map<WorkloadId, WorkloadPriority>();

  private _measuredBaseline: MeasuredBaseline | undefined;
  private warmUpComplete = false;
  private readonly warmUpThreshold = 20;

  private readonly violationListeners = new Map<
    string,
    (violation: BudgetViolation) => void
  >();
  private nextListenerId = 0;

  constructor(
    latencyTracker?: LatencyTracker,
    batteryTracker?: BatteryDrainTracker,
    thermalMonitor?: ThermalMonitor,
    resourceMonitor?: ResourceMonitor
  ) {
    this.latencyTracker = latencyTracker ?? new LatencyTracker();
    this.batteryTracker = batteryTracker ?? new BatteryDrainTracker();
    this.thermalMonitor = thermalMonitor ?? new ThermalMonitor();
    this.resourceMonitor = resourceMonitor ?? new ResourceMonitor();
  }

  // ---------------------------------------------------------------------------
  // Budget Management
  // ---------------------------------------------------------------------------

  /**
   * Set the compute budget for task execution.
   *
   * If the budget uses an adaptive profile, it will be resolved after warm-up
   * (20+ task samples). Until then, no budget enforcement occurs.
   */
  setComputeBudget(budget: EdgeVedaBudget): void {
    this.budget = budget;

    if (budget.adaptiveProfile !== undefined) {
      console.log(
        `[EdgeVeda.Scheduler] Adaptive budget set: ${budget.adaptiveProfile}. Warming up...`
      );
    }
  }

  /** Get the current compute budget. */
  getComputeBudget(): EdgeVedaBudget | undefined {
    return this.budget;
  }

  /**
   * Get the measured baseline after warm-up completes.
   *
   * Returns undefined if warm-up hasn't completed yet.
   */
  getMeasuredBaseline(): MeasuredBaseline | undefined {
    return this._measuredBaseline;
  }

  // ---------------------------------------------------------------------------
  // Task Scheduling
  // ---------------------------------------------------------------------------

  /**
   * Schedule a task with the specified priority.
   *
   * Tasks are queued and executed in priority order. High-priority tasks
   * run before normal and low-priority tasks. Budget constraints are checked
   * before each execution; violations are emitted but do not block execution.
   *
   * @param priority Task priority (HIGH, NORMAL, or LOW)
   * @param workload Workload type (TEXT or VISION)
   * @param task Async function to execute
   * @returns Result of the task execution
   */
  async scheduleTask<T>(
    priority: TaskPriority,
    workload: WorkloadId,
    task: () => Promise<T> | T
  ): Promise<T> {
    const taskId = generateTaskId();

    console.log(
      `[EdgeVeda.Scheduler] Task scheduled: ${taskId} priority=${TaskPriority[priority]}`
    );

    const startTime = Date.now();

    // Check budget before execution
    this.checkBudgetConstraints();

    // Execute task
    try {
      const result = await task();

      // Record latency
      const durationMs = Date.now() - startTime;
      this.latencyTracker.record(durationMs);

      // Update warm-up status
      if (!this.warmUpComplete && this.latencyTracker.sampleCount >= this.warmUpThreshold) {
        this.completeWarmUp();
      }

      console.log(
        `[EdgeVeda.Scheduler] Task completed: ${taskId} duration=${durationMs}ms`
      );
      return result;
    } catch (error) {
      console.error(
        `[EdgeVeda.Scheduler] Task failed: ${taskId} error=${error}`
      );
      throw error;
    }
  }

  /**
   * Cancel a scheduled task by ID.
   *
   * Only queued tasks can be cancelled. Running tasks cannot be cancelled.
   */
  cancelTask(taskId: string): void {
    this.taskQueue.removeTask(taskId);
  }

  /** Get current queue status. */
  getQueueStatus(): QueueStatus {
    return {
      queuedTasks: this.taskQueue.count,
      runningTasks: 0, // Simplified: single-threaded JS
      completedTasks: this.latencyTracker.sampleCount,
      highPriorityCount: this.taskQueue.countByPriority(TaskPriority.HIGH),
      normalPriorityCount: this.taskQueue.countByPriority(TaskPriority.NORMAL),
      lowPriorityCount: this.taskQueue.countByPriority(TaskPriority.LOW),
    };
  }

  // ---------------------------------------------------------------------------
  // Workload Management
  // ---------------------------------------------------------------------------

  /** Register a workload with its priority for degradation policy. */
  registerWorkload(workload: WorkloadId, priority: WorkloadPriority): void {
    this.workloadRegistry.set(workload, priority);
  }

  // ---------------------------------------------------------------------------
  // Violation Callbacks
  // ---------------------------------------------------------------------------

  /**
   * Register a callback for budget violation events.
   *
   * @param callback Called when a budget constraint is violated.
   * @returns Listener ID to use for removal via removeViolationListener().
   */
  onBudgetViolation(callback: (violation: BudgetViolation) => void): string {
    const id = `violation_${this.nextListenerId++}`;
    this.violationListeners.set(id, callback);
    return id;
  }

  /** Remove a budget violation listener. */
  removeViolationListener(id: string): void {
    this.violationListeners.delete(id);
  }

  // ---------------------------------------------------------------------------
  // Accessors for sub-components (useful for external telemetry / testing)
  // ---------------------------------------------------------------------------

  /** Get the internal LatencyTracker instance. */
  getLatencyTracker(): LatencyTracker {
    return this.latencyTracker;
  }

  /** Get the internal BatteryDrainTracker instance. */
  getBatteryTracker(): BatteryDrainTracker {
    return this.batteryTracker;
  }

  /** Get the internal ThermalMonitor instance. */
  getThermalMonitor(): ThermalMonitor {
    return this.thermalMonitor;
  }

  /** Get the internal ResourceMonitor instance. */
  getResourceMonitor(): ResourceMonitor {
    return this.resourceMonitor;
  }

  // ---------------------------------------------------------------------------
  // Private - Warm-up
  // ---------------------------------------------------------------------------

  private completeWarmUp(): void {
    if (this.budget === undefined) return;
    const profile = this.budget.adaptiveProfile;
    if (profile === undefined) return;

    const baseline: MeasuredBaseline = {
      measuredP95Ms: this.latencyTracker.p95,
      measuredDrainPerTenMin: this.batteryTracker.currentDrainRate,
      currentThermalState: this.thermalMonitor.currentLevel,
      currentRssMb: this.resourceMonitor.currentRssMb,
      sampleCount: this.latencyTracker.sampleCount,
      measuredAt: new Date(),
    };

    const resolvedBudget = Budget.resolve(profile, baseline);

    this._measuredBaseline = baseline;
    this.budget = resolvedBudget;
    this.warmUpComplete = true;

    console.log(
      `[EdgeVeda.Scheduler] Warm-up complete: ${Budget.baselineToString(baseline)}`
    );
    console.log(
      `[EdgeVeda.Scheduler] Resolved budget: ${Budget.toString(resolvedBudget)}`
    );
  }

  // ---------------------------------------------------------------------------
  // Private - Budget Enforcement
  // ---------------------------------------------------------------------------

  private checkBudgetConstraints(): void {
    const currentBudget = this.budget;
    if (currentBudget === undefined) return;
    if (!this.warmUpComplete) return;

    // Check p95 latency
    if (currentBudget.p95LatencyMs !== undefined) {
      const currentP95 = this.latencyTracker.p95;
      if (currentP95 > currentBudget.p95LatencyMs) {
        this.handleViolation(
          BudgetConstraint.P95_LATENCY,
          currentP95,
          currentBudget.p95LatencyMs
        );
      }
    }

    // Check battery drain
    if (currentBudget.batteryDrainPerTenMinutes !== undefined) {
      const currentDrain = this.batteryTracker.currentDrainRate;
      if (currentDrain !== undefined && currentDrain > currentBudget.batteryDrainPerTenMinutes) {
        this.handleViolation(
          BudgetConstraint.BATTERY_DRAIN,
          currentDrain,
          currentBudget.batteryDrainPerTenMinutes
        );
      }
    }

    // Check thermal level
    if (currentBudget.maxThermalLevel !== undefined) {
      const currentThermal = this.thermalMonitor.currentLevel;
      if (currentThermal > currentBudget.maxThermalLevel) {
        this.handleViolation(
          BudgetConstraint.THERMAL_LEVEL,
          currentThermal,
          currentBudget.maxThermalLevel
        );
      }
    }

    // Check memory ceiling (observe-only)
    if (currentBudget.memoryCeilingMb !== undefined) {
      const currentMemory = this.resourceMonitor.currentRssMb;
      if (currentMemory > currentBudget.memoryCeilingMb) {
        this.handleViolation(
          BudgetConstraint.MEMORY_CEILING,
          currentMemory,
          currentBudget.memoryCeilingMb
        );
      }
    }
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
      case BudgetConstraint.BATTERY_DRAIN:
        return 'Lower model quality';
      case BudgetConstraint.THERMAL_LEVEL:
        return 'Pause high-priority workloads';
      case BudgetConstraint.MEMORY_CEILING:
        return 'Observe only - cannot reduce model memory';
    }
  }

  private emitViolation(violation: BudgetViolation): void {
    console.warn(
      `[EdgeVeda.Scheduler] ⚠️ Budget Violation: ${Budget.violationToString(violation)}`
    );

    for (const listener of this.violationListeners.values()) {
      try {
        listener(violation);
      } catch (error) {
        console.warn(
          `[EdgeVeda.Scheduler] Error in violation listener: ${error}`
        );
      }
    }
  }
}