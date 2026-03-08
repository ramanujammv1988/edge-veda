import 'dart:io' show Platform;

import 'package:edge_veda/edge_veda.dart';

/// Selects the best already-downloaded model for each modality.
///
/// Priority lists are ordered best-first. The first model whose files are
/// already on disk is returned immediately — no download is triggered.
/// If nothing is found the [fallback] is returned so the caller can decide
/// whether to download it.
///
/// Usage:
/// ```dart
/// final result = await ModelSelector.bestLlm();
/// if (result.needsDownload) {
///   await modelManager.downloadModel(result.model);
/// }
/// final path = await modelManager.getModelPath(result.model.id);
/// ```
class ModelSelector {
  const ModelSelector._();

  // ── LLM / Chat ─────────────────────────────────────────────────────────────

  static List<ModelInfo> get _llmPriority => Platform.isMacOS
      ? [
          ModelRegistry.llama31_8b,
          ModelRegistry.mistral_nemo_12b,
          ModelRegistry.phi35_mini,
          ModelRegistry.gemma2_2b,
          ModelRegistry.llama32_1b,
          ModelRegistry.qwen3_06b,
          ModelRegistry.tinyLlama,
        ]
      : [
          ModelRegistry.llama32_1b,
          ModelRegistry.gemma2_2b,
          ModelRegistry.phi35_mini,
          ModelRegistry.qwen3_06b,
          ModelRegistry.tinyLlama,
        ];

  static Future<ModelSelection> bestLlm([ModelManager? mm]) =>
      _pick(_llmPriority, fallback: ModelRegistry.llama32_1b, mm: mm);

  // ── Vision (VLM + mmproj) ──────────────────────────────────────────────────

  static List<ModelInfo> get _visionPriority => Platform.isMacOS
      ? [
          ModelRegistry.qwen2vl_7b,
          ModelRegistry.llava16_mistral_7b,
          ModelRegistry.smolvlm2_500m,
          ModelRegistry.smolvlm2_256m,
        ]
      : [
          ModelRegistry.smolvlm2_256m,
          ModelRegistry.smolvlm2_500m,
        ];

  static Future<ModelSelection> bestVision([ModelManager? mm]) =>
      _pickVision(_visionPriority,
          fallback: ModelRegistry.smolvlm2_500m, mm: mm);

  // ── STT (Whisper) ──────────────────────────────────────────────────────────

  static List<ModelInfo> get _whisperPriority {
    if (Platform.isMacOS) {
      return [
        ModelRegistry.whisperLargeV3,
        ModelRegistry.whisperMedium,
        ModelRegistry.whisperSmall,
        ModelRegistry.whisperBaseEn,
        ModelRegistry.whisperTinyEn,
      ];
    }
    if (Platform.isAndroid) {
      // Device-tier aware: on low-end Android (CPU-only), prefer tiny
      // for 2x faster inference. Medium+ devices can handle base.
      final tier = DeviceProfile.detect().tier;
      if (tier.index <= DeviceTier.low.index) {
        return [
          ModelRegistry.whisperTinyEn,
          ModelRegistry.whisperBaseEn,
        ];
      }
      // medium+ Android: unchanged
      return [
        ModelRegistry.whisperBaseEn,
        ModelRegistry.whisperTinyEn,
        ModelRegistry.whisperSmall,
      ];
    }
    // iOS
    return [
      ModelRegistry.whisperBaseEn,
      ModelRegistry.whisperTinyEn,
      ModelRegistry.whisperSmall,
    ];
  }

  static Future<ModelSelection> bestWhisper([ModelManager? mm]) =>
      _pick(_whisperPriority, fallback: ModelRegistry.whisperTinyEn, mm: mm);

  // ── Image Generation ───────────────────────────────────────────────────────

  static List<ModelInfo> get _imagePriority => Platform.isMacOS
      ? [
          ModelRegistry.flux1Schnell,
          ModelRegistry.sdxlTurbo,
          ModelRegistry.sdV21Turbo,
        ]
      : [
          ModelRegistry.sdV21Turbo,
        ];

  static Future<ModelSelection> bestImageGen([ModelManager? mm]) =>
      _pick(_imagePriority, fallback: ModelRegistry.sdV21Turbo, mm: mm);

  // ── Embeddings ─────────────────────────────────────────────────────────────

  static List<ModelInfo> get _embeddingPriority => Platform.isMacOS
      ? [
          ModelRegistry.mxbaiEmbedLarge,
          ModelRegistry.nomicEmbedText,
          ModelRegistry.allMiniLmL6V2,
        ]
      : [
          ModelRegistry.allMiniLmL6V2,
          ModelRegistry.nomicEmbedText,
        ];

  static Future<ModelSelection> bestEmbedding([ModelManager? mm]) =>
      _pick(_embeddingPriority, fallback: ModelRegistry.allMiniLmL6V2, mm: mm);

  // ── Internal helpers ───────────────────────────────────────────────────────

  /// Scan [candidates] and return the first one that is already on disk.
  /// Falls back to [fallback] (marked needsDownload=true) if none found.
  static Future<ModelSelection> _pick(
    List<ModelInfo> candidates, {
    required ModelInfo fallback,
    ModelManager? mm,
  }) async {
    final mgr = mm ?? ModelManager();
    for (final candidate in candidates) {
      if (await mgr.isModelDownloaded(candidate.id)) {
        return ModelSelection(model: candidate, needsDownload: false);
      }
    }
    return ModelSelection(model: fallback, needsDownload: true);
  }

  /// Like [_pick] but also checks that the matching mmproj is available.
  static Future<ModelSelection> _pickVision(
    List<ModelInfo> candidates, {
    required ModelInfo fallback,
    ModelManager? mm,
  }) async {
    final mgr = mm ?? ModelManager();
    for (final candidate in candidates) {
      final mmproj = ModelRegistry.getMmprojForModel(candidate.id);
      final modelReady = await mgr.isModelDownloaded(candidate.id);
      final mmprojReady =
          mmproj == null || await mgr.isModelDownloaded(mmproj.id);
      if (modelReady && mmprojReady) {
        return ModelSelection(
          model: candidate,
          mmproj: mmproj,
          needsDownload: false,
        );
      }
    }
    return ModelSelection(
      model: fallback,
      mmproj: ModelRegistry.getMmprojForModel(fallback.id),
      needsDownload: true,
    );
  }
}

/// Result of a [ModelSelector] query.
class ModelSelection {
  final ModelInfo model;

  /// Non-null for vision models that need a multimodal projector.
  final ModelInfo? mmproj;

  /// True when neither the model nor the mmproj is on disk yet.
  /// The caller should download [model] (and [mmproj] if non-null)
  /// before attempting inference.
  final bool needsDownload;

  const ModelSelection({
    required this.model,
    this.mmproj,
    required this.needsDownload,
  });
}
