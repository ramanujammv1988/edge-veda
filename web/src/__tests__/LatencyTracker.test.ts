import { LatencyTracker } from '../LatencyTracker';

describe('LatencyTracker', () => {
  let tracker: LatencyTracker;

  beforeEach(() => {
    tracker = new LatencyTracker();
  });

  describe('initial state', () => {
    it('starts with zero samples', () => {
      expect(tracker.sampleCount).toBe(0);
    });

    it('returns 0 for all stats when empty', () => {
      expect(tracker.p50).toBe(0);
      expect(tracker.p95).toBe(0);
      expect(tracker.p99).toBe(0);
      expect(tracker.average).toBe(0);
      expect(tracker.min).toBe(0);
      expect(tracker.max).toBe(0);
    });
  });

  describe('record()', () => {
    it('increments sample count', () => {
      tracker.record(100);
      expect(tracker.sampleCount).toBe(1);
      tracker.record(200);
      expect(tracker.sampleCount).toBe(2);
    });

    it('tracks min and max', () => {
      tracker.record(100);
      tracker.record(50);
      tracker.record(200);
      expect(tracker.min).toBe(50);
      expect(tracker.max).toBe(200);
    });

    it('computes correct average', () => {
      tracker.record(100);
      tracker.record(200);
      tracker.record(300);
      expect(tracker.average).toBeCloseTo(200);
    });
  });

  describe('percentiles', () => {
    it('computes p50 correctly', () => {
      for (let i = 1; i <= 100; i++) {
        tracker.record(i);
      }
      expect(tracker.p50).toBeGreaterThanOrEqual(49);
      expect(tracker.p50).toBeLessThanOrEqual(51);
    });

    it('computes p95 correctly', () => {
      for (let i = 1; i <= 100; i++) {
        tracker.record(i);
      }
      expect(tracker.p95).toBeGreaterThanOrEqual(94);
      expect(tracker.p95).toBeLessThanOrEqual(96);
    });

    it('computes p99 correctly', () => {
      for (let i = 1; i <= 100; i++) {
        tracker.record(i);
      }
      expect(tracker.p99).toBeGreaterThanOrEqual(98);
      expect(tracker.p99).toBeLessThanOrEqual(100);
    });

    it('single sample returns that value for all percentiles', () => {
      tracker.record(42);
      expect(tracker.p50).toBe(42);
      expect(tracker.p95).toBe(42);
      expect(tracker.p99).toBe(42);
    });
  });

  describe('sliding window', () => {
    it('respects window size', () => {
      const small = new LatencyTracker(5);
      for (let i = 0; i < 10; i++) {
        small.record(i * 100);
      }
      expect(small.sampleCount).toBe(5);
      // Window should contain last 5 values: 500,600,700,800,900
      expect(small.min).toBe(500);
      expect(small.max).toBe(900);
    });
  });

  describe('reset()', () => {
    it('clears all data', () => {
      tracker.record(100);
      tracker.record(200);
      tracker.reset();
      expect(tracker.sampleCount).toBe(0);
      expect(tracker.p50).toBe(0);
      expect(tracker.average).toBe(0);
    });
  });
});