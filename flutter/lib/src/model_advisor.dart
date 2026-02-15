/// Device-aware model recommendation engine for Edge Veda SDK
///
/// Provides device profiling (via sysctlbyname FFI), memory estimation
/// with calibrated formulas, and 4-dimensional model scoring with
/// use-case weighted recommendations.
library;

import 'dart:ffi' as ffi;
import 'dart:io' show Platform;
import 'dart:math' show log, min, max;

import 'package:ffi/ffi.dart';

import 'types.dart';
import 'model_manager.dart';
import 'telemetry_service.dart';
import 'edge_veda_impl.dart';

// ── FFI Typedefs ──────────────────────────────────────────────────────────

typedef _SysctlByNameC = ffi.Int Function(
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Size>,
  ffi.Pointer<ffi.Void>,
  ffi.Size,
);
typedef _SysctlByNameDart = int Function(
  ffi.Pointer<ffi.Char>,
  ffi.Pointer<ffi.Void>,
  ffi.Pointer<ffi.Size>,
  ffi.Pointer<ffi.Void>,
  int,
);

// ── Enums ─────────────────────────────────────────────────────────────────

/// Device capability tier based on RAM and chip generation
enum DeviceTier {
  minimum, // 4 GB, A14/A15
  low, // 6 GB, A14/A15
  medium, // 6 GB, A16
  high, // 8 GB, A17 Pro/A18/A18 Pro/A19
  ultra, // 12 GB, A19 Pro
}

/// Use case for model recommendation
enum UseCase {
  chat,
  reasoning,
  toolCalling,
  vision,
  stt,
  embedding,
  fast,
}

// ── DeviceProfile ─────────────────────────────────────────────────────────

/// Device hardware profile detected via sysctlbyname FFI
///
/// Provides sync, cached device identification for model recommendations.
/// Uses hw.machine identifier to look up chip, RAM, and tier from a
/// built-in database of 27 iPhone models (iPhone 12 through iPhone 17).
class DeviceProfile {
  /// Raw hw.machine identifier (e.g., "iPhone17,1")
  final String identifier;

  /// Human-readable device name (e.g., "iPhone 16 Pro")
  final String deviceName;

  /// Total device RAM in GB
  final double totalRamGB;

  /// Apple chip name (e.g., "A18 Pro")
  final String chipName;

  /// Device capability tier
  final DeviceTier tier;

  const DeviceProfile({
    required this.identifier,
    required this.deviceName,
    required this.totalRamGB,
    required this.chipName,
    required this.tier,
  });

  /// Safe memory budget in MB (60% of total RAM)
  int get safeMemoryBudgetMB => (totalRamGB * 1024 * 0.60).round();

  // ── Detection (sync, cached) ──

  static DeviceProfile? _cached;

  static final _sysctlbyname = ffi.DynamicLibrary.process()
      .lookupFunction<_SysctlByNameC, _SysctlByNameDart>('sysctlbyname');

  /// Detect current device hardware profile.
  ///
  /// Sync call, cached after first invocation. On simulator or unknown
  /// hardware, falls back to RAM-based tier detection via hw.memsize.
  static DeviceProfile detect() {
    if (_cached != null) return _cached!;

    String identifier;
    try {
      identifier = _readString('hw.machine');
    } catch (_) {
      identifier = Platform.operatingSystem;
    }

    final entry = _deviceDb[identifier];
    if (entry != null) {
      _cached = DeviceProfile(
        identifier: identifier,
        deviceName: entry.$1,
        totalRamGB: entry.$2,
        chipName: entry.$3,
        tier: entry.$4,
      );
      return _cached!;
    }

    // Simulator or unknown device -- fall back to RAM-based tier
    double ramGB;
    try {
      ramGB = _readInt64('hw.memsize') / (1024 * 1024 * 1024);
    } catch (_) {
      ramGB = 4;
    }

    final tier = ramGB < 6
        ? DeviceTier.minimum
        : ramGB < 8
            ? DeviceTier.low
            : ramGB < 10
                ? DeviceTier.medium
                : ramGB < 16
                    ? DeviceTier.high
                    : DeviceTier.ultra;

    _cached = DeviceProfile(
      identifier: identifier,
      deviceName: identifier,
      totalRamGB: ramGB,
      chipName: 'Unknown',
      tier: tier,
    );
    return _cached!;
  }

