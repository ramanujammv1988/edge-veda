/**
 * Edge Veda Web SDK - RuntimePolicy
 * Adaptive runtime policy configuration and enforcement.
 *
 * RuntimePolicy defines how the SDK adapts behavior based on device state,
 * battery level, thermal conditions, and execution context.
 *
 * Browser-specific capability detection replaces native platform detection:
 * - WebGPU availability
 * - WASM threading (SharedArrayBuffer + cross-origin isolation)
 * - Web Worker support
 * - Battery Status API availability
 * - performance.memory availability (Chrome-only)
 *
 * JavaScript is single-threaded so no mutex is needed.
 *
 * @example
 * ```typescript
 * const enforcer = new RuntimePolicyEnforcer({
 *   policy: RuntimePolicyPresets.BALANCED,
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

  /** Optimize for background execution mode (e.g., hidden tab). */
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

/** Browser-specific runtime policy options. */
export interface RuntimePolicyOptions {
  /** Enable thermal state monitoring (manual updates only in browsers). */
  thermalStateMonitoring: boolean;

  /** Support background tab detection via Page Visibility API. */
  backgroundTaskSupport: boolean;

  /** Enable PerformanceObserver APIs for monitoring. */
  performanceObserver: boolean;

  /** Enable Web Worker pooling for parallel workloads. */
  workerPooling: boolean;
}

function defaultPolicyOptions(): RuntimePolicyOptions {
  return {
    thermalStateMonitoring: true,
    backgroundTaskSupport: true,
    performanceObserver: true,
    workerPooling: true,
  };
}

// =============================================================================
// RuntimeCapabilities
// =============================================================================

/** Runtime capabilities available in the current browser environment. */
export interface RuntimeCapabilities {
  /** Thermal monitoring is available (always false natively; true if manual updates received). */
  hasThermalMonitoring: boolean;

  /** Battery monitoring is available (Battery Status API). */
  hasBatteryMonitoring: boolean;

  /** Memory monitoring is available (Chrome performance.memory). */
  hasMemoryMonitoring: boolean;

  /** Background tab detection is available (Page Visibility API). */
  hasBackgroundTasks: boolean;

  /** WebGPU is available for GPU-accelerated inference. */
  hasWebGPU: boolean;

  /** WASM threading is available (SharedArrayBuffer + cross-origin isolation). */
  hasWasmThreads: boolean;

  /** Web Workers are available. */
  hasWebWorkers: boolean;

  /** Current platform name. */
  platform: string;

  /** Browser user agent string (truncated). */
  userAgent: string;

  /** Whether the page is cross-origin isolated (required for SharedArrayBuffer). */
  crossOriginIsolated: boolean;
}

/** Navigator with optional getBattery() method. */
interface NavigatorWithBattery extends Navigator {
  getBattery?: () => Promise<unknown>;
}

/** Extended Performance interface for Chrome's memory property. */
interface PerformanceWithMemory extends Performance {
  memory?: { usedJSHeapSize: number };
}

/** Detect runtime capabilities for the current browser environment. */
export function detectCapabilities(): RuntimeCapabilities {
  // Battery Status API (Chromium-only, deprecated)
  let hasBatteryMonitoring = false;
  try {
    const nav = navigator as NavigatorWithBattery;
    hasBatteryMonitoring = typeof nav.getBattery === 'function';
  } catch {
    // Not available
  }

  // Chrome performance.memory
  let hasMemoryMonitoring = false;
  try {
    const perf = performance as PerformanceWithMemory;
    hasMemoryMonitoring = perf.memory !== undefined && perf.memory !== null;
  } catch {
    // Not available
  }

  // Page Visibility API
  const hasBackgroundTasks = typeof document !== 'undefined' && 'visibilityState' in document;

  // WebGPU
  const hasWebGPU = typeof navigator !== 'undefined' && 'gpu' in navigator;

  // SharedArrayBuffer + cross-origin isolation (required for WASM threads)
  const crossOriginIsolated =
    typeof globalThis !== 'undefined' && (globalThis as { crossOriginIsolated?: boolean }).crossOriginIsolated === true;
  const hasSharedArrayBuffer = typeof SharedArrayBuffer !== 'undefined';
  const hasWasmThreads = hasSharedArrayBuffer && crossOriginIsolated;

  // Web Workers
  const hasWebWorkers = typeof Worker !== 'undefined';

  // User agent (truncated for readability)
  const ua = typeof navigator !== 'undefined' ? navigator.userAgent : 'unknown';
  const userAgent = ua.length > 120 ? ua.substring(0, 120) + '…' : ua;

  // Platform detection
  let platform = 'browser';
  if (ua.includes('Chrome')) platform = 'Chrome';
  else if (ua.includes('Firefox')) platform = 'Firefox';
  else if (ua.includes('Safari')) platform = 'Safari';
  else if (ua.includes('Edge')) platform = 'Edge';

  return {
    hasThermalMonitoring: false, // No native browser thermal API
    hasBatteryMonitoring,
    hasMemoryMonitoring,
    hasBackgroundTasks,
    hasWebGPU,
    hasWasmThreads,
    hasWebWorkers,
    platform,
    userAgent,
    crossOriginIsolated,
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
 * Browser-specific: also considers Page Visibility API for background
 * tab detection and adapts recommendations accordingly.
 *
 * No mutex needed — JavaScript is single-threaded.
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

  /** Get runtime capabilities for the current browser. */
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

    // Check background tab (Page Visibility API)
    if (policy.backgroundOptimization && this.isPageHidden()) {
      throttle = true;
      reasons.push('Tab is hidden (background)');
      factor *= 0.3;
    }

    return { shouldThrottle: throttle, throttleFactor: factor, reasons };
  }

  /**
   * Check if background optimizations should be applied.
   *
   * In the browser, uses the Page Visibility API to detect hidden tabs.
   */
  shouldOptimizeForBackground(): boolean {
    if (!this.currentPolicy.backgroundOptimization) return false;
    return this.isPageHidden();
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

  // -------------------------------------------------------------------------
  // Private
  // -------------------------------------------------------------------------

  /** Check if the page/tab is currently hidden. */
  private isPageHidden(): boolean {
    try {
      return typeof document !== 'undefined' && document.visibilityState === 'hidden';
    } catch {
      return false;
    }
  }
}