/// Quality-of-Service levels for vision inference runtime.
///
/// Ordered from best quality to most degraded. The [index] property
/// gives a numeric ordering: full=0, reduced=1, minimal=2, paused=3.
enum QoSLevel {
  /// Full quality: max FPS, full resolution, full tokens.
  full,

  /// Reduced quality: lower FPS and resolution, fewer tokens.
  reduced,

  /// Minimal quality: minimum viable inference settings.
  minimal,

  /// Paused: inference stopped due to critical thermal/memory pressure.
  paused,
}

/// QoS knob values for a given [QoSLevel].
///
/// These control the vision inference pipeline:
/// - [maxFps]: maximum frames per second to process
/// - [resolution]: target image dimension (shorter side) before encoding
/// - [maxTokens]: maximum tokens for the LLM to generate per frame
class QoSKnobs {
  /// Maximum frames per second to process. 0 means paused.
  final int maxFps;

  /// Target image resolution (shorter side in pixels). 0 means no inference.
  final int resolution;

  /// Maximum tokens for LLM generation per frame. 0 means no inference.
  final int maxTokens;

  const QoSKnobs({
    required this.maxFps,
    required this.resolution,
    required this.maxTokens,
  });

  @override
  String toString() =>
      'QoSKnobs(maxFps=$maxFps, resolution=$resolution, maxTokens=$maxTokens)';
}

/// Runtime policy that adapts vision inference QoS based on thermal,
/// battery, and memory pressure signals.
///
/// Implements hysteresis inspired by the TAPAS paper (arxiv 2501.02600):
/// - **Escalation** (quality degradation) is **immediate** when pressure is
///   detected. Thermal spikes and memory pressure are dangerous and must be
///   responded to without delay.
/// - **Restoration** (quality improvement) requires a **cooldown period** and
///   happens **one level at a time**. This prevents oscillation where the
///   system rapidly alternates between high and low quality.
///
/// QoS levels and their knob mappings:
/// - [QoSLevel.full]:    2 FPS, 640px, 100 tokens
/// - [QoSLevel.reduced]: 1 FPS, 480px, 75 tokens
/// - [QoSLevel.minimal]: 1 FPS, 320px, 50 tokens
/// - [QoSLevel.paused]:  0 FPS, 0px, 0 tokens (inference stopped)
///
/// Resolution reduction is prioritized over FPS reduction because reducing
/// visual tokens is more effective for lowering compute and energy usage
/// (per SmolVLM paper findings on token compression).
class RuntimePolicy {
  QoSLevel _currentLevel = QoSLevel.full;
  DateTime? _lastEscalation;

  /// Cooldown duration before allowing restoration after an escalation event.
  ///
  /// After any escalation, the policy will not improve QoS for at least this
  /// duration. This prevents rapid oscillation.
  final Duration escalationCooldown;

  /// Minimum time between successive restoration steps.
  ///
  /// When restoring, the policy improves by one level at a time, waiting
  /// at least this duration between each step.
  final Duration restoreCooldown;

  /// Minimum available memory (bytes) below which escalation triggers.
  ///
  /// Uses absolute bytes (from [os_proc_available_memory]) rather than
  /// RSS ratio because iOS jetsam uses absolute available memory thresholds.
  /// Default: 200 MB.
  final int availableMemoryMinBytes;

  /// Creates a [RuntimePolicy] with configurable cooldown and memory thresholds.
  ///
  /// Default values provide conservative hysteresis suitable for sustained
  /// vision sessions on iPhone hardware:
  /// - [escalationCooldown]: 30 seconds before first restore attempt
  /// - [restoreCooldown]: 60 seconds between restore steps
  /// - [availableMemoryMinBytes]: 200 MB threshold for "reduced" level
  RuntimePolicy({
    this.escalationCooldown = const Duration(seconds: 30),
    this.restoreCooldown = const Duration(seconds: 60),
    this.availableMemoryMinBytes = 200 * 1024 * 1024, // 200 MB
  });

  /// The current QoS level.
  QoSLevel get currentLevel => _currentLevel;

  /// The current QoS knob values for the active level.
  QoSKnobs get knobs => _knobsForLevel(_currentLevel);

  /// The timestamp of the last escalation event, or null if never escalated.
  DateTime? get lastEscalation => _lastEscalation;