  // ── FFI Helpers ──

  static String _readString(String name) {
    final namePtr = name.toNativeUtf8();
    final sizePtr = calloc<ffi.Size>();
    try {
      _sysctlbyname(namePtr.cast(), ffi.nullptr, sizePtr, ffi.nullptr, 0);
      final bufLen = sizePtr.value;
      if (bufLen == 0) return 'Unknown';

      final buf = calloc<ffi.Uint8>(bufLen);
      try {
        _sysctlbyname(namePtr.cast(), buf.cast(), sizePtr, ffi.nullptr, 0);
        return buf.cast<Utf8>().toDartString();
      } finally {
        calloc.free(buf);
      }
    } finally {
      calloc.free(sizePtr);
      calloc.free(namePtr);
    }
  }

  static int _readInt64(String name) {
    final namePtr = name.toNativeUtf8();
    final sizePtr = calloc<ffi.Size>();
    final valPtr = calloc<ffi.Int64>();
    try {
      sizePtr.value = ffi.sizeOf<ffi.Int64>();
      _sysctlbyname(namePtr.cast(), valPtr.cast(), sizePtr, ffi.nullptr, 0);
      return valPtr.value;
    } finally {
      calloc.free(valPtr);
      calloc.free(sizePtr);
      calloc.free(namePtr);
    }
  }

  // ── Device Database (27 entries: iPhone 12 through iPhone 17 series) ──

  /// hw.machine -> (Device Name, RAM GB, Chip, DeviceTier)
  static const Map<String, (String, double, String, DeviceTier)> _deviceDb = {
    // iPhone 12 series (2020) - A14 Bionic
    'iPhone13,1': ('iPhone 12 mini', 4, 'A14 Bionic', DeviceTier.minimum),
    'iPhone13,2': ('iPhone 12', 4, 'A14 Bionic', DeviceTier.minimum),
    'iPhone13,3': ('iPhone 12 Pro', 6, 'A14 Bionic', DeviceTier.low),
    'iPhone13,4': ('iPhone 12 Pro Max', 6, 'A14 Bionic', DeviceTier.low),

    // iPhone 13 series (2021) - A15 Bionic
    'iPhone14,4': ('iPhone 13 mini', 4, 'A15 Bionic', DeviceTier.minimum),
    'iPhone14,5': ('iPhone 13', 4, 'A15 Bionic', DeviceTier.minimum),
    'iPhone14,2': ('iPhone 13 Pro', 6, 'A15 Bionic', DeviceTier.low),
    'iPhone14,3': ('iPhone 13 Pro Max', 6, 'A15 Bionic', DeviceTier.low),

    // iPhone SE 3rd gen (2022) - A15 Bionic
    'iPhone14,6': ('iPhone SE (3rd gen)', 4, 'A15 Bionic', DeviceTier.minimum),

    // iPhone 14 series (2022) - A15/A16 Bionic
    'iPhone14,7': ('iPhone 14', 6, 'A15 Bionic', DeviceTier.low),
    'iPhone14,8': ('iPhone 14 Plus', 6, 'A15 Bionic', DeviceTier.low),
    'iPhone15,2': ('iPhone 14 Pro', 6, 'A16 Bionic', DeviceTier.medium),
    'iPhone15,3': ('iPhone 14 Pro Max', 6, 'A16 Bionic', DeviceTier.medium),

    // iPhone 15 series (2023) - A16/A17 Pro
    'iPhone15,4': ('iPhone 15', 6, 'A16 Bionic', DeviceTier.medium),
    'iPhone15,5': ('iPhone 15 Plus', 6, 'A16 Bionic', DeviceTier.medium),
    'iPhone16,1': ('iPhone 15 Pro', 8, 'A17 Pro', DeviceTier.high),
    'iPhone16,2': ('iPhone 15 Pro Max', 8, 'A17 Pro', DeviceTier.high),

    // iPhone 16 series (2024) - A18/A18 Pro
    'iPhone17,3': ('iPhone 16', 8, 'A18', DeviceTier.high),
    'iPhone17,4': ('iPhone 16 Plus', 8, 'A18', DeviceTier.high),
    'iPhone17,1': ('iPhone 16 Pro', 8, 'A18 Pro', DeviceTier.high),
    'iPhone17,2': ('iPhone 16 Pro Max', 8, 'A18 Pro', DeviceTier.high),

    // iPhone 16e / SE 4th gen (2025) - A18
    'iPhone17,5': ('iPhone 16e', 8, 'A18', DeviceTier.high),

    // iPhone 17 series (2025) - A19/A19 Pro
    'iPhone18,3': ('iPhone 17', 8, 'A19', DeviceTier.high),
    'iPhone18,4': ('iPhone Air', 8, 'A19', DeviceTier.high),
    'iPhone18,1': ('iPhone 17 Pro', 12, 'A19 Pro', DeviceTier.ultra),
    'iPhone18,2': ('iPhone 17 Pro Max', 12, 'A19 Pro', DeviceTier.ultra),
  };

