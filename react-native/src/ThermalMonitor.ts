/**
 * Edge Veda SDK - ThermalMonitor
 * Monitors device thermal state for budget enforcement.
 *
 * In React Native, thermal state is obtained from the native side via
 * NativeEventEmitter events. The native iOS/Android layers push thermal
 * state changes which this monitor tracks.
 *
 * Thermal Levels:
 * - 0: Nominal (normal operation)
 * - 1: Fair / Light (slight thermal pressure)
 * - 2: Serious / Moderate (significant pressure, recommend throttling)
 * - 3: Critical / Severe (severe pressure, must throttle)
 * - -1: Unavailable (platform doesn't support thermal monitoring)
 */

/**
 * Monitors device thermal state with listener support.
 *
 * JavaScript is single-threaded in React Native, so no mutex is needed.
 * The API matches Swift/Kotlin for cross-platform consistency.
 */
export class ThermalMonitor {
  private _currentLevel: number = -1;
  private readonly stateChangeListeners = new Map<string, (level: number) => void>();
  private nextListenerId: number = 0;

  constructor() {
    // Initial level is -1 (unavailable) until native side reports
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

  /** Whether thermal monitoring is supported (set to true once native reports a level). */
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
  // Update (called by Scheduler or native event handler)
  // ---------------------------------------------------------------------------

  /**
   * Update the thermal level.
   *
   * Typically called by the native event handler when the OS reports
   * a thermal state change, or by the Scheduler during budget checks.
   *
   * @param level New thermal level (0-3, or -1 for unavailable).
   */
  updateLevel(level: number): void {
    const previous = this._currentLevel;
    this._currentLevel = level;

    if (previous !== level) {
      // Notify listeners
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