  /// Evaluate telemetry signals and return the appropriate [QoSLevel].
  ///
  /// Call this periodically (e.g., every 1-2 seconds) with current telemetry
  /// values. The method applies the following priority rules:
  ///
  /// 1. **Critical** (thermal >= 3 OR available memory < 50 MB): paused
  /// 2. **Serious** (thermal >= 2 OR available memory < 100 MB OR battery < 5%): minimal
  /// 3. **Moderate** (thermal >= 1 OR available memory < threshold OR battery < 15% OR low power mode): reduced
  /// 4. **No pressure**: attempt gradual restoration with hysteresis
  ///
  /// Parameters:
  /// - [thermalState]: iOS thermal state (0=nominal, 1=fair, 2=serious, 3=critical).
  ///   Pass -1 if unavailable (treated as nominal).
  /// - [batteryLevel]: Battery level 0.0 to 1.0. Pass -1.0 if unavailable
  ///   (battery checks are skipped).
  /// - [availableMemoryBytes]: Available memory from os_proc_available_memory.
  ///   Pass 0 if unavailable (memory checks are skipped).
  /// - [isLowPowerMode]: Whether iOS Low Power Mode is enabled.
  QoSLevel evaluate({
    required int thermalState,
    required double batteryLevel,
    required int availableMemoryBytes,
    bool isLowPowerMode = false,
  }) {
    // Normalize unavailable values: treat as no-pressure
    final thermal = thermalState < 0 ? 0 : thermalState;
    final battery = batteryLevel < 0 ? 1.0 : batteryLevel;
    final availMem = availableMemoryBytes <= 0
        ? availableMemoryMinBytes + 1 // above threshold = no pressure
        : availableMemoryBytes;

    // --- Determine the level demanded by current pressure ---
    QoSLevel demandedLevel;
    if (thermal >= 3 || availMem < 50 * 1024 * 1024) {
      demandedLevel = QoSLevel.paused;
    } else if (thermal >= 2 ||
        availMem < 100 * 1024 * 1024 ||
        battery < 0.05) {
      demandedLevel = QoSLevel.minimal;
    } else if (thermal >= 1 ||
        availMem < availableMemoryMinBytes ||
        battery < 0.15 ||
        isLowPowerMode) {
      demandedLevel = QoSLevel.reduced;
    } else {
      demandedLevel = QoSLevel.full;
    }

    // --- Apply level transition rules ---

    if (demandedLevel.index >= _currentLevel.index) {
      // Pressure is same or worse: escalate immediately
      return _escalateTo(demandedLevel);
    }

    if (demandedLevel == QoSLevel.full) {
      // No pressure at all: restore gradually with hysteresis to avoid
      // oscillation (e.g. paused→full→paused→full).
      return _attemptRestore();
    }

    // Pressure improved but still present (e.g. Critical→Serious means
    // paused→minimal). De-escalate to the demanded level — the ongoing
    // pressure conditions are themselves the safety mechanism.
    _currentLevel = demandedLevel;
    _lastEscalation = DateTime.now();
    return _currentLevel;
  }

  /// Immediately escalate (degrade) to [target] if it is worse than current.
  ///
  /// If [target] is the same level, refreshes the escalation timestamp
  /// (sustaining the cooldown). If [target] is better than current,
  /// does nothing (restoration requires hysteresis).
  QoSLevel _escalateTo(QoSLevel target) {
    if (target.index > _currentLevel.index) {
      // Degrading to a worse level
      _currentLevel = target;
      _lastEscalation = DateTime.now();
    } else if (target.index == _currentLevel.index) {
      // Same level: refresh escalation time to sustain cooldown
      _lastEscalation = DateTime.now();
    }
    // If target is better than current: do nothing (hysteresis)
    return _currentLevel;
  }

  /// Attempt to restore (improve) by one QoS level.
  ///
  /// Only succeeds if sufficient time has passed since the last escalation.
  /// Restores one level at a time and resets the cooldown timer, so
  /// full restoration from paused -> full takes 3 * [restoreCooldown].
  QoSLevel _attemptRestore() {
    if (_lastEscalation == null) {
      // Never escalated, just go to full
      _currentLevel = QoSLevel.full;
      return _currentLevel;
    }

    final elapsed = DateTime.now().difference(_lastEscalation!);
    if (elapsed >= restoreCooldown) {
      // Restore one level (not all at once)
      final currentIndex = _currentLevel.index;
      if (currentIndex > 0) {
        _currentLevel = QoSLevel.values[currentIndex - 1];
        // Reset cooldown for next restore step
        _lastEscalation = DateTime.now();
      }
    }

    return _currentLevel;
  }

  /// Reset policy to [QoSLevel.full] and clear escalation history.
  ///
  /// Use when starting a new vision session or after the user explicitly
  /// resumes inference.
  void reset() {
    _currentLevel = QoSLevel.full;
    _lastEscalation = null;
  }

  /// Map a [QoSLevel] to its corresponding [QoSKnobs].
  static QoSKnobs _knobsForLevel(QoSLevel level) {
    return switch (level) {
      QoSLevel.full => const QoSKnobs(
          maxFps: 2,
          resolution: 640,
          maxTokens: 100,
        ),
      QoSLevel.reduced => const QoSKnobs(
          maxFps: 1,
          resolution: 480,
          maxTokens: 75,
        ),
      QoSLevel.minimal => const QoSKnobs(
          maxFps: 1,
          resolution: 320,
          maxTokens: 50,
        ),
      QoSLevel.paused => const QoSKnobs(
          maxFps: 0,
          resolution: 0,
          maxTokens: 0,
        ),
    };
  }
}
