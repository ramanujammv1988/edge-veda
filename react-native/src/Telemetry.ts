/**
 * Edge Veda SDK - Telemetry
 * Structured logging and metrics collection for runtime supervision.
 *
 * Provides console-based logging with appropriate categories and stores
 * performance metrics (latency, budget violations, resource snapshots)
 * for retrieval and analysis.
 *
 * JavaScript is single-threaded in React Native, so no mutex is needed.
 *
 * @example
 * ```typescript
 * const telemetry = Telemetry.instance;
 * telemetry.logInferenceStart('req-123', 'my-model');
 * telemetry.recordLatency('req-123', 42.5);
 * telemetry.logBudgetViolation(BudgetViolationType.LATENCY, 50, 40);
 * ```
 */

// =============================================================================
// Supporting Types
// =============================================================================

/** Budget violation type. */
export enum BudgetViolationType {
  LATENCY = 'latency',
  MEMORY = 'memory',
  BATTERY = 'battery',
  THERMAL = 'thermal',
}

/** Violation severity level. */
export enum ViolationSeverity {
  INFO = 'info',
  WARNING = 'warning',
  CRITICAL = 'critical',
}

/** Latency metric for a single inference request. */
export interface LatencyMetric {
  requestId: string;
  modelName?: string;
  startTime?: Date;
  endTime?: Date;
  latencyMs?: number;
}

/** Budget violation record. */
export interface BudgetViolationRecord {
  timestamp: Date;
  type: BudgetViolationType;
  current: number;
  limit: number;
  severity: ViolationSeverity;
}

/** Resource usage snapshot. */
export interface ResourceSnapshot {
  timestamp: Date;
  memoryMb: number;
  batteryLevel?: number;
  thermalLevel: number;
}

/** Aggregated latency statistics. */
export interface LatencyStats {
  count: number;
  min: number;
  max: number;
  mean: number;
  p50: number;
  p95: number;
  p99: number;
}

/** Format LatencyStats as a human-readable string. */
export function latencyStatsToString(s: LatencyStats): string {
  return (
    `LatencyStats(count=${s.count}, min=${s.min.toFixed(2)}ms, max=${s.max.toFixed(2)}ms, ` +
    `mean=${s.mean.toFixed(2)}ms, p50=${s.p50.toFixed(2)}ms, ` +
    `p95=${s.p95.toFixed(2)}ms, p99=${s.p99.toFixed(2)}ms)`
  );
}

// =============================================================================
// Log Tags
// =============================================================================

const TAG_INFERENCE = 'EdgeVeda.Inference';
const TAG_BUDGET = 'EdgeVeda.Budget';
const TAG_RESOURCES = 'EdgeVeda.Resources';
const TAG_SCHEDULER = 'EdgeVeda.Scheduler';
const TAG_POLICY = 'EdgeVeda.Policy';

// =============================================================================
// Telemetry
// =============================================================================

/**
 * Singleton telemetry subsystem for structured logging and metrics collection.
 *
 * Access via `Telemetry.instance`.
 */
export class Telemetry {
  // -------------------------------------------------------------------------
  // Singleton
  // -------------------------------------------------------------------------

  private static _instance: Telemetry | null = null;

  static get instance(): Telemetry {
    if (!Telemetry._instance) {
      Telemetry._instance = new Telemetry();
    }
    return Telemetry._instance;
  }

  private constructor() {
    console.info(`[${TAG_INFERENCE}] Telemetry system initialized`);
  }

  // -------------------------------------------------------------------------
  // Metrics Storage
  // -------------------------------------------------------------------------

  private latencyMetrics = new Map<string, LatencyMetric>();
  private budgetViolations: BudgetViolationRecord[] = [];
  private resourceSnapshots: ResourceSnapshot[] = [];

  private maxStoredMetrics = 1000;
  private maxStoredViolations = 100;
  private maxStoredSnapshots = 100;

