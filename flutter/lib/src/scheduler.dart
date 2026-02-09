/// Central coordinator for compute budget enforcement across concurrent
/// on-device inference workloads.
///
/// The [Scheduler] polls [TelemetryService] every 2 seconds and checks
/// declared [EdgeVedaBudget] constraints. When a constraint is violated,
/// the scheduler degrades the lowest-priority workload first (reducing
/// its [QoSLevel]). When all constraints are satisfied, it gradually
/// restores workloads with a cooldown to prevent oscillation.
///
/// Usage:
/// ```dart
/// final scheduler = Scheduler(
///   telemetry: telemetryService,
///   perfTrace: trace,
/// );
/// scheduler.setBudget(EdgeVedaBudget(p95LatencyMs: 2000));
/// scheduler.registerWorkload(WorkloadId.vision, priority: WorkloadPriority.high);
/// scheduler.registerWorkload(WorkloadId.text, priority: WorkloadPriority.low);
/// scheduler.start();
/// ```
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'budget.dart';
import 'latency_tracker.dart';
import 'perf_trace.dart';
import 'runtime_policy.dart';
import 'telemetry_service.dart';

/// Internal state for a registered workload.
class _WorkloadState {
  final WorkloadPriority priority;
  final LatencyTracker latencyTracker;
  QoSLevel level = QoSLevel.full;
  DateTime? lastDegradation;

  _WorkloadState({
    required this.priority,
    required this.latencyTracker,
  });
}

/// Central coordinator that enforces [EdgeVedaBudget] constraints across
/// concurrent on-device inference workloads.
///
/// The scheduler does NOT replace [RuntimePolicy] or [TelemetryService].
/// It builds on top of them:
/// - Polls [TelemetryService.snapshot] every 2 seconds
/// - Uses [RuntimePolicy.knobsForLevel] to map QoS levels to knob values
/// - Manages per-workload QoS levels independently
/// - Emits [BudgetViolation] events when constraints cannot be satisfied
/// - Logs all decisions to [PerfTrace]
class Scheduler {
  final TelemetryService _telemetry;
  final PerfTrace? _trace;

  EdgeVedaBudget? _budget;
  final Map<WorkloadId, _WorkloadState> _workloads = {};
  final BatteryDrainTracker _batteryTracker = BatteryDrainTracker();

  Timer? _timer;
  final StreamController<BudgetViolation> _violationController =
      StreamController<BudgetViolation>.broadcast();

  /// Cooldown duration before allowing restoration after a degradation.
  ///
  /// Each workload tracks its own last degradation time. Restoration is
  /// only attempted if at least this duration has elapsed since the last
  /// degradation of that specific workload.
  final Duration restorationCooldown;

  /// Creates a Scheduler that polls the given [telemetry] service and
  /// optionally logs decisions to [perfTrace].
  Scheduler({
    required TelemetryService telemetry,
    PerfTrace? perfTrace,
    this.restorationCooldown = const Duration(seconds: 30),
  })  : _telemetry = telemetry,
        _trace = perfTrace;

  /// Stream of budget violation events.
  ///
  /// Emitted when a constraint cannot be satisfied even after attempting
  /// mitigation (degrading workloads). Listen to this stream to display
  /// warnings or take app-level action.
  Stream<BudgetViolation> get onBudgetViolation =>
      _violationController.stream;

  /// The currently active budget, or null if none set.
  EdgeVedaBudget? get budget => _budget;

  /// Set or replace the active budget.
  ///
  /// Calls [EdgeVedaBudget.validate] and logs any warnings via
  /// [debugPrint]. Can be called multiple times to change the budget
  /// at runtime.
  void setBudget(EdgeVedaBudget budget) {
    _budget = budget;
    final warnings = budget.validate();
    for (final w in warnings) {
      debugPrint('[Scheduler] Budget warning: $w');
    }
  }

  /// Register a workload for budget tracking.
  ///
  /// The workload starts at [QoSLevel.full]. If a workload with the same
  /// [id] is already registered, it is replaced.
  void registerWorkload(WorkloadId id,
      {required WorkloadPriority priority}) {
    _workloads[id] = _WorkloadState(
      priority: priority,
      latencyTracker: LatencyTracker(),
    );
  }

  /// Unregister a workload. Removes all tracking state for it.
  void unregisterWorkload(WorkloadId id) {
    _workloads.remove(id);
  }

  /// Get the current QoS knobs for a workload.
  ///
  /// Returns [RuntimePolicy.knobsForLevel] mapped from the workload's
  /// current [QoSLevel]. If the workload is not registered, returns
  /// full-quality knobs.
  QoSKnobs getKnobsForWorkload(WorkloadId id) {
    final state = _workloads[id];
    final level = state?.level ?? QoSLevel.full;
    return RuntimePolicy.knobsForLevel(level);
  }

