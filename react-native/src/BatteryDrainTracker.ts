/**
 * Edge Veda SDK - BatteryDrainTracker
 * Tracks battery drain rate for budget enforcement.
 *
 * In React Native, battery level is obtained from the native side.
 * This tracker monitors battery level changes over time to calculate
 * drain rate as percentage per 10 minutes.
 *
 * Drain Rate Calculation:
 * - Samples battery level on demand (caller triggers via recordSample)
 * - Maintains sliding window of last 10 minutes
 * - Calculates rate: (initial% - current%) / elapsed × 600 seconds
 *
 * JavaScript is single-threaded so no mutex is needed.
 */

/** Individual battery level sample with timestamp. */
interface BatterySample {
  /** Battery level 0.0-1.0. */
  level: number;
  /** Timestamp in milliseconds (Date.now()). */
  timestamp: number;
}

/** Window duration: 10 minutes in milliseconds. */
const WINDOW_DURATION_MS = 600_000;

/** Maximum samples retained (~10 min at 1-min intervals). */
const MAX_SAMPLES = 11;

/**
 * Tracks battery drain rate with sliding window statistics.
 *
 * The API matches Swift/Kotlin for cross-platform consistency.
 */
export class BatteryDrainTracker {
  private samples: BatterySample[] = [];
  private _isSupported: boolean = false;
  private _lastKnownLevel: number | null = null;

  constructor() {
    // Battery level will be fed from native side
  }

  // ---------------------------------------------------------------------------
  // Public Properties
  // ---------------------------------------------------------------------------

  /**
   * Current battery drain rate in percentage per 10 minutes.
   *
   * Returns undefined if not enough samples collected (need at least 2).
   */
  get currentDrainRate(): number | undefined {
    if (this.samples.length < 2) return undefined;

    const first = this.samples[0]!;
    const last = this.samples[this.samples.length - 1]!;

    const timeDiffMs = last.timestamp - first.timestamp;
    if (timeDiffMs <= 0) return undefined;

    // Level difference (positive = draining)
    const levelDiff = first.level - last.level;

    // Drain per millisecond → scale to 10 minutes (600,000ms) → percentage
    const drainPerMs = levelDiff / timeDiffMs;
    const drainPerTenMinutes = drainPerMs * 600_000 * 100;

    return drainPerTenMinutes >= 0 ? drainPerTenMinutes : 0;
  }

  /**
   * Average battery drain rate over available sample intervals.
   *
   * Calculates drain rate for each consecutive pair of samples,
   * then averages the non-negative rates.
   */
  get averageDrainRate(): number | undefined {
    if (this.samples.length < 3) {
      return this.currentDrainRate; // Fall back to simple calculation
    }

    const rates: number[] = [];
    for (let i = 0; i < this.samples.length - 1; i++) {
      const first = this.samples[i]!;
      const second = this.samples[i + 1]!;

      const timeDiffMs = second.timestamp - first.timestamp;
      if (timeDiffMs <= 0) continue;

      const levelDiff = first.level - second.level;
      const drainPerMs = levelDiff / timeDiffMs;
      const drainPerTenMinutes = drainPerMs * 600_000 * 100;

      if (drainPerTenMinutes >= 0) {
        rates.push(drainPerTenMinutes);
      }
    }

    if (rates.length === 0) return undefined;
    return rates.reduce((a, b) => a + b, 0) / rates.length;
  }

  /**
   * Current battery level (0.0-1.0), or undefined if unavailable.
   */
  get currentBatteryLevel(): number | undefined {
    return this._lastKnownLevel ?? undefined;
  }

  /** Number of samples collected. */
  get sampleCount(): number {
    return this.samples.length;
  }

  /** Whether battery monitoring is supported. */
  get isSupported(): boolean {
    return this._isSupported;
  }

  // ---------------------------------------------------------------------------
  // Public Methods
  // ---------------------------------------------------------------------------

  /**
   * Record a battery level sample.
   *
   * In React Native, the caller (typically the Scheduler or a native event
   * handler) provides the battery level obtained from the native side.
   *
   * @param level Battery level 0.0-1.0.
   */
  recordSample(level: number): void {
    if (level < 0 || level > 1) return;

    this._isSupported = true;
    this._lastKnownLevel = level;

    const sample: BatterySample = {
      level,
      timestamp: Date.now(),
    };

    this.samples.push(sample);

    // Trim to sliding window (10 minutes)
    const cutoff = Date.now() - WINDOW_DURATION_MS;
    while (this.samples.length > 0 && this.samples[0]!.timestamp < cutoff) {
      this.samples.shift();
    }

    // Also cap at MAX_SAMPLES
    while (this.samples.length > MAX_SAMPLES) {
      this.samples.shift();
    }
  }

  /** Reset all collected samples. */
  reset(): void {
    this.samples = [];
    this._lastKnownLevel = null;
  }

  /** Stop tracking and release resources. */
  destroy(): void {
    this.reset();
    this._isSupported = false;
  }
}