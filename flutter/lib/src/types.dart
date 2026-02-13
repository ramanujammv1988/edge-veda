/// Public types and configuration classes for Edge Veda SDK
library;

/// Configuration for initializing Edge Veda SDK
class EdgeVedaConfig {
  /// Path to the model file (GGUF format)
  final String modelPath;

  /// Number of threads to use for inference (defaults to 4)
  final int numThreads;

  /// Maximum context length in tokens (defaults to 2048)
  final int contextLength;

  /// Enable GPU acceleration via Metal/Vulkan (defaults to true)
  final bool useGpu;

  /// Maximum memory budget in MB (defaults to 1536 for safety on 4GB devices)
  final int maxMemoryMb;

  /// Enable verbose logging for debugging
  final bool verbose;

  /// Flash attention type: -1=auto (recommended), 0=disabled, 1=enabled
  ///
  /// AUTO lets llama.cpp enable flash attention when the backend supports it
  /// (Metal on iOS does). This improves memory access patterns during attention.
  final int flashAttn;

  /// KV cache quantization type for keys (1=F16, 8=Q8_0)
  ///
  /// Q8_0 halves KV cache memory with negligible quality loss.
  /// Default is Q8_0 (8) for mobile memory optimization.
  final int kvCacheTypeK;

  /// KV cache quantization type for values (1=F16, 8=Q8_0)
  ///
  /// Q8_0 halves KV cache memory with negligible quality loss.
  /// Default is Q8_0 (8) for mobile memory optimization.
  final int kvCacheTypeV;

  const EdgeVedaConfig({
    required this.modelPath,
    this.numThreads = 4,
    this.contextLength = 2048,
    this.useGpu = true,
    this.maxMemoryMb = 1536,
    this.verbose = false,
    this.flashAttn = -1,
    this.kvCacheTypeK = 8,
    this.kvCacheTypeV = 8,
  });

  Map<String, dynamic> toJson() => {
        'modelPath': modelPath,
        'numThreads': numThreads,
        'contextLength': contextLength,
        'useGpu': useGpu,
        'maxMemoryMb': maxMemoryMb,
        'verbose': verbose,
        'flashAttn': flashAttn,
        'kvCacheTypeK': kvCacheTypeK,
        'kvCacheTypeV': kvCacheTypeV,
      };

  @override
  String toString() => 'EdgeVedaConfig(${toJson()})';
}

/// Options for text generation
class GenerateOptions {
  /// System prompt to set context/behavior
  final String? systemPrompt;

  /// Maximum number of tokens to generate (defaults to 512)
  final int maxTokens;

  /// Temperature for sampling randomness (0.0 = deterministic, 1.0 = creative)
  final double temperature;

  /// Top-p nucleus sampling threshold
  final double topP;

  /// Top-k sampling - limit to k most likely tokens
  final int topK;

  /// Repetition penalty to discourage repetitive output
  final double repeatPenalty;

  /// Stop sequences - generation stops when any of these are encountered
  final List<String> stopSequences;

  /// Enable JSON mode - forces output to be valid JSON
  final bool jsonMode;

  /// Stream responses token-by-token (defaults to false)
  final bool stream;

  /// GBNF grammar string for constrained decoding (null = no constraint)
  ///
  /// When set, the model output is constrained to match this GBNF grammar.
  /// Use with [grammarRoot] to specify the root rule name.
  final String? grammarStr;

  /// Grammar root rule name (null = "root")
  ///
  /// Specifies which rule in the GBNF grammar is the entry point.
  /// Only used when [grammarStr] is also set.
  final String? grammarRoot;

  /// Confidence threshold for cloud handoff signal (0.0 = disabled)
  /// When enabled, each token's confidence is tracked via softmax entropy.
  /// If average confidence drops below this threshold, needsCloudHandoff is set.
  final double confidenceThreshold;

  const GenerateOptions({
    this.systemPrompt,
    this.maxTokens = 512,
    this.temperature = 0.7,
    this.topP = 0.9,
    this.topK = 40,
    this.repeatPenalty = 1.1,
    this.stopSequences = const [],
    this.jsonMode = false,
    this.stream = false,
    this.grammarStr,
    this.grammarRoot,
    this.confidenceThreshold = 0.0,
  });

