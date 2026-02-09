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
