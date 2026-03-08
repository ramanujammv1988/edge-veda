/// Model download and management for Edge Veda SDK
library;

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'telemetry_service.dart';
import 'types.dart';

/// Manages model downloads, caching, and verification
class ModelManager {
  static const String _modelsCacheDir = 'edge_veda_models';
  static const String _metadataFileName = 'metadata.json';
  static const int _maxRetries = 3;
  static const Duration _initialRetryDelay = Duration(seconds: 1);
  static const Duration _streamChunkTimeout = Duration(seconds: 30);

  /// Telemetry service for disk space checks.
  /// Replaceable in tests to inject a mock.
  @visibleForTesting
  TelemetryService telemetryService = TelemetryService();

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

    // Check disk space before downloading
    final freeBytes = await telemetryService.getFreeDiskSpace();
    if (freeBytes >= 0) {
      const bufferBytes = 100 * 1024 * 1024; // 100MB buffer for temp files
      if (freeBytes < model.sizeBytes + bufferBytes) {
        final freeMB = (freeBytes / (1024 * 1024)).round();
        final requiredMB = (model.sizeBytes / (1024 * 1024)).round();
        throw DownloadException(
          'Insufficient disk space',
          details:
              '${freeMB}MB free, ${requiredMB}MB required for ${model.name}',
        );
      }
    }

    // Store cancel token for external cancellation
    _currentDownloadToken = cancelToken;

