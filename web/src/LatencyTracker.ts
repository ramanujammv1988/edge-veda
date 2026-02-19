/**
 * Edge Veda Web SDK - LatencyTracker
 * Sliding window latency tracker for browser-based inference timing.
 *
 * Records latency samples and provides percentile statistics (p50, p95, p99).
 * Uses a sliding window of the most recent samples for accurate tracking.
 *
 * In the browser, JavaScript is single-threaded so no mutex is needed.
 * Uses performance.now() for high-resolution timing when available.
 */

/** Default maximum number of samples in the sliding window. */
const DEFAULT_WINDOW_SIZE = 100;

/**
 * Tracks inference latency with sliding window percentile statistics.
 *
 * Single-threaded JS means no synchronization is needed — the API matches
 * Swift/Kotlin/React Native for cross-platform consistency.
 */
export class LatencyTracker {
  private samples: number[] = [];
  private sortedCache: number[] = [];
  private dirty = false;
  private readonly windowSize: number;

  /**
   * @param windowSize Maximum number of samples to retain (default 100).
   */
  constructor(windowSize: number = DEFAULT_WINDOW_SIZE) {
    this.windowSize = windowSize;
  }

  /**
   * Record a latency sample in milliseconds.
   */
  record(latencyMs: number): void {
    this.samples.push(latencyMs);
    if (this.samples.length > this.windowSize) {
      this.samples.shift();
    }
    this.dirty = true;
  }

  /**
   * Get the p50 (median) latency in milliseconds.
   * Returns 0 if no samples have been recorded.
   */
  get p50(): number {
    return this.percentile(0.5);
  }

  /**
   * Get the p95 latency in milliseconds.
   * Returns 0 if no samples have been recorded.
   */
  get p95(): number {
    return this.percentile(0.95);
  }

  /**
   * Get the p99 latency in milliseconds.
   * Returns 0 if no samples have been recorded.
   */
  get p99(): number {
    return this.percentile(0.99);
  }

  /**
   * Get the average latency in milliseconds.
   * Returns 0 if no samples have been recorded.
   */
  get average(): number {
    if (this.samples.length === 0) return 0;
    const sum = this.samples.reduce((a, b) => a + b, 0);
    return sum / this.samples.length;
  }

  /**
   * Get the minimum latency in milliseconds.
   * Returns 0 if no samples have been recorded.
   */
  get min(): number {
    if (this.samples.length === 0) return 0;
    return Math.min(...this.samples);
  }

  /**
   * Get the maximum latency in milliseconds.
   * Returns 0 if no samples have been recorded.
   */
  get max(): number {
    if (this.samples.length === 0) return 0;
    return Math.max(...this.samples);
  }

  /**
   * Get the number of samples currently in the window.
   */
  get sampleCount(): number {
    return this.samples.length;
  }

  /**
   * Reset all recorded samples.
   */
  reset(): void {
    this.samples = [];
    this.sortedCache = [];
    this.dirty = false;
  }

  /**
   * Compute a specific percentile from the current samples.
   *
   * @param p Percentile value between 0.0 and 1.0.
   * @returns The latency at the given percentile, or 0 if no samples.
   */
  private percentile(p: number): number {
    if (this.samples.length === 0) return 0;

    if (this.dirty) {
      this.sortedCache = [...this.samples].sort((a, b) => a - b);
      this.dirty = false;
    }
    const index = Math.ceil(p * this.sortedCache.length) - 1;
    return this.sortedCache[Math.max(0, index)]!;
  }
}