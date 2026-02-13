/// Model download and management for Edge Veda SDK
library;

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'types.dart';

/// Manages model downloads, caching, and verification
class ModelManager {
  static const String _modelsCacheDir = 'edge_veda_models';
  static const String _metadataFileName = 'metadata.json';
  static const int _maxRetries = 3;
  static const Duration _initialRetryDelay = Duration(seconds: 1);

  final StreamController<DownloadProgress> _progressController =
      StreamController<DownloadProgress>.broadcast();

  /// Current active download cancel token (if any)
  CancelToken? _currentDownloadToken;

  /// Stream of download progress updates
  Stream<DownloadProgress> get downloadProgress => _progressController.stream;

  /// Cancel the current download (if any)
  void cancelDownload() {
    _currentDownloadToken?.cancel();
  }

  /// Get the models directory path
  ///
  /// Uses [getApplicationSupportDirectory] which maps to:
  /// - iOS: ~/Library/Application Support/ (excluded from iCloud backup)
  /// - Android: /data/data/<package>/files/ (internal, persists across updates)
  ///
  /// This directory is NOT cleared when the user clears cache,
  /// ensuring models survive between app sessions and process kills.
  /// Models are only removed on app uninstall.
  Future<Directory> getModelsDirectory() async {
    final appDir = await getApplicationSupportDirectory();
    final modelsDir = Directory(path.join(appDir.path, _modelsCacheDir));

    if (!await modelsDir.exists()) {
      await modelsDir.create(recursive: true);
    }

    return modelsDir;
  }

  /// Get path for a specific model file.
  ///
  /// Whisper models use .bin extension, all other models use .gguf.
  /// Using modelId prefix is safer than format field to avoid breaking
  /// existing models if format metadata is ever inconsistent.
  Future<String> getModelPath(String modelId) async {
    final modelsDir = await getModelsDirectory();
    final ext = modelId.startsWith('whisper-') ? 'bin' : 'gguf';
    return path.join(modelsDir.path, '$modelId.$ext');
  }

  /// Check if a model is already downloaded
  Future<bool> isModelDownloaded(String modelId) async {
    final modelPath = await getModelPath(modelId);
    return File(modelPath).exists();
  }

  /// Get downloaded model file size
  Future<int?> getModelSize(String modelId) async {
    final modelPath = await getModelPath(modelId);
    final file = File(modelPath);
    if (await file.exists()) {
      return await file.length();
    }
    return null;
  }

  /// Download a model with progress tracking
  ///
  /// Downloads to a temporary file first, verifies checksum, then atomically
  /// renames to final location. This ensures no corrupt files are left if
  /// download is interrupted.
  ///
  /// If a valid cached model exists, returns immediately without re-downloading.
  ///
  /// [cancelToken] can be used to cancel the download mid-stream.
  Future<String> downloadModel(
    ModelInfo model, {
    bool verifyChecksum = true,
    CancelToken? cancelToken,
  }) async {
    final modelPath = await getModelPath(model.id);
    final file = File(modelPath);

    // CHECK CACHE FIRST - skip download if valid model exists (R2.3)
    if (await file.exists()) {
      if (verifyChecksum && model.checksum != null) {
        final isValid = await _verifyChecksum(modelPath, model.checksum!);
        if (isValid) {
          // Valid cached model - skip download entirely
          return modelPath;
        }
        // Invalid checksum - delete and re-download
        await file.delete();
      } else {
        // No checksum to verify - assume cached file is valid
        return modelPath;
      }
    }

    // Store cancel token for external cancellation
    _currentDownloadToken = cancelToken;

    // Attempt download with retries for transient network errors
    return _downloadWithRetry(model, modelPath, verifyChecksum, cancelToken);
  }

  /// Internal download implementation with retry logic
  Future<String> _downloadWithRetry(
    ModelInfo model,
    String modelPath,
    bool verifyChecksum,
    CancelToken? cancelToken,
  ) async {
    int attempt = 0;
    Duration retryDelay = _initialRetryDelay;

    while (true) {
      attempt++;
      try {
        return await _performDownload(model, modelPath, verifyChecksum, cancelToken);
      } on SocketException catch (e) {
        // Transient network error - retry with exponential backoff
        if (attempt >= _maxRetries) {
          throw DownloadException(
            'Failed to download model after $_maxRetries attempts',
            details: 'Network error: ${e.message}',
            originalError: e,
          );
        }
        // Wait before retry (exponential backoff)
        await Future.delayed(retryDelay);
        retryDelay *= 2;
      }
    }
  }