  @override
  String toString() =>
      'DeviceProfile($deviceName, ${totalRamGB}GB, $chipName, $tier)';
}

// ── MemoryEstimate ────────────────────────────────────────────────────────

/// Detailed memory usage estimate for a model on a specific device
class MemoryEstimate {
  final int totalMB;
  final int modelWeightsMB;
  final int kvCacheMB;
  final int metalBuffersMB;
  final int runtimeOverheadMB;

  /// Ratio of estimated memory to device safe budget (>1.0 means won't fit)
  final double memoryRatio;

  /// Whether the model fits within the device's safe memory budget
  final bool fits;

  const MemoryEstimate({
    required this.totalMB,
    required this.modelWeightsMB,
    required this.kvCacheMB,
    required this.metalBuffersMB,
    required this.runtimeOverheadMB,
    required this.memoryRatio,
    required this.fits,
  });

  @override
  String toString() =>
      'MemoryEstimate(${totalMB}MB, ratio: ${memoryRatio.toStringAsFixed(2)}, fits: $fits)';
}

// ── MemoryEstimator ───────────────────────────────────────────────────────

/// Estimates model memory usage using calibrated formulas
///
/// Calibrated against real-world Phase 19 measurements: Llama 3.2 1B Q4_K_M
/// uses 400-550MB RSS on iPhone with KV cache Q8_0 at context 2048.
class MemoryEstimator {
  /// Estimate total memory usage for a model on a device
  ///
  /// For whisper/minilm families (non-LLM): simpler formula (file size + 100MB).
  /// For LLM/VLM models: calibrated formula with 1.3x safety multiplier.
  static MemoryEstimate estimate({
    required ModelInfo model,
    required DeviceProfile device,
    int contextLength = 2048,
  }) {
    final family = model.family ?? '';

    // Non-LLM models: simpler formula
    if (family == 'whisper' || family == 'minilm') {
      final totalMB = (model.sizeBytes / (1024 * 1024) + 100).round();
      final ratio = totalMB / device.safeMemoryBudgetMB;
      return MemoryEstimate(
        totalMB: totalMB,
        modelWeightsMB: (model.sizeBytes / (1024 * 1024)).round(),
        kvCacheMB: 0,
        metalBuffersMB: 0,
        runtimeOverheadMB: 100,
        memoryRatio: ratio,
        fits: ratio <= 1.0,
      );
    }

    // LLM/VLM models: calibrated formula from research
    final modelWeightsMB = (model.sizeBytes * 0.15 / (1024 * 1024)).round();

    // KV cache quantization factor
    final kvQuantFactor = model.quantization == 'F16' ? 2.0 : 1.0;
    final kvCacheMB = ((model.parametersB ?? 1.0) *
            4.0 *
            (contextLength / 2048) *
            kvQuantFactor)
        .round();

    final metalBuffersMB = ((model.parametersB ?? 1.0) * 80).round();
    const runtimeOverheadMB = 150;

    final rawTotal =
        modelWeightsMB + kvCacheMB + metalBuffersMB + runtimeOverheadMB;
    final totalMB = (rawTotal * 1.3).round(); // 1.3x safety multiplier

    final ratio = totalMB / device.safeMemoryBudgetMB;
    return MemoryEstimate(
      totalMB: totalMB,
      modelWeightsMB: modelWeightsMB,
      kvCacheMB: kvCacheMB,
      metalBuffersMB: metalBuffersMB,
      runtimeOverheadMB: runtimeOverheadMB,
      memoryRatio: ratio,
      fits: ratio <= 1.0,
    );
  }
}

