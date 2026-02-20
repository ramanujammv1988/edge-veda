/**
 * Edge Veda SDK - RuntimePolicy
 * Adaptive runtime policy configuration and enforcement.
 *
 * RuntimePolicy defines how the SDK adapts behavior based on device state,
 * battery level, thermal conditions, and execution context.
 *
 * JavaScript is single-threaded in React Native, so no mutex is needed.
 * Platform detection uses react-native's Platform module.
 *
 * @example
 * ```typescript
 * const enforcer = new RuntimePolicyEnforcer({
 *   policy: RuntimePolicy.BALANCED,
 *   thermalMonitor,
 *   batteryTracker,
 *   resourceMonitor,
 * });
 * const rec = enforcer.shouldThrottle();
 * if (rec.shouldThrottle) {
 *   // Apply rec.throttleFactor to workload
 * }
 * ```
 */

import { Platform } from 'react-native';
import type { ThermalMonitor } from './ThermalMonitor';
import type { BatteryDrainTracker } from './BatteryDrainTracker';
import type { ResourceMonitor } from './ResourceMonitor';

// =============================================================================
// RuntimePolicy
// =============================================================================

/**
 * Runtime policy configuration for adaptive behavior.
 */
export interface RuntimePolicy {
  /** Reduce performance when device is on battery power. */
  throttleOnBattery: boolean;

  /** Automatically adjust memory usage based on available memory. */
  adaptiveMemory: boolean;

  /** Throttle workload based on thermal pressure. */
  thermalAware: boolean;

  /** Optimize for background execution mode. */
  backgroundOptimization: boolean;

  /** Platform-specific options. */
  options: RuntimePolicyOptions;
}

/** Static preset factory and helpers. */
export const RuntimePolicyPresets = {
  /** Conservative: Prioritize battery life and device health. */
  CONSERVATIVE: {
    throttleOnBattery: true,
    adaptiveMemory: true,
    thermalAware: true,
    backgroundOptimization: true,
    options: defaultPolicyOptions(),
  } as RuntimePolicy,

  /** Balanced: Balance performance and resource usage. */
  BALANCED: {
    throttleOnBattery: true,
    adaptiveMemory: true,
    thermalAware: true,
    backgroundOptimization: false,
    options: defaultPolicyOptions(),
  } as RuntimePolicy,

  /** Performance: Prioritize inference speed. */
  PERFORMANCE: {
    throttleOnBattery: false,
    adaptiveMemory: false,
    thermalAware: false,
    backgroundOptimization: false,
    options: defaultPolicyOptions(),
  } as RuntimePolicy,

  /** Default policy (same as balanced). */
  DEFAULT: {
    throttleOnBattery: true,
    adaptiveMemory: true,
    thermalAware: true,
    backgroundOptimization: false,
    options: defaultPolicyOptions(),
  } as RuntimePolicy,

  /** Format a policy as a human-readable string. */
  toString(policy: RuntimePolicy): string {
    return (
      `RuntimePolicy(throttleOnBattery=${policy.throttleOnBattery}, ` +
      `adaptiveMemory=${policy.adaptiveMemory}, ` +
      `thermalAware=${policy.thermalAware}, ` +
      `backgroundOptimization=${policy.backgroundOptimization})`
    );
  },
};

// =============================================================================
// RuntimePolicyOptions
// =============================================================================

/** Platform-specific runtime policy options. */
export interface RuntimePolicyOptions {
  /** Enable thermal state monitoring. */
  thermalStateMonitoring: boolean;

  /** Support background task execution. */
  backgroundTaskSupport: boolean;

  /** Enable performance observer APIs (Web only, no-op on RN). */
  performanceObserver: boolean;

  /** Enable worker pooling (Web only, no-op on RN). */
  workerPooling: boolean;
}

function defaultPolicyOptions(): RuntimePolicyOptions {
  return {
    thermalStateMonitoring: true,
    backgroundTaskSupport: false,
    performanceObserver: true,
    workerPooling: true,
  };
}

// =============================================================================
// RuntimeCapabilities
// =============================================================================

/** Runtime capabilities available on the current platform. */
export interface RuntimeCapabilities {
  /** Thermal monitoring is available. */
  hasThermalMonitoring: boolean;

  /** Battery monitoring is available. */
  hasBatteryMonitoring: boolean;

  /** Memory monitoring is available. */
  hasMemoryMonitoring: boolean;

  /** Background task support is available. */
  hasBackgroundTasks: boolean;

  /** Current platform name. */
  platform: string;

  /** Operating system version string. */
  osVersion: string;

  /** Device model identifier. */
  deviceModel: string;
}

/** Detect runtime capabilities for the current React Native platform. */
export function detectCapabilities(): RuntimeCapabilities {
  const os = Platform.OS; // 'ios' | 'android' | 'web' | ...
  const version = Platform.Version; // number (Android API) or string (iOS version)

  const isIOS = os === 'ios';
  const isAndroid = os === 'android';

  // Thermal monitoring: iOS always supports, Android API 29+
  const hasThermalMonitoring = isIOS || (isAndroid && typeof version === 'number' && version >= 29);

  // Battery monitoring available on both iOS and Android via native module
  const hasBatteryMonitoring = isIOS || isAndroid;

  // Memory monitoring: available via NativeEdgeVeda on both
  const hasMemoryMonitoring = isIOS || isAndroid;

  // Background tasks: both platforms support (iOS BGTaskScheduler, Android services)
  const hasBackgroundTasks = isIOS || isAndroid;

  const osVersion = isIOS
    ? `iOS ${version}`
    : isAndroid
      ? `Android API ${version}`
      : `${os} ${version}`;

  return {
    hasThermalMonitoring,
    hasBatteryMonitoring,
    hasMemoryMonitoring,
    hasBackgroundTasks,
    platform: isIOS ? 'iOS' : isAndroid ? 'Android' : os,
    osVersion,
    deviceModel: `${os}_device`, // Detailed model requires native module
  };
}