    // Attempt download with retries for transient network errors
    return _downloadWithRetry(model, modelPath, verifyChecksum, cancelToken);
  }

  /// Import a model from a local file path into the SDK model cache.
  ///
  /// Copies the source file to a temporary location in the models directory,
  /// optionally verifies SHA256 checksum, then atomically renames to the final
  /// location. This ensures no corrupt files if the copy is interrupted.
  ///
  /// If a valid cached model already exists (matching checksum), returns
  /// immediately without re-copying.
  ///
  /// The [sourcePath] must point to an existing file (e.g., a Flutter asset
  /// extracted to a temp directory, or a file the user already has on disk).
  ///
  /// [onProgress] is called periodically with (bytesCopied, totalBytes).
  ///
  /// Throws [ModelValidationException] if:
  /// - Source file does not exist
  /// - Source file size does not match [model.sizeBytes] (when > 0)
  /// - SHA256 checksum does not match [model.checksum] (when non-null and verifyChecksum is true)
  Future<String> importModel(
    ModelInfo model, {
    required String sourcePath,
    bool verifyChecksum = true,
    void Function(int bytesCopied, int totalBytes)? onProgress,
  }) async {
    final modelPath = await getModelPath(model.id);
    final file = File(modelPath);

    // Guard: source and destination must not be the same file.
    // Only check when both files exist (resolveSymbolicLinks throws on missing files).
    final sourceExists = await File(sourcePath).exists();
    if (sourceExists && await File(modelPath).exists()) {
      final resolvedSource = await File(sourcePath).resolveSymbolicLinks();
      final resolvedDestPath = await File(modelPath).resolveSymbolicLinks();
      if (resolvedSource == resolvedDestPath) {
        // Same file — still verify checksum if requested
        if (verifyChecksum && model.checksum != null) {
          final isValid = await _verifyChecksum(modelPath, model.checksum!);
          if (!isValid) {
            throw ModelValidationException(
              'Model file failed checksum verification',
              details:
                  'File at $modelPath has invalid SHA256 (expected: ${model.checksum})',
            );
          }
        }
        return modelPath;
      }
    }

    // CHECK CACHE - skip copy if valid model exists
    if (await file.exists()) {
      if (verifyChecksum && model.checksum != null) {
        final isValid = await _verifyChecksum(modelPath, model.checksum!);
        if (isValid) {
          return modelPath;
        }
        // Invalid checksum -- validate source exists BEFORE deleting cache
        // to prevent data loss when source is missing
        if (!sourceExists) {
          throw ModelValidationException(
            'Source file not found',
            details: sourcePath,
          );
        }
        await file.delete();
      } else {
        // No checksum to verify - assume cached file is valid
        return modelPath;
      }
    }

    // Validate source file exists
    final sourceFile = File(sourcePath);
    if (!sourceExists) {
      throw ModelValidationException(
        'Source file not found',
        details: sourcePath,
      );
    }

    // Validate source file size
    final sourceSize = await sourceFile.length();
    if (model.sizeBytes > 0 && sourceSize != model.sizeBytes) {
      throw ModelValidationException(
        'Source file size mismatch',
        details: 'Expected ${model.sizeBytes} bytes, got $sourceSize bytes',
      );
    }

    // Create temp file for atomic copy
    final tempPath = '$modelPath.tmp';
    final tempFile = File(tempPath);

    // Delete any stale .tmp file from a prior interrupted copy
    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    IOSink? sink;
    try {
      // Chunked copy with progress reporting
      final sourceStream = sourceFile.openRead();
      sink = tempFile.openWrite();
      var bytesCopied = 0;
      final totalBytes = sourceSize;

      await for (final chunk in sourceStream) {
        sink.add(chunk);
        bytesCopied += chunk.length;
        onProgress?.call(bytesCopied, totalBytes);
      }

      await sink.flush();
      await sink.close();
      sink = null; // Prevent double-close in catch

      // Verify checksum before atomic rename
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

      // Atomic rename
      await tempFile.rename(modelPath);

      // Save metadata
      await _saveModelMetadata(model);

      return modelPath;
    } catch (e) {
      // Close sink before cleanup to release file handle
      try {
        if (sink != null) {
          await sink.close();
        }
      } catch (_) {}
      // Clean up .tmp on any error
      try {
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {
        // Ignore cleanup errors
      }
      if (e is EdgeVedaException) {
        rethrow;
      }
      throw ModelValidationException(
        'Failed to import model',
        details: e.toString(),
        originalError: e,
      );
    }
  }

  /// Internal download implementation with retry logic
  Future<String> _downloadWithRetry(
    ModelInfo model,
    String modelPath,
    bool verifyChecksum,
    CancelToken? cancelToken,
  ) async {
    final candidateUrls = _buildDownloadUrlCandidates(model.downloadUrl);
    SocketException? lastSocketError;
    DownloadException? lastDownloadError;

    for (final downloadUrl in candidateUrls) {
      int attempt = 0;
      Duration retryDelay = _initialRetryDelay;

      while (true) {
        attempt++;
        try {
          return await _performDownload(
            model,
            modelPath,
            verifyChecksum,
            cancelToken,
            downloadUrl: downloadUrl,
          );
        } on SocketException catch (e) {
          lastSocketError = e;
          // Transient network error - retry with exponential backoff.
          // If retries for this host are exhausted, try next host.
          if (attempt >= _maxRetries) {
            break;
          }
          await Future.delayed(retryDelay);
          retryDelay *= 2;
        } on DownloadException catch (e) {
          // HTTP/status/validation error for this host - move to next candidate.
          lastDownloadError = e;
          break;
        }
      }
    }

    if (lastDownloadError != null) {
      throw lastDownloadError;
    }

    throw DownloadException(
      'Failed to download model',
      details:
          'Unable to reach model host(s). Tried: ${candidateUrls.join(', ')}. '
          'Last network error: ${lastSocketError?.message ?? 'unknown'}',
      originalError: lastSocketError,
    );
  }

  /// Perform the actual download to temp file with atomic rename.
  ///
  /// Supports HTTP byte-range resume: if a .tmp file exists from a prior
  /// interrupted download, sends `Range: bytes=N-` to resume from byte N.
  /// Handles 206 (resume), 200 (fresh/fallback), and 416 (corrupt .tmp).
  Future<String> _performDownload(
    ModelInfo model,
    String modelPath,
    bool verifyChecksum,
    CancelToken? cancelToken, {
    required String downloadUrl,
    bool isRetry = false,
  }) async {
    // Create temporary file for downloading (atomic pattern - Pitfall 12)
    final tempPath = '$modelPath.tmp';
    final tempFile = File(tempPath);

    // Check for existing .tmp file to determine resume offset
    int resumeOffset = 0;
    if (await tempFile.exists()) {
      resumeOffset = await tempFile.length();
    }

    final client = http.Client();
    IOSink? sink;

    try {
      // Check for cancellation before starting
      if (cancelToken?.isCancelled == true) {
        throw const DownloadException('Download cancelled');
      }

      // Start download with optional Range header for resume
      final request = http.Request('GET', Uri.parse(downloadUrl));
      if (resumeOffset > 0) {
        request.headers['Range'] = 'bytes=$resumeOffset-';
      }
      final response = await client.send(request);

      var downloadedBytes = 0;
      var lastReportedBytes = 0;

      if (response.statusCode == 206 && resumeOffset > 0) {
        // Resume supported - append to existing temp file
        sink = tempFile.openWrite(mode: FileMode.append);
        downloadedBytes = resumeOffset;
        lastReportedBytes = resumeOffset;
      } else if (response.statusCode == 200) {
        // Fresh download (server may not support Range, or no resume needed)
        if (resumeOffset > 0) {
          // Server ignored Range header - restart from scratch
          await tempFile.delete();
        }
        sink = tempFile.openWrite();
      } else if (response.statusCode == 416 && resumeOffset > 0) {
        // Range not satisfiable - temp file corrupt, restart
        await tempFile.delete();
        client.close();
        if (isRetry) {
          throw const DownloadException(
            'Failed to download model',
            details: 'HTTP 416 Range Not Satisfiable after retry',
          );
        }
        return _performDownload(
          model,
          modelPath,
          verifyChecksum,
          cancelToken,
          downloadUrl: downloadUrl,
          isRetry: true,
        );
      } else {
        throw DownloadException(
          'Failed to download model',
          details: 'HTTP ${response.statusCode}',
        );
      }

      // Compute total bytes correctly for resumed vs fresh downloads.
      // For 206, Content-Length is the remaining bytes, not the total.
      final contentLength = response.contentLength ?? 0;
      final totalBytes =
          response.statusCode == 206
              ? resumeOffset + contentLength
              : (contentLength > 0 ? contentLength : model.sizeBytes);

      final startTime = DateTime.now();

      // Emit initial progress immediately on resume so UI shows
      // the already-downloaded portion right away.
      if (resumeOffset > 0 && response.statusCode == 206) {
        _progressController.add(
          DownloadProgress(
            totalBytes: totalBytes,
            downloadedBytes: resumeOffset,
            speedBytesPerSecond: 0,
            estimatedSecondsRemaining: null,
          ),
        );
      }

      // At this point sink is guaranteed non-null: the 416 and error
      // branches above all return/throw before reaching here.
      final IOSink activeSink = sink!; // ignore: unnecessary_non_null_assertion

      await for (final chunk in response.stream.timeout(
        _streamChunkTimeout,
        onTimeout: (sink) => sink.close(),
      )) {
        // Check for cancellation during download
        if (cancelToken?.isCancelled == true) {
          await activeSink.close();
          sink = null;
          // Keep temp file for resume on next attempt
          throw const DownloadException('Download cancelled');
        }

        downloadedBytes += chunk.length;
        activeSink.add(chunk);

        // Only emit progress if it increased (guard against backwards progress)
        if (downloadedBytes > lastReportedBytes) {
          lastReportedBytes = downloadedBytes;

          // Calculate download speed and ETA (speed based on NEW bytes only)
          final elapsed = DateTime.now().difference(startTime).inMilliseconds;
          final newBytes = downloadedBytes - resumeOffset;
          final speed = elapsed > 0 ? (newBytes / elapsed) * 1000 : 0.0;
          final remaining =
              speed > 0
                  ? ((totalBytes - downloadedBytes) / speed).round()
                  : null;

          // Emit progress update (0-100%)
          _progressController.add(
            DownloadProgress(
              totalBytes: totalBytes,
              downloadedBytes: downloadedBytes,
              speedBytesPerSecond: speed,
              estimatedSecondsRemaining: remaining,
            ),
          );
        }
      }

      await activeSink.flush();
      await activeSink.close();
      sink = null;

      // Detect incomplete download (e.g. stream closed by timeout)
      if (totalBytes > 0 && downloadedBytes < totalBytes) {
        throw SocketException(
          'Download stalled at ${(downloadedBytes * 100 / totalBytes).round()}%'
          ' ($downloadedBytes/$totalBytes bytes)',
        );
      }

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
      _progressController.add(
        DownloadProgress(
          totalBytes: totalBytes,
          downloadedBytes: totalBytes,
          speedBytesPerSecond: 0,
          estimatedSecondsRemaining: 0,
        ),
      );

      // Save metadata
      await _saveModelMetadata(model);

      return modelPath;
    } catch (e) {
      // Clean up sink on error, but KEEP .tmp file for resume
      try {
        if (sink != null) {
          await sink.close();
        }
      } catch (_) {
        // Ignore cleanup errors
      }

      // Only delete .tmp on non-resumable errors (validation failures)
      if (e is ModelValidationException) {
        try {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {}
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

  /// Build ordered download URL candidates.
  ///
  /// For Hugging Face URLs, we try an alternate mirror host as fallback for
  /// environments where `huggingface.co` DNS/routing is blocked.
  List<String> _buildDownloadUrlCandidates(String primaryUrl) {
    final candidates = <String>[primaryUrl];
    final uri = Uri.parse(primaryUrl);

    if (uri.host == 'huggingface.co') {
      candidates.add(uri.replace(host: 'hf-mirror.com').toString());
    }

    return candidates.toSet().toList();
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
  Future<bool> verifyModelChecksum(
    String filePath,
    String expectedChecksum,
  ) async {
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
    final metadataFile = File(
      path.join(modelsDir.path, '${model.id}_$_metadataFileName'),
    );

    final metadata = {
      'model': model.toJson(),
      'downloadedAt': DateTime.now().toIso8601String(),
    };

    await metadataFile.writeAsString(jsonEncode(metadata));
  }

  /// Delete model metadata
  Future<void> _deleteModelMetadata(String modelId) async {
    final modelsDir = await getModelsDirectory();
    final metadataFile = File(
      path.join(modelsDir.path, '${modelId}_$_metadataFileName'),
    );

    if (await metadataFile.exists()) {
      await metadataFile.delete();
    }
  }

  /// Get model metadata if available
  Future<ModelInfo?> getModelMetadata(String modelId) async {
    final modelsDir = await getModelsDirectory();
    final metadataFile = File(
      path.join(modelsDir.path, '${modelId}_$_metadataFileName'),
    );

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
  static const String huggingFaceBaseUrl = 'https://huggingface.co/models';

  // === Desktop Class Models ===

  /// Llama 3.1 8B Instruct (Q4_K_M) - Desktop class reasoning model
  static const ModelInfo llama31_8b = ModelInfo(
    id: 'llama-3.1-8b-instruct-q4',
    name: 'Llama 3.1 8B Instruct',
    sizeBytes: 4920 * 1024 * 1024, // ~4.9 GB
    description: 'Highly capable desktop-class 8B instruction model',
    downloadUrl:
        'https://huggingface.co/bartowski/Meta-Llama-3.1-8B-Instruct-GGUF/resolve/main/Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf',
    format: 'GGUF',
    quantization: 'Q4_K_M',
    parametersB: 8.0,
    maxContextLength: 131072,
    capabilities: ['chat', 'instruct', 'reasoning', 'tool-calling'],
    family: 'llama3',
  );

  /// Mistral Nemo 12B Instruct (Q4_K_M) - Desktop class wide-knowledge model
  // ignore: constant_identifier_names
  static const ModelInfo mistral_nemo_12b = ModelInfo(
    id: 'mistral-nemo-12b-instruct-q4',
    name: 'Mistral Nemo 12B Instruct',
    sizeBytes: 7100 * 1024 * 1024, // ~7.1 GB
    description: 'Powerful desktop-class 12B model with large context window',
    downloadUrl:
        'https://huggingface.co/bartowski/Mistral-Nemo-Instruct-2407-GGUF/resolve/main/Mistral-Nemo-Instruct-2407-Q4_K_M.gguf',
    format: 'GGUF',
    quantization: 'Q4_K_M',
    parametersB: 12.0,
    maxContextLength: 128000,
    capabilities: ['chat', 'instruct', 'reasoning'],
    family: 'mistral',
  );

  // === Mobile Class Models ===

  /// Llama 3.2 1B Instruct (Q4_K_M quantization) - Primary model
  static const ModelInfo llama32_1b = ModelInfo(
    id: 'llama-3.2-1b-instruct-q4',
    name: 'Llama 3.2 1B Instruct',
    sizeBytes: 668 * 1024 * 1024, // ~668 MB
    description: 'Fast and efficient instruction-tuned model',
    downloadUrl:
        'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
    format: 'GGUF',
    quantization: 'Q4_K_M',
    parametersB: 1.24,
    maxContextLength: 131072,
    capabilities: ['chat', 'instruct'],
    family: 'llama3',
  );

  /// Phi-3.5 Mini Instruct (Q4_K_M quantization) - Reasoning model
  // ignore: constant_identifier_names
  static const ModelInfo phi35_mini = ModelInfo(
    id: 'phi-3.5-mini-instruct-q4',
    name: 'Phi 3.5 Mini Instruct',
    sizeBytes: 2300 * 1024 * 1024, // ~2.3 GB
    description: 'High-quality reasoning model from Microsoft',
    downloadUrl:
        'https://huggingface.co/bartowski/Phi-3.5-mini-instruct-GGUF/resolve/main/Phi-3.5-mini-instruct-Q4_K_M.gguf',
    format: 'GGUF',
    quantization: 'Q4_K_M',
    parametersB: 3.82,
    maxContextLength: 131072,
    capabilities: ['chat', 'instruct', 'reasoning'],
    family: 'phi3',
  );

  /// Gemma 2 2B Instruct (Q4_K_M quantization)
  static const ModelInfo gemma2_2b = ModelInfo(
    id: 'gemma-2-2b-instruct-q4',
    name: 'Gemma 2 2B Instruct',
    sizeBytes: 1600 * 1024 * 1024, // ~1.6 GB
    description: 'Google\'s efficient instruction model',
    downloadUrl:
        'https://huggingface.co/bartowski/gemma-2-2b-it-GGUF/resolve/main/gemma-2-2b-it-Q4_K_M.gguf',
    format: 'GGUF',
    quantization: 'Q4_K_M',
    parametersB: 2.61,
    maxContextLength: 8192,
    capabilities: ['chat', 'instruct'],
    family: 'gemma2',
  );

  /// TinyLlama 1.1B Chat (Q4_K_M quantization) - Smallest option
  static const ModelInfo tinyLlama = ModelInfo(
    id: 'tinyllama-1.1b-chat-q4',
    name: 'TinyLlama 1.1B Chat',
    sizeBytes: 669 * 1024 * 1024, // ~669 MB
    description: 'Ultra-fast lightweight chat model',
    downloadUrl:
        'https://huggingface.co/TheBloke/TinyLlama-1.1B-Chat-v1.0-GGUF/resolve/main/tinyllama-1.1b-chat-v1.0.Q4_K_M.gguf',
    format: 'GGUF',
    quantization: 'Q4_K_M',
    parametersB: 1.10,
    maxContextLength: 2048,
    capabilities: ['chat'],
    family: 'tinyllama',
  );

  // === Tool Calling Models ===

  /// Qwen3 0.6B (Q4_K_M) - Tool calling capable model
  static const ModelInfo qwen3_06b = ModelInfo(
    id: 'qwen3-0.6b-q4',
    name: 'Qwen3 0.6B',
    sizeBytes: 397 * 1024 * 1024, // ~397 MB Q4_K_M
    description: 'Compact model with native tool calling support',
    downloadUrl:
        'https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf',
    format: 'GGUF',
    quantization: 'Q4_K_M',
    parametersB: 0.60,
    maxContextLength: 32768,
    capabilities: ['chat', 'tool-calling'],
    family: 'qwen3',
  );

  // === Vision Language Models ===

  // -- Mobile --

  /// SmolVLM2-500M-Video-Instruct (Q8_0) - Vision Language Model
  static const ModelInfo smolvlm2_500m = ModelInfo(
    id: 'smolvlm2-500m-video-instruct-q8',
    name: 'SmolVLM2 500M Video Instruct',
    sizeBytes: 436808704, // ~417 MB
    description: 'Vision + video understanding model for image description',
    downloadUrl:
        'https://huggingface.co/ggml-org/SmolVLM2-500M-Video-Instruct-GGUF/resolve/main/SmolVLM2-500M-Video-Instruct-Q8_0.gguf',
    format: 'GGUF',
    quantization: 'Q8_0',
    parametersB: 0.50,
    maxContextLength: 4096,
    capabilities: ['vision'],
    family: 'smolvlm',
  );

  /// SmolVLM2-500M mmproj (F16) - Multimodal projector for SmolVLM2
  // ignore: constant_identifier_names
  static const ModelInfo smolvlm2_500m_mmproj = ModelInfo(
    id: 'smolvlm2-500m-mmproj-f16',
    name: 'SmolVLM2 500M Multimodal Projector',
    sizeBytes: 199470624, // ~190 MB
    description: 'Multimodal projector for SmolVLM2 vision model',
    downloadUrl:
        'https://huggingface.co/ggml-org/SmolVLM2-500M-Video-Instruct-GGUF/resolve/main/mmproj-SmolVLM2-500M-Video-Instruct-f16.gguf',
    format: 'GGUF',
    quantization: 'F16',
    capabilities: ['vision-projector'],
    family: 'smolvlm',
  );

  /// SmolVLM2-256M-Video-Instruct (Q8_0) - Tiny VLM for low-end devices
  // ignore: constant_identifier_names
  static const ModelInfo smolvlm2_256m = ModelInfo(
    id: 'smolvlm2-256m-video-instruct-q8',
    name: 'SmolVLM2 256M Video Instruct',
    sizeBytes: 175056352, // ~167 MB
    description: 'Tiny vision model for low-end devices',
    downloadUrl:
        'https://huggingface.co/ggml-org/SmolVLM2-256M-Video-Instruct-GGUF/resolve/main/SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
    format: 'GGUF',
    quantization: 'Q8_0',
    parametersB: 0.26,
    maxContextLength: 4096,
    capabilities: ['vision'],
    family: 'smolvlm',
  );

  /// SmolVLM2-256M mmproj (Q8_0) - Quantized projector for SmolVLM2 256M
  // ignore: constant_identifier_names
  static const ModelInfo smolvlm2_256m_mmproj = ModelInfo(
    id: 'smolvlm2-256m-mmproj-q8',
    name: 'SmolVLM2 256M Multimodal Projector',
    sizeBytes: 103771680, // ~99 MB
    description: 'Q8 multimodal projector for SmolVLM2 256M',
    downloadUrl:
        'https://huggingface.co/ggml-org/SmolVLM2-256M-Video-Instruct-GGUF/resolve/main/mmproj-SmolVLM2-256M-Video-Instruct-Q8_0.gguf',
    format: 'GGUF',
    quantization: 'Q8_0',
    capabilities: ['vision-projector'],
    family: 'smolvlm',
  );

  // -- macOS Desktop --

  /// LLaVA 1.6 Mistral 7B (Q4_K_M) - High quality VLM for macOS (~4.8 GB)
  // ignore: constant_identifier_names
  static const ModelInfo llava16_mistral_7b = ModelInfo(
    id: 'llava-1.6-mistral-7b-q4',
    name: 'LLaVA 1.6 Mistral 7B',
    sizeBytes: 4370 * 1024 * 1024, // ~4.8 GB
    description:
        'State-of-the-art 7B vision-language model for detailed image understanding',
    downloadUrl:
        'https://huggingface.co/cjpais/llava-1.6-mistral-7b-gguf/resolve/main/llava-1.6-mistral-7b.Q4_K_M.gguf',
    format: 'GGUF',
    quantization: 'Q4_K_M',
    parametersB: 7.0,
    maxContextLength: 32768,
    capabilities: ['vision', 'chat'],
    family: 'llava',
  );

  /// LLaVA 1.6 Mistral 7B mmproj (F16)
  // ignore: constant_identifier_names
  static const ModelInfo llava16_mistral_7b_mmproj = ModelInfo(
    id: 'llava-1.6-mistral-7b-mmproj-f16',
    name: 'LLaVA 1.6 Mistral 7B Multimodal Projector',
    sizeBytes: 624 * 1024 * 1024, // ~624 MB
    description: 'Multimodal projector for LLaVA 1.6 Mistral 7B',
    downloadUrl:
        'https://huggingface.co/cjpais/llava-1.6-mistral-7b-gguf/resolve/main/mmproj-model-f16.gguf',
    format: 'GGUF',
    quantization: 'F16',
    capabilities: ['vision-projector'],
    family: 'llava',
  );

  /// Qwen2-VL 7B Instruct (Q4_K_M) - OCR-capable VLM, great for screen reading (~4.5 GB)
  // ignore: constant_identifier_names
  static const ModelInfo qwen2vl_7b = ModelInfo(
    id: 'qwen2-vl-7b-instruct-q4',
    name: 'Qwen2-VL 7B Instruct',
    sizeBytes: 4540 * 1024 * 1024, // ~4.5 GB
    description: 'Expert VLM with strong OCR and screen reading capabilities',
    downloadUrl:
        'https://huggingface.co/bartowski/Qwen2-VL-7B-Instruct-GGUF/resolve/main/Qwen2-VL-7B-Instruct-Q4_K_M.gguf',
    format: 'GGUF',
    quantization: 'Q4_K_M',
    parametersB: 7.0,
    maxContextLength: 32768,
    capabilities: ['vision', 'chat', 'ocr'],
    family: 'qwen2vl',
  );

  /// Qwen2-VL 7B mmproj (F16)
  // ignore: constant_identifier_names
  static const ModelInfo qwen2vl_7b_mmproj = ModelInfo(
    id: 'qwen2-vl-7b-mmproj-f16',
    name: 'Qwen2-VL 7B Multimodal Projector',
    sizeBytes: 892 * 1024 * 1024, // ~892 MB
    description: 'Multimodal projector for Qwen2-VL 7B',
    downloadUrl:
        'https://huggingface.co/bartowski/Qwen2-VL-7B-Instruct-GGUF/resolve/main/mmproj-Qwen2-VL-7B-Instruct-f16.gguf',
    format: 'GGUF',
    quantization: 'F16',
    capabilities: ['vision-projector'],
    family: 'qwen2vl',
  );

  // === Whisper Speech-to-Text Models ===

  // -- Mobile --

  /// Whisper Tiny English - Fast, low memory (~77MB)
  static const ModelInfo whisperTinyEn = ModelInfo(
    id: 'whisper-tiny-en',
    name: 'Whisper Tiny (English)',
    sizeBytes: 77 * 1024 * 1024,
    description: 'Fast English speech recognition, low memory footprint',
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-tiny.en.bin',
    format: 'GGML',
    quantization: null,
    parametersB: 0.04,
    capabilities: ['stt'],
    family: 'whisper',
  );

  /// Whisper Base English - Better accuracy (~148MB)
  static const ModelInfo whisperBaseEn = ModelInfo(
    id: 'whisper-base-en',
    name: 'Whisper Base (English)',
    sizeBytes: 148 * 1024 * 1024,
    description: 'Higher accuracy English speech recognition',
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin',
    format: 'GGML',
    quantization: null,
    parametersB: 0.07,
    capabilities: ['stt'],
    family: 'whisper',
  );

  // -- macOS Desktop --

  /// Whisper Small Multilingual - Good accuracy, 50+ languages (~244MB)
  static const ModelInfo whisperSmall = ModelInfo(
    id: 'whisper-small-multilingual',
    name: 'Whisper Small (Multilingual)',
    sizeBytes: 244 * 1024 * 1024,
    description: 'Good accuracy STT in 50+ languages — best mobile fallback',
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin',
    format: 'GGML',
    quantization: null,
    parametersB: 0.24,
    capabilities: ['stt'],
    family: 'whisper',
  );

  /// Whisper Medium Multilingual - Production quality, 50+ languages (~769MB)
  static const ModelInfo whisperMedium = ModelInfo(
    id: 'whisper-medium-multilingual',
    name: 'Whisper Medium (Multilingual)',
    sizeBytes: 769 * 1024 * 1024,
    description: 'Production-quality multilingual STT for macOS',
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-medium.bin',
    format: 'GGML',
    quantization: null,
    parametersB: 0.31,
    capabilities: ['stt'],
    family: 'whisper',
  );

  /// Whisper Large v3 Multilingual - SOTA quality (~3.1GB, requires 8GB+ Mac)
  // ignore: constant_identifier_names
  static const ModelInfo whisperLargeV3 = ModelInfo(
    id: 'whisper-large-v3-multilingual',
    name: 'Whisper Large v3 (Multilingual)',
    sizeBytes: 3100 * 1024 * 1024,
    description: 'State-of-the-art STT in 100 languages — requires 8GB+ Mac',
    downloadUrl:
        'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin',
    format: 'GGML',
    quantization: null,
    parametersB: 1.55,
    capabilities: ['stt'],
    family: 'whisper',
  );

  /// Get all available text models
  static List<ModelInfo> getAllModels() {
    return [
      llama31_8b,
      mistral_nemo_12b,
      llama32_1b,
      phi35_mini,
      gemma2_2b,
      tinyLlama,
      qwen3_06b,
    ];
  }

  /// Get all available vision models (model + mmproj pairs)
  static List<ModelInfo> getVisionModels() {
    return [smolvlm2_256m, smolvlm2_500m, llava16_mistral_7b, qwen2vl_7b];
  }

  /// Get the multimodal projector for a vision model
  ///
  /// Vision models require both the main model file and a separate
  /// mmproj (multimodal projector) file. This method returns the
  /// corresponding mmproj for a given vision model ID.
  static ModelInfo? getMmprojForModel(String modelId) {
    switch (modelId) {
      case 'smolvlm2-256m-video-instruct-q8':
        return smolvlm2_256m_mmproj;
      case 'smolvlm2-500m-video-instruct-q8':
        return smolvlm2_500m_mmproj;
      case 'llava-1.6-mistral-7b-q4':
        return llava16_mistral_7b_mmproj;
      case 'qwen2-vl-7b-instruct-q4':
        return qwen2vl_7b_mmproj;
      default:
        return null;
    }
  }

  /// Get all available whisper STT models
  static List<ModelInfo> getWhisperModels() {
    return [
      whisperTinyEn,
      whisperBaseEn,
      whisperSmall,
      whisperMedium,
      whisperLargeV3,
    ];
  }

  // === Image Generation Models ===

  // -- Mobile --

  /// SD v2.1 Turbo Q8_0 - Fast 1-4 step 512x512 image generation
  static const ModelInfo sdV21Turbo = ModelInfo(
    id: 'sd-v2-1-turbo-q8',
    name: 'SD v2.1 Turbo Q8_0',
    sizeBytes: 2023745376,
    description: 'Fast 1-4 step 512x512 image generation via Stable Diffusion',
    downloadUrl:
        'https://huggingface.co/Green-Sky/SD-Turbo-GGUF/resolve/main/sd_turbo-f16-q8_0.gguf',
    format: 'GGUF',
    quantization: 'Q8_0',
    capabilities: ['imageGeneration'],
    family: 'stable-diffusion',
  );

  // -- macOS Desktop --

  /// SDXL Turbo FP16 - 1024x1024 high quality, 4-step generation (~6.7 GB)
  // ignore: constant_identifier_names
  static const ModelInfo sdxlTurbo = ModelInfo(
    id: 'sdxl-turbo-fp16',
    name: 'SDXL Turbo FP16',
    sizeBytes: 6800 * 1024 * 1024, // ~6.7 GB
    description: '1024×1024 high-quality 4-step image generation for macOS',
    downloadUrl:
        'https://huggingface.co/stabilityai/sdxl-turbo/resolve/main/sd_xl_turbo_1.0_fp16.safetensors',
    format: 'safetensors',
    quantization: 'FP16',
    capabilities: ['imageGeneration'],
    family: 'stable-diffusion-xl',
  );

  /// FLUX.1 Schnell Q4_0 - SOTA 4-step 1024x1024 generation (~12 GB, 16GB+ Mac)
  // ignore: constant_identifier_names
  static const ModelInfo flux1Schnell = ModelInfo(
    id: 'flux-1-schnell-q4',
    name: 'FLUX.1 Schnell Q4_0',
    sizeBytes: 12400 * 1024 * 1024, // ~12 GB
    description: 'State-of-the-art 4-step text-to-image — requires 16GB+ Mac',
    downloadUrl:
        'https://huggingface.co/city96/FLUX.1-schnell-gguf/resolve/main/flux1-schnell-Q4_0.gguf',
    format: 'GGUF',
    quantization: 'Q4_0',
    capabilities: ['imageGeneration'],
    family: 'flux',
  );

  /// Get all available image generation models
  static List<ModelInfo> getImageModels() {
    return [sdV21Turbo, sdxlTurbo, flux1Schnell];
  }

  // === Embedding Models ===

  // -- Mobile + macOS --

  /// All MiniLM L6 v2 (F16) - Lightweight sentence embedding model (~46MB)
  static const ModelInfo allMiniLmL6V2 = ModelInfo(
    id: 'all-minilm-l6-v2-f16',
    name: 'All MiniLM L6 v2',
    sizeBytes: 46 * 1024 * 1024,
    description: 'Lightweight sentence embedding model (384 dimensions)',
    downloadUrl:
        'https://huggingface.co/leliuga/all-MiniLM-L6-v2-GGUF/resolve/main/all-MiniLM-L6-v2.F16.gguf',
    format: 'GGUF',
    quantization: 'F16',
    parametersB: 0.02,
    maxContextLength: 512,
    capabilities: ['embedding'],
    family: 'minilm',
  );

  // -- macOS Desktop --

  /// nomic-embed-text v1.5 (F16) - High quality 768-dim embeddings (~87MB)
  // ignore: constant_identifier_names
  static const ModelInfo nomicEmbedText = ModelInfo(
    id: 'nomic-embed-text-v1.5-f16',
    name: 'Nomic Embed Text v1.5',
    sizeBytes: 87 * 1024 * 1024, // ~87 MB
    description: 'High quality 768-dimension embeddings for RAG on macOS',
    downloadUrl:
        'https://huggingface.co/nomic-ai/nomic-embed-text-v1.5-GGUF/resolve/main/nomic-embed-text-v1.5.f16.gguf',
    format: 'GGUF',
    quantization: 'F16',
    parametersB: 0.14,
    maxContextLength: 8192,
    capabilities: ['embedding'],
    family: 'nomic-embed',
  );

  /// mxbai-embed-large v1 (F16) - Best-in-class 1024-dim embeddings (~335MB)
  // ignore: constant_identifier_names
  static const ModelInfo mxbaiEmbedLarge = ModelInfo(
    id: 'mxbai-embed-large-v1-f16',
    name: 'mxbai-embed-large v1',
    sizeBytes: 335 * 1024 * 1024, // ~335 MB
    description: 'State-of-the-art 1024-dimension embeddings for complex RAG',
    downloadUrl:
        'https://huggingface.co/ChristianAzinn/mxbai-embed-large-v1-gguf/resolve/main/mxbai-embed-large-v1-f16.gguf',
    format: 'GGUF',
    quantization: 'F16',
    parametersB: 0.34,
    maxContextLength: 512,
    capabilities: ['embedding'],
    family: 'mxbai-embed',
  );

  /// Get all available embedding models
  static List<ModelInfo> getEmbeddingModels() {
    return [allMiniLmL6V2, nomicEmbedText, mxbaiEmbedLarge];
  }

  /// Get model by ID (searches all categories)
  static ModelInfo? getModelById(String id) {
    final allModels = [
      ...getAllModels(),
      ...getVisionModels(),
      smolvlm2_256m_mmproj,
      smolvlm2_500m_mmproj,
      llava16_mistral_7b_mmproj,
      qwen2vl_7b_mmproj,
      ...getWhisperModels(),
      ...getEmbeddingModels(),
      ...getImageModels(),
    ];
    try {
      return allModels.firstWhere((model) => model.id == id);
    } catch (e) {
      return null;
    }
  }
}