// ── ModelScore ────────────────────────────────────────────────────────────

/// Composite score for a model on a specific device and use case
class ModelScore {
  final ModelInfo model;
  final int fitScore;
  final int qualityScore;
  final int speedScore;
  final int contextScore;
  final int finalScore;
  final MemoryEstimate memoryEstimate;
  final bool fits;
  final EdgeVedaConfig recommendedConfig;
  final String? warning;

  const ModelScore({
    required this.model,
    required this.fitScore,
    required this.qualityScore,
    required this.speedScore,
    required this.contextScore,
    required this.finalScore,
    required this.memoryEstimate,
    required this.fits,
    required this.recommendedConfig,
    this.warning,
  });

  @override
  String toString() =>
      'ModelScore(${model.name}, score: $finalScore, fits: $fits)';
}

// ── ModelRecommendation ───────────────────────────────────────────────────

/// Ranked list of model recommendations for a device and use case
class ModelRecommendation {
  /// All models ranked by final score (descending), including non-fitting
  final List<ModelScore> ranked;

  /// Best fitting model (first entry where fits == true), or null
  final ModelScore? bestMatch;

  /// Device the recommendation was generated for
  final DeviceProfile device;

  /// Use case the recommendation was generated for
  final UseCase useCase;

  const ModelRecommendation({
    required this.ranked,
    this.bestMatch,
    required this.device,
    required this.useCase,
  });
}

// ── StorageCheck ──────────────────────────────────────────────────────────

/// Result of a storage availability check for a model download
class StorageCheck {
  /// Free disk space in bytes (-1 if unavailable)
  final int freeDiskBytes;

  /// Model file size in bytes
  final int requiredBytes;

  /// Whether there is sufficient free space
  final bool hasSufficientSpace;

  /// Human-readable warning message, or null if OK
  final String? warning;

  const StorageCheck({
    required this.freeDiskBytes,
    required this.requiredBytes,
    required this.hasSufficientSpace,
    this.warning,
  });

  @override
  String toString() =>
      'StorageCheck(free: ${(freeDiskBytes / (1024 * 1024)).round()}MB, '
      'required: ${(requiredBytes / (1024 * 1024)).round()}MB, ok: $hasSufficientSpace)';
}

// ── MemoryValidation ─────────────────────────────────────────────────────

/// Result of real-time memory validation after model load
class MemoryValidation {
  /// Current memory usage percentage (0.0 - 1.0)
  final double usagePercent;

  /// Whether memory pressure is detected (>80%)
  final bool isHighPressure;

  /// Whether memory usage is critical (>90%)
  final bool isCritical;

  /// Human-readable status message
  final String status;

  /// Human-readable warning, or null if healthy
  final String? warning;

  const MemoryValidation({
    required this.usagePercent,
    required this.isHighPressure,
    required this.isCritical,
    required this.status,
    this.warning,
  });

  @override
  String toString() =>
      'MemoryValidation(${(usagePercent * 100).toStringAsFixed(1)}%, '
      'status: $status)';
}

// ── ModelAdvisor ──────────────────────────────────────────────────────────