  // -------------------------------------------------------------------------
  // Configuration
  // -------------------------------------------------------------------------

  /** Set maximum number of latency metrics to store in memory. */
  setMaxStoredMetrics(count: number): void {
    this.maxStoredMetrics = count;
    this.trimMetrics();
  }

  /** Set maximum number of budget violations to store. */
  setMaxStoredViolations(count: number): void {
    this.maxStoredViolations = count;
    this.trimViolations();
  }

  /** Set maximum number of resource snapshots to store. */
  setMaxStoredSnapshots(count: number): void {
    this.maxStoredSnapshots = count;
    this.trimSnapshots();
  }

  // -------------------------------------------------------------------------
  // Inference Logging
  // -------------------------------------------------------------------------

  /** Log the start of an inference request. */
  logInferenceStart(requestId: string, modelName?: string): void {
    const msg = modelName
      ? `Inference started: ${requestId} model=${modelName}`
      : `Inference started: ${requestId}`;
    console.info(`[${TAG_INFERENCE}] ${msg}`);

    this.latencyMetrics.set(requestId, {
      requestId,
      modelName,
      startTime: new Date(),
    });
    this.trimMetrics();
  }

  /** Log the completion of an inference request. */
  logInferenceComplete(requestId: string, tokensGenerated?: number): void {
    const msg = tokensGenerated !== undefined
      ? `Inference completed: ${requestId} tokens=${tokensGenerated}`
      : `Inference completed: ${requestId}`;
    console.info(`[${TAG_INFERENCE}] ${msg}`);

    const metric = this.latencyMetrics.get(requestId);
    if (metric) {
      const endTime = new Date();
      const latencyMs = metric.startTime
        ? endTime.getTime() - metric.startTime.getTime()
        : undefined;
      this.latencyMetrics.set(requestId, {
        ...metric,
        endTime,
        latencyMs,
      });
    }
  }

  /** Log an inference error. */
  logInferenceError(requestId: string, error: string): void {
    console.error(`[${TAG_INFERENCE}] Inference failed: ${requestId} error=${error}`);
  }

  /** Record latency for a completed request. */
  recordLatency(requestId: string, latencyMs: number): void {
    console.debug(`[${TAG_INFERENCE}] Latency recorded: ${requestId} latency=${latencyMs}ms`);

    const metric = this.latencyMetrics.get(requestId);
    if (metric) {
      this.latencyMetrics.set(requestId, { ...metric, latencyMs });
    }
  }

  // -------------------------------------------------------------------------
  // Budget Logging
  // -------------------------------------------------------------------------

  /** Log a budget violation. */
  logBudgetViolation(
    type: BudgetViolationType,
    current: number,
    limit: number,
    severity: ViolationSeverity = ViolationSeverity.WARNING
  ): void {
    const message = `Budget violation: ${type} current=${current} limit=${limit} severity=${severity}`;

    switch (severity) {
      case ViolationSeverity.INFO:
        console.info(`[${TAG_BUDGET}] ${message}`);
        break;
      case ViolationSeverity.WARNING:
        console.warn(`[${TAG_BUDGET}] ${message}`);
        break;
      case ViolationSeverity.CRITICAL:
        console.error(`[${TAG_BUDGET}] ${message}`);
        break;
    }

    this.budgetViolations.push({
      timestamp: new Date(),
      type,
      current,
      limit,
      severity,
    });
    this.trimViolations();
  }

  /** Log budget enforcement action. */
  logBudgetEnforcement(action: string, reason: string): void {
    console.info(`[${TAG_BUDGET}] Budget enforcement: ${action} reason=${reason}`);
  }

  /** Log measured baseline update. */
  logBaselineUpdate(p50: number, p95: number, p99: number, sampleCount: number): void {
    console.info(
      `[${TAG_BUDGET}] Baseline updated: p50=${p50}ms p95=${p95}ms p99=${p99}ms samples=${sampleCount}`
    );
  }

