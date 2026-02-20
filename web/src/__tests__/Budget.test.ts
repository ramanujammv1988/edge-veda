import {
  Budget,
  BudgetProfile,
  BudgetConstraint,
  WorkloadPriority,
  WorkloadId,
  type EdgeVedaBudget,
  type MeasuredBaseline,
  type BudgetViolation,
} from '../Budget';

describe('Budget', () => {
  // ---------------------------------------------------------------------------
  // adaptive()
  // ---------------------------------------------------------------------------
  describe('adaptive()', () => {
    it('creates a budget with only the adaptiveProfile set', () => {
      const budget = Budget.adaptive(BudgetProfile.BALANCED);
      expect(budget.adaptiveProfile).toBe(BudgetProfile.BALANCED);
      expect(budget.p95LatencyMs).toBeUndefined();
      expect(budget.batteryDrainPerTenMinutes).toBeUndefined();
      expect(budget.maxThermalLevel).toBeUndefined();
      expect(budget.memoryCeilingMb).toBeUndefined();
    });

    it.each([
      BudgetProfile.CONSERVATIVE,
      BudgetProfile.BALANCED,
      BudgetProfile.PERFORMANCE,
    ])('works with profile %s', (profile) => {
      const budget = Budget.adaptive(profile);
      expect(budget.adaptiveProfile).toBe(profile);
    });
  });

  // ---------------------------------------------------------------------------
  // resolve()
  // ---------------------------------------------------------------------------
  describe('resolve()', () => {
    const baseline: MeasuredBaseline = {
      measuredP95Ms: 1000,
      measuredDrainPerTenMin: 2.0,
      currentThermalState: 0,
      currentRssMb: 500,
      sampleCount: 50,
      measuredAt: new Date(),
    };

    it('resolves CONSERVATIVE profile correctly', () => {
      const resolved = Budget.resolve(BudgetProfile.CONSERVATIVE, baseline);
      expect(resolved.p95LatencyMs).toBe(2000); // 1000 * 2.0
      expect(resolved.batteryDrainPerTenMinutes).toBeCloseTo(1.2); // 2.0 * 0.6
      expect(resolved.maxThermalLevel).toBe(1); // max(1, currentThermalState=0)
      expect(resolved.memoryCeilingMb).toBeUndefined();
    });

    it('resolves BALANCED profile correctly', () => {
      const resolved = Budget.resolve(BudgetProfile.BALANCED, baseline);
      expect(resolved.p95LatencyMs).toBe(1500); // 1000 * 1.5
      expect(resolved.batteryDrainPerTenMinutes).toBeCloseTo(2.0); // 2.0 * 1.0
      expect(resolved.maxThermalLevel).toBe(1);
      expect(resolved.memoryCeilingMb).toBeUndefined();
    });

    it('resolves PERFORMANCE profile correctly', () => {
      const resolved = Budget.resolve(BudgetProfile.PERFORMANCE, baseline);
      expect(resolved.p95LatencyMs).toBe(1100); // 1000 * 1.1
      expect(resolved.batteryDrainPerTenMinutes).toBeCloseTo(3.0); // 2.0 * 1.5
      expect(resolved.maxThermalLevel).toBe(3);
      expect(resolved.memoryCeilingMb).toBeUndefined();
    });

    it('handles undefined battery drain in baseline', () => {
      const noBattery: MeasuredBaseline = {
        ...baseline,
        measuredDrainPerTenMin: undefined,
      };
      const resolved = Budget.resolve(BudgetProfile.BALANCED, noBattery);
      expect(resolved.batteryDrainPerTenMinutes).toBeUndefined();
    });

    it('CONSERVATIVE uses currentThermalState when >= 1', () => {
      const warmBaseline: MeasuredBaseline = {
        ...baseline,
        currentThermalState: 2,
      };
      const resolved = Budget.resolve(BudgetProfile.CONSERVATIVE, warmBaseline);
      expect(resolved.maxThermalLevel).toBe(2);
    });
  });

  // ---------------------------------------------------------------------------
  // validate()
  // ---------------------------------------------------------------------------
  describe('validate()', () => {
    it('returns empty array for reasonable budget', () => {
      const budget: EdgeVedaBudget = {
        p95LatencyMs: 2000,
        batteryDrainPerTenMinutes: 2.0,
        memoryCeilingMb: 1000,
      };
      expect(Budget.validate(budget)).toHaveLength(0);
    });

    it('warns on unrealistically low p95LatencyMs', () => {
      const budget: EdgeVedaBudget = { p95LatencyMs: 100 };
      const warnings = Budget.validate(budget);
      expect(warnings.length).toBeGreaterThan(0);
      expect(warnings[0]).toContain('p95LatencyMs');
    });

    it('warns on unrealistically low batteryDrainPerTenMinutes', () => {
      const budget: EdgeVedaBudget = { batteryDrainPerTenMinutes: 0.1 };
      const warnings = Budget.validate(budget);
      expect(warnings.length).toBeGreaterThan(0);
      expect(warnings[0]).toContain('batteryDrainPerTenMinutes');
    });

    it('warns on unrealistically low memoryCeilingMb', () => {
      const budget: EdgeVedaBudget = { memoryCeilingMb: 100 };
      const warnings = Budget.validate(budget);
      expect(warnings.length).toBeGreaterThan(0);
      expect(warnings[0]).toContain('memoryCeilingMb');
    });

    it('returns no warnings for undefined fields', () => {
      const budget: EdgeVedaBudget = {};
      expect(Budget.validate(budget)).toHaveLength(0);
    });
  });

  // ---------------------------------------------------------------------------
  // toString helpers
  // ---------------------------------------------------------------------------
  describe('toString()', () => {
    it('formats adaptive budget', () => {
      const budget = Budget.adaptive(BudgetProfile.BALANCED);
      expect(Budget.toString(budget)).toContain('adaptive');
      expect(Budget.toString(budget)).toContain('balanced');
    });

    it('formats explicit budget', () => {
      const budget: EdgeVedaBudget = { p95LatencyMs: 2000, memoryCeilingMb: 1000 };
      const str = Budget.toString(budget);
      expect(str).toContain('2000');
      expect(str).toContain('1000');
    });
  });

  describe('baselineToString()', () => {
    it('formats a baseline', () => {
      const baseline: MeasuredBaseline = {
        measuredP95Ms: 1500,
        measuredDrainPerTenMin: 1.5,
        currentThermalState: 1,
        currentRssMb: 750,
        sampleCount: 100,
        measuredAt: new Date(),
      };
      const str = Budget.baselineToString(baseline);
      expect(str).toContain('1500');
      expect(str).toContain('1.5');
      expect(str).toContain('samples=100');
    });
  });

  describe('violationToString()', () => {
    it('formats a violation', () => {
      const violation: BudgetViolation = {
        constraint: BudgetConstraint.P95_LATENCY,
        currentValue: 3000,
        budgetValue: 2000,
        mitigation: 'reduce batch size',
        timestamp: new Date(),
        mitigated: false,
        observeOnly: false,
      };
      const str = Budget.violationToString(violation);
      expect(str).toContain('p95_latency');
      expect(str).toContain('3000');
      expect(str).toContain('2000');
    });

    it('includes observeOnly flag when true', () => {
      const violation: BudgetViolation = {
        constraint: BudgetConstraint.MEMORY_CEILING,
        currentValue: 1200,
        budgetValue: 1000,
        mitigation: 'none',
        timestamp: new Date(),
        mitigated: false,
        observeOnly: true,
      };
      const str = Budget.violationToString(violation);
      expect(str).toContain('observeOnly=true');
    });
  });

  // ---------------------------------------------------------------------------
  // Enum values
  // ---------------------------------------------------------------------------
  describe('enums', () => {
    it('BudgetProfile has correct values', () => {
      expect(BudgetProfile.CONSERVATIVE).toBe('conservative');
      expect(BudgetProfile.BALANCED).toBe('balanced');
      expect(BudgetProfile.PERFORMANCE).toBe('performance');
    });

    it('BudgetConstraint has correct values', () => {
      expect(BudgetConstraint.P95_LATENCY).toBe('p95_latency');
      expect(BudgetConstraint.BATTERY_DRAIN).toBe('battery_drain');
      expect(BudgetConstraint.THERMAL_LEVEL).toBe('thermal_level');
      expect(BudgetConstraint.MEMORY_CEILING).toBe('memory_ceiling');
    });

    it('WorkloadPriority has correct values', () => {
      expect(WorkloadPriority.LOW).toBe('low');
      expect(WorkloadPriority.HIGH).toBe('high');
    });

    it('WorkloadId has correct values', () => {
      expect(WorkloadId.VISION).toBe('vision');
      expect(WorkloadId.TEXT).toBe('text');
    });
  });
});