/// Rolling window telemetry trackers for compute budget enforcement.
///
/// [LatencyTracker] computes percentiles (p50, p95, p99) from a bounded
/// sorted list of inference latency samples.
///
/// [BatteryDrainTracker] estimates battery drain rate per 10 minutes from
/// rolling battery level samples.
library;

/// Rolling window percentile tracker for inference latencies.
///
/// Uses a bounded sorted list for O(log n) insert and O(1) percentile lookup.
/// Suitable for modest sample sizes (100-200 entries per session).
///
/// The tracker has a warm-up period: [isWarmedUp] returns false until at
/// least [minSamplesForEnforcement] samples have been collected. During
/// warm-up, latency budget constraints should NOT be enforced but data IS
/// collected.
class LatencyTracker {
  /// Maximum number of samples to retain in the rolling window.
  final int windowSize;

  /// Minimum samples needed before percentile enforcement is meaningful.
  final int minSamplesForEnforcement;

  final List<double> _sorted = [];

  /// Creates a latency tracker with configurable window size and warm-up
  /// threshold.
  LatencyTracker({
    this.windowSize = 100,
    this.minSamplesForEnforcement = 20,
  });

  /// Whether enough samples have been collected for statistically
  /// meaningful percentile enforcement.
  bool get isWarmedUp => _sorted.length >= minSamplesForEnforcement;

  /// Number of samples currently in the rolling window.
  int get sampleCount => _sorted.length;

  /// Add a latency sample in milliseconds.
  ///
  /// Uses binary search for O(log n) insertion point, then O(n) list insert.
  /// When the window exceeds [windowSize], the smallest (oldest-sorted) value
  /// is evicted to maintain the bounded window.
  void add(double latencyMs) {
    // Binary search for insertion point
    int lo = 0, hi = _sorted.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_sorted[mid] < latencyMs) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    _sorted.insert(lo, latencyMs);

    // Evict oldest (smallest) if over capacity
    if (_sorted.length > windowSize) {
      _sorted.removeAt(0);
    }
  }

  /// Get the p-th percentile (0.0 to 1.0).
  ///
  /// Returns null if no samples have been collected.
  /// Uses ceiling interpolation: index = ceil(p * (length - 1)).
  double? percentile(double p) {
    if (_sorted.isEmpty) return null;
    final index =
        (p * (_sorted.length - 1)).ceil().clamp(0, _sorted.length - 1);
    return _sorted[index];
  }

  /// Median latency (50th percentile).
  double? get p50 => percentile(0.50);

  /// 95th percentile latency -- the primary enforcement metric.
  double? get p95 => percentile(0.95);

  /// 99th percentile latency.
  double? get p99 => percentile(0.99);

  /// Clear all samples and reset warm-up state.
  void reset() => _sorted.clear();
}

/// Rolling battery drain rate estimator.
///
/// Tracks battery level samples over a configurable window (default 10
/// minutes) and computes the drain rate as percentage per 10 minutes.
///
/// Battery level is expected as a fraction (0.0 to 1.0), matching
/// [TelemetryService.getBatteryLevel] output.
class BatteryDrainTracker {
  /// Duration of the rolling sample window.
  final Duration windowDuration;

  final List<({DateTime time, double level})> _samples = [];

  /// Creates a battery drain tracker with configurable window duration.
  BatteryDrainTracker({
    this.windowDuration = const Duration(minutes: 10),
  });

  /// Add a battery level sample (0.0 to 1.0).
  ///
  /// Negative values (unknown/error) are ignored. Samples outside the
  /// rolling window are automatically evicted.
  void addSample(double batteryLevel) {
    if (batteryLevel < 0) return; // Unknown
    final now = DateTime.now();
    _samples.add((time: now, level: batteryLevel));

    // Evict samples outside the window
    final cutoff = now.subtract(windowDuration);
    _samples.removeWhere((s) => s.time.isBefore(cutoff));
  }

  /// Estimated battery drain per 10 minutes as a percentage.
  ///
  /// Returns null if fewer than 2 samples or less than 120 seconds of data.
  /// Returns 0.0 if the battery is charging (negative drain).
  /// Normalizes the observed drain to a per-10-minute rate.
  double? get drainPerTenMinutes {
    if (_samples.length < 2) return null;

    final oldest = _samples.first;
    final newest = _samples.last;
    final elapsed = newest.time.difference(oldest.time);

    // Need at least 2 minutes of data for a meaningful estimate
    if (elapsed.inSeconds < 120) return null;

    final drainPercent = (oldest.level - newest.level) * 100;

    // If drainPercent is negative, battery is charging -- return 0
    if (drainPercent <= 0) return 0.0;

    // Normalize to per-10-minutes
    const tenMinutes = 10 * 60; // seconds
    return drainPercent * tenMinutes / elapsed.inSeconds;
  }

  /// Clear all samples.
  void reset() => _samples.clear();
}
