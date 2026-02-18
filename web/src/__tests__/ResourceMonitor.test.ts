import { ResourceMonitor } from '../ResourceMonitor';

// Mock performance.memory (Chrome-only API)
const mockMemory = {
  usedJSHeapSize: 50 * 1024 * 1024, // 50 MB
  totalJSHeapSize: 100 * 1024 * 1024,
  jsHeapSizeLimit: 2048 * 1024 * 1024, // 2 GB
};

beforeEach(() => {
  (performance as any).memory = { ...mockMemory };
});

afterEach(() => {
  delete (performance as any).memory;
});

describe('ResourceMonitor', () => {
  it('should start with zero samples', () => {
    const monitor = new ResourceMonitor();
    expect(monitor.sampleCount).toBe(0);
    expect(monitor.peakRssMb).toBe(0);
    expect(monitor.averageRssMb).toBe(0);
  });

  it('should read current heap as currentRssMb', () => {
    const monitor = new ResourceMonitor();
    const rss = monitor.currentRssMb;
    expect(rss).toBeCloseTo(50, 0);
    expect(monitor.sampleCount).toBe(1);
  });

  it('should track peak usage', () => {
    const monitor = new ResourceMonitor();

    (performance as any).memory.usedJSHeapSize = 30 * 1024 * 1024;
    monitor.sample();

    (performance as any).memory.usedJSHeapSize = 80 * 1024 * 1024;
    monitor.sample();

    (performance as any).memory.usedJSHeapSize = 40 * 1024 * 1024;
    monitor.sample();

    expect(monitor.peakRssMb).toBeCloseTo(80, 0);
  });

  it('should compute average over samples', () => {
    const monitor = new ResourceMonitor();

    // Record 40, 60, 80 MB
    (performance as any).memory.usedJSHeapSize = 40 * 1024 * 1024;
    monitor.sample();
    (performance as any).memory.usedJSHeapSize = 60 * 1024 * 1024;
    monitor.sample();
    (performance as any).memory.usedJSHeapSize = 80 * 1024 * 1024;
    monitor.sample();

    expect(monitor.averageRssMb).toBeCloseTo(60, 0);
    expect(monitor.sampleCount).toBe(3);
  });

  it('should respect sliding window maxSamples', () => {
    const monitor = new ResourceMonitor(3);

    for (let i = 0; i < 5; i++) {
      (performance as any).memory.usedJSHeapSize = (i + 1) * 10 * 1024 * 1024;
      monitor.sample();
    }

    // Only last 3 samples kept: 30, 40, 50 MB
    expect(monitor.sampleCount).toBe(3);
  });

  it('should report isSupported when performance.memory exists', () => {
    const monitor = new ResourceMonitor();
    expect(monitor.isSupported).toBe(true);
  });

  it('should report isSupported=false when no performance.memory', () => {
    delete (performance as any).memory;
    const monitor = new ResourceMonitor();
    expect(monitor.isSupported).toBe(false);
  });

  it('should report heapLimitMb', () => {
    const monitor = new ResourceMonitor();
    expect(monitor.heapLimitMb).toBeCloseTo(2048, 0);
  });

  it('should return 0 heapLimitMb when API unavailable', () => {
    delete (performance as any).memory;
    const monitor = new ResourceMonitor();
    expect(monitor.heapLimitMb).toBe(0);
  });

  it('should return 0 currentRssMb when API unavailable', () => {
    delete (performance as any).memory;
    const monitor = new ResourceMonitor();
    expect(monitor.currentRssMb).toBe(0);
  });

  it('should reset all state', () => {
    const monitor = new ResourceMonitor();
    monitor.sample();
    monitor.sample();
    expect(monitor.sampleCount).toBe(2);

    monitor.reset();
    expect(monitor.sampleCount).toBe(0);
    expect(monitor.peakRssMb).toBe(0);
    expect(monitor.averageRssMb).toBe(0);
  });
});