  // -------------------------------------------------------------------------
  // Resource Logging
  // -------------------------------------------------------------------------

  /** Log current resource usage. */
  logResourceUsage(memoryMb: number, batteryLevel?: number, thermalLevel: number = 0): void {
    const msg = batteryLevel !== undefined
      ? `Resources: memory=${memoryMb}MB battery=${Math.round(batteryLevel * 100)}% thermal=${thermalLevel}`
      : `Resources: memory=${memoryMb}MB thermal=${thermalLevel}`;
    console.debug(`[${TAG_RESOURCES}] ${msg}`);

    this.resourceSnapshots.push({
      timestamp: new Date(),
      memoryMb,
      batteryLevel,
      thermalLevel,
    });
    this.trimSnapshots();
  }

  /** Log memory pressure event. */
  logMemoryPressure(current: number, peak: number, available?: number): void {
    const msg = available !== undefined
      ? `Memory pressure: current=${current}MB peak=${peak}MB available=${available}MB`
      : `Memory pressure: current=${current}MB peak=${peak}MB`;
    console.warn(`[${TAG_RESOURCES}] ${msg}`);
  }

  /** Log thermal state change. */
  logThermalStateChange(from: number, to: number): void {
    console.info(`[${TAG_RESOURCES}] Thermal state changed: ${from} -> ${to}`);
  }

  /** Log battery drain rate. */
  logBatteryDrain(drainRate: number, currentLevel: number): void {
    console.info(
      `[${TAG_RESOURCES}] Battery drain: rate=${drainRate}%/10min level=${Math.round(currentLevel * 100)}%`
    );
  }

  // -------------------------------------------------------------------------
  // Scheduler Logging
  // -------------------------------------------------------------------------

  /** Log task scheduling. */
  logTaskScheduled(taskId: string, priority: string): void {
    console.debug(`[${TAG_SCHEDULER}] Task scheduled: ${taskId} priority=${priority}`);
  }

  /** Log task execution start. */
  logTaskStarted(taskId: string): void {
    console.debug(`[${TAG_SCHEDULER}] Task started: ${taskId}`);
  }

  /** Log task completion. */
  logTaskCompleted(taskId: string, durationMs: number): void {
    console.debug(`[${TAG_SCHEDULER}] Task completed: ${taskId} duration=${durationMs}ms`);
  }

  /** Log task cancellation. */
  logTaskCancelled(taskId: string, reason: string): void {
    console.info(`[${TAG_SCHEDULER}] Task cancelled: ${taskId} reason=${reason}`);
  }

  /** Log queue status. */
  logQueueStatus(pending: number, running: number, priority: string): void {
    console.debug(
      `[${TAG_SCHEDULER}] Queue status: pending=${pending} running=${running} priority=${priority}`
    );
  }

  // -------------------------------------------------------------------------
  // Policy Logging
  // -------------------------------------------------------------------------

  /** Log policy change. */
  logPolicyChange(from: string, to: string): void {
    console.info(`[${TAG_POLICY}] Policy changed: ${from} -> ${to}`);
  }

  /** Log throttle decision. */
  logThrottleDecision(shouldThrottle: boolean, factor: number, reasons: string[]): void {
    if (shouldThrottle) {
      console.warn(
        `[${TAG_POLICY}] Throttling applied: factor=${factor} reasons=${reasons.join(', ')}`
      );
    } else {
      console.debug(`[${TAG_POLICY}] No throttling needed`);
    }
  }

  /** Log policy enforcement action. */
  logPolicyEnforcement(action: string, context: string): void {
    console.info(`[${TAG_POLICY}] Policy enforcement: ${action} context=${context}`);
  }

  // -------------------------------------------------------------------------
  // Metrics Retrieval
  // -------------------------------------------------------------------------

  /** Get all stored latency metrics. */
  getLatencyMetrics(): LatencyMetric[] {
    return Array.from(this.latencyMetrics.values());
  }

