import {
  Budget,
  BudgetProfile,
  BudgetConstraint,
  WorkloadPriority,
  WorkloadId,
  type EdgeVedaBudget,
  type MeasuredBaseline,
} from '../Budget';

describe('Budget.adaptive', () => {
  it('creates adaptive budget with profile', () => {
    const b = Budget.adaptive(BudgetProfile.BALANCED);
    expect(b.adaptiveProfile).toBe(BudgetProfile.BALANCED);
    expect(b.p95LatencyMs).toBeUndefined();
  });
});

describe('Budget.resolve', () => {
  const baseline: MeasuredBaseline = {
    measuredP95Ms: 1000,
    measuredDrainPerTenMin: 2.0,
    currentThermalState: 0,
    currentRssMb: 500,
    sampleCount: 25,
    measuredAt: new Date(),
  };

  it('CONSERVATIVE: p95×2.0, drain×0.6, thermal≥1', () => {
    const b = Budget.resolve(BudgetProfile.CONSERVATIVE, baseline);
    expect(b.p95LatencyMs).toBe(2000);
    expect(b.batteryDrainPerTenMinutes).toBeCloseTo(1.2);
    expect(b.maxThermalLevel).toBe(1);
  });

  it('BALANCED: p95×1.5, drain×1.0, thermal=1', () => {
    const b = Budget.resolve(BudgetProfile.BALANCED, baseline);
    expect(b.p95LatencyMs).toBe(1500);
    expect(b.batteryDrainPerTenMinutes).toBeCloseTo(2.0);
    expect(b.maxThermalLevel).toBe(1);
  });

  it('PERFORMANCE: p95×1.1, drain×1.5, thermal=3', () => {
    const b = Budget.resolve(BudgetProfile.PERFORMANCE, baseline);
    expect(b.p95LatencyMs).toBe(1100);
    expect(b.batteryDrainPerTenMinutes).toBeCloseTo(3.0);
    expect(b.maxThermalLevel).toBe(3);
  });

  it('handles undefined drain', () => {
    const noDrain = { ...baseline, measuredDrainPerTenMin: undefined };
    const b = Budget.resolve(BudgetProfile.BALANCED, noDrain);
    expect(b.batteryDrainPerTenMinutes).toBeUndefined();
  });
});

describe('Budget.validate', () => {
  it('returns empty array for reasonable budget', () => {
    const b: EdgeVedaBudget = { p95LatencyMs: 2000, memoryCeilingMb: 2500 };
    expect(Budget.validate(b)).toEqual([]);
  });

  it('warns on low p95', () => {
    const w = Budget.validate({ p95LatencyMs: 100 });
    expect(w.length).toBeGreaterThan(0);
    expect(w[0]).toContain('unrealistic');
  });

  it('warns on low battery drain', () => {
    const w = Budget.validate({ batteryDrainPerTenMinutes: 0.1 });
    expect(w.length).toBeGreaterThan(0);
  });

  it('warns on low memory ceiling', () => {
    const w = Budget.validate({ memoryCeilingMb: 500 });
    expect(w.length).toBeGreaterThan(0);
  });
});

describe('Budget.toString / baselineToString / violationToString', () => {
  it('toString adaptive', () => {
    const s = Budget.toString(Budget.adaptive(BudgetProfile.BALANCED));
    expect(s).toContain('adaptive');
    expect(s).toContain('balanced');
  });

  it('toString explicit', () => {
    const s = Budget.toString({ p95LatencyMs: 2000 });
    expect(s).toContain('2000');
  });

  it('baselineToString', () => {
    const s = Budget.baselineToString({
      measuredP95Ms: 1000,
      measuredDrainPerTenMin: 2.5,
      currentThermalState: 1,
      currentRssMb: 800,
      sampleCount: 30,
      measuredAt: new Date(),
    });
    expect(s).toContain('p95=1000ms');
    expect(s).toContain('samples=30');
  });

  it('violationToString', () => {
    const s = Budget.violationToString({
      constraint: BudgetConstraint.P95_LATENCY,
      currentValue: 3000,
      budgetValue: 2000,
      mitigation: 'reduce frequency',
      timestamp: new Date(),
      mitigated: false,
      observeOnly: false,
    });
    expect(s).toContain('p95_latency');
    expect(s).toContain('3000');
  });
});

describe('Enums', () => {
  it('BudgetProfile values', () => {
    expect(BudgetProfile.CONSERVATIVE).toBe('conservative');
    expect(BudgetProfile.BALANCED).toBe('balanced');
    expect(BudgetProfile.PERFORMANCE).toBe('performance');
  });

  it('BudgetConstraint values', () => {
    expect(BudgetConstraint.P95_LATENCY).toBe('p95_latency');
    expect(BudgetConstraint.BATTERY_DRAIN).toBe('battery_drain');
    expect(BudgetConstraint.THERMAL_LEVEL).toBe('thermal_level');
    expect(BudgetConstraint.MEMORY_CEILING).toBe('memory_ceiling');
  });

  it('WorkloadPriority values', () => {
    expect(WorkloadPriority.LOW).toBe('low');
    expect(WorkloadPriority.HIGH).toBe('high');
  });

  it('WorkloadId values', () => {
    expect(WorkloadId.VISION).toBe('vision');
    expect(WorkloadId.TEXT).toBe('text');
  });
});