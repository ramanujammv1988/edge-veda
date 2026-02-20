/**
 * Edge Veda React Native SDK — Runtime Supervision (Phase 4) Example
 *
 * Demonstrates the declarative budget system, adaptive profiles, runtime
 * policies, scheduler priority queues, latency tracking, resource monitoring,
 * thermal monitoring, battery drain tracking, and telemetry — all adapted
 * for React Native.
 *
 * Usage:
 * ```typescript
 * import { runRuntimeSupervisionExample } from './RuntimeSupervisionExample';
 * runRuntimeSupervisionExample();
 * ```
 */

import {
  Budget,
  BudgetProfile,
  BudgetConstraint,
  WorkloadPriority,
  WorkloadId,
  LatencyTracker,
  ResourceMonitor,
  ThermalMonitor,
  BatteryDrainTracker,
  Scheduler,
  TaskPriority,
  RuntimePolicyEnforcer,
  RuntimePolicyPresets,
  Telemetry,
  BudgetViolationType,
  ViolationSeverity,
  detectCapabilities,
  throttleRecommendationToString,
  latencyStatsToString,
} from '../src/index';

import type {
  EdgeVedaBudget,
  MeasuredBaseline,
  BudgetViolation,
  RuntimePolicy,
} from '../src/index';

export async function runRuntimeSupervisionExample(): Promise<void> {
  console.log('EdgeVeda React Native SDK — Runtime Supervision (Phase 4)');
  console.log('==========================================================\n');

  // ─────────────────────────────────────────────────────
  // 1. Declarative Compute Budgets
  // ─────────────────────────────────────────────────────
  console.log('1. Declarative Compute Budgets');
  console.log('───────────────────────────────');

  // Explicit budget with hard limits
  const explicitBudget: EdgeVedaBudget = {
    p95LatencyMs: 2000,
    batteryDrainPerTenMinutes: 3.0,
    maxThermalLevel: 2,
    memoryCeilingMb: 800,
  };
  console.log('Explicit budget: ', Budget.toString(explicitBudget));

  // Validate — will warn about memory ceiling
  const warnings = Budget.validate(explicitBudget);
  if (warnings.length > 0) {
    console.log('Warnings:');
    for (const w of warnings) console.log(`  ⚠️  ${w}`);
  }
  console.log();

  // ─────────────────────────────────────────────────────
  // 2. Adaptive Budget Profiles
  // ─────────────────────────────────────────────────────
  console.log('2. Adaptive Budget Profiles');
  console.log('───────────────────────────');

  const profiles = [BudgetProfile.CONSERVATIVE, BudgetProfile.BALANCED, BudgetProfile.PERFORMANCE];
  for (const profile of profiles) {
    const budget = Budget.adaptive(profile);
    console.log(`  .${profile}  →  ${Budget.toString(budget)}`);
  }
  console.log();

  // Resolve a profile against a simulated baseline
  const baseline: MeasuredBaseline = {
    measuredP95Ms: 1500,
    measuredDrainPerTenMin: 2.0,
    currentThermalState: 0,
    currentRssMb: 1800,
    sampleCount: 25,
    measuredAt: new Date(),
  };
  console.log('Measured baseline: ', Budget.baselineToString(baseline));

  for (const profile of profiles) {
    const resolved = Budget.resolve(profile, baseline);
    console.log(`  .${profile} resolved →  ${Budget.toString(resolved)}`);
  }
  console.log();

  // ─────────────────────────────────────────────────────
  // 3. Budget Violations
  // ─────────────────────────────────────────────────────
  console.log('3. Budget Violation Events');
  console.log('──────────────────────────');

  const violation: BudgetViolation = {
    constraint: BudgetConstraint.P95_LATENCY,
    currentValue: 2500,
    budgetValue: 2000,
    mitigation: 'Reduced vision FPS 30→15',
    timestamp: new Date(),
    mitigated: true,
    observeOnly: false,
  };
  console.log(`  ${Budget.violationToString(violation)}`);

  const memViolation: BudgetViolation = {
    constraint: BudgetConstraint.MEMORY_CEILING,
    currentValue: 2100,
    budgetValue: 800,
    mitigation: 'Observe-only: QoS cannot reduce model heap',
    timestamp: new Date(),
    mitigated: false,
    observeOnly: true,
  };
  console.log(`  ${Budget.violationToString(memViolation)}`);
  console.log();

  // ─────────────────────────────────────────────────────
  // 4. Runtime Policy
  // ─────────────────────────────────────────────────────
  console.log('4. Runtime Policy');
  console.log('─────────────────');

  const capabilities = detectCapabilities();
  console.log('  Capabilities:', capabilities);

  const presetPolicies: { label: string; policy: RuntimePolicy }[] = [
    { label: 'CONSERVATIVE', policy: RuntimePolicyPresets.CONSERVATIVE },
    { label: 'BALANCED', policy: RuntimePolicyPresets.BALANCED },
    { label: 'PERFORMANCE', policy: RuntimePolicyPresets.PERFORMANCE },
  ];
  for (const { label, policy } of presetPolicies) {
    console.log(`  ${label}: ${RuntimePolicyPresets.toString(policy)}`);
  }

  // Custom policy
  const customPolicy: RuntimePolicy = {
    throttleOnBattery: true,
    adaptiveMemory: true,
    thermalAware: false,
    backgroundOptimization: true,
    options: {
      thermalStateMonitoring: false,
      backgroundTaskSupport: true,
      performanceObserver: false, // Not applicable in RN
      workerPooling: false,       // Not applicable in RN
    },
  };
  console.log(`  Custom: ${RuntimePolicyPresets.toString(customPolicy)}`);
  console.log();

  // RuntimePolicyEnforcer
  const thermalMonitor = new ThermalMonitor();
  const batteryTracker = new BatteryDrainTracker();
  const resourceMonitor = new ResourceMonitor();

  const enforcer = new RuntimePolicyEnforcer({
    policy: RuntimePolicyPresets.BALANCED,
    thermalMonitor,
    batteryTracker,
    resourceMonitor,
  });

  const throttle = enforcer.shouldThrottle();
  console.log(`  Throttle recommendation: ${throttleRecommendationToString(throttle)}`);
  console.log(`  Priority multiplier: ${enforcer.getPriorityMultiplier()}`);
  console.log();

  // ─────────────────────────────────────────────────────
  // 5. Latency Tracker
  // ─────────────────────────────────────────────────────
  console.log('5. Latency Tracker');
  console.log('──────────────────');

  const latencyTracker = new LatencyTracker();

  // Simulate 30 inference latency samples
  for (let i = 0; i < 30; i++) {
    latencyTracker.record(800 + Math.random() * 1400);
  }

  const count = latencyTracker.sampleCount;
  const p50 = latencyTracker.p50;
  const p95 = latencyTracker.p95;
  const p99 = latencyTracker.p99;
  const avg = latencyTracker.average;

  console.log(`  Samples: ${count}`);
  console.log(
    `  p50=${p50 !== undefined ? Math.round(p50) : 'n/a'}ms  ` +
      `p95=${p95 !== undefined ? Math.round(p95) : 'n/a'}ms  ` +
      `p99=${p99 !== undefined ? Math.round(p99) : 'n/a'}ms`
  );
  console.log(`  average=${avg !== undefined ? Math.round(avg) : 'n/a'}ms`);
  console.log();

  // ─────────────────────────────────────────────────────
  // 6. Resource Monitor
  // ─────────────────────────────────────────────────────
  console.log('6. Resource Monitor (Native Memory)');
  console.log('────────────────────────────────────');

  for (let i = 0; i < 5; i++) {
    resourceMonitor.sample();
  }

  const currentRss = resourceMonitor.currentRssMb;
  const peakRss = resourceMonitor.peakRssMb;
  const avgRss = resourceMonitor.averageRssMb;
  const rssSamples = resourceMonitor.sampleCount;

  console.log(`  Current RSS: ${currentRss.toFixed(1)} MB`);
  console.log(`  Peak RSS:    ${peakRss.toFixed(1)} MB`);
  console.log(`  Average RSS: ${avgRss.toFixed(1)} MB`);
  console.log(`  Samples:     ${rssSamples}`);
  console.log();

  // ─────────────────────────────────────────────────────
  // 7. Thermal Monitor
  // ─────────────────────────────────────────────────────
  console.log('7. Thermal Monitor');
  console.log('──────────────────');

  const thermalLevel = thermalMonitor.currentLevel;
  const thermalName = thermalMonitor.currentStateName;
  const shouldThrottleThermal = thermalMonitor.shouldThrottle;
  const isCritical = thermalMonitor.isCritical;

  console.log(`  Supported:       ${thermalMonitor.isSupported}`);
  console.log(`  Level:           ${thermalLevel} (${thermalName})`);
  console.log(`  Should throttle: ${shouldThrottleThermal}`);
  console.log(`  Is critical:     ${isCritical}`);

  // Register a thermal listener
  const listenerId = thermalMonitor.onThermalStateChange((level: number) => {
    console.log(`  🌡️  Thermal state changed → level ${level}`);
  });
  console.log(`  Listener registered: ${listenerId.substring(0, 8)}…`);
  thermalMonitor.removeListener(listenerId);

  // Manual thermal level update (simulating native event)
  thermalMonitor.updateLevel(1);
  console.log(`  After updateLevel(1): ${thermalMonitor.currentLevel} (${thermalMonitor.currentStateName})`);
  thermalMonitor.updateLevel(0); // reset
  console.log();

  // ─────────────────────────────────────────────────────
  // 8. Battery Drain Tracker
  // ─────────────────────────────────────────────────────
  console.log('8. Battery Drain Tracker');
  console.log('────────────────────────');

  const batterySupported = batteryTracker.isSupported;
  console.log(`  Supported: ${batterySupported}`);

  // In React Native, battery level comes from native events.
  // Simulate with manual samples.
  batteryTracker.recordSample(0.85);
  await new Promise((r) => setTimeout(r, 100));
  batteryTracker.recordSample(0.84);

  const batteryLevel = batteryTracker.currentBatteryLevel;
  if (batteryLevel !== undefined) {
    console.log(`  Battery level: ${Math.round(batteryLevel * 100)}%`);
  }

  const drainRate = batteryTracker.currentDrainRate;
  if (drainRate !== undefined) {
    console.log(`  Drain rate: ${drainRate.toFixed(2)}% / 10 min`);
  } else {
    console.log('  Drain rate: accumulating samples…');
  }

  const avgDrain = batteryTracker.averageDrainRate;
  if (avgDrain !== undefined) {
    console.log(`  Average drain: ${avgDrain.toFixed(2)}% / 10 min`);
  }
  console.log();

  // ─────────────────────────────────────────────────────
  // 9. Scheduler (priority queue)
  // ─────────────────────────────────────────────────────
  console.log('9. Scheduler — Priority Task Queue');
  console.log('───────────────────────────────────');

  const scheduler = new Scheduler(
    latencyTracker,
    batteryTracker,
    thermalMonitor,
    resourceMonitor
  );

  // Set a compute budget
  scheduler.setComputeBudget(Budget.adaptive(BudgetProfile.BALANCED));
  console.log(`  Budget set: ${Budget.toString(scheduler.getComputeBudget()!)}`);

  // Schedule tasks at different priorities
  const highResult = await scheduler.scheduleTask<string>(
    TaskPriority.HIGH,
    WorkloadId.TEXT,
    async () => {
      await new Promise((r) => setTimeout(r, 10));
      return 'high-priority result';
    }
  );

  const normalResult = await scheduler.scheduleTask<string>(
    TaskPriority.NORMAL,
    WorkloadId.TEXT,
    async () => 'normal-priority result'
  );

  const lowResult = await scheduler.scheduleTask<string>(
    TaskPriority.LOW,
    WorkloadId.VISION,
    async () => 'low-priority result'
  );

  console.log(`  HIGH   → ${highResult}`);
  console.log(`  NORMAL → ${normalResult}`);
  console.log(`  LOW    → ${lowResult}`);

  const queueStatus = scheduler.getQueueStatus();
  console.log(`  Queue status:`, queueStatus);

  // Register workloads
  scheduler.registerWorkload(WorkloadId.VISION, WorkloadPriority.LOW);
  scheduler.registerWorkload(WorkloadId.TEXT, WorkloadPriority.HIGH);

  // Listen for budget violations
  const violationListenerId = scheduler.onBudgetViolation((v: BudgetViolation) => {
    console.log(
      `  ⚠️  Budget violation: ${v.constraint} ` +
        `(current=${v.currentValue}, budget=${v.budgetValue})`
    );
  });
  console.log(`  Violation listener: ${violationListenerId.substring(0, 8)}…`);
  scheduler.removeViolationListener(violationListenerId);

  // Measured baseline (from scheduler's internal trackers)
  const measuredBaseline = scheduler.getMeasuredBaseline();
  if (measuredBaseline) {
    console.log(`  Measured baseline: ${Budget.baselineToString(measuredBaseline)}`);
  }
  console.log();

  // ─────────────────────────────────────────────────────
  // 10. Telemetry
  // ─────────────────────────────────────────────────────
  console.log('10. Telemetry — Structured Logging & Metrics');
  console.log('─────────────────────────────────────────────');

  const telemetry = Telemetry.instance;

  telemetry.logInferenceStart('req-001', 'gemma-2b');
  telemetry.logInferenceComplete('req-001', 42);
  telemetry.recordLatency('req-001', p95 ?? 1500);
  telemetry.logResourceUsage(
    currentRss,
    batteryTracker.currentBatteryLevel,
    thermalLevel
  );
  telemetry.logBudgetViolation(
    BudgetViolationType.LATENCY,
    2500,
    2000,
    ViolationSeverity.WARNING
  );

  const latencyMetrics = telemetry.getLatencyMetrics();
  console.log(`  Latency metrics: ${latencyMetrics.length} entries`);

  const latencyStats = telemetry.getLatencyStats();
  if (latencyStats) {
    console.log(`  Stats: ${latencyStatsToString(latencyStats)}`);
  }

  const recentViolations = telemetry.getRecentViolations(5);
  console.log(`  Recent violations: ${recentViolations.length}`);

  const snapshots = telemetry.getRecentSnapshots(5);
  console.log(`  Recent snapshots: ${snapshots.length}`);

  telemetry.clearMetrics();
  console.log('  Metrics cleared.');
  console.log();

  // Clean up
  thermalMonitor.destroy();
  batteryTracker.destroy();
  enforcer.destroy();

  // ─────────────────────────────────────────────────────
  // Summary
  // ─────────────────────────────────────────────────────
  console.log('==========================================================');
  console.log('Phase 4 Runtime Supervision — all components active');
  console.log('  ✅ ComputeBudget (declarative + adaptive)');
  console.log('  ✅ BudgetProfile (conservative / balanced / performance)');
  console.log('  ✅ MeasuredBaseline + budget resolution');
  console.log('  ✅ BudgetViolation events');
  console.log('  ✅ RuntimePolicy (conservative / balanced / performance / custom)');
  console.log('  ✅ RuntimePolicyEnforcer (throttle, priority multiplier)');
  console.log('  ✅ LatencyTracker (percentiles)');
  console.log('  ✅ ResourceMonitor (native RSS, peak, average)');
  console.log('  ✅ ThermalMonitor (level, native events, listeners)');
  console.log('  ✅ BatteryDrainTracker (native events + manual samples)');
  console.log('  ✅ Scheduler (priority queue, budget violations)');
  console.log('  ✅ Telemetry (inference logs, latency stats, resource snapshots)');
  console.log('==========================================================');
}

// Auto-run if executed directly
runRuntimeSupervisionExample().catch(console.error);