  /** Get latency metric for a specific request. */
  getLatencyMetric(requestId: string): LatencyMetric | undefined {
    return this.latencyMetrics.get(requestId);
  }

  /** Get all budget violations. */
  getBudgetViolations(): BudgetViolationRecord[] {
    return [...this.budgetViolations];
  }

  /** Get recent budget violations (last N). */
  getRecentViolations(count: number): BudgetViolationRecord[] {
    const start = Math.max(0, this.budgetViolations.length - count);
    return this.budgetViolations.slice(start);
  }

  /** Get all resource snapshots. */
  getResourceSnapshots(): ResourceSnapshot[] {
    return [...this.resourceSnapshots];
  }

  /** Get recent resource snapshots (last N). */
  getRecentSnapshots(count: number): ResourceSnapshot[] {
    const start = Math.max(0, this.resourceSnapshots.length - count);
    return this.resourceSnapshots.slice(start);
  }

  /** Get aggregated latency statistics, or undefined if no completed metrics. */
  getLatencyStats(): LatencyStats | undefined {
    const latencies: number[] = [];
    for (const metric of this.latencyMetrics.values()) {
      if (metric.latencyMs !== undefined) {
        latencies.push(metric.latencyMs);
      }
    }
    if (latencies.length === 0) return undefined;

    const sorted = [...latencies].sort((a, b) => a - b);
    const count = sorted.length;
    const sum = sorted.reduce((a, b) => a + b, 0);

    return {
      count,
      min: sorted[0]!,
      max: sorted[count - 1]!,
      mean: sum / count,
      p50: sorted[Math.min(Math.floor(count * 0.5), count - 1)]!,
      p95: sorted[Math.min(Math.floor(count * 0.95), count - 1)]!,
      p99: sorted[Math.min(Math.floor(count * 0.99), count - 1)]!,
    };
  }

  // -------------------------------------------------------------------------
  // Cleanup
  // -------------------------------------------------------------------------

  /** Clear all stored metrics. */
  clearMetrics(): void {
    this.latencyMetrics.clear();
    this.budgetViolations = [];
    this.resourceSnapshots = [];
    console.info(`[${TAG_INFERENCE}] All metrics cleared`);
  }

  /** Clear metrics older than specified duration in milliseconds. */
  clearOldMetrics(olderThanMs: number): void {
    const cutoff = new Date(Date.now() - olderThanMs);

    for (const [key, metric] of this.latencyMetrics) {
      if (!metric.startTime || metric.startTime < cutoff) {
        this.latencyMetrics.delete(key);
      }
    }

    this.budgetViolations = this.budgetViolations.filter(
      (v) => v.timestamp >= cutoff
    );
    this.resourceSnapshots = this.resourceSnapshots.filter(
      (s) => s.timestamp >= cutoff
    );

    console.info(`[${TAG_INFERENCE}] Cleared metrics older than ${olderThanMs}ms`);
  }

  // -------------------------------------------------------------------------
  // Private - Trimming
  // -------------------------------------------------------------------------

  private trimMetrics(): void {
    if (this.latencyMetrics.size > this.maxStoredMetrics) {
      // Remove oldest entries (Map preserves insertion order)
      const toRemove = this.latencyMetrics.size - this.maxStoredMetrics;
      let removed = 0;
      for (const key of this.latencyMetrics.keys()) {
        if (removed >= toRemove) break;
        this.latencyMetrics.delete(key);
        removed++;
      }
    }
  }

  private trimViolations(): void {
    if (this.budgetViolations.length > this.maxStoredViolations) {
      const toRemove = this.budgetViolations.length - this.maxStoredViolations;
      this.budgetViolations.splice(0, toRemove);
    }
  }

  private trimSnapshots(): void {
    if (this.resourceSnapshots.length > this.maxStoredSnapshots) {
      const toRemove = this.resourceSnapshots.length - this.maxStoredSnapshots;
      this.resourceSnapshots.splice(0, toRemove);
    }
  }
}