  GenerateOptions copyWith({
    String? systemPrompt,
    int? maxTokens,
    double? temperature,
    double? topP,
    int? topK,
    double? repeatPenalty,
    List<String>? stopSequences,
    bool? jsonMode,
    bool? stream,
    String? grammarStr,
    String? grammarRoot,
    double? confidenceThreshold,
  }) {
    return GenerateOptions(
      systemPrompt: systemPrompt ?? this.systemPrompt,
      maxTokens: maxTokens ?? this.maxTokens,
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      repeatPenalty: repeatPenalty ?? this.repeatPenalty,
      stopSequences: stopSequences ?? this.stopSequences,
      jsonMode: jsonMode ?? this.jsonMode,
      stream: stream ?? this.stream,
      grammarStr: grammarStr ?? this.grammarStr,
      grammarRoot: grammarRoot ?? this.grammarRoot,
      confidenceThreshold: confidenceThreshold ?? this.confidenceThreshold,
    );
  }

  Map<String, dynamic> toJson() => {
        'systemPrompt': systemPrompt,
        'maxTokens': maxTokens,
        'temperature': temperature,
        'topP': topP,
        'topK': topK,
        'repeatPenalty': repeatPenalty,
        'stopSequences': stopSequences,
        'jsonMode': jsonMode,
        'stream': stream,
        'grammarStr': grammarStr,
        'grammarRoot': grammarRoot,
        'confidenceThreshold': confidenceThreshold,
      };

  @override
  String toString() => 'GenerateOptions(${toJson()})';
}

/// Response from text generation
class GenerateResponse {
  /// Generated text content
  final String text;

  /// Number of tokens in the prompt
  final int promptTokens;

  /// Number of tokens generated
  final int completionTokens;

  /// Total tokens used (prompt + completion)
  int get totalTokens => promptTokens + completionTokens;

  /// Time taken for generation in milliseconds
  final int? latencyMs;

  /// Average confidence across all generated tokens (null if not tracked)
  final double? avgConfidence;

  /// Whether cloud handoff was recommended during generation
  final bool needsCloudHandoff;

  /// Tokens per second throughput
  double? get tokensPerSecond {
    if (latencyMs == null || latencyMs == 0) return null;
    return (completionTokens / latencyMs!) * 1000;
  }

  const GenerateResponse({
    required this.text,
    required this.promptTokens,
    required this.completionTokens,
    this.latencyMs,
    this.avgConfidence,
    this.needsCloudHandoff = false,
  });

  Map<String, dynamic> toJson() => {
        'text': text,
        'promptTokens': promptTokens,
        'completionTokens': completionTokens,
        'totalTokens': totalTokens,
        'latencyMs': latencyMs,
        'tokensPerSecond': tokensPerSecond,
        'avgConfidence': avgConfidence,
        'needsCloudHandoff': needsCloudHandoff,
      };

  @override
  String toString() => 'GenerateResponse(${toJson()})';
}

/// Token chunk in a streaming response
class TokenChunk {
  /// The token text content
  final String token;

  /// Token index in the sequence
  final int index;

  /// Whether this is the final token
  final bool isFinal;

  /// Per-token confidence score (0.0-1.0), null if confidence tracking disabled
  final double? confidence;

  /// Whether cloud handoff is recommended at this point
  final bool needsCloudHandoff;

  const TokenChunk({
    required this.token,
    required this.index,
    this.isFinal = false,
    this.confidence,
    this.needsCloudHandoff = false,
  });

  @override
  String toString() {
    final confStr = confidence != null ? ', confidence: ${confidence!.toStringAsFixed(3)}' : '';
    return 'TokenChunk(token: "$token", index: $index, isFinal: $isFinal$confStr)';
  }
}

/// Model download progress information
class DownloadProgress {
  /// Total bytes to download
  final int totalBytes;

  /// Bytes downloaded so far
  final int downloadedBytes;

  /// Download progress as percentage (0.0 - 1.0)
  double get progress =>
      totalBytes > 0 ? downloadedBytes / totalBytes : 0.0;

  /// Download progress as percentage (0 - 100)
  int get progressPercent => (progress * 100).round();

  /// Download speed in bytes per second
  final double? speedBytesPerSecond;

  /// Estimated time remaining in seconds
  final int? estimatedSecondsRemaining;

