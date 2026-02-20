import {
  Telemetry,
  BudgetViolationType,
  ViolationSeverity,
  latencyStatsToString,
} from '../Telemetry';

// Reset singleton between tests
beforeEach(() => {
  (Telemetry as any)._instance = null;
  jest.spyOn(console, 'info').mockImplementation(() => {});
  jest.spyOn(console, 'debug').mockImplementation(() => {});
  jest.spyOn(console, 'warn').mockImplementation(() => {});
  jest.spyOn(console, 'error').mockImplementation(() => {});
  jest.spyOn(console, 'log').mockImplementation(() => {});
});

afterEach(() => {
  jest.restoreAllMocks();
});

describe('Telemetry singleton', () => {
  it('returns the same instance', () => {
    const a = Telemetry.instance;
    const b = Telemetry.instance;
    expect(a).toBe(b);
  });
});

describe('Telemetry inference logging', () => {
  it('logInferenceStart stores a metric with startTime', () => {
    const t = Telemetry.instance;
    t.logInferenceStart('r1', 'model-a');
    const m = t.getLatencyMetric('r1');
    expect(m).toBeDefined();
    expect(m!.requestId).toBe('r1');
    expect(m!.modelName).toBe('model-a');
    expect(m!.startTime).toBeGreaterThan(0);
  });

  it('logInferenceComplete records endTime and latencyMs', () => {
    const t = Telemetry.instance;
    t.logInferenceStart('r2');
    t.logInferenceComplete('r2', 10);
    const m = t.getLatencyMetric('r2');
    expect(m!.endTime).toBeGreaterThan(0);
    expect(m!.latencyMs).toBeDefined();
    expect(m!.latencyMs).toBeGreaterThanOrEqual(0);
  });

  it('recordLatency overrides latencyMs on existing metric', () => {
    const t = Telemetry.instance;
    t.logInferenceStart('r3');
    t.recordLatency('r3', 99.9);
    expect(t.getLatencyMetric('r3')!.latencyMs).toBe(99.9);
  });

  it('logInferenceError does not throw', () => {
    const t = Telemetry.instance;
    expect(() => t.logInferenceError('r4', 'boom')).not.toThrow();
  });
});

describe('Telemetry budget logging', () => {
  it('logBudgetViolation stores a violation record', () => {
    const t = Telemetry.instance;
    t.logBudgetViolation(BudgetViolationType.LATENCY, 50, 40, ViolationSeverity.WARNING);
    const violations = t.getBudgetViolations();
    expect(violations.length).toBe(1);
    expect(violations[0]!.type).toBe(BudgetViolationType.LATENCY);
    expect(violations[0]!.current).toBe(50);
    expect(violations[0]!.limit).toBe(40);
    expect(violations[0]!.severity).toBe(ViolationSeverity.WARNING);
    expect(violations[0]!.timestamp).toBeGreaterThan(0);
    expect(violations[0]!.wallTime).toBeInstanceOf(Date);
  });

  it('severity INFO logs via console.info', () => {
    const t = Telemetry.instance;
    t.logBudgetViolation(BudgetViolationType.MEMORY, 1, 2, ViolationSeverity.INFO);
    expect(console.info).toHaveBeenCalled();
  });

  it('severity CRITICAL logs via console.error', () => {
    const t = Telemetry.instance;
    t.logBudgetViolation(BudgetViolationType.THERMAL, 3, 2, ViolationSeverity.CRITICAL);
    expect(console.error).toHaveBeenCalled();
  });

  it('logBudgetEnforcement and logBaselineUpdate do not throw', () => {
    const t = Telemetry.instance;
    expect(() => t.logBudgetEnforcement('pause', 'thermal')).not.toThrow();
    expect(() => t.logBaselineUpdate(100, 200, 300, 20)).not.toThrow();
  });
});

describe('Telemetry resource logging', () => {
  it('logResourceUsage stores a snapshot', () => {
    const t = Telemetry.instance;
    t.logResourceUsage(512, 0.8, 1);
    const snaps = t.getResourceSnapshots();
    expect(snaps.length).toBe(1);
    expect(snaps[0]!.memoryMb).toBe(512);
    expect(snaps[0]!.batteryLevel).toBe(0.8);
    expect(snaps[0]!.thermalLevel).toBe(1);
  });

  it('logMemoryPressure, logThermalStateChange, logBatteryDrain do not throw', () => {
    const t = Telemetry.instance;
    expect(() => t.logMemoryPressure(100, 200)).not.toThrow();
    expect(() => t.logMemoryPressure(100, 200, 300)).not.toThrow();
    expect(() => t.logThermalStateChange(0, 2)).not.toThrow();
    expect(() => t.logBatteryDrain(1.5, 0.6)).not.toThrow();
  });
});

describe('Telemetry scheduler & policy logging', () => {
  it('scheduler log methods do not throw', () => {
    const t = Telemetry.instance;
    expect(() => t.logTaskScheduled('t1', 'HIGH')).not.toThrow();
    expect(() => t.logTaskStarted('t1')).not.toThrow();
    expect(() => t.logTaskCompleted('t1', 42)).not.toThrow();
    expect(() => t.logTaskCancelled('t2', 'timeout')).not.toThrow();
    expect(() => t.logQueueStatus(1, 2, 'HIGH')).not.toThrow();
  });

  it('policy log methods do not throw', () => {
    const t = Telemetry.instance;
    expect(() => t.logPolicyChange('balanced', 'conservative')).not.toThrow();
    expect(() => t.logThrottleDecision(true, 0.5, ['thermal'])).not.toThrow();
    expect(() => t.logThrottleDecision(false, 1.0, [])).not.toThrow();
    expect(() => t.logPolicyEnforcement('pause', 'thermal')).not.toThrow();
  });
});

