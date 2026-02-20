import 'package:edge_veda/edge_veda.dart';

/// Shared singleton holding [LatencyTracker] and [BatteryDrainTracker]
/// instances used across the app.
///
/// Call [PerformanceTrackers.latency.add(ms)] from ChatScreen after each
/// generation completes. Call [PerformanceTrackers.battery.addSample(level)]
/// from battery monitoring code.
class PerformanceTrackers {
  PerformanceTrackers._();

  /// Tracks generation latency percentiles (p50/p95/p99).
  static final LatencyTracker latency = LatencyTracker(
    windowSize: 100,
    minSamplesForEnforcement: 5,
  );

  /// Tracks battery drain rate over a 10-minute sliding window.
  static final BatteryDrainTracker battery = BatteryDrainTracker(
    windowDuration: const Duration(minutes: 10),
  );

  /// Reset all trackers.
  static void resetAll() {
    latency.reset();
    battery.reset();
  }
}