  const DownloadProgress({
    required this.totalBytes,
    required this.downloadedBytes,
    this.speedBytesPerSecond,
    this.estimatedSecondsRemaining,
  });

  @override
  String toString() =>
      'DownloadProgress($progressPercent%, ${_formatBytes(downloadedBytes)}/${_formatBytes(totalBytes)})';

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Model information
class ModelInfo {
  /// Model identifier (e.g., "llama-3.2-1b")
  final String id;

  /// Human-readable model name
  final String name;

  /// Model size in bytes
  final int sizeBytes;

  /// Model description
  final String? description;

  /// Download URL
  final String downloadUrl;

  /// SHA256 checksum for verification
  final String? checksum;

  /// Model format (e.g., "GGUF")
  final String format;

  /// Quantization level (e.g., "Q4_K_M")
  final String? quantization;

  const ModelInfo({
    required this.id,
    required this.name,
    required this.sizeBytes,
    this.description,
    required this.downloadUrl,
    this.checksum,
    this.format = 'GGUF',
    this.quantization,
  });

  factory ModelInfo.fromJson(Map<String, dynamic> json) {
    return ModelInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      sizeBytes: json['sizeBytes'] as int,
      description: json['description'] as String?,
      downloadUrl: json['downloadUrl'] as String,
      checksum: json['checksum'] as String?,
      format: json['format'] as String? ?? 'GGUF',
      quantization: json['quantization'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sizeBytes': sizeBytes,
        'description': description,
        'downloadUrl': downloadUrl,
        'checksum': checksum,
        'format': format,
        'quantization': quantization,
      };

  @override
  String toString() => 'ModelInfo($name, ${_formatSize()})';

  String _formatSize() {
    final mb = sizeBytes / (1024 * 1024);
    if (mb < 1024) return '${mb.toStringAsFixed(0)} MB';
    return '${(mb / 1024).toStringAsFixed(1)} GB';
  }
}

/// Base exception class for Edge Veda errors
abstract class EdgeVedaException implements Exception {
  final String message;
  final String? details;
  final dynamic originalError;

  const EdgeVedaException(this.message, {this.details, this.originalError});

  @override
  String toString() {
    final buffer = StringBuffer(runtimeType.toString());
    buffer.write(': $message');
    if (details != null) {
      buffer.write(' ($details)');
    }
    return buffer.toString();
  }
}

/// Thrown when SDK initialization fails
class InitializationException extends EdgeVedaException {
  const InitializationException(super.message, {super.details, super.originalError});
}

/// Thrown when model loading fails
class ModelLoadException extends EdgeVedaException {
  const ModelLoadException(super.message, {super.details, super.originalError});
}

/// Thrown when text generation fails
class GenerationException extends EdgeVedaException {
  const GenerationException(super.message, {super.details, super.originalError});
}

/// Thrown when model download fails
class DownloadException extends EdgeVedaException {
  const DownloadException(super.message, {super.details, super.originalError});
}

/// Thrown when checksum verification fails
class ChecksumException extends EdgeVedaException {
  const ChecksumException(super.message, {super.details, super.originalError});
}

/// Thrown when memory limit is exceeded
class MemoryException extends EdgeVedaException {
  const MemoryException(super.message, {super.details, super.originalError});
}

/// Thrown when invalid configuration is provided
class ConfigurationException extends EdgeVedaException {
  const ConfigurationException(super.message, {super.details, super.originalError});
}

/// Thrown when vision inference fails
class VisionException extends EdgeVedaException {
  const VisionException(super.message, {super.details, super.originalError});
}

/// Thrown when model file fails validation (checksum mismatch, corrupted file)
class ModelValidationException extends EdgeVedaException {
  const ModelValidationException(super.message, {super.details, super.originalError});
}

/// Memory pressure event from native layer
class MemoryPressureEvent {
  /// Current memory usage in bytes
  final int currentBytes;

  /// Memory limit in bytes
  final int limitBytes;

  /// Memory usage as a percentage (0.0 - 1.0)
  double get usagePercent => limitBytes > 0 ? currentBytes / limitBytes : 0.0;

  /// Whether memory usage is critical (>90%)
  bool get isCritical => usagePercent > 0.9;

  /// Whether memory usage is warning level (>75%)
  bool get isWarning => usagePercent > 0.75;