describe('Telemetry metrics retrieval', () => {
  it('getLatencyMetrics returns all stored metrics', () => {
    const t = Telemetry.instance;
    t.logInferenceStart('a');
    t.logInferenceStart('b');
    expect(t.getLatencyMetrics().length).toBe(2);
  });

  it('getRecentViolations returns last N', () => {
    const t = Telemetry.instance;
    for (let i = 0; i < 5; i++) {
      t.logBudgetViolation(BudgetViolationType.LATENCY, i, 10);
    }
    const recent = t.getRecentViolations(2);
    expect(recent.length).toBe(2);
    expect(recent[0]!.current).toBe(3);
    expect(recent[1]!.current).toBe(4);
  });

  it('getRecentSnapshots returns last N', () => {
    const t = Telemetry.instance;
    for (let i = 0; i < 5; i++) {
      t.logResourceUsage(i * 100);
    }
    const recent = t.getRecentSnapshots(3);
    expect(recent.length).toBe(3);
    expect(recent[0]!.memoryMb).toBe(200);
  });

  it('getLatencyStats returns undefined when no completed metrics', () => {
    const t = Telemetry.instance;
    expect(t.getLatencyStats()).toBeUndefined();
  });

  it('getLatencyStats computes correct stats', () => {
    const t = Telemetry.instance;
    const values = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100];
    for (let i = 0; i < values.length; i++) {
      t.logInferenceStart(`s${i}`);
      t.recordLatency(`s${i}`, values[i]!);
    }
    const stats = t.getLatencyStats()!;
    expect(stats.count).toBe(10);
    expect(stats.min).toBe(10);
    expect(stats.max).toBe(100);
    expect(stats.mean).toBe(55);
  });
});

describe('Telemetry cleanup', () => {
  it('clearMetrics empties all stores', () => {
    const t = Telemetry.instance;
    t.logInferenceStart('x');
    t.logBudgetViolation(BudgetViolationType.MEMORY, 1, 2);
    t.logResourceUsage(100);
    t.clearMetrics();
    expect(t.getLatencyMetrics().length).toBe(0);
    expect(t.getBudgetViolations().length).toBe(0);
    expect(t.getResourceSnapshots().length).toBe(0);
  });

  it('clearOldMetrics removes metrics older than cutoff', () => {
    const t = Telemetry.instance;
    // Record something now
    t.logInferenceStart('keep');
    t.logBudgetViolation(BudgetViolationType.LATENCY, 1, 2);
    t.logResourceUsage(100);
    // Nothing is old enough to remove
    t.clearOldMetrics(60000);
    expect(t.getLatencyMetrics().length).toBe(1);
    expect(t.getBudgetViolations().length).toBe(1);
    expect(t.getResourceSnapshots().length).toBe(1);
  });
});

describe('Telemetry configuration (max stored)', () => {
  it('setMaxStoredMetrics trims excess', () => {
    const t = Telemetry.instance;
    for (let i = 0; i < 10; i++) {
      t.logInferenceStart(`m${i}`);
    }
    t.setMaxStoredMetrics(3);
    expect(t.getLatencyMetrics().length).toBe(3);
  });

  it('setMaxStoredViolations trims excess', () => {
    const t = Telemetry.instance;
    for (let i = 0; i < 10; i++) {
      t.logBudgetViolation(BudgetViolationType.LATENCY, i, 100);
    }
    t.setMaxStoredViolations(5);
    expect(t.getBudgetViolations().length).toBe(5);
  });

  it('setMaxStoredSnapshots trims excess', () => {
    const t = Telemetry.instance;
    for (let i = 0; i < 10; i++) {
      t.logResourceUsage(i * 10);
    }
    t.setMaxStoredSnapshots(4);
    expect(t.getResourceSnapshots().length).toBe(4);
  });
});

describe('latencyStatsToString', () => {
  it('formats stats correctly', () => {
    const str = latencyStatsToString({
      count: 10,
      min: 1.1,
      max: 99.9,
      mean: 50.5,
      p50: 50,
      p95: 95,
      p99: 99,
    });
    expect(str).toContain('count=10');
    expect(str).toContain('min=1.10ms');
    expect(str).toContain('max=99.90ms');
  });
});

describe('BudgetViolationType and ViolationSeverity enums', () => {
  it('has expected values', () => {
    expect(BudgetViolationType.LATENCY).toBe('latency');
    expect(BudgetViolationType.MEMORY).toBe('memory');
    expect(BudgetViolationType.BATTERY).toBe('battery');
    expect(BudgetViolationType.THERMAL).toBe('thermal');
    expect(ViolationSeverity.INFO).toBe('info');
    expect(ViolationSeverity.WARNING).toBe('warning');
    expect(ViolationSeverity.CRITICAL).toBe('critical');
  });
});