/// Device-aware model recommendation engine with 4D scoring
///
/// Scores models across four dimensions (fit, quality, speed, context)
/// weighted by use case, and generates optimal EdgeVedaConfig for each.
class ModelAdvisor {
  // ── Scoring Constants ──

  static const _familyBaseScores = <String, int>{
    'llama3': 78,
    'phi3': 82,
    'gemma2': 72,
    'qwen3': 70,
    'tinyllama': 55,
    'smolvlm': 65,
    'whisper': 70,
    'minilm': 70,
  };

  static const _chipMultipliers = <String, double>{
    'A14 Bionic': 0.6,
    'A15 Bionic': 0.7,
    'A16 Bionic': 0.8,
    'A17 Pro': 1.0,
    'A18': 1.1,
    'A18 Pro': 1.2,
    'A19': 1.2,
    'A19 Pro': 1.4,
  };

  static const _quantSpeedMultipliers = <String, double>{
    'Q4_K_M': 1.15,
    'Q8_0': 0.85,
    'F16': 0.6,
  };

  static const _useCaseTargetContext = <UseCase, int>{
    UseCase.chat: 4096,
    UseCase.reasoning: 8192,
    UseCase.toolCalling: 4096,
    UseCase.vision: 2048,
    UseCase.stt: 512,
    UseCase.embedding: 512,
    UseCase.fast: 2048,
  };

  static const _weights = <UseCase, ({double q, double s, double f, double c})>{
    UseCase.chat: (q: 0.35, s: 0.30, f: 0.25, c: 0.10),
    UseCase.reasoning: (q: 0.50, s: 0.15, f: 0.25, c: 0.10),
    UseCase.toolCalling: (q: 0.40, s: 0.25, f: 0.25, c: 0.10),
    UseCase.vision: (q: 0.35, s: 0.25, f: 0.30, c: 0.10),
    UseCase.stt: (q: 0.30, s: 0.40, f: 0.25, c: 0.05),
    UseCase.embedding: (q: 0.25, s: 0.40, f: 0.30, c: 0.05),
    UseCase.fast: (q: 0.20, s: 0.50, f: 0.25, c: 0.05),
  };

  /// Score a single model for a device and use case
  ///
  /// Returns a [ModelScore] with per-dimension breakdown, composite score,
  /// memory estimate, and an optimal [EdgeVedaConfig].
  static ModelScore score({
    required ModelInfo model,
    required DeviceProfile device,
    required UseCase useCase,
  }) {
    final targetCtx = _useCaseTargetContext[useCase] ?? 4096;

    // ── Fit Score ──
    final estimate = MemoryEstimator.estimate(
      model: model,
      device: device,
      contextLength: targetCtx,
    );
    final memRatio = estimate.memoryRatio;
    final fitScore = memRatio <= 0.50
        ? 100
        : memRatio <= 0.70
            ? 85
            : memRatio <= 0.85
                ? 60
                : memRatio <= 1.00
                    ? 30
                    : 0;

    // ── Quality Score ──
    final baseQuality = _familyBaseScores[model.family] ?? 50;
    final paramBonus =
        min(15, (log(max(model.parametersB ?? 0.1, 0.1)) / log(2)) * 5)
            .round();
    final quantPenalty = model.quantization == 'Q4_K_M' ? -3 : 0;
    final taskBonus = (model.capabilities ?? [])
            .contains(_requiredCapability(useCase))
        ? 10
        : 0;
    final qualityScore =
        (baseQuality + paramBonus + quantPenalty + taskBonus).clamp(0, 100);

    // ── Speed Score ──
    final baseTokPerSec = 160.0 / max(model.parametersB ?? 1.0, 0.1);
    final chipMult = _chipMultipliers[device.chipName] ?? 0.8;
    final quantMult = _quantSpeedMultipliers[model.quantization] ?? 1.0;
    final estimatedTps = baseTokPerSec * chipMult * quantMult;
    final speedScore = (estimatedTps * 2.0).round().clamp(0, 100);

    // ── Context Score ──
    final maxCtx = model.maxContextLength ?? 2048;
    final contextScore = maxCtx >= targetCtx * 2
        ? 100
        : maxCtx >= targetCtx
            ? 80
            : maxCtx >= targetCtx ~/ 2
                ? 50
                : 20;

    // ── Final Score ──
    final w = _weights[useCase]!;
    final finalScore = (qualityScore * w.q +
            speedScore * w.s +
            fitScore * w.f +
            contextScore * w.c)
        .round();

    // ── Warning ──
    String? warning;
    if (memRatio > 1.0) {
      warning = 'Exceeds device memory budget';
    } else if (memRatio > 0.85) {
      warning = 'Tight fit, may cause jetsam on heavy usage';
    }

    // ── Recommended Config ──
    final config = _recommendedConfig(model, device, useCase);

    return ModelScore(
      model: model,
      fitScore: fitScore,
      qualityScore: qualityScore,
      speedScore: speedScore,
      contextScore: contextScore,
      finalScore: finalScore,
      memoryEstimate: estimate,
      fits: estimate.fits,
      recommendedConfig: config,
      warning: warning,
    );
  }

