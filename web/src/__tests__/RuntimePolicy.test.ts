import {
  RuntimePolicyPresets,
  RuntimePolicyEnforcer,
  detectCapabilities,
  throttleRecommendationToString,
  type RuntimePolicy,
  type RuntimeCapabilities,
} from '../RuntimePolicy';
import { ThermalMonitor } from '../ThermalMonitor';
import { BatteryDrainTracker } from '../BatteryDrainTracker';
import { ResourceMonitor } from '../ResourceMonitor';

// ---------------------------------------------------------------------------
// Mock browser globals
// ---------------------------------------------------------------------------

const originalNavigator = global.navigator;
const originalDocument = global.document;

beforeAll(() => {
  // Provide minimal navigator/document for tests
  Object.defineProperty(global, 'navigator', {
    value: {
      getBattery: undefined,
      userAgent: 'TestAgent/1.0 Chrome',
      gpu: undefined,
    },
    writable: true,
    configurable: true,
  });
  Object.defineProperty(global, 'document', {
    value: { visibilityState: 'visible' },
    writable: true,
    configurable: true,
  });
});

afterAll(() => {
  Object.defineProperty(global, 'navigator', {
    value: originalNavigator,
    writable: true,
    configurable: true,
  });
  Object.defineProperty(global, 'document', {
    value: originalDocument,
    writable: true,
    configurable: true,
  });
});

// ---------------------------------------------------------------------------
// Presets
// ---------------------------------------------------------------------------

describe('RuntimePolicyPresets', () => {
  test('CONSERVATIVE has all protections enabled', () => {
    const p = RuntimePolicyPresets.CONSERVATIVE;
    expect(p.throttleOnBattery).toBe(true);
    expect(p.adaptiveMemory).toBe(true);
    expect(p.thermalAware).toBe(true);
    expect(p.backgroundOptimization).toBe(true);
  });

  test('BALANCED has background optimization disabled', () => {
    const p = RuntimePolicyPresets.BALANCED;
    expect(p.throttleOnBattery).toBe(true);
    expect(p.backgroundOptimization).toBe(false);
  });

  test('PERFORMANCE has all protections disabled', () => {
    const p = RuntimePolicyPresets.PERFORMANCE;
    expect(p.throttleOnBattery).toBe(false);
    expect(p.adaptiveMemory).toBe(false);
    expect(p.thermalAware).toBe(false);
    expect(p.backgroundOptimization).toBe(false);
  });

  test('DEFAULT matches BALANCED', () => {
    const d = RuntimePolicyPresets.DEFAULT;
    const b = RuntimePolicyPresets.BALANCED;
    expect(d.throttleOnBattery).toBe(b.throttleOnBattery);
    expect(d.thermalAware).toBe(b.thermalAware);
    expect(d.backgroundOptimization).toBe(b.backgroundOptimization);
  });

  test('toString formats policy', () => {
    const s = RuntimePolicyPresets.toString(RuntimePolicyPresets.CONSERVATIVE);
    expect(s).toContain('throttleOnBattery=true');
    expect(s).toContain('backgroundOptimization=true');
  });
});

// ---------------------------------------------------------------------------
// detectCapabilities
// ---------------------------------------------------------------------------

