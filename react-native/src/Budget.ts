/**
 * Edge Veda SDK - Budget Types
 * Declarative compute budget contracts for on-device inference.
 *
 * An EdgeVedaBudget declares maximum resource limits that the Scheduler
 * enforces across concurrent workloads. Constraints are optional — set only
 * the ones you care about.
 *
 * @example
 * ```typescript
 * const budget: EdgeVedaBudget = {
 *   p95LatencyMs: 2000,
 *   batteryDrainPerTenMinutes: 3.0,
 *   maxThermalLevel: 2,
 *   memoryCeilingMb: 1200,
 * };
 * ```
 */

// =============================================================================
// EdgeVedaBudget
// =============================================================================

/**
 * Declarative compute budget with optional resource constraints.
 *
 * Set only the constraints you care about — unset fields are not enforced.
 */
export interface EdgeVedaBudget {
  /** Maximum p95 inference latency in milliseconds. Undefined to skip latency enforcement. */
  p95LatencyMs?: number;

  /** Maximum battery drain percentage per 10 minutes. Undefined to skip battery enforcement. */
  batteryDrainPerTenMinutes?: number;

  /** Maximum thermal level (0=nominal, 1=light, 2=moderate, 3=severe/critical). Undefined to skip. */
  maxThermalLevel?: number;

  /** Maximum memory RSS in megabytes. Undefined to skip memory enforcement. */
  memoryCeilingMb?: number;

  /** The adaptive profile, if created via Budget.adaptive(). Undefined for explicit-value budgets. */
  adaptiveProfile?: BudgetProfile;
}

// =============================================================================
// BudgetProfile
// =============================================================================

/**
 * Adaptive budget profile expressing intent as multipliers on measured device baseline.
 *
 * Instead of hard-coding absolute values, profiles multiply the actual measured
 * performance of THIS device with THIS model. The Scheduler resolves profile
 * multipliers against MeasuredBaseline after warm-up.
 */
export enum BudgetProfile {
  /**
   * Generous headroom: p95×2.0, battery×0.6 (strict), thermal=1 (light).
   * Best for background/secondary workloads where stability matters more than speed.
   */
  CONSERVATIVE = 'conservative',

  /**
   * Moderate headroom: p95×1.5, battery×1.0 (match baseline), thermal=1 (light).
   * Good default for most apps.
   */
  BALANCED = 'balanced',

  /**
   * Tight headroom: p95×1.1, battery×1.5 (generous), thermal=3 (allow critical).
   * For latency-sensitive apps willing to trade battery/thermal for speed.
   */
  PERFORMANCE = 'performance',
}

// =============================================================================
// MeasuredBaseline
// =============================================================================

/**
 * Snapshot of actual device performance measured during warm-up.
 *
 * The Scheduler builds this after its LatencyTracker and BatteryDrainTracker
 * have collected sufficient data.
 */
export interface MeasuredBaseline {
  /** Measured p95 inference latency in milliseconds. */
  measuredP95Ms: number;

  /** Measured battery drain rate per 10 minutes (percentage). Undefined if unavailable. */
  measuredDrainPerTenMin?: number;

  /** Current thermal state at time of measurement (0-3, or -1 if unknown). */
  currentThermalState: number;

  /** Current process RSS in megabytes at time of measurement. */
  currentRssMb: number;

  /** Number of latency samples collected during warm-up. */
  sampleCount: number;

  /** When this baseline was captured. */
  measuredAt: Date;
}

// =============================================================================
// BudgetViolation
// =============================================================================

/**
 * Emitted when the Scheduler cannot satisfy a declared budget constraint
 * even after attempting mitigation.
 */
export interface BudgetViolation {
  /** Which constraint was violated. */
  constraint: BudgetConstraint;

  /** Current measured value that exceeds the budget. */
  currentValue: number;

  /** Declared budget value that was exceeded. */
  budgetValue: number;

  /** What mitigation was attempted (e.g., "degrade vision to minimal"). */
  mitigation: string;

  /** When the violation was detected. */
  timestamp: Date;

  /** Whether the mitigation was successful (constraint now satisfied). */
  mitigated: boolean;

  /** Whether this violation is observe-only (no QoS mitigation possible). */
  observeOnly: boolean;
}

// =============================================================================
// BudgetConstraint
// =============================================================================

/** Which budget constraint was violated. */
export enum BudgetConstraint {
  /** p95 inference latency exceeded the declared maximum. */
  P95_LATENCY = 'p95_latency',

  /** Battery drain rate exceeded the declared maximum per 10 minutes. */
  BATTERY_DRAIN = 'battery_drain',

  /** Thermal level exceeded the declared maximum. */
  THERMAL_LEVEL = 'thermal_level',

  /** Memory RSS exceeded the declared ceiling. */
  MEMORY_CEILING = 'memory_ceiling',
}

// =============================================================================
// WorkloadPriority
// =============================================================================

/**
 * Priority level for a registered workload.
 *
 * Higher-priority workloads are degraded **last** when the scheduler needs
 * to reduce resource usage to satisfy budget constraints.
 */
export enum WorkloadPriority {
  /** Low priority — degraded first when budget is at risk. */
  LOW = 'low',

  /** High priority — maintained as long as possible. */
  HIGH = 'high',
}

// =============================================================================
// WorkloadId
// =============================================================================

/** Unique identifier for each workload type managed by the scheduler. */
export enum WorkloadId {
  /** Vision inference (VisionWorker). */
  VISION = 'vision',

