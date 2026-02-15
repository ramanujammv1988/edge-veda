/// Typed message classes for worker isolate communication
///
/// Uses sealed classes for exhaustive pattern matching on message types.
/// All messages are simple data classes with primitive/serializable fields
/// that can safely cross isolate boundaries.
library;

// =============================================================================
// Commands (Main Isolate -> Worker Isolate)
// =============================================================================

/// Base class for all commands sent to worker isolate
sealed class WorkerCommand {}

/// Initialize native context with model configuration
class InitWorkerCommand extends WorkerCommand {
  /// Path to model file
  final String modelPath;

  /// Number of CPU threads for inference
  final int numThreads;

  /// Context size in tokens
  final int contextSize;

  /// Use GPU acceleration (Metal on iOS, Vulkan on Android)
  final bool useGpu;

  /// Memory limit in bytes (0 = no limit)
  final int memoryLimitBytes;

  /// Flash attention type (-1=auto, 0=disabled, 1=enabled)
  final int flashAttn;

  /// KV cache type for keys (1=F16, 8=Q8_0)
  final int kvCacheTypeK;

  /// KV cache type for values (1=F16, 8=Q8_0)
  final int kvCacheTypeV;

  InitWorkerCommand({
    required this.modelPath,
    required this.numThreads,
    required this.contextSize,
    required this.useGpu,
    this.memoryLimitBytes = 0,
    this.flashAttn = -1,
    this.kvCacheTypeK = 8,
    this.kvCacheTypeV = 8,
  });
}

/// Start streaming generation for a prompt
class StartStreamCommand extends WorkerCommand {
  /// The prompt to generate from
  final String prompt;

  /// Maximum tokens to generate
  final int maxTokens;

  /// Sampling temperature
  final double temperature;

  /// Top-p nucleus sampling
  final double topP;

  /// Top-k sampling
  final int topK;

  /// Repetition penalty
  final double repeatPenalty;

  /// Confidence threshold for cloud handoff (0.0 = disabled)
  final double confidenceThreshold;

  /// GBNF grammar string (empty = no grammar constraint)
  final String grammarStr;

  /// GBNF grammar root rule name
  final String grammarRoot;

  StartStreamCommand({
    required this.prompt,
    this.maxTokens = 512,
    this.temperature = 0.7,
    this.topP = 0.9,
    this.topK = 40,
    this.repeatPenalty = 1.1,
    this.confidenceThreshold = 0.0,
    this.grammarStr = '',
    this.grammarRoot = '',
  });
}

/// Request next token from active stream
class NextTokenCommand extends WorkerCommand {}

/// Cancel active stream
class CancelStreamCommand extends WorkerCommand {}

/// Query memory stats from the active native context
class GetMemoryStatsCommand extends WorkerCommand {}

/// Dispose worker and free native resources
class DisposeWorkerCommand extends WorkerCommand {}

// =============================================================================
// Responses (Worker Isolate -> Main Isolate)
// =============================================================================

/// Base class for all responses from worker isolate
sealed class WorkerResponse {}

/// Worker initialization succeeded
class InitSuccessResponse extends WorkerResponse {
  /// Backend being used (Metal, CPU, etc.)
  final String backend;

  InitSuccessResponse({required this.backend});
}

/// Worker initialization failed
class InitErrorResponse extends WorkerResponse {
  /// Error message
  final String message;

  /// Native error code
  final int errorCode;

  InitErrorResponse({required this.message, required this.errorCode});
}

/// Stream started successfully
class StreamStartedResponse extends WorkerResponse {}

/// Token generated (or stream ended naturally)
class TokenResponse extends WorkerResponse {
  /// The generated token text (null if stream ended)
  final String? token;

  /// Whether this is the final token (stream complete)
  final bool isFinal;

  /// Native error code (0 = success)
  final int errorCode;

  /// Per-token confidence score (0.0-1.0), -1.0 if not computed
  final double confidence;

  /// Whether cloud handoff is recommended at this point
  final bool needsCloudHandoff;

  TokenResponse({
    this.token,
    required this.isFinal,
    this.errorCode = 0,
    this.confidence = -1.0,
    this.needsCloudHandoff = false,
  });

  /// Create response for successful token
  factory TokenResponse.token(String token) => TokenResponse(
        token: token,
        isFinal: false,
        errorCode: 0,
      );

  /// Create response for stream end
  factory TokenResponse.end() => TokenResponse(
        token: null,
        isFinal: true,
        errorCode: 0,
      );
}

/// Stream error occurred
class StreamErrorResponse extends WorkerResponse {
  /// Error message
  final String message;

  /// Native error code
  final int errorCode;

  StreamErrorResponse({required this.message, required this.errorCode});
}

/// Stream was cancelled
class CancelledResponse extends WorkerResponse {}

/// Memory stats from the native context
class MemoryStatsResponse extends WorkerResponse {
  /// Current total memory usage in bytes
  final int currentBytes;

  /// Peak memory usage in bytes
  final int peakBytes;

  /// Memory limit in bytes
  final int limitBytes;

  /// Memory used by the loaded model in bytes
  final int modelBytes;

  /// Memory used by inference context in bytes
  final int contextBytes;

  MemoryStatsResponse({
    required this.currentBytes,
    required this.peakBytes,
    required this.limitBytes,
    required this.modelBytes,
    required this.contextBytes,
  });
}

/// Worker disposed and ready to terminate
class DisposedResponse extends WorkerResponse {}
