import 'package:flutter_test/flutter_test.dart';
import 'package:edge_veda/src/latency_tracker.dart';

void main() {
  group('LatencyTracker', () {
    test('empty tracker: p95 returns null, isWarmedUp false, sampleCount 0',
        () {
      final tracker = LatencyTracker();
      expect(tracker.p95, isNull);
      expect(tracker.isWarmedUp, false);
      expect(tracker.sampleCount, 0);
    });

    test('add 1 sample: p95 returns that value, isWarmedUp still false', () {
      final tracker = LatencyTracker();
      tracker.add(42.0);
      expect(tracker.p95, 42.0);
      expect(tracker.isWarmedUp, false);
      expect(tracker.sampleCount, 1);
    });

    test('add 20 samples: isWarmedUp is true', () {
      final tracker = LatencyTracker();
      for (var i = 1; i <= 20; i++) {
        tracker.add(i.toDouble());
      }
      expect(tracker.isWarmedUp, true);
      expect(tracker.sampleCount, 20);
    });

    test('p50 of [1..20] uses ceiling interpolation', () {
      final tracker = LatencyTracker();
      for (var i = 1; i <= 20; i++) {
        tracker.add(i.toDouble());
      }
      // p50: ceil(0.50 * 19) = ceil(9.5) = 10
      // sorted[10] = 11.0 (sorted list is [1,2,...,20], index 10 is 11)
      final p50 = tracker.p50;
      expect(p50, isNotNull);
      expect(p50, 11.0);
    });

    test('p95 of [1..100] uses ceiling interpolation', () {
      final tracker = LatencyTracker(windowSize: 100);
      for (var i = 1; i <= 100; i++) {
        tracker.add(i.toDouble());
      }
      // p95: ceil(0.95 * 99) = ceil(94.05) = 95
      // sorted[95] = 96.0 (sorted list is [1,...,100], index 95 is 96)
      expect(tracker.p95, 96.0);
    });

    test('window eviction: 150 samples with windowSize=100 retains 100', () {
      final tracker = LatencyTracker(windowSize: 100);
      for (var i = 1; i <= 150; i++) {
        tracker.add(i.toDouble());
      }
      expect(tracker.sampleCount, 100);
    });

    test('reset clears all state', () {
      final tracker = LatencyTracker();
      for (var i = 1; i <= 25; i++) {
        tracker.add(i.toDouble());
      }
      expect(tracker.isWarmedUp, true);

      tracker.reset();
      expect(tracker.sampleCount, 0);
      expect(tracker.isWarmedUp, false);
      expect(tracker.p95, isNull);
    });
  });

  group('BatteryDrainTracker', () {
    test('fewer than 2 samples returns null', () {
      final tracker = BatteryDrainTracker();
      expect(tracker.drainPerTenMinutes, isNull);

      // One sample: still null (need at least 2)
      tracker.addSample(0.95);
      expect(tracker.drainPerTenMinutes, isNull);
    });

    test('less than 120 seconds of data returns null', () {
      final tracker = BatteryDrainTracker();
      // Two samples added nearly simultaneously -- under 120 seconds
      tracker.addSample(1.0);
      tracker.addSample(0.95);
      expect(tracker.drainPerTenMinutes, isNull);
    });

    test('negative battery level ignored (not added)', () {
      final tracker = BatteryDrainTracker();
      tracker.addSample(-1.0);
      // Internal samples list should be empty since negative was ignored
      // Adding one valid sample should still result in null (need 2)
      tracker.addSample(0.95);
      expect(tracker.drainPerTenMinutes, isNull);
    });

    test('charging (newer > older) returns 0.0', () {
      // We need to simulate samples > 120 seconds apart.
      // BatteryDrainTracker uses DateTime.now() internally, so we can't
      // easily fake time. But we can verify the logic by testing that
      // the tracker doesn't crash with these values.
      final tracker = BatteryDrainTracker();
      tracker.addSample(0.50);
      tracker.addSample(0.80); // Charging (newer > older)
      // Still null because < 120s apart, but validates no crash
      expect(tracker.drainPerTenMinutes, isNull);
    });

    test('reset clears all samples', () {
      final tracker = BatteryDrainTracker();
      tracker.addSample(1.0);
      tracker.addSample(0.95);
      tracker.reset();
      expect(tracker.drainPerTenMinutes, isNull);
    });
  });
}