  /** Text/chat inference (StreamingWorker via ChatSession). */
  TEXT = 'text',
}

// =============================================================================
// Budget Utility Class
// =============================================================================

/**
 * Static utility methods for creating and resolving budgets.
 */
export class Budget {
  /**
   * Create an adaptive budget resolved against measured device performance after warm-up.
   *
   * Unlike explicit values, this stores the profile and lets the Scheduler
   * resolve concrete values after trackers have warmed up. Before resolution,
   * no budget enforcement occurs.
   */
  static adaptive(profile: BudgetProfile): EdgeVedaBudget {
    return {
      adaptiveProfile: profile,
    };
  }

  /**
   * Resolve an adaptive profile against a baseline to produce concrete budget values.
   *
   * Called internally by Scheduler after warm-up.
   */
  static resolve(
    profile: BudgetProfile,
    baseline: MeasuredBaseline
  ): EdgeVedaBudget {
    let resolvedP95: number;
    let resolvedDrain: number | undefined;
    let resolvedThermal: number;

    switch (profile) {
      case BudgetProfile.CONSERVATIVE:
        resolvedP95 = Math.round(baseline.measuredP95Ms * 2.0);
        resolvedDrain =
          baseline.measuredDrainPerTenMin !== undefined
            ? baseline.measuredDrainPerTenMin * 0.6
            : undefined;
        resolvedThermal =
          baseline.currentThermalState < 1 ? 1 : baseline.currentThermalState;
        break;

      case BudgetProfile.BALANCED:
        resolvedP95 = Math.round(baseline.measuredP95Ms * 1.5);
        resolvedDrain =
          baseline.measuredDrainPerTenMin !== undefined
            ? baseline.measuredDrainPerTenMin * 1.0
            : undefined;
        resolvedThermal = 1;
        break;

      case BudgetProfile.PERFORMANCE:
        resolvedP95 = Math.round(baseline.measuredP95Ms * 1.1);
        resolvedDrain =
          baseline.measuredDrainPerTenMin !== undefined
            ? baseline.measuredDrainPerTenMin * 1.5
            : undefined;
        resolvedThermal = 3;
        break;
    }

    return {
      p95LatencyMs: resolvedP95,
      batteryDrainPerTenMinutes: resolvedDrain,
      maxThermalLevel: resolvedThermal,
      memoryCeilingMb: undefined, // Memory is always observe-only
    };
  }

  /**
   * Validate budget parameters for sanity.
   *
   * @returns list of warnings for unrealistic values; empty means all OK.
   */
  static validate(budget: EdgeVedaBudget): string[] {
    const warnings: string[] = [];

    if (
      budget.p95LatencyMs !== undefined &&
      budget.p95LatencyMs < 500
    ) {
      warnings.push(
        `p95LatencyMs=${budget.p95LatencyMs} is likely unrealistic for on-device LLM inference ` +
          '(typical: 1000-3000ms)'
      );
    }

    if (
      budget.batteryDrainPerTenMinutes !== undefined &&
      budget.batteryDrainPerTenMinutes < 0.5
    ) {
      warnings.push(
        `batteryDrainPerTenMinutes=${budget.batteryDrainPerTenMinutes} may be too restrictive for active inference`
      );
    }

    if (
      budget.memoryCeilingMb !== undefined &&
      budget.memoryCeilingMb < 2000
    ) {
      warnings.push(
        `memoryCeilingMb=${budget.memoryCeilingMb} may be too low for VLM workloads ` +
          '(typical RSS: 1500-2500MB including model + GPU buffers + image tensors). ' +
          'Consider setting to undefined to skip memory enforcement, or measure actual RSS ' +
          'after model load.'
      );
    }

    return warnings;
  }

  /**
   * Format a budget as a human-readable string.
   */
  static toString(budget: EdgeVedaBudget): string {
    if (budget.adaptiveProfile !== undefined) {
      return `EdgeVedaBudget.adaptive(${budget.adaptiveProfile})`;
    }
    return (
      `EdgeVedaBudget(p95LatencyMs=${budget.p95LatencyMs ?? 'undefined'}, ` +
      `batteryDrainPerTenMinutes=${budget.batteryDrainPerTenMinutes ?? 'undefined'}, ` +
      `maxThermalLevel=${budget.maxThermalLevel ?? 'undefined'}, ` +
      `memoryCeilingMb=${budget.memoryCeilingMb ?? 'undefined'})`
    );
  }

  /**
   * Format a MeasuredBaseline as a human-readable string.
   */
  static baselineToString(baseline: MeasuredBaseline): string {
    const drainStr =
      baseline.measuredDrainPerTenMin !== undefined
        ? baseline.measuredDrainPerTenMin.toFixed(1)
        : 'n/a';
    return (
      `MeasuredBaseline(p95=${baseline.measuredP95Ms.toFixed(0)}ms, ` +
      `drain=${drainStr}%/10min, thermal=${baseline.currentThermalState}, ` +
      `rss=${baseline.currentRssMb.toFixed(0)}MB, samples=${baseline.sampleCount})`
    );
  }

  /**
   * Format a BudgetViolation as a human-readable string.
   */
  static violationToString(violation: BudgetViolation): string {
    const observeStr = violation.observeOnly ? 'observeOnly=true, ' : '';
    return (
      `BudgetViolation(${violation.constraint}: current=${violation.currentValue}, ` +
      `budget=${violation.budgetValue}, ${observeStr}mitigated=${violation.mitigated}, ` +
      `mitigation=${violation.mitigation})`
    );
  }
}