  /// Perform the actual download to temp file with atomic rename
  Future<String> _performDownload(
    ModelInfo model,
    String modelPath,
    bool verifyChecksum,
    CancelToken? cancelToken,
  ) async {
    // Create temporary file for downloading (atomic pattern - Pitfall 12)
    final tempPath = '$modelPath.tmp';
    final tempFile = File(tempPath);

    // Clean up any stale temp file from previous interrupted download
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final client = http.Client();
    IOSink? sink;

    try {
      // Check for cancellation before starting
      if (cancelToken?.isCancelled == true) {
        throw DownloadException('Download cancelled');
      }

      // Start download with progress tracking
      final request = http.Request('GET', Uri.parse(model.downloadUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw DownloadException(
          'Failed to download model',
          details: 'HTTP ${response.statusCode}',
        );
      }

      // Use Content-Length if available, otherwise fall back to model.sizeBytes
      final totalBytes = response.contentLength ?? model.sizeBytes;
      var downloadedBytes = 0;
      var lastReportedBytes = 0; // Guard against progress going backwards
      final startTime = DateTime.now();

      sink = tempFile.openWrite();

      await for (final chunk in response.stream) {
        // Check for cancellation during download
        if (cancelToken?.isCancelled == true) {
          await sink.close();
          await tempFile.delete();
          throw DownloadException('Download cancelled');
        }

        downloadedBytes += chunk.length;
        sink.add(chunk);

        // Only emit progress if it increased (guard against backwards progress)
        if (downloadedBytes > lastReportedBytes) {
          lastReportedBytes = downloadedBytes;

          // Calculate download speed and ETA
          final elapsed = DateTime.now().difference(startTime).inMilliseconds;
          final speed = elapsed > 0 ? (downloadedBytes / elapsed) * 1000 : 0.0;
          final remaining = speed > 0
              ? ((totalBytes - downloadedBytes) / speed).round()
              : null;

          // Emit progress update (0-100%)
          _progressController.add(DownloadProgress(
            totalBytes: totalBytes,
            downloadedBytes: downloadedBytes,
            speedBytesPerSecond: speed,
            estimatedSecondsRemaining: remaining,
          ));
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;

      // Verify checksum BEFORE atomic rename
      if (verifyChecksum && model.checksum != null) {
        final isValid = await _verifyChecksum(tempPath, model.checksum!);
        if (!isValid) {
          await tempFile.delete();
          throw ModelValidationException(
            'SHA256 checksum mismatch',
            details: 'Expected: ${model.checksum}, file may be corrupted',
          );
        }
      }

      // Atomic rename - ensures no corrupt files if interrupted here
      await tempFile.rename(modelPath);

      // Emit final 100% progress after successful rename
      _progressController.add(DownloadProgress(
        totalBytes: totalBytes,
        downloadedBytes: totalBytes,
        speedBytesPerSecond: 0,
        estimatedSecondsRemaining: 0,
      ));

      // Save metadata
      await _saveModelMetadata(model);

      return modelPath;
    } catch (e) {
      // Clean up temp file on error - ensures no corrupt files left
      try {
        if (sink != null) {
          await sink.close();
        }
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {
        // Ignore cleanup errors
      }

      if (e is EdgeVedaException) {
        rethrow;
      }
      throw DownloadException(
        'Failed to download model',
        details: e.toString(),
        originalError: e,
      );
    } finally {
      client.close();
      _currentDownloadToken = null;
    }
  }

  /// Verify file checksum (internal helper)
  Future<bool> _verifyChecksum(String filePath, String expectedChecksum) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return false;
      }

      final digest = await _computeSha256(file);
      return digest.toLowerCase() == expectedChecksum.toLowerCase();
    } catch (e) {
      return false;
    }
  }

  /// Verify model file checksum (SHA-256)
  ///
  /// Returns true if the file exists and its SHA-256 hash matches the expected checksum.
  Future<bool> verifyModelChecksum(String filePath, String expectedChecksum) async {
    return _verifyChecksum(filePath, expectedChecksum);
  }

  /// Compute SHA-256 hash of a file
  Future<String> _computeSha256(File file) async {
    final stream = file.openRead();
    final digest = await sha256.bind(stream).first;
    return digest.toString();
  }

  /// Delete a downloaded model
  Future<void> deleteModel(String modelId) async {
    final modelPath = await getModelPath(modelId);
    final file = File(modelPath);

    if (await file.exists()) {
      await file.delete();
    }

    // Also delete metadata
    await _deleteModelMetadata(modelId);
  }

  /// Get list of all downloaded models.
  ///
  /// Scans for both .gguf (LLM/VLM) and .bin (Whisper) model files.
  Future<List<String>> getDownloadedModels() async {
    final modelsDir = await getModelsDirectory();
    final entities = await modelsDir.list().toList();

    final modelIds = <String>[];
    for (final entity in entities) {
      if (entity is File) {
        final filename = path.basename(entity.path);
        if (filename.endsWith('.gguf')) {
          modelIds.add(filename.substring(0, filename.length - 5));
        } else if (filename.endsWith('.bin')) {
          modelIds.add(filename.substring(0, filename.length - 4));
        }
      }
    }

    return modelIds;
  }

  /// Get total size of all downloaded models.
  ///
  /// Includes both .gguf (LLM/VLM) and .bin (Whisper) model files.
  Future<int> getTotalModelsSize() async {
    final modelsDir = await getModelsDirectory();
    final entities = await modelsDir.list().toList();

    var totalSize = 0;
    for (final entity in entities) {
      if (entity is File) {
        final filename = path.basename(entity.path);
        if (filename.endsWith('.gguf') || filename.endsWith('.bin')) {
          totalSize += await entity.length();
        }
      }
    }

    return totalSize;
  }

  /// Clear all downloaded models
  Future<void> clearAllModels() async {
    final modelsDir = await getModelsDirectory();
    if (await modelsDir.exists()) {
      await modelsDir.delete(recursive: true);
      await modelsDir.create(recursive: true);
    }
  }

  /// Save model metadata to disk
  Future<void> _saveModelMetadata(ModelInfo model) async {
    final modelsDir = await getModelsDirectory();
    final metadataFile = File(path.join(modelsDir.path, '${model.id}_$_metadataFileName'));

    final metadata = {
      'model': model.toJson(),
      'downloadedAt': DateTime.now().toIso8601String(),
    };

    await metadataFile.writeAsString(jsonEncode(metadata));
  }

  /// Delete model metadata
  Future<void> _deleteModelMetadata(String modelId) async {
    final modelsDir = await getModelsDirectory();
    final metadataFile = File(path.join(modelsDir.path, '${modelId}_$_metadataFileName'));

    if (await metadataFile.exists()) {
      await metadataFile.delete();
    }
  }

  /// Get model metadata if available
  Future<ModelInfo?> getModelMetadata(String modelId) async {
    final modelsDir = await getModelsDirectory();
    final metadataFile = File(path.join(modelsDir.path, '${modelId}_$_metadataFileName'));

    if (!await metadataFile.exists()) {
      return null;
    }

    try {
      final content = await metadataFile.readAsString();
      final json = jsonDecode(content) as Map<String, dynamic>;
      return ModelInfo.fromJson(json['model'] as Map<String, dynamic>);
    } catch (e) {
      return null;
    }
  }

  /// Dispose resources
  void dispose() {
    _progressController.close();
  }
}

/// Pre-configured model registry with popular models
class ModelRegistry {
  static const String huggingFaceBaseUrl =
      'https://huggingface.co/models';