  /// Generate ranked model recommendations for a device and use case
  ///
  /// Returns ALL models (including those that don't fit) sorted by
  /// final score descending. Non-fitting models have fits: false.
  static ModelRecommendation recommend({
    required DeviceProfile device,
    required UseCase useCase,
    List<ModelInfo>? models,
  }) {
    // Collect all unique models (exclude mmproj)
    final allModels = models ??
        <ModelInfo>{
          ...ModelRegistry.getAllModels(),
          ...ModelRegistry.getVisionModels(),
          ...ModelRegistry.getWhisperModels(),
          ...ModelRegistry.getEmbeddingModels(),
        }.toList();

    final scores = <ModelScore>[];
    for (final model in allModels) {
      scores.add(score(model: model, device: device, useCase: useCase));
    }

    scores.sort((a, b) => b.finalScore.compareTo(a.finalScore));

    ModelScore? bestMatch;
    for (final s in scores) {
      if (s.fits) {
        bestMatch = s;
        break;
      }
    }

    return ModelRecommendation(
      ranked: scores,
      bestMatch: bestMatch,
      device: device,
      useCase: useCase,
    );
  }

  /// Quick boolean check: can this device run a given model for a use case?
  ///
  /// Wraps [score()] and returns true if the model fits within the device's
  /// memory budget. No network or async calls -- purely local estimation.
  static bool canRun({
    required ModelInfo model,
    UseCase useCase = UseCase.chat,
    DeviceProfile? device,
  }) {
    final d = device ?? DeviceProfile.detect();
    final result = score(model: model, device: d, useCase: useCase);
    return result.fits;
  }

  /// Check if there is sufficient free disk space to download a model.
  ///
  /// Uses NSFileManager (iOS) via MethodChannel to query real free space.
  /// Includes a 100MB buffer beyond model size to account for extraction
  /// and temp files. Returns [StorageCheck] with warning if insufficient.
  ///
  /// On non-iOS platforms or when disk space query fails, returns
  /// hasSufficientSpace: true with freeDiskBytes: -1 (optimistic fallback).
  static Future<StorageCheck> checkStorageAvailability({
    required ModelInfo model,
  }) async {
    final telemetry = TelemetryService();
    final freeBytes = await telemetry.getFreeDiskSpace();

    if (freeBytes < 0) {
      // Can't determine free space -- optimistic fallback
      return StorageCheck(
        freeDiskBytes: -1,
        requiredBytes: model.sizeBytes,
        hasSufficientSpace: true,
        warning: null,
      );
    }

    // Require model size + 100MB buffer for temp files
    const bufferBytes = 100 * 1024 * 1024;
    final requiredWithBuffer = model.sizeBytes + bufferBytes;
    final sufficient = freeBytes >= requiredWithBuffer;

    String? warning;
    if (!sufficient) {
      final freeMB = (freeBytes / (1024 * 1024)).round();
      final requiredMB = (model.sizeBytes / (1024 * 1024)).round();
      warning = 'Insufficient storage: ${freeMB}MB free, '
          '${requiredMB}MB required for ${model.name}';
    } else if (freeBytes < requiredWithBuffer * 2) {
      // Warn if space is tight (less than 2x required)
      final freeMB = (freeBytes / (1024 * 1024)).round();
      warning = 'Low storage: ${freeMB}MB free after download';
    }

    return StorageCheck(
      freeDiskBytes: freeBytes,
      requiredBytes: model.sizeBytes,
      hasSufficientSpace: sufficient,
      warning: warning,
    );
  }

