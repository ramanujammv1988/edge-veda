import { BatteryDrainTracker } from '../BatteryDrainTracker';

describe('BatteryDrainTracker', () => {
  let tracker: BatteryDrainTracker;
  let dateNowSpy: jest.SpyInstance;

  beforeEach(() => {
    dateNowSpy = jest.spyOn(Date, 'now');
    dateNowSpy.mockReturnValue(1000);
    tracker = new BatteryDrainTracker();
  });

  afterEach(() => {
    tracker.destroy();
    dateNowSpy.mockRestore();
  });

  // ---------------------------------------------------------------------------
  // Initial State
  // ---------------------------------------------------------------------------

  test('initial state has no samples and undefined rates', () => {
    expect(tracker.sampleCount).toBe(0);
    expect(tracker.currentDrainRate).toBeUndefined();
    expect(tracker.averageDrainRate).toBeUndefined();
    expect(tracker.currentBatteryLevel).toBeUndefined();
    expect(tracker.isSupported).toBe(false);
  });

  // ---------------------------------------------------------------------------
  // recordSample
  // ---------------------------------------------------------------------------

  test('recordSample stores level and marks supported', () => {
    tracker.recordSample(0.85);
    expect(tracker.sampleCount).toBe(1);
    expect(tracker.currentBatteryLevel).toBe(0.85);
    expect(tracker.isSupported).toBe(true);
  });

  test('recordSample rejects level < 0', () => {
    tracker.recordSample(-0.1);
    expect(tracker.sampleCount).toBe(0);
  });

  test('recordSample rejects level > 1', () => {
    tracker.recordSample(1.5);
    expect(tracker.sampleCount).toBe(0);
  });

  test('recordSample accepts boundary values 0 and 1', () => {
    tracker.recordSample(0);
    tracker.recordSample(1);
    expect(tracker.sampleCount).toBe(2);
  });

  // ---------------------------------------------------------------------------
  // Drain Rate Calculation
  // ---------------------------------------------------------------------------

  test('currentDrainRate needs at least 2 samples', () => {
    tracker.recordSample(0.9);
    expect(tracker.currentDrainRate).toBeUndefined();
  });

  test('currentDrainRate calculates correctly', () => {
    // Sample 1: level=0.9 at t=1000
    dateNowSpy.mockReturnValue(1000);
    tracker.recordSample(0.9);

    // Sample 2: level=0.8 at t=61000 (60s later)
    dateNowSpy.mockReturnValue(61000);
    tracker.recordSample(0.8);

    // Drain: (0.9 - 0.8) / 60000ms * 600000ms * 100 = 100%/10min
    const rate = tracker.currentDrainRate!;
    expect(rate).toBeCloseTo(100, 0);
  });

  test('currentDrainRate returns 0 for charging (negative drain)', () => {
    dateNowSpy.mockReturnValue(1000);
    tracker.recordSample(0.5);
    dateNowSpy.mockReturnValue(61000);
    tracker.recordSample(0.7); // level went up = charging
    expect(tracker.currentDrainRate).toBe(0);
  });

  // ---------------------------------------------------------------------------
  // Average Drain Rate
  // ---------------------------------------------------------------------------

  test('averageDrainRate falls back to currentDrainRate with < 3 samples', () => {
    dateNowSpy.mockReturnValue(1000);
    tracker.recordSample(0.9);
    dateNowSpy.mockReturnValue(61000);
    tracker.recordSample(0.8);
    expect(tracker.averageDrainRate).toBe(tracker.currentDrainRate);
  });

  test('averageDrainRate averages intervals with 3+ samples', () => {
    dateNowSpy.mockReturnValue(1000);
    tracker.recordSample(0.9);
    dateNowSpy.mockReturnValue(61000);
    tracker.recordSample(0.85);
    dateNowSpy.mockReturnValue(121000);
    tracker.recordSample(0.8);

    const rate = tracker.averageDrainRate!;
    expect(rate).toBeGreaterThan(0);
    expect(typeof rate).toBe('number');
  });

  // ---------------------------------------------------------------------------
  // Sliding Window
  // ---------------------------------------------------------------------------

  test('caps at MAX_SAMPLES (11)', () => {
    for (let i = 0; i < 15; i++) {
      dateNowSpy.mockReturnValue(1000 + i * 1000);
      tracker.recordSample(0.9 - i * 0.01);
    }
    expect(tracker.sampleCount).toBeLessThanOrEqual(11);
  });

  // ---------------------------------------------------------------------------
  // reset & destroy
  // ---------------------------------------------------------------------------

  test('reset clears samples but keeps isSupported', () => {
    tracker.recordSample(0.8);
    expect(tracker.isSupported).toBe(true);
    tracker.reset();
    expect(tracker.sampleCount).toBe(0);
    expect(tracker.currentBatteryLevel).toBeUndefined();
    // isSupported stays true after reset (only destroy clears it)
    expect(tracker.isSupported).toBe(true);
  });

  test('destroy clears everything including isSupported', () => {
    tracker.recordSample(0.8);
    tracker.destroy();
    expect(tracker.sampleCount).toBe(0);
    expect(tracker.isSupported).toBe(false);
  });
});