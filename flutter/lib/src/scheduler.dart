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
  final Map<WorkloadId, Future<void> Function()> _memoryEvictionCallbacks = {};

  MeasuredBaseline? _measuredBaseline;
  EdgeVedaBudget? _resolvedBudget;
  bool _latencyResolved = false;
  bool _batteryResolved = false;

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

  /// The measured device baseline after warm-up, or null if trackers
  /// haven't collected enough data yet.
  ///
  /// Populated when the latency tracker reaches [LatencyTracker.minSamplesForEnforcement]
  /// samples (default 20). Use this to inspect what the device actually measured.
  MeasuredBaseline? get measuredBaseline => _measuredBaseline;

  /// The concrete budget being enforced after adaptive resolution,
  /// or null if no adaptive budget has been resolved yet.
  ///
  /// For static budgets (created with explicit values), this returns the
  /// same budget passed to [setBudget]. For adaptive budgets, this returns
  /// the resolved budget with concrete values derived from [measuredBaseline].
  EdgeVedaBudget? get resolvedBudget => _resolvedBudget;

  /// Set or replace the active budget.
  ///
  /// Calls [EdgeVedaBudget.validate] and logs any warnings via
  /// [debugPrint]. Can be called multiple times to change the budget
  /// at runtime.
  void setBudget(EdgeVedaBudget budget) {
    _budget = budget;
    _resolvedBudget = budget.adaptiveProfile == null ? budget : null;
    _latencyResolved = budget.adaptiveProfile == null;
    _batteryResolved = budget.adaptiveProfile == null;
    final warnings = budget.validate();
    for (final w in warnings) {
      debugPrint('[Scheduler] Budget warning: $w');
    }
    if (budget.adaptiveProfile != null) {
      debugPrint('[Scheduler] Adaptive budget (${budget.adaptiveProfile!.name}) '
          'set. Enforcement deferred until warm-up completes.');
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

  /// Get the current QoS level for the tool calling workload.
  ///
  /// If no tool calling workload is registered, returns null (no
  /// degradation). Developers should call this before sending
  /// tool-enabled messages to [ChatSession] to get the
  /// budget-appropriate tool filtering level via
  /// [ToolRegistry.forBudgetLevel].
  ///
  /// Returns null if tool calling workload is not registered.
  QoSLevel? getToolQoSLevel() {
    final state = _workloads[WorkloadId.toolCall];
    return state?.level;
  }

  /// Report an inference latency sample for a workload.
  ///
  /// Call this after each inference completes to feed the per-workload
  /// [LatencyTracker]. The scheduler uses these samples to compute p95
  /// for budget enforcement.
  void reportLatency(WorkloadId id, double latencyMs) {
    _workloads[id]?.latencyTracker.add(latencyMs);
  }

  /// Register a memory eviction callback for a workload.
  ///
  /// When memory ceiling is violated and the workload is idle (at
  /// [QoSLevel.full]), the Scheduler may call [callback] to free the
  /// workload's model memory. This is a one-shot mechanism: after
  /// eviction fires, both the workload and callback are unregistered.
  void registerMemoryEviction(
      WorkloadId id, Future<void> Function() callback) {
    _memoryEvictionCallbacks[id] = callback;
  }

  /// Unregister a memory eviction callback for a workload.
  ///
  /// Safe to call even if no callback was registered for [id].
  void unregisterMemoryEviction(WorkloadId id) {
    _memoryEvictionCallbacks.remove(id);
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

  /// Attempt to resolve an adaptive budget against measured baseline.
  ///
  /// Two-phase resolution:
  /// 1. First resolution when latency tracker warms up (~40s). Battery
  ///    constraint may be null if drain data isn't available yet.
  /// 2. Second resolution (battery only) when BatteryDrainTracker first
  ///    produces data, updating the resolved budget with the battery
  ///    constraint. This is a one-time update, not continuous re-resolution.
  ///
  /// Called on every enforcement tick. Returns true if resolution happened
  /// or was updated this tick.
  bool _tryResolveAdaptiveBudget(TelemetrySnapshot snap) {
    final budget = _budget;
    if (budget == null || budget.adaptiveProfile == null) return false;

    // Both phases complete -- nothing to do
    if (_latencyResolved && _batteryResolved) return false;

    // --- Phase 1: Initial resolution gated on latency warm-up ---
    if (!_latencyResolved) {
      // Check if ANY workload's latency tracker is warmed up
      bool latencyWarmedUp = false;
      double? worstP95;
      int totalSamples = 0;
      for (final state in _workloads.values) {
        totalSamples += state.latencyTracker.sampleCount;
        if (state.latencyTracker.isWarmedUp) {
          latencyWarmedUp = true;
          final p95 = state.latencyTracker.p95;
          if (p95 != null && (worstP95 == null || p95 > worstP95)) {
            worstP95 = p95;
          }
        }
      }

      if (!latencyWarmedUp || worstP95 == null) return false;

      // Build measured baseline (battery may be null at this point)
      final rssMb = snap.memoryRssBytes / (1024 * 1024);
      final drainRate = _batteryTracker.drainPerTenMinutes;

      _measuredBaseline = MeasuredBaseline(
        measuredP95Ms: worstP95,
        measuredDrainPerTenMin: drainRate,
        currentThermalState: snap.thermalState,
        currentRssMb: rssMb,
        sampleCount: totalSamples,
        measuredAt: DateTime.now(),
      );

      // Resolve adaptive budget (battery constraint will be null if drainRate is null)
      _resolvedBudget = EdgeVedaBudget.resolve(budget.adaptiveProfile!, _measuredBaseline!);
      _latencyResolved = true;
      // If battery data was already available, mark battery as resolved too
      if (drainRate != null) _batteryResolved = true;

      debugPrint('[Scheduler] Warm-up complete. Measured baseline: $_measuredBaseline');
      debugPrint('[Scheduler] Resolved budget: $_resolvedBudget');
      if (drainRate == null) {
        debugPrint('[Scheduler] Battery data not yet available. '
            'Will update battery constraint when drain tracker warms up.');
      }

      _trace?.record(
        stage: 'budget_resolved',
        value: worstP95,
        extra: {
          'profile': budget.adaptiveProfile!.name,
          'phase': drainRate != null ? 'full' : 'latency_only',
          'measured_p95': worstP95,
          'measured_drain': drainRate,
          'resolved_p95': _resolvedBudget!.p95LatencyMs,
          'resolved_drain': _resolvedBudget!.batteryDrainPerTenMinutes,
          'resolved_thermal': _resolvedBudget!.maxThermalLevel,
          'samples': totalSamples,
        },
      );

      return true;
    }

    // --- Phase 2: Battery re-resolution (latency already resolved) ---
    if (!_batteryResolved) {
      final drainRate = _batteryTracker.drainPerTenMinutes;
      if (drainRate == null) return false; // Still waiting for battery data

      // Update baseline with battery data
      _measuredBaseline = MeasuredBaseline(
        measuredP95Ms: _measuredBaseline!.measuredP95Ms,
        measuredDrainPerTenMin: drainRate,
        currentThermalState: _measuredBaseline!.currentThermalState,
        currentRssMb: _measuredBaseline!.currentRssMb,
        sampleCount: _measuredBaseline!.sampleCount,
        measuredAt: _measuredBaseline!.measuredAt,
      );

      // Re-resolve to add battery constraint
      _resolvedBudget = EdgeVedaBudget.resolve(budget.adaptiveProfile!, _measuredBaseline!);
      _batteryResolved = true;

      debugPrint('[Scheduler] Battery data available. Updated resolved budget: $_resolvedBudget');

      _trace?.record(
        stage: 'budget_battery_resolved',
        value: drainRate,
        extra: {
          'profile': budget.adaptiveProfile!.name,
          'measured_drain': drainRate,
          'resolved_drain': _resolvedBudget!.batteryDrainPerTenMinutes,
        },
      );

      return true;
    }

    return false;
  }

  /// The enforcement loop -- called every 2 seconds by the periodic timer.
  Future<void> _enforce() async {
    // Early exit: no budget set at all (neither static nor adaptive)
    if (_budget == null) return;

    // 1. Poll telemetry -- MUST happen before resolution check so that
    //    battery tracker gets samples during adaptive warm-up period.
    //    Without this, battery drain data would never accumulate and
    //    phase 2 battery re-resolution would never trigger.
    final snap = await _telemetry.snapshot();

    // 2. Feed battery level to drain tracker (needs continuous samples)
    _batteryTracker.addSample(snap.batteryLevel);

    // 3. Try adaptive resolution (no-op if already fully resolved or not adaptive)
    _tryResolveAdaptiveBudget(snap);

    // 4. Use resolved budget for enforcement. Null means adaptive budget
    //    hasn't resolved yet (latency tracker still warming up) -- skip
    //    enforcement this tick but telemetry/battery polling above still ran.
    final budget = _resolvedBudget;
    if (budget == null) return;

    // 5. Check each budget constraint
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
        observeOnly: true,
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

    // 4b. Try to evict idle workers when memory ceiling is violated
    if (observeOnlyViolations.contains(BudgetConstraint.memoryCeiling)) {
      _tryEvictIdleWorkers(rssMb);
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

      // Log tool-specific degradation for tracing
      if (id == WorkloadId.toolCall) {
        _trace?.record(
          stage: 'tool_degradation',
          value: state.level.index.toDouble(),
          extra: {
            'action': 'tool_degrade',
            'level': state.level.name,
            'tools_available': state.level == QoSLevel.full
                ? 'all'
                : state.level == QoSLevel.reduced
                    ? 'required_only'
                    : 'none',
          },
        );
      }

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
        observeOnly: false,
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

  /// Try to evict idle workers when memory ceiling is exceeded.
  ///
  /// Only evicts workloads that have a registered eviction callback AND
  /// are at [QoSLevel.full] (idle -- not currently degraded/under load).
  /// Prefers evicting lowest-priority workloads first. Eviction is
  /// fire-and-forget (async, not awaited in enforcement loop).
  void _tryEvictIdleWorkers(double rssMb) {
    final budget = _resolvedBudget;
    if (budget == null || budget.memoryCeilingMb == null) return;

    // Only evict if RSS exceeds ceiling by more than 10%
    final ceiling = budget.memoryCeilingMb!;
    if (rssMb <= ceiling * 1.1) return;

    // Collect evictable workloads: have callback AND are at QoSLevel.full
    final evictable = <WorkloadId>[];
    for (final id in _memoryEvictionCallbacks.keys) {
      final state = _workloads[id];
      if (state != null && state.level == QoSLevel.full) {
        evictable.add(id);
      }
    }
    if (evictable.isEmpty) return;

    // Sort by priority: lowest first (evict lowest priority first)
    evictable.sort((a, b) {
      final pa = _workloads[a]!.priority.index;
      final pb = _workloads[b]!.priority.index;
      return pa.compareTo(pb);
    });

    // Evict the lowest-priority idle workload
    final target = evictable.first;
    final callback = _memoryEvictionCallbacks[target];
    if (callback == null) return;

    _trace?.record(
      stage: 'memory_eviction',
      value: rssMb,
      extra: {
        'workload': target.name,
        'ceiling_mb': ceiling,
        'rss_mb': rssMb.round(),
        'overshoot_pct':
            (((rssMb - ceiling) / ceiling) * 100).toStringAsFixed(1),
      },
    );

    // Fire-and-forget eviction
    unawaited(callback());

    // One-shot: unregister workload and eviction callback
    _workloads.remove(target);
    _memoryEvictionCallbacks.remove(target);

    debugPrint('[Scheduler] Memory eviction: unloaded ${target.name} '
        '(RSS ${rssMb.round()}MB > ceiling ${ceiling}MB)');
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