  /// Report an inference latency sample for a workload.
  ///
  /// Call this after each inference completes to feed the per-workload
  /// [LatencyTracker]. The scheduler uses these samples to compute p95
  /// for budget enforcement.
  void reportLatency(WorkloadId id, double latencyMs) {
    _workloads[id]?.latencyTracker.add(latencyMs);
  }

  /// Start the periodic enforcement loop (every 2 seconds).
  ///
  /// If already started, this is a no-op.
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _enforce());
  }

  /// Stop the enforcement loop.
  ///
  /// Does NOT reset workload state or the budget. Call [start] to resume.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Stop the enforcement loop and close the violation stream.
  ///
  /// After calling dispose, this scheduler instance should not be reused.
  void dispose() {
    stop();
    _violationController.close();
  }

  /// The enforcement loop -- called every 2 seconds by the periodic timer.
  Future<void> _enforce() async {
    final budget = _budget;
    if (budget == null) return;

    // 1. Poll telemetry
    final snap = await _telemetry.snapshot();

    // 2. Feed battery level to drain tracker
    _batteryTracker.addSample(snap.batteryLevel);

    // 3. Check each budget constraint
    // Separate into actionable (QoS changes help) and observe-only (QoS changes don't help).
    // Memory RSS is determined by model loading -- degrading fps/resolution/tokens won't free it.
    final actionableViolations = <BudgetConstraint>[];
    final observeOnlyViolations = <BudgetConstraint>[];

    final rssMb = snap.memoryRssBytes / (1024 * 1024);

    // Memory ceiling -- observe-only (model footprint can't be reduced by QoS knobs)
    if (budget.memoryCeilingMb != null && rssMb > budget.memoryCeilingMb!) {
      observeOnlyViolations.add(BudgetConstraint.memoryCeiling);
    }

    // Thermal level -- actionable (reducing inference intensity reduces heat)
    if (budget.maxThermalLevel != null &&
        snap.thermalState >= 0 &&
        snap.thermalState > budget.maxThermalLevel!) {
      actionableViolations.add(BudgetConstraint.thermalLevel);
    }

    // Battery drain -- actionable (reducing inference frequency reduces drain)
    final drainRate = _batteryTracker.drainPerTenMinutes;
    if (budget.batteryDrainPerTenMinutes != null && drainRate != null) {
      if (drainRate > budget.batteryDrainPerTenMinutes!) {
        actionableViolations.add(BudgetConstraint.batteryDrain);
      }
    }

    // p95 latency -- actionable (reducing tokens/resolution reduces latency)
    if (budget.p95LatencyMs != null) {
      for (final entry in _workloads.entries) {
        final tracker = entry.value.latencyTracker;
        if (tracker.isWarmedUp) {
          final p95 = tracker.p95;
          if (p95 != null && p95 > budget.p95LatencyMs!) {
            actionableViolations.add(BudgetConstraint.p95Latency);
            break; // One violation is enough to trigger degradation
          }
        }
      }
    }

    // 4. Emit observe-only violations (no degradation)
    for (final constraint in observeOnlyViolations) {
      double currentValue;
      double budgetValue;
      switch (constraint) {
        case BudgetConstraint.memoryCeiling:
          currentValue = rssMb;
          budgetValue = (budget.memoryCeilingMb ?? 0).toDouble();
        default:
          continue;
      }
      final violation = BudgetViolation(
        constraint: constraint,
        currentValue: currentValue,
        budgetValue: budgetValue,
        mitigation: 'Observe-only: QoS changes cannot reduce memory footprint',
        timestamp: DateTime.now(),
        mitigated: false,
      );
      _violationController.add(violation);
      _trace?.record(
        stage: 'budget_violation',
        value: currentValue,
        extra: {
          'constraint': constraint.name,
          'budget': budgetValue,
          'mitigated': false,
          'observe_only': true,
        },
      );
    }

    // 5. Handle actionable violations (trigger degradation)
    if (actionableViolations.isNotEmpty) {
      _handleViolations(actionableViolations, budget, rssMb, snap, drainRate);
    } else {
      // 6. No actionable violations -- attempt restoration
      _attemptRestoration();
    }

    // 7. Log budget check
    final totalViolations = actionableViolations.length + observeOnlyViolations.length;
    _trace?.record(
      stage: 'budget_check',
      value: totalViolations.toDouble(),
      extra: {
        'thermal': snap.thermalState,
        'battery': snap.batteryLevel,
        'rss_mb': rssMb.round(),
        'actionable': actionableViolations.length,
        'observe_only': observeOnlyViolations.length,
      },
    );
  }

  /// Degrade the lowest-priority workload to address budget violations.
  void _handleViolations(
    List<BudgetConstraint> violations,
    EdgeVedaBudget budget,
    double rssMb,
    TelemetrySnapshot snap,
    double? drainRate,
  ) {
    // Sort workloads by priority: low first (degrade first)
    final sortedWorkloads = _workloads.entries.toList()
      ..sort((a, b) => a.value.priority.index.compareTo(b.value.priority.index));

    bool degraded = false;

    for (final entry in sortedWorkloads) {
      final id = entry.key;
      final state = entry.value;

      if (state.level == QoSLevel.paused) continue; // Already at worst

      // Degrade by one level
      final oldLevel = state.level;
      final newIndex = oldLevel.index + 1;
      if (newIndex >= QoSLevel.values.length) continue;

      state.level = QoSLevel.values[newIndex];
      state.lastDegradation = DateTime.now();

      _trace?.record(
        stage: 'scheduler_decision',
        value: 0,
        extra: {
          'action': 'degrade',
          'workload': id.name,
          'from': oldLevel.name,
          'to': state.level.name,
          'reason': violations.first.name,
        },
      );

      degraded = true;
      break; // Only degrade one workload per enforcement cycle
    }

    // After degradation, check if constraints are STILL violated.
    // For each violation, emit a BudgetViolation event if mitigation
    // was insufficient or if we couldn't degrade further.
    for (final constraint in violations) {
      final mitigation = degraded
          ? 'Degraded lowest-priority workload'
          : 'All workloads already at maximum degradation';

      // Determine current and budget values for the violation
      double currentValue;
      double budgetValue;

      switch (constraint) {
        case BudgetConstraint.memoryCeiling:
          currentValue = rssMb;
          budgetValue = (budget.memoryCeilingMb ?? 0).toDouble();
        case BudgetConstraint.thermalLevel:
          currentValue = snap.thermalState.toDouble();
          budgetValue = (budget.maxThermalLevel ?? 0).toDouble();
        case BudgetConstraint.batteryDrain:
          currentValue = drainRate ?? 0.0;
          budgetValue = budget.batteryDrainPerTenMinutes ?? 0.0;
        case BudgetConstraint.p95Latency:
          currentValue = _worstP95() ?? 0.0;
          budgetValue = (budget.p95LatencyMs ?? 0).toDouble();
      }

      // Only emit if not mitigated (still violated after degradation)
      // We can't re-check instantly since degradation effect takes time,
      // so emit as unmitigated when we couldn't degrade further
      final mitigated = degraded;

      final violation = BudgetViolation(
        constraint: constraint,
        currentValue: currentValue,
        budgetValue: budgetValue,
        mitigation: mitigation,
        timestamp: DateTime.now(),
        mitigated: mitigated,
      );

      if (!mitigated) {
        _violationController.add(violation);
      }

      _trace?.record(
        stage: 'budget_violation',
        value: currentValue,
        extra: {
          'constraint': constraint.name,
          'budget': budgetValue,
          'mitigated': mitigated,
        },
      );
    }
  }

  /// Get the worst (highest) p95 across all warmed-up workloads.
  double? _worstP95() {
    double? worst;
    for (final state in _workloads.values) {
      if (state.latencyTracker.isWarmedUp) {
        final p95 = state.latencyTracker.p95;
        if (p95 != null && (worst == null || p95 > worst)) {
          worst = p95;
        }
      }
    }
    return worst;
  }

  /// Attempt to restore workloads that have been degraded.
  ///
  /// Restores the highest-priority workload first, one level at a time.
  /// Restoration requires at least [restorationCooldown] since the last
  /// degradation of that specific workload.
  void _attemptRestoration() {
    // Sort workloads by priority: high first (restore first)
    final sortedWorkloads = _workloads.entries.toList()
      ..sort(
          (a, b) => b.value.priority.index.compareTo(a.value.priority.index));

    for (final entry in sortedWorkloads) {
      final id = entry.key;
      final state = entry.value;

      if (state.level == QoSLevel.full) continue; // Already at best

      // Check cooldown
      if (state.lastDegradation != null) {
        final elapsed = DateTime.now().difference(state.lastDegradation!);
        if (elapsed < restorationCooldown) continue;
      }

      // Restore by one level
      final oldLevel = state.level;
      final newIndex = oldLevel.index - 1;
      if (newIndex < 0) continue;

      state.level = QoSLevel.values[newIndex];

      _trace?.record(
        stage: 'scheduler_decision',
        value: 0,
        extra: {
          'action': 'restore',
          'workload': id.name,
          'from': oldLevel.name,
          'to': state.level.name,
        },
      );

      break; // Only restore one workload per enforcement cycle
    }
  }
}