// =============================================================================
// ThrottleRecommendation
// =============================================================================

/** Throttle recommendation based on current device state. */
export interface ThrottleRecommendation {
  /** Whether workload should be throttled. */
  shouldThrottle: boolean;

  /** Suggested throttle factor (0.0-1.0, where 1.0 = no throttling). */
  throttleFactor: number;

  /** Human-readable reasons for throttling. */
  reasons: string[];
}

/** Format a ThrottleRecommendation as a string. */
export function throttleRecommendationToString(rec: ThrottleRecommendation): string {
  if (rec.shouldThrottle) {
    const pct = Math.round((1.0 - rec.throttleFactor) * 100);
    return `Throttle by ${pct}%: ${rec.reasons.join(', ')}`;
  }
  return 'No throttling needed';
}

// =============================================================================
// RuntimePolicyEnforcer
// =============================================================================

/** Options for creating a RuntimePolicyEnforcer. */
export interface RuntimePolicyEnforcerOptions {
  policy?: RuntimePolicy;
  thermalMonitor?: ThermalMonitor;
  batteryTracker?: BatteryDrainTracker;
  resourceMonitor?: ResourceMonitor;
}

/**
 * Policy enforcement engine that applies runtime policies.
 *
 * Evaluates current device state (thermal, battery, memory) against the
 * active RuntimePolicy and provides throttle recommendations.
 *
 * No mutex needed — JavaScript is single-threaded in React Native.
 */
export class RuntimePolicyEnforcer {
  private currentPolicy: RuntimePolicy;
  private readonly thermalMonitor?: ThermalMonitor;
  private readonly batteryTracker?: BatteryDrainTracker;
  private readonly resourceMonitor?: ResourceMonitor;

  constructor(options: RuntimePolicyEnforcerOptions = {}) {
    this.currentPolicy = options.policy ?? RuntimePolicyPresets.DEFAULT;
    this.thermalMonitor = options.thermalMonitor;
    this.batteryTracker = options.batteryTracker;
    this.resourceMonitor = options.resourceMonitor;
  }

  // -------------------------------------------------------------------------
  // Policy Management
  // -------------------------------------------------------------------------

  /** Set the runtime policy. */
  setPolicy(policy: RuntimePolicy): void {
    this.currentPolicy = policy;
  }

  /** Get the current runtime policy. */
  getPolicy(): RuntimePolicy {
    return this.currentPolicy;
  }

  /** Get runtime capabilities for the current platform. */
  getCapabilities(): RuntimeCapabilities {
    return detectCapabilities();
  }

  // -------------------------------------------------------------------------
  // Policy Enforcement
  // -------------------------------------------------------------------------

  /**
   * Check if workload should be throttled based on current policy and device state.
   */
  shouldThrottle(): ThrottleRecommendation {
    const policy = this.currentPolicy;
    const reasons: string[] = [];
    let throttle = false;
    let factor = 1.0;

    // Check thermal state
    if (policy.thermalAware && this.thermalMonitor) {
      const level = this.thermalMonitor.currentLevel;
      if (level >= 2) {
        throttle = true;
        reasons.push(`Thermal pressure (level ${level})`);
        factor *= 0.5;
      } else if (level === 1) {
        factor *= 0.8;
      }
    }

    // Check battery state
    if (policy.throttleOnBattery && this.batteryTracker) {
      const level = this.batteryTracker.currentBatteryLevel;
      if (level !== undefined) {
        if (level < 0.2) {
          throttle = true;
          reasons.push(`Low battery (${Math.round(level * 100)}%)`);
          factor *= 0.6;
        } else if (level < 0.5) {
          factor *= 0.9;
        }
      }
    }

    // Check memory pressure
    if (policy.adaptiveMemory && this.resourceMonitor) {
      const current = this.resourceMonitor.currentRssMb;
      const peak = this.resourceMonitor.peakRssMb;
      if (peak > 0 && current > peak * 0.9) {
        throttle = true;
        reasons.push(`High memory usage (${Math.round(current)}MB)`);
        factor *= 0.7;
      }
    }

    return { shouldThrottle: throttle, throttleFactor: factor, reasons };
  }

  /**
   * Check if background optimizations should be applied.
   *
   * In React Native, we cannot directly detect foreground/background state
   * from JS without AppState. Returns the policy flag directly.
   */
  shouldOptimizeForBackground(): boolean {
    return this.currentPolicy.backgroundOptimization;
  }

  /**
   * Get suggested workload priority adjustment based on current policy.
   *
   * @returns Multiplier for workload priority (0.0-2.0).
   */
  getPriorityMultiplier(): number {
    const rec = this.shouldThrottle();
    if (rec.shouldThrottle) {
      return rec.throttleFactor;
    }

    // Performance policy with no throttling → boost
    if (!this.currentPolicy.throttleOnBattery && !this.currentPolicy.thermalAware) {
      return 1.2;
    }

    return 1.0;
  }

  /** Clean up resources. */
  destroy(): void {
    // ThermalMonitor and BatteryDrainTracker are owned externally;
    // we don't destroy them here to avoid double-free patterns.
  }
}