  /// Validate actual memory pressure after a model has been loaded.
  ///
  /// Uses [EdgeVeda.getMemoryStats()] (routed through StreamingWorker)
  /// to read real memory usage. Call this after [EdgeVeda.init()] to
  /// verify the model loaded within safe memory bounds.
  ///
  /// Requires an initialized [EdgeVeda] instance. If no worker is active,
  /// returns healthy status (model not yet loaded = no pressure).
  static Future<MemoryValidation> validateMemoryAfterLoad(
      EdgeVeda edgeVeda) async {
    final stats = await edgeVeda.getMemoryStats();

    if (stats.currentBytes == 0) {
      return const MemoryValidation(
        usagePercent: 0,
        isHighPressure: false,
        isCritical: false,
        status: 'No model loaded',
      );
    }

    final percent = stats.usagePercent;
    final currentMB = (stats.currentBytes / (1024 * 1024)).round();
    final limitMB = (stats.limitBytes / (1024 * 1024)).round();

    String status;
    String? warning;

    if (stats.isCritical) {
      status = 'Critical';
      warning = 'Memory usage critical: ${currentMB}MB / ${limitMB}MB '
          '(${(percent * 100).toStringAsFixed(0)}%). '
          'Risk of jetsam termination. Consider reducing context size or using a smaller model.';
    } else if (stats.isHighPressure) {
      status = 'Warning';
      warning = 'High memory pressure: ${currentMB}MB / ${limitMB}MB '
          '(${(percent * 100).toStringAsFixed(0)}%). '
          'May experience jetsam under heavy usage.';
    } else if (percent > 0.6) {
      status = 'Moderate';
      warning =
          'Memory usage moderate: ${currentMB}MB / ${limitMB}MB. Stable for normal use.';
    } else {
      status = 'Healthy';
    }

    return MemoryValidation(
      usagePercent: percent,
      isHighPressure: stats.isHighPressure,
      isCritical: stats.isCritical,
      status: status,
      warning: warning,
    );
  }

  // ── Helpers ──

  static String _requiredCapability(UseCase useCase) {
    switch (useCase) {
      case UseCase.chat:
        return 'chat';
      case UseCase.reasoning:
        return 'reasoning';
      case UseCase.toolCalling:
        return 'tool-calling';
      case UseCase.vision:
        return 'vision';
      case UseCase.stt:
        return 'stt';
      case UseCase.embedding:
        return 'embedding';
      case UseCase.fast:
        return 'chat';
    }
  }

  static EdgeVedaConfig _recommendedConfig(
    ModelInfo model,
    DeviceProfile device,
    UseCase useCase,
  ) {
    final targetCtx = _useCaseTargetContext[useCase] ?? 4096;
    var contextLength = min(targetCtx, model.maxContextLength ?? 2048);
    if (device.tier == DeviceTier.minimum) {
      contextLength = min(contextLength, 1024);
    }
    if (device.tier == DeviceTier.low) {
      contextLength = min(contextLength, 2048);
    }
    final threads = device.tier.index >= DeviceTier.high.index ? 6 : 4;
    final maxMemoryMb = (device.totalRamGB * 1024 * 0.6).round();

    return EdgeVedaConfig(
      modelPath: '',
      numThreads: threads,
      contextLength: contextLength,
      useGpu: true,
      maxMemoryMb: maxMemoryMb,
      kvCacheTypeK: 8,
      kvCacheTypeV: 8,
      flashAttn: -1,
    );
  }
}
