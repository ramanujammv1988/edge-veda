/**
 * Edge Veda Web SDK - BatteryDrainTracker
 * Tracks battery drain rate for budget enforcement.
 *
 * In the browser, battery information can be obtained through the Battery
 * Status API (`navigator.getBattery()`). This API is deprecated and only
 * available in some Chromium-based browsers — it is NOT supported in
 * Firefox or Safari. When unavailable, callers must feed battery levels
 * manually via `recordSample()`.
 *
 * Drain Rate Calculation:
 * - Samples battery level on demand (caller triggers via recordSample)
 * - Maintains sliding window of last 10 minutes
 * - Calculates rate: (initial% - current%) / elapsed × 600 seconds
 *
 * JavaScript is single-threaded so no synchronization is needed.
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
 * Browser BatteryManager interface (Battery Status API).
 * Only available in some Chromium-based browsers.
 */
interface BatteryManager {
  /** Battery level 0.0-1.0. */
  level: number;
  /** Whether the device is charging. */
  charging: boolean;
  /** Seconds until fully charged (Infinity if not charging). */
  chargingTime: number;
  /** Seconds until fully discharged (Infinity if charging). */
  dischargingTime: number;
  /** Event listener support. */
  addEventListener(type: string, listener: EventListener): void;
  removeEventListener(type: string, listener: EventListener): void;
}

/** Navigator with optional getBattery() method. */
interface NavigatorWithBattery extends Navigator {
  getBattery?: () => Promise<BatteryManager>;
}

/**
 * Tracks battery drain rate with sliding window statistics.
 *
 * The API matches Swift/Kotlin/React Native for cross-platform consistency.
 */
export class BatteryDrainTracker {
  private samples: BatterySample[] = [];
  private _isSupported: boolean = false;
  private _lastKnownLevel: number | null = null;
  private batteryManager: BatteryManager | null = null;
  private levelChangeHandler: EventListener | null = null;

  constructor() {
    // Attempt to use Battery Status API
    this.initBatteryAPI();
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

  /**
   * Whether battery monitoring is supported.
   *
   * Returns true if the Battery Status API is available or if at least
   * one manual sample has been recorded.
   */
  get isSupported(): boolean {
    return this._isSupported;
  }

  // ---------------------------------------------------------------------------
  // Public Methods
  // ---------------------------------------------------------------------------

  /**
   * Record a battery level sample.
   *
   * If the Battery Status API is available, samples are recorded
   * automatically on level change events. You can also call this
   * method manually to feed battery levels from an external source.
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

  /**
   * Attempt to read the current battery level from the Battery Status API
   * and record it as a sample.
   *
   * No-op if the API is not available.
   */
  async sampleFromAPI(): Promise<void> {
    if (this.batteryManager) {
      this.recordSample(this.batteryManager.level);
    }
  }

  /** Reset all collected samples. */
  reset(): void {
    this.samples = [];
    this._lastKnownLevel = null;
  }

  /** Stop tracking and release resources. */
  destroy(): void {
    if (this.batteryManager && this.levelChangeHandler) {
      this.batteryManager.removeEventListener('levelchange', this.levelChangeHandler);
      this.levelChangeHandler = null;
    }
    this.batteryManager = null;
    this.reset();
    this._isSupported = false;
  }

  // ---------------------------------------------------------------------------
  // Private - Battery Status API Initialization
  // ---------------------------------------------------------------------------

  private initBatteryAPI(): void {
    try {
      const nav = navigator as NavigatorWithBattery;
      if (typeof nav.getBattery === 'function') {
        nav
          .getBattery()
          .then((manager: BatteryManager) => {
            this.batteryManager = manager;
            this._isSupported = true;

            // Record initial level
            this.recordSample(manager.level);

            // Listen for level changes
            this.levelChangeHandler = () => {
              this.recordSample(manager.level);
            };
            manager.addEventListener('levelchange', this.levelChangeHandler);
          })
          .catch(() => {
            // Battery API not available or rejected
          });
      }
    } catch {
      // getBattery not available
    }
  }
}