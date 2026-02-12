/// Declarative compute budget contracts for on-device inference.
///
/// An [EdgeVedaBudget] declares maximum resource limits that the [Scheduler]
/// enforces across concurrent workloads. Constraints are optional -- set only
/// the ones you care about.
///
/// Example:
/// ```dart
/// final budget = EdgeVedaBudget(
///   p95LatencyMs: 2000,
///   batteryDrainPerTenMinutes: 3.0,
///   maxThermalLevel: 2,
///   memoryCeilingMb: 1200,
/// );
/// ```
library;

/// Which budget constraint was violated.
enum BudgetConstraint {
  /// p95 inference latency exceeded the declared maximum.
  p95Latency,

  /// Battery drain rate exceeded the declared maximum per 10 minutes.
  batteryDrain,

  /// Thermal level exceeded the declared maximum.
  thermalLevel,

  /// Memory RSS exceeded the declared ceiling.
  memoryCeiling,
}

/// Priority level for a registered workload.
///
/// Higher-priority workloads are degraded **last** when the scheduler needs
/// to reduce resource usage to satisfy budget constraints.
enum WorkloadPriority {
  /// Low priority -- degraded first when budget is at risk.
  low,

  /// High priority -- maintained as long as possible.
  high,
}

/// Unique identifier for each workload type managed by the scheduler.
enum WorkloadId {
  /// Vision inference (VisionWorker).
  vision,

  /// Text/chat inference (StreamingWorker via ChatSession).
  text,

  /// Speech-to-text inference (WhisperWorker via WhisperSession).
  stt,

  /// Tool/function calling inference.
  toolCall,
}

/// Adaptive budget profile expressing intent as multipliers on measured device baseline.
///
/// Instead of hardcoding absolute values, profiles multiply the actual measured
/// performance of THIS device with THIS model. The [Scheduler] resolves
/// profile multipliers against [MeasuredBaseline] after warm-up.
enum BudgetProfile {
  /// Generous headroom: p95 x2.0, battery x0.6 (strict), thermal = 1 (Fair).
  /// Best for background/secondary workloads where stability matters more than speed.
  conservative,

  /// Moderate headroom: p95 x1.5, battery x1.0 (match baseline), thermal = 1 (Fair).
  /// Good default for most apps.
  balanced,

  /// Tight headroom: p95 x1.1, battery x1.5 (generous), thermal = 3 (allow critical).
  /// For latency-sensitive apps willing to trade battery/thermal for speed.
  performance,
}

/// Snapshot of actual device performance measured during warm-up.
///
/// The [Scheduler] builds this after its [LatencyTracker] and
/// [BatteryDrainTracker] have collected sufficient data. Use
/// [Scheduler.measuredBaseline] to access it.
class MeasuredBaseline {
  /// Measured p95 inference latency in milliseconds.
  final double measuredP95Ms;

  /// Measured battery drain rate per 10 minutes (percentage).
  /// Null if battery data was insufficient (e.g., plugged in, simulator).
  final double? measuredDrainPerTenMin;

  /// Current thermal state at time of measurement (0-3, or -1 if unknown).
  final int currentThermalState;

  /// Current process RSS in megabytes at time of measurement.
  final double currentRssMb;

  /// Number of latency samples collected during warm-up.
  final int sampleCount;

  /// When this baseline was captured.
  final DateTime measuredAt;

  const MeasuredBaseline({
    required this.measuredP95Ms,
    this.measuredDrainPerTenMin,
    required this.currentThermalState,
    required this.currentRssMb,
    required this.sampleCount,
    required this.measuredAt,
  });

  @override
  String toString() => 'MeasuredBaseline('
      'p95=${measuredP95Ms.toStringAsFixed(0)}ms, '
      'drain=${measuredDrainPerTenMin?.toStringAsFixed(1) ?? "n/a"}%/10min, '
      'thermal=$currentThermalState, '
      'rss=${currentRssMb.toStringAsFixed(0)}MB, '
      'samples=$sampleCount)';
}

/// Declarative resource budget for on-device inference.
///
/// Immutable once created. Pass to `Scheduler.setBudget()` to activate
/// enforcement. All fields are optional -- set only the constraints you
/// want enforced.
class EdgeVedaBudget {
  /// Maximum p95 inference latency in milliseconds.
  ///
  /// Set to null to skip latency enforcement.
  final int? p95LatencyMs;

  /// Maximum battery drain percentage per 10 minutes.
  ///
  /// E.g., 3.0 means max 3% drain per 10 minutes.
  /// Set to null to skip battery enforcement.
  final double? batteryDrainPerTenMinutes;

  /// Maximum thermal level (0=nominal, 1=fair, 2=serious, 3=critical).
  ///
  /// Scheduler will degrade workloads to prevent exceeding this level.
  /// Set to null to skip thermal enforcement (RuntimePolicy still runs).
  final int? maxThermalLevel;

  /// Maximum memory RSS in megabytes.
  ///
  /// Set to null to skip memory enforcement.
  final int? memoryCeilingMb;

  /// Creates a declarative budget with optional constraints.
  const EdgeVedaBudget({
    this.p95LatencyMs,
    this.batteryDrainPerTenMinutes,
    this.maxThermalLevel,
    this.memoryCeilingMb,
  });