  const MemoryPressureEvent(this.currentBytes, this.limitBytes);

  @override
  String toString() =>
      'MemoryPressureEvent(${(usagePercent * 100).toStringAsFixed(1)}%, $currentBytes/$limitBytes bytes)';
}

/// Memory usage statistics from native layer
///
/// Provides detailed memory breakdown for monitoring and responding to
/// memory pressure on iOS devices. Use [usagePercent] to check overall
/// utilization and [isHighPressure] for quick threshold checks.
class MemoryStats {
  /// Current total memory usage in bytes
  final int currentBytes;

  /// Peak memory usage in bytes (high watermark)
  final int peakBytes;

  /// Memory limit in bytes (0 = no limit set)
  final int limitBytes;

  /// Memory used by the loaded model in bytes
  final int modelBytes;

  /// Memory used by inference context in bytes
  final int contextBytes;

  /// Memory usage as a percentage (0.0 - 1.0)
  ///
  /// Returns 0 if no limit is set.
  double get usagePercent => limitBytes > 0 ? currentBytes / limitBytes : 0.0;

  /// Whether memory usage is above 80% threshold
  bool get isHighPressure => usagePercent > 0.8;

  /// Whether memory usage is critical (>90%)
  bool get isCritical => usagePercent > 0.9;

  const MemoryStats({
    required this.currentBytes,
    required this.peakBytes,
    required this.limitBytes,
    required this.modelBytes,
    required this.contextBytes,
  });

  Map<String, dynamic> toJson() => {
        'currentBytes': currentBytes,
        'peakBytes': peakBytes,
        'limitBytes': limitBytes,
        'modelBytes': modelBytes,
        'contextBytes': contextBytes,
        'usagePercent': usagePercent,
        'isHighPressure': isHighPressure,
      };

  @override
  String toString() {
    final percent = (usagePercent * 100).toStringAsFixed(1);
    return 'MemoryStats($percent% used, ${_formatBytes(currentBytes)} current, ${_formatBytes(modelBytes)} model)';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

/// Native error codes matching edge_veda.h ev_error_t
enum NativeErrorCode {
  /// Operation successful
  success(0),

  /// Invalid parameter provided
  invalidParam(-1),

  /// Out of memory
  outOfMemory(-2),

  /// Failed to load model
  modelLoadFailed(-3),

  /// Failed to initialize backend
  backendInitFailed(-4),

  /// Inference operation failed
  inferenceFailed(-5),

  /// Invalid context
  contextInvalid(-6),

  /// Stream has ended
  streamEnded(-7),

  /// Feature not implemented
  notImplemented(-8),

  /// Memory limit exceeded
  memoryLimitExceeded(-9),

  /// Backend not supported on this platform
  unsupportedBackend(-10),

  /// Unknown error
  unknown(-999);

  /// The integer code matching ev_error_t
  final int code;

  const NativeErrorCode(this.code);

  /// Look up error code from integer value
  static NativeErrorCode fromCode(int code) {
    return NativeErrorCode.values.firstWhere(
      (e) => e.code == code,
      orElse: () => NativeErrorCode.unknown,
    );
  }

  /// Whether this represents a successful operation
  bool get isSuccess => this == NativeErrorCode.success;

  /// Whether this is a memory-related error
  bool get isMemoryError =>
      this == NativeErrorCode.outOfMemory ||
      this == NativeErrorCode.memoryLimitExceeded;

  /// Convert to appropriate EdgeVedaException
  ///
  /// Returns null for success code.
  EdgeVedaException? toException([String? details]) {
    switch (this) {
      case NativeErrorCode.success:
        return null;

      case NativeErrorCode.invalidParam:
        return ConfigurationException('Invalid parameter', details: details);

      case NativeErrorCode.outOfMemory:
      case NativeErrorCode.memoryLimitExceeded:
        return MemoryException('Out of memory', details: details);

      case NativeErrorCode.modelLoadFailed:
        return ModelLoadException('Failed to load model', details: details);

      case NativeErrorCode.backendInitFailed:
        return InitializationException('Failed to initialize backend', details: details);

      case NativeErrorCode.inferenceFailed:
        return GenerationException('Inference failed', details: details);

      case NativeErrorCode.contextInvalid:
        return InitializationException('Invalid context', details: details);

      case NativeErrorCode.streamEnded:
        return GenerationException('Stream ended unexpectedly', details: details);

      case NativeErrorCode.notImplemented:
        return ConfigurationException('Feature not implemented', details: details);

      case NativeErrorCode.unsupportedBackend:
        return InitializationException('Backend not supported', details: details);

      case NativeErrorCode.unknown:
        return EdgeVedaGenericException('Unknown error', details: details);
    }
  }
}

/// Generic exception for unknown native errors
class EdgeVedaGenericException extends EdgeVedaException {
  const EdgeVedaGenericException(super.message, {super.details, super.originalError});
}

/// Configuration for initializing vision inference
///
/// Vision context is separate from text context - developers control
/// when the ~540MB vision models load into memory.
class VisionConfig {
  /// Path to the VLM GGUF model file
  final String modelPath;

  /// Path to the mmproj GGUF file (multimodal projector)
  final String mmprojPath;

  /// Number of threads for inference (defaults to 4)
  final int numThreads;

  /// Context size in tokens (0 = auto based on model)
  final int contextSize;

  /// Enable GPU acceleration (defaults to true)
  final bool useGpu;

  /// Maximum memory budget in MB
  final int maxMemoryMb;

  const VisionConfig({
    required this.modelPath,
    required this.mmprojPath,
    this.numThreads = 4,
    this.contextSize = 0,
    this.useGpu = true,
    this.maxMemoryMb = 1536,
  });

  Map<String, dynamic> toJson() => {
        'modelPath': modelPath,
        'mmprojPath': mmprojPath,
        'numThreads': numThreads,
        'contextSize': contextSize,
        'useGpu': useGpu,
        'maxMemoryMb': maxMemoryMb,
      };

  @override
  String toString() => 'VisionConfig(${toJson()})';
}

/// Token for cancelling ongoing operations (downloads, streaming generation)
///
/// For streaming, the CancelToken notifies listeners when cancel() is called,
/// allowing the worker isolate to be notified immediately.
class CancelToken {
  bool _isCancelled = false;
  final List<void Function()> _listeners = [];

  /// Whether cancellation has been requested
  bool get isCancelled => _isCancelled;

  /// Request cancellation of the operation
  ///
  /// Notifies all registered listeners synchronously.
  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final listener in _listeners) {
      listener();
    }
  }

