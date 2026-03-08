// Mock NativeEdgeVeda before importing ResourceMonitor
jest.mock('../NativeEdgeVeda', () => {
  let memoryJson = JSON.stringify({ usedMemory: 30 * 1024 * 1024, nativeHeap: 20 * 1024 * 1024 });
  return {
    __esModule: true,
    default: {
      getMemoryUsage: jest.fn(() => memoryJson),
    },
    _setMemory: (usedMemory: number, nativeHeap: number) => {
      memoryJson = JSON.stringify({ usedMemory, nativeHeap });
      const mod = require('../NativeEdgeVeda').default;
      mod.getMemoryUsage.mockReturnValue(memoryJson);
    },
  };
});

import { ResourceMonitor } from '../ResourceMonitor';
import NativeEdgeVeda from '../NativeEdgeVeda';

// Helper to change what the mock returns (usedMemory + nativeHeap in bytes)
function setNativeMemory(usedMemoryBytes: number, nativeHeapBytes: number) {
  const json = JSON.stringify({ usedMemory: usedMemoryBytes, nativeHeap: nativeHeapBytes });
  (NativeEdgeVeda.getMemoryUsage as jest.Mock).mockReturnValue(json);
}

describe('ResourceMonitor', () => {
  beforeEach(() => {
    // Default: 30 MB usedMemory + 20 MB nativeHeap = 50 MB total
    setNativeMemory(30 * 1024 * 1024, 20 * 1024 * 1024);
  });

  it('should start with zero samples', () => {
    const monitor = new ResourceMonitor();
    expect(monitor.sampleCount).toBe(0);
    expect(monitor.peakRssMb).toBe(0);
    expect(monitor.averageRssMb).toBe(0);
  });

  it('should read current RSS from native module', () => {
    const monitor = new ResourceMonitor();
    const rss = monitor.currentRssMb;
    // 30MB + 20MB = 50MB
    expect(rss).toBeCloseTo(50, 0);
    expect(monitor.sampleCount).toBe(1);
  });

  it('should track peak usage', () => {
    const monitor = new ResourceMonitor();

    setNativeMemory(20 * 1024 * 1024, 10 * 1024 * 1024); // 30 MB
    monitor.sample();

    setNativeMemory(60 * 1024 * 1024, 20 * 1024 * 1024); // 80 MB
    monitor.sample();

    setNativeMemory(25 * 1024 * 1024, 15 * 1024 * 1024); // 40 MB
    monitor.sample();

    expect(monitor.peakRssMb).toBeCloseTo(80, 0);
  });

  it('should compute average over samples', () => {
    const monitor = new ResourceMonitor();

    // 40, 60, 80 MB total
    setNativeMemory(20 * 1024 * 1024, 20 * 1024 * 1024); // 40
    monitor.sample();
    setNativeMemory(30 * 1024 * 1024, 30 * 1024 * 1024); // 60
    monitor.sample();
    setNativeMemory(40 * 1024 * 1024, 40 * 1024 * 1024); // 80
    monitor.sample();

    expect(monitor.averageRssMb).toBeCloseTo(60, 0);
    expect(monitor.sampleCount).toBe(3);
  });

  it('should respect sliding window maxSamples', () => {
    const monitor = new ResourceMonitor(3);

    for (let i = 0; i < 5; i++) {
      setNativeMemory((i + 1) * 10 * 1024 * 1024, 0);
      monitor.sample();
    }

    // Only last 3 samples kept: 30, 40, 50 MB
    expect(monitor.sampleCount).toBe(3);
  });

  it('should return 0 when native module throws', () => {
    (NativeEdgeVeda.getMemoryUsage as jest.Mock).mockImplementation(() => {
      throw new Error('Native module unavailable');
    });

    const monitor = new ResourceMonitor();
    const rss = monitor.currentRssMb;
    expect(rss).toBe(0);
    expect(monitor.sampleCount).toBe(1);
  });

  it('should return 0 when native module returns invalid JSON', () => {
    (NativeEdgeVeda.getMemoryUsage as jest.Mock).mockReturnValue('not json');

    const monitor = new ResourceMonitor();
    const rss = monitor.currentRssMb;
    expect(rss).toBe(0);
  });

  it('should handle missing fields in JSON gracefully', () => {
    (NativeEdgeVeda.getMemoryUsage as jest.Mock).mockReturnValue('{}');

    const monitor = new ResourceMonitor();
    const rss = monitor.currentRssMb;
    // (0 + 0) / (1024*1024) = 0
    expect(rss).toBe(0);
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