  /// Create an adaptive budget that will be resolved against measured device
  /// performance after warm-up.
  ///
  /// Unlike the default constructor where you specify absolute values, this
  /// factory stores the [profile] and lets the [Scheduler] resolve concrete
  /// values after its trackers have warmed up. Before resolution, no budget
  /// enforcement occurs.
  ///
  /// See [BudgetProfile] for multiplier details.
  factory EdgeVedaBudget.adaptive(BudgetProfile profile) {
    return _AdaptiveBudget(profile);
  }

  /// The adaptive profile, if this budget was created via [EdgeVedaBudget.adaptive].
  /// Returns null for budgets created with explicit values.
  BudgetProfile? get adaptiveProfile => null;

  /// Resolve an adaptive [profile] against a [baseline] to produce concrete
  /// budget values.
  ///
  /// Called internally by [Scheduler] after warm-up. Not typically called
  /// by application code.
  static EdgeVedaBudget resolve(BudgetProfile profile, MeasuredBaseline baseline) {
    final int resolvedP95;
    final double? resolvedDrain;
    final int resolvedThermal;

    switch (profile) {
      case BudgetProfile.conservative:
        resolvedP95 = (baseline.measuredP95Ms * 2.0).round();
        resolvedDrain = baseline.measuredDrainPerTenMin != null
            ? baseline.measuredDrainPerTenMin! * 0.6
            : null;
        resolvedThermal = baseline.currentThermalState < 1 ? 1 : baseline.currentThermalState;
      case BudgetProfile.balanced:
        resolvedP95 = (baseline.measuredP95Ms * 1.5).round();
        resolvedDrain = baseline.measuredDrainPerTenMin != null
            ? baseline.measuredDrainPerTenMin! * 1.0
            : null;
        resolvedThermal = 1;
      case BudgetProfile.performance:
        resolvedP95 = (baseline.measuredP95Ms * 1.1).round();
        resolvedDrain = baseline.measuredDrainPerTenMin != null
            ? baseline.measuredDrainPerTenMin! * 1.5
            : null;
        resolvedThermal = 3;
    }

    return EdgeVedaBudget(
      p95LatencyMs: resolvedP95,
      batteryDrainPerTenMinutes: resolvedDrain,
      maxThermalLevel: resolvedThermal,
      memoryCeilingMb: null, // Memory is always observe-only
    );
  }

  /// Validate budget parameters for sanity.
  ///
  /// Returns a list of warnings for unrealistic values. An empty list means
  /// all parameters are within reasonable bounds.
  List<String> validate() {
    final warnings = <String>[];
    if (p95LatencyMs != null && p95LatencyMs! < 500) {
      warnings.add('p95LatencyMs=$p95LatencyMs is likely unrealistic '
          'for on-device LLM inference (typical: 1000-3000ms)');
    }
    if (batteryDrainPerTenMinutes != null &&
        batteryDrainPerTenMinutes! < 0.5) {
      warnings.add('batteryDrainPerTenMinutes=$batteryDrainPerTenMinutes '
          'may be too restrictive for active inference');
    }
    if (memoryCeilingMb != null && memoryCeilingMb! < 2000) {
      warnings.add('memoryCeilingMb=$memoryCeilingMb may be too low for VLM '
          'workloads (typical RSS: 1500-2500MB including model + Metal '
          'buffers + image tensors). Consider setting to null to skip memory '
          'enforcement, or measure actual RSS after model load.');
    }
    return warnings;
  }

  @override
  String toString() => 'EdgeVedaBudget('
      'p95LatencyMs=$p95LatencyMs, '
      'batteryDrainPerTenMinutes=$batteryDrainPerTenMinutes, '
      'maxThermalLevel=$maxThermalLevel, '
      'memoryCeilingMb=$memoryCeilingMb)';
}

/// Emitted when the Scheduler cannot satisfy a declared budget constraint
/// even after attempting mitigation.
class BudgetViolation {
  /// Which constraint was violated.
  final BudgetConstraint constraint;

  /// Current measured value that exceeds the budget.
  final double currentValue;

  /// Declared budget value that was exceeded.
  final double budgetValue;

  /// What mitigation was attempted (e.g., 'degrade vision to minimal').
  final String mitigation;

  /// When the violation was detected.
  final DateTime timestamp;

  /// Whether the mitigation was successful (constraint now satisfied).
  final bool mitigated;

  /// Whether this violation is observe-only (no QoS mitigation possible).
  ///
  /// Memory ceiling violations are observe-only because QoS knob changes
  /// (fps, resolution, tokens) cannot reduce model memory footprint.
  final bool observeOnly;

  const BudgetViolation({
    required this.constraint,
    required this.currentValue,
    required this.budgetValue,
    required this.mitigation,
    required this.timestamp,
    required this.mitigated,
    this.observeOnly = false,
  });

  @override
  String toString() => 'BudgetViolation('
      '${constraint.name}: current=$currentValue, '
      'budget=$budgetValue, '
      '${observeOnly ? 'observeOnly=$observeOnly, ' : ''}'
      'mitigated=$mitigated, '
      'mitigation=$mitigation)';
}

/// Internal marker subclass for adaptive budgets.
///
/// The [Scheduler] checks `budget.adaptiveProfile != null` to determine
/// whether resolution is needed. Before resolution, all constraint fields
/// are null (no enforcement). After resolution, the scheduler replaces
/// this with a concrete [EdgeVedaBudget] containing resolved values.
class _AdaptiveBudget extends EdgeVedaBudget {
  final BudgetProfile profile;

  _AdaptiveBudget(this.profile) : super();

  @override
  BudgetProfile? get adaptiveProfile => profile;

  @override
  String toString() => 'EdgeVedaBudget.adaptive(${profile.name})';
}