  /// Add a listener to be notified when cancel() is called
  ///
  /// If the token is already cancelled, the listener is called immediately.
  void addListener(void Function() listener) {
    _listeners.add(listener);
    if (_isCancelled) {
      listener();
    }
  }

  /// Remove a previously added listener
  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }

  /// Reset the token for reuse
  ///
  /// Clears the cancelled state and removes all listeners.
  void reset() {
    _isCancelled = false;
    _listeners.clear();
  }
}


/// Result of a text embedding operation
class EmbeddingResult {
  /// The embedding vector (L2-normalized)
  final List<double> embedding;

  /// Number of dimensions
  int get dimensions => embedding.length;

  /// Number of tokens in the input text
  final int tokenCount;

  const EmbeddingResult({
    required this.embedding,
    required this.tokenCount,
  });

  @override
  String toString() => 'EmbeddingResult(dims: $dimensions, tokens: $tokenCount)';
}

/// Confidence information for a generated token or response
class ConfidenceInfo {
  /// Per-token confidence score (0.0-1.0), -1.0 if not computed
  final double confidence;

  /// Running average confidence across all generated tokens
  final double avgConfidence;

  /// Whether the model recommends cloud handoff (avg confidence below threshold)
  final bool needsCloudHandoff;

  /// Token position in generated sequence
  final int tokenIndex;

  const ConfidenceInfo({
    required this.confidence,
    required this.avgConfidence,
    required this.needsCloudHandoff,
    required this.tokenIndex,
  });

  /// Whether confidence was computed (threshold was > 0)
  bool get isComputed => confidence >= 0.0;

  @override
  String toString() =>
    'ConfidenceInfo(confidence: ${confidence.toStringAsFixed(3)}, avg: ${avgConfidence.toStringAsFixed(3)}, handoff: $needsCloudHandoff)';
}

/// Exception thrown when embedding operation fails
class EmbeddingException extends EdgeVedaException {
  const EmbeddingException(super.message, {super.details, super.originalError});
}