describe('detectCapabilities', () => {
  test('detects Chrome platform from user agent', () => {
    const caps = detectCapabilities();
    expect(caps.platform).toBe('Chrome');
    expect(caps.userAgent).toContain('Chrome');
  });

  test('hasThermalMonitoring is always false in browser', () => {
    const caps = detectCapabilities();
    expect(caps.hasThermalMonitoring).toBe(false);
  });

  test('hasBatteryMonitoring reflects navigator.getBattery', () => {
    const caps = detectCapabilities();
    // We set getBattery to undefined in beforeAll
    expect(caps.hasBatteryMonitoring).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// RuntimePolicyEnforcer
// ---------------------------------------------------------------------------

describe('RuntimePolicyEnforcer', () => {
  let thermalMonitor: ThermalMonitor;
  let batteryTracker: BatteryDrainTracker;
  let resourceMonitor: ResourceMonitor;

  beforeEach(() => {
    thermalMonitor = new ThermalMonitor();
    batteryTracker = new BatteryDrainTracker();
    resourceMonitor = new ResourceMonitor();
  });

  test('defaults to DEFAULT policy', () => {
    const enforcer = new RuntimePolicyEnforcer();
    const policy = enforcer.getPolicy();
    expect(policy.throttleOnBattery).toBe(true);
    expect(policy.thermalAware).toBe(true);
  });

  test('setPolicy updates active policy', () => {
    const enforcer = new RuntimePolicyEnforcer();
    enforcer.setPolicy(RuntimePolicyPresets.PERFORMANCE);
    expect(enforcer.getPolicy().throttleOnBattery).toBe(false);
  });

  test('getCapabilities returns RuntimeCapabilities', () => {
    const enforcer = new RuntimePolicyEnforcer();
    const caps = enforcer.getCapabilities();
    expect(caps).toHaveProperty('platform');
    expect(caps).toHaveProperty('hasThermalMonitoring');
  });

  // -----------------------------------------------------------------------
  // shouldThrottle — thermal
  // -----------------------------------------------------------------------

  test('shouldThrottle returns no throttle when all clear', () => {
    const enforcer = new RuntimePolicyEnforcer({
      policy: RuntimePolicyPresets.BALANCED,
      thermalMonitor,
      batteryTracker,
      resourceMonitor,
    });
    const rec = enforcer.shouldThrottle();
    expect(rec.shouldThrottle).toBe(false);
    expect(rec.throttleFactor).toBeGreaterThan(0);
    expect(rec.reasons).toHaveLength(0);
  });

  test('shouldThrottle detects thermal pressure >= 2', () => {
    thermalMonitor.updateLevel(2);
    const enforcer = new RuntimePolicyEnforcer({
      policy: RuntimePolicyPresets.BALANCED,
      thermalMonitor,
    });
    const rec = enforcer.shouldThrottle();
    expect(rec.shouldThrottle).toBe(true);
    expect(rec.reasons.some((r) => r.includes('Thermal'))).toBe(true);
    expect(rec.throttleFactor).toBeLessThan(1.0);
  });

  // -----------------------------------------------------------------------
  // shouldThrottle — battery
  // -----------------------------------------------------------------------

  test('shouldThrottle detects low battery < 0.2', () => {
    batteryTracker.recordSample(0.1);
    const enforcer = new RuntimePolicyEnforcer({
      policy: RuntimePolicyPresets.BALANCED,
      batteryTracker,
    });
    const rec = enforcer.shouldThrottle();
    expect(rec.shouldThrottle).toBe(true);
    expect(rec.reasons.some((r) => r.includes('battery'))).toBe(true);
  });

  test('shouldThrottle does not throttle battery when policy disabled', () => {
    batteryTracker.recordSample(0.1);
    const enforcer = new RuntimePolicyEnforcer({
      policy: RuntimePolicyPresets.PERFORMANCE,
      batteryTracker,
    });
    const rec = enforcer.shouldThrottle();
    expect(rec.shouldThrottle).toBe(false);
  });

  // -----------------------------------------------------------------------
  // shouldThrottle — memory
  // -----------------------------------------------------------------------

  test('shouldThrottle detects high memory usage', () => {
    // Mock performance.memory for ResourceMonitor
    Object.defineProperty(performance, 'memory', {
      value: { usedJSHeapSize: 900 * 1024 * 1024 },
      writable: true,
      configurable: true,
    });

    const rm = new ResourceMonitor();
    // Force a sample at lower value to set a peak, then sample at 95% of peak
    // Access currentRssMb to trigger sample
    const _ = rm.currentRssMb;
    // Now the peak is ~900MB. Current also ~900MB which is >90% of peak.
    const enforcer = new RuntimePolicyEnforcer({
      policy: RuntimePolicyPresets.BALANCED,
      resourceMonitor: rm,
    });
    const rec = enforcer.shouldThrottle();
    // peak > 0 and current > peak * 0.9 is true (current == peak)
    expect(rec.shouldThrottle).toBe(true);
    expect(rec.reasons.some((r) => r.includes('memory'))).toBe(true);

    // Cleanup
    Object.defineProperty(performance, 'memory', {
      value: undefined,
      writable: true,
      configurable: true,
    });
  });

  // -----------------------------------------------------------------------
  // shouldThrottle — background tab
  // -----------------------------------------------------------------------

  test('shouldThrottle detects hidden tab with backgroundOptimization', () => {
    Object.defineProperty(global, 'document', {
      value: { visibilityState: 'hidden' },
      writable: true,
      configurable: true,
    });

    const enforcer = new RuntimePolicyEnforcer({
      policy: RuntimePolicyPresets.CONSERVATIVE, // backgroundOptimization = true
    });
    const rec = enforcer.shouldThrottle();
    expect(rec.shouldThrottle).toBe(true);
    expect(rec.reasons.some((r) => r.includes('hidden'))).toBe(true);

    // Restore
    Object.defineProperty(global, 'document', {
      value: { visibilityState: 'visible' },
      writable: true,
      configurable: true,
    });
  });

  // -----------------------------------------------------------------------
  // shouldOptimizeForBackground
  // -----------------------------------------------------------------------

  test('shouldOptimizeForBackground returns false when policy disabled', () => {
    const enforcer = new RuntimePolicyEnforcer({
      policy: RuntimePolicyPresets.BALANCED, // backgroundOptimization = false
    });
    expect(enforcer.shouldOptimizeForBackground()).toBe(false);
  });

  test('shouldOptimizeForBackground returns true when tab hidden and policy enabled', () => {
    Object.defineProperty(global, 'document', {
      value: { visibilityState: 'hidden' },
      writable: true,
      configurable: true,
    });

    const enforcer = new RuntimePolicyEnforcer({
      policy: RuntimePolicyPresets.CONSERVATIVE,
    });
    expect(enforcer.shouldOptimizeForBackground()).toBe(true);

    Object.defineProperty(global, 'document', {
      value: { visibilityState: 'visible' },
      writable: true,
      configurable: true,
    });
  });

  // -----------------------------------------------------------------------
  // getPriorityMultiplier
  // -----------------------------------------------------------------------

  test('getPriorityMultiplier returns 1.0 for balanced with no pressure', () => {
    const enforcer = new RuntimePolicyEnforcer({
      policy: RuntimePolicyPresets.BALANCED,
    });
    expect(enforcer.getPriorityMultiplier()).toBe(1.0);
  });

  test('getPriorityMultiplier returns 1.2 for performance policy', () => {
    const enforcer = new RuntimePolicyEnforcer({
      policy: RuntimePolicyPresets.PERFORMANCE,
    });
    expect(enforcer.getPriorityMultiplier()).toBe(1.2);
  });

  test('getPriorityMultiplier returns throttle factor under pressure', () => {
    thermalMonitor.updateLevel(3);
    const enforcer = new RuntimePolicyEnforcer({
      policy: RuntimePolicyPresets.BALANCED,
      thermalMonitor,
    });
    const mult = enforcer.getPriorityMultiplier();
    expect(mult).toBeLessThan(1.0);
  });

  // -----------------------------------------------------------------------
  // destroy
  // -----------------------------------------------------------------------

  test('destroy does not throw', () => {
    const enforcer = new RuntimePolicyEnforcer({
      thermalMonitor,
      batteryTracker,
      resourceMonitor,
    });
    expect(() => enforcer.destroy()).not.toThrow();
  });
});

// ---------------------------------------------------------------------------
// throttleRecommendationToString
// ---------------------------------------------------------------------------

describe('throttleRecommendationToString', () => {
  test('formats throttle recommendation', () => {
    const s = throttleRecommendationToString({
      shouldThrottle: true,
      throttleFactor: 0.5,
      reasons: ['Thermal pressure'],
    });
    expect(s).toContain('50%');
    expect(s).toContain('Thermal');
  });

  test('formats no-throttle recommendation', () => {
    const s = throttleRecommendationToString({
      shouldThrottle: false,
      throttleFactor: 1.0,
      reasons: [],
    });
    expect(s).toBe('No throttling needed');
  });
});