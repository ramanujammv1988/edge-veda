/**
 * Edge Veda Web SDK - ThermalMonitor
 * Monitors thermal state for budget enforcement.
 *
 * Browsers have NO native thermal API. This monitor relies entirely on
 * manual `updateLevel()` calls — typically fed by a server-side signal,
 * a companion native app, or a heuristic based on sustained high CPU usage.
 *
 * Thermal Levels:
 * - 0: Nominal (normal operation)
 * - 1: Fair / Light (slight thermal pressure)
 * - 2: Serious / Moderate (significant pressure, recommend throttling)
 * - 3: Critical / Severe (severe pressure, must throttle)
 * - -1: Unavailable (no thermal data received yet)
 */

/**
 * Monitors thermal state with listener support.
 *
 * JavaScript is single-threaded so no synchronization is needed.
 * The API matches Swift/Kotlin/React Native for cross-platform consistency.
 */
export class ThermalMonitor {
  private _currentLevel: number = -1;
  private readonly stateChangeListeners = new Map<string, (level: number) => void>();
  private nextListenerId: number = 0;

  constructor() {
    // Initial level is -1 (unavailable) until manually updated
  }

  // ---------------------------------------------------------------------------
  // Public Properties
  // ---------------------------------------------------------------------------

  /** Current thermal level (0-3, or -1 if unavailable). */
  get currentLevel(): number {
    return this._currentLevel;
  }

  /** Human-readable thermal state name. */
  get currentStateName(): string {
    return ThermalMonitor.thermalLevelName(this._currentLevel);
  }

  /**
   * Whether thermal monitoring is supported.
   * Returns true once at least one valid level (≥0) has been received.
   *
   * Note: browsers have no native thermal API — this will only become true
   * if `updateLevel()` is called with a non-negative value.
   */
  get isSupported(): boolean {
    return this._currentLevel >= 0;
  }

  /**
   * Check if current thermal state requires throttling.
   * Returns true if thermal level is 2 (serious) or higher.
   */
  get shouldThrottle(): boolean {
    return this._currentLevel >= 2;
  }

  /**
   * Check if current thermal state is critical.
   * Returns true if thermal level is 3 (critical).
   */
  get isCritical(): boolean {
    return this._currentLevel >= 3;
  }

  // ---------------------------------------------------------------------------
  // Update (called externally — no native browser thermal events)
  // ---------------------------------------------------------------------------

  /**
   * Update the thermal level.
   *
   * In the browser there is no native thermal state API. Call this method
   * from an external source such as:
   * - A server-sent event or WebSocket message with device telemetry
   * - A companion native app reporting via postMessage
   * - A heuristic based on sustained high CPU / frame drops
   *
   * @param level New thermal level (0-3, or -1 for unavailable).
   */
  updateLevel(level: number): void {
    const previous = this._currentLevel;
    this._currentLevel = level;

    if (previous !== level) {
      for (const callback of this.stateChangeListeners.values()) {
        try {
          callback(level);
        } catch {
          // Swallow listener errors to avoid disrupting the monitor
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Listener Management
  // ---------------------------------------------------------------------------

  /**
   * Register a callback for thermal state changes.
   *
   * @param callback Called when thermal state changes with the new level.
   * @returns Listener ID to use for removal via removeListener().
   */
  onThermalStateChange(callback: (level: number) => void): string {
    const id = `thermal_${this.nextListenerId++}`;
    this.stateChangeListeners.set(id, callback);
    return id;
  }

  /** Remove a thermal state change listener. */
  removeListener(id: string): void {
    this.stateChangeListeners.delete(id);
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  /** Remove all listeners and reset state. */
  destroy(): void {
    this.stateChangeListeners.clear();
    this._currentLevel = -1;
  }

  // ---------------------------------------------------------------------------
  // Static Helpers
  // ---------------------------------------------------------------------------

  /** Map a thermal level to a human-readable name. */
  static thermalLevelName(level: number): string {
    switch (level) {
      case 0:
        return 'nominal';
      case 1:
        return 'fair';
      case 2:
        return 'serious';
      case 3:
        return 'critical';
      default:
        return 'unavailable';
    }
  }
}