import { ThermalMonitor } from '../ThermalMonitor';

describe('ThermalMonitor', () => {
  it('should start with level -1 (unavailable)', () => {
    const monitor = new ThermalMonitor();
    expect(monitor.currentLevel).toBe(-1);
    expect(monitor.currentStateName).toBe('unavailable');
    expect(monitor.isSupported).toBe(false);
    expect(monitor.shouldThrottle).toBe(false);
    expect(monitor.isCritical).toBe(false);
  });

  it('should update level and become supported', () => {
    const monitor = new ThermalMonitor();
    monitor.updateLevel(0);
    expect(monitor.currentLevel).toBe(0);
    expect(monitor.currentStateName).toBe('nominal');
    expect(monitor.isSupported).toBe(true);
  });

  it('should report shouldThrottle at level 2+', () => {
    const monitor = new ThermalMonitor();
    monitor.updateLevel(1);
    expect(monitor.shouldThrottle).toBe(false);
    monitor.updateLevel(2);
    expect(monitor.shouldThrottle).toBe(true);
    monitor.updateLevel(3);
    expect(monitor.shouldThrottle).toBe(true);
  });

  it('should report isCritical at level 3+', () => {
    const monitor = new ThermalMonitor();
    monitor.updateLevel(2);
    expect(monitor.isCritical).toBe(false);
    monitor.updateLevel(3);
    expect(monitor.isCritical).toBe(true);
  });

  it('should notify listeners on state change', () => {
    const monitor = new ThermalMonitor();
    const levels: number[] = [];
    monitor.onThermalStateChange((level) => levels.push(level));

    monitor.updateLevel(0);
    monitor.updateLevel(1);
    monitor.updateLevel(2);

    expect(levels).toEqual([0, 1, 2]);
  });

  it('should not notify when level unchanged', () => {
    const monitor = new ThermalMonitor();
    const levels: number[] = [];
    monitor.onThermalStateChange((level) => levels.push(level));

    monitor.updateLevel(1);
    monitor.updateLevel(1); // same level
    monitor.updateLevel(2);

    expect(levels).toEqual([1, 2]);
  });

  it('should remove listener by id', () => {
    const monitor = new ThermalMonitor();
    const levels: number[] = [];
    const id = monitor.onThermalStateChange((level) => levels.push(level));

    monitor.updateLevel(1);
    monitor.removeListener(id);
    monitor.updateLevel(2);

    expect(levels).toEqual([1]);
  });

  it('should swallow listener errors', () => {
    const monitor = new ThermalMonitor();
    monitor.onThermalStateChange(() => {
      throw new Error('boom');
    });

    // Should not throw
    expect(() => monitor.updateLevel(1)).not.toThrow();
  });

  it('should reset on destroy', () => {
    const monitor = new ThermalMonitor();
    monitor.updateLevel(2);
    const levels: number[] = [];
    monitor.onThermalStateChange((level) => levels.push(level));

    monitor.destroy();
    expect(monitor.currentLevel).toBe(-1);

    // Listeners cleared — no notification
    monitor.updateLevel(1);
    expect(levels).toEqual([]);
  });

  it('should map thermal level names correctly', () => {
    expect(ThermalMonitor.thermalLevelName(0)).toBe('nominal');
    expect(ThermalMonitor.thermalLevelName(1)).toBe('fair');
    expect(ThermalMonitor.thermalLevelName(2)).toBe('serious');
    expect(ThermalMonitor.thermalLevelName(3)).toBe('critical');
    expect(ThermalMonitor.thermalLevelName(-1)).toBe('unavailable');
    expect(ThermalMonitor.thermalLevelName(99)).toBe('unavailable');
  });
});