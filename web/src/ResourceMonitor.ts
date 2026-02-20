/**
 * Edge Veda Web SDK - ResourceMonitor
 * Monitors JS heap memory usage for budget enforcement.
 *
 * In the browser, direct process memory (RSS) is not available. This monitor
 * uses the Chrome-only `performance.memory` API to read JS heap usage.
 * On browsers that don't expose this API, heap values default to 0.
 *
 * Tracks the page's memory footprint with a sliding window of samples,
 * providing current, peak, and average heap readings in megabytes.
 *
 * Note: `performance.memory` requires the `--enable-precise-memory-info` flag
 * in Chrome for precise readings. Without it, values are bucketed.
 */

/** Default maximum number of samples in the sliding window. */
const DEFAULT_MAX_SAMPLES = 100;

/** Bytes-to-megabytes divisor. */
const BYTES_PER_MB = 1024 * 1024;

/**
 * Extended Performance interface for Chrome's non-standard memory property.
 */
interface PerformanceWithMemory extends Performance {
  memory?: {
    /** Total JS heap size allocated by the browser. */
    totalJSHeapSize: number;
    /** Currently used JS heap size. */
    usedJSHeapSize: number;
    /** Maximum JS heap size available. */
    jsHeapSizeLimit: number;
  };
}

/**
 * Monitors JS heap memory with sliding window statistics.
 *
 * Single-threaded JS means no synchronization is needed — the API matches
 * Swift/Kotlin/React Native for cross-platform consistency.
 *
 * Property naming uses `currentRssMb` / `peakRssMb` for API parity with other
 * platforms, even though the browser measures JS heap rather than RSS.
 */
export class ResourceMonitor {
  private samples: number[] = [];
  private _peakRssMb: number = 0;
  private readonly maxSamples: number;

  constructor(maxSamples: number = DEFAULT_MAX_SAMPLES) {
    this.maxSamples = maxSamples;
  }

  /**
   * Current JS heap usage in megabytes (analogous to RSS on native platforms).
   *
   * Triggers a fresh memory sample before returning.
   * Returns 0 if the browser doesn't support `performance.memory`.
   */
  get currentRssMb(): number {
    this.updateMemoryUsage();
    return this.samples.length > 0
      ? this.samples[this.samples.length - 1]!
      : 0;
  }

  /** Peak heap usage observed since monitoring started. */
  get peakRssMb(): number {
    return this._peakRssMb;
  }

  /** Average heap usage over the sample window. */
  get averageRssMb(): number {
    if (this.samples.length === 0) return 0;
    const sum = this.samples.reduce((a, b) => a + b, 0);
    return sum / this.samples.length;
  }

  /** Number of samples collected. */
  get sampleCount(): number {
    return this.samples.length;
  }

  /**
   * Whether the browser supports heap memory monitoring.
   *
   * Currently only Chromium-based browsers expose `performance.memory`.
   */
  get isSupported(): boolean {
    return this.hasMemoryAPI();
  }

  /**
   * Get the JS heap size limit in megabytes, or 0 if unavailable.
   */
  get heapLimitMb(): number {
    const perf = performance as PerformanceWithMemory;
    if (perf.memory) {
      return perf.memory.jsHeapSizeLimit / BYTES_PER_MB;
    }
    return 0;
  }

  /**
   * Manually trigger a memory usage update.
   *
   * Memory is automatically sampled when accessing `currentRssMb`,
   * but this method allows explicit sampling for telemetry purposes.
   */
  sample(): void {
    this.updateMemoryUsage();
  }

  /** Reset all samples and peak tracking. */
  reset(): void {
    this.samples = [];
    this._peakRssMb = 0;
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  private updateMemoryUsage(): void {
    const heapMb = this.getHeapUsageMb();
    this.samples.push(heapMb);

    if (heapMb > this._peakRssMb) {
      this._peakRssMb = heapMb;
    }

    // Keep sliding window
    if (this.samples.length > this.maxSamples) {
      this.samples.shift();
    }
  }

  /**
   * Get the current JS heap usage in megabytes.
   *
   * Uses Chrome's `performance.memory.usedJSHeapSize`.
   * Returns 0 on browsers that don't support this API.
   */
  private getHeapUsageMb(): number {
    const perf = performance as PerformanceWithMemory;
    if (perf.memory) {
      return perf.memory.usedJSHeapSize / BYTES_PER_MB;
    }
    return 0;
  }

  /** Check if the `performance.memory` API is available. */
  private hasMemoryAPI(): boolean {
    try {
      const perf = performance as PerformanceWithMemory;
      return perf.memory !== undefined && perf.memory !== null;
    } catch {
      return false;
    }
  }
}