  /// Llama 3.2 1B Instruct (Q4_K_M quantization) - Primary model
  static final ModelInfo llama32_1b = ModelInfo(
    id: 'llama-3.2-1b-instruct-q4',
    name: 'Llama 3.2 1B Instruct',
    sizeBytes: 668 * 1024 * 1024, // ~668 MB
    description: 'Fast and efficient instruction-tuned model',
    downloadUrl:
        'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
    format: 'GGUF',
    quantization: 'Q4_K_M',
  );

  /// Phi-3.5 Mini Instruct (Q4_K_M quantization) - Reasoning model
  static final ModelInfo phi35_mini = ModelInfo(
    id: 'phi-3.5-mini-instruct-q4',
    name: 'Phi 3.5 Mini Instruct',
    sizeBytes: 2300 * 1024 * 1024, // ~2.3 GB
    description: 'High-quality reasoning model from Microsoft',
    downloadUrl:
        'https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf',
    format: 'GGUF',
    quantization: 'Q4_K_M',
  );

  /// Gemma 2 2B Instruct (Q4_K_M quantization)
  static final ModelInfo gemma2_2b = ModelInfo(
    id: 'gemma-2-2b-instruct-q4',
    name: 'Gemma 2 2B Instruct',
    sizeBytes: 1600 * 1024 * 1024, // ~1.6 GB
    description: 'Google\'s efficient instruction model',
    downloadUrl:
        'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
    format: 'GGUF',
    quantization: 'Q4_K_M',
  );

  /// TinyLlama 1.1B Chat (Q4_K_M quantization) - Smallest option
  static final ModelInfo tinyLlama = ModelInfo(
    id: 'tinyllama-1.1b-chat-q4',
    name: 'TinyLlama 1.1B Chat',
    sizeBytes: 669 * 1024 * 1024, // ~669 MB
    description: 'Ultra-fast lightweight chat model',
    downloadUrl:
        'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf',
    format: 'GGUF',
    quantization: 'Q4_K_M',
  );

  // === Tool Calling Models ===

