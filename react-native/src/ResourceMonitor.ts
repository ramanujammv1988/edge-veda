/**
 * Edge Veda SDK - ResourceMonitor
 * Monitors memory resource usage (RSS) for budget enforcement.
 *
 * In React Native, JavaScript cannot directly access process memory.
 * This monitor delegates to the native side via NativeEdgeVeda.getMemoryUsage()
 * when available, with a fallback of 0 when native data is unavailable.
 *
 * Tracks the app's memory footprint with a sliding window of samples,
 * providing current, peak, and average RSS readings.
 */

import NativeEdgeVeda from './NativeEdgeVeda';

/** Default maximum number of samples in the sliding window. */
const DEFAULT_MAX_SAMPLES = 100;

/**
 * Monitors memory RSS with sliding window statistics.
 *
 * JavaScript is single-threaded in React Native, so no mutex is needed.
 * The API matches Swift/Kotlin for cross-platform consistency.
 */
export class ResourceMonitor {
  private samples: number[] = [];
  private _peakRssMb: number = 0;
  private readonly maxSamples: number;

  constructor(maxSamples: number = DEFAULT_MAX_SAMPLES) {
    this.maxSamples = maxSamples;
  }

  /**
   * Current RSS (Resident Set Size) in megabytes.
   *
   * Triggers a fresh memory sample before returning.
   */
  get currentRssMb(): number {
    this.updateMemoryUsage();
    return this.samples.length > 0
      ? this.samples[this.samples.length - 1]!
      : 0;
  }

  /** Peak RSS observed since monitoring started. */
  get peakRssMb(): number {
    return this._peakRssMb;
  }

  /** Average RSS over the sample window. */
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
   * Manually trigger a memory usage update.
   *
   * Memory is automatically sampled when accessing currentRssMb,
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
    const rss = this.getResidentSetSize();
    this.samples.push(rss);

    if (rss > this._peakRssMb) {
      this._peakRssMb = rss;
    }

    // Keep sliding window
    if (this.samples.length > this.maxSamples) {
      this.samples.shift();
    }
  }

  /**
   * Get the current approximate RSS in megabytes.
   *
   * Attempts to read memory usage from the native module via
   * NativeEdgeVeda.getMemoryUsage(). Falls back to 0 if unavailable.
   */
  private getResidentSetSize(): number {
    try {
      const memoryJson = NativeEdgeVeda.getMemoryUsage();
      const memory = JSON.parse(memoryJson);
      // Native module returns memory in bytes; convert to MB
      const totalBytes =
        (memory.usedMemory ?? 0) + (memory.nativeHeap ?? 0);
      return totalBytes / (1024 * 1024);
    } catch {
      // Native module unavailable or returned invalid data
      return 0;
    }
  }
}