  /// Qwen3 0.6B (Q4_K_M) - Tool calling capable model
  static final ModelInfo qwen3_06b = ModelInfo(
    id: 'qwen3-0.6b-q4',
    name: 'Qwen3 0.6B',
    sizeBytes: 524 * 1024 * 1024, // ~524 MB Q4_K_M
    description: 'Compact model with native tool calling support',
    downloadUrl:
        'https://huggingface.co/Mungert/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf',
    format: 'GGUF',
    quantization: 'Q4_K_M',
  );

  // === Vision Language Models ===

  /// SmolVLM2-500M-Video-Instruct (Q8_0) - Vision Language Model
  static final ModelInfo smolvlm2_500m = ModelInfo(
    id: 'smolvlm2-500m-video-instruct-q8',
    name: 'SmolVLM2 500M Video Instruct',
    sizeBytes: 436808704, // ~417 MB
    description: 'Vision + video understanding model for image description',
    downloadUrl:
        'https://huggingface.co/ggml-org/SmolVLM2-500M-Video-Instruct-GGUF/resolve/main/SmolVLM2-500M-Video-Instruct-Q8_0.gguf',
    format: 'GGUF',
    quantization: 'Q8_0',
  );

  /// SmolVLM2-500M mmproj (F16) - Multimodal projector for SmolVLM2
  static final ModelInfo smolvlm2_500m_mmproj = ModelInfo(
    id: 'smolvlm2-500m-mmproj-f16',
    name: 'SmolVLM2 500M Multimodal Projector',
    sizeBytes: 199470624, // ~190 MB
    description: 'Multimodal projector for SmolVLM2 vision model',
    downloadUrl:
        'https://huggingface.co/ggml-org/SmolVLM2-500M-Video-Instruct-GGUF/resolve/main/mmproj-SmolVLM2-500M-Video-Instruct-f16.gguf',
    format: 'GGUF',
    quantization: 'F16',
  );

  // === Whisper Speech-to-Text Models ===

  /// Whisper Tiny English - Fast, low memory (~77MB)
  static final ModelInfo whisperTinyEn = ModelInfo(
    id: 'whisper-tiny-en',
    name: 'Whisper Tiny (English)',
    sizeBytes: 77 * 1024 * 1024, // ~77 MB download
    description: 'Fast English speech recognition, low memory footprint',
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin',
    format: 'GGML',
    quantization: null,
  );

  /// Whisper Base English - Better accuracy (~148MB)
  static final ModelInfo whisperBaseEn = ModelInfo(
    id: 'whisper-base-en',
    name: 'Whisper Base (English)',
    sizeBytes: 148 * 1024 * 1024, // ~148 MB download
    description: 'Higher accuracy English speech recognition',
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin',
    format: 'GGML',
    quantization: null,
  );

  /// Get all available text models
  static List<ModelInfo> getAllModels() {
    return [llama32_1b, phi35_mini, gemma2_2b, tinyLlama, qwen3_06b];
  }

  /// Get all available vision models (model + mmproj pairs)
  static List<ModelInfo> getVisionModels() {
    return [smolvlm2_500m];
  }

  /// Get the multimodal projector for a vision model
  ///
  /// Vision models require both the main model file and a separate
  /// mmproj (multimodal projector) file. This method returns the
  /// corresponding mmproj for a given vision model ID.
  static ModelInfo? getMmprojForModel(String modelId) {
    switch (modelId) {
      case 'smolvlm2-500m-video-instruct-q8':
        return smolvlm2_500m_mmproj;
      default:
        return null;
    }
  }

  /// Get all available whisper STT models
  static List<ModelInfo> getWhisperModels() {
    return [whisperTinyEn, whisperBaseEn];
  }

  // === Embedding Models ===

  /// All MiniLM L6 v2 (F16) - Lightweight sentence embedding model
  static final ModelInfo allMiniLmL6V2 = ModelInfo(
    id: 'all-minilm-l6-v2-f16',
    name: 'All MiniLM L6 v2',
    sizeBytes: 46 * 1024 * 1024, // ~46 MB F16
    description: 'Lightweight sentence embedding model (384 dimensions)',
    downloadUrl:
        'https://huggingface.co/leliuga/all-MiniLM-L6-v2-GGUF/resolve/main/all-MiniLM-L6-v2.F16.gguf',
    format: 'GGUF',
    quantization: 'F16',
  );

  /// Get all available embedding models
  static List<ModelInfo> getEmbeddingModels() {
    return [allMiniLmL6V2];
  }

  /// Get model by ID (searches text, vision, whisper, and embedding models)
  static ModelInfo? getModelById(String id) {
    final allModels = [
      ...getAllModels(),
      ...getVisionModels(),
      smolvlm2_500m_mmproj,
      ...getWhisperModels(),
      ...getEmbeddingModels(),
    ];
    try {
      return allModels.firstWhere((model) => model.id == id);
    } catch (e) {
      return null;
    }
  }
}
