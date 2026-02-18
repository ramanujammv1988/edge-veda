/// Typed message classes for VisionWorker isolate communication
///
/// Uses sealed classes for exhaustive pattern matching on message types.
/// All messages are simple data classes with primitive/serializable fields
/// that can safely cross isolate boundaries.
///
/// See also: [worker_messages.dart] for the text streaming equivalent.
library;

import 'dart:typed_data';

// =============================================================================
// Commands (Main Isolate -> VisionWorker Isolate)
// =============================================================================

/// Base class for all commands sent to the vision worker isolate
sealed class VisionWorkerCommand {}

/// Initialize vision context with model and mmproj paths
class InitVisionCommand extends VisionWorkerCommand {
  /// Path to VLM GGUF model file
  final String modelPath;

  /// Path to mmproj (multimodal projector) GGUF file
  final String mmprojPath;

  /// Number of CPU threads for inference (0 = auto-detect)
  final int numThreads;

  /// Token context window size
  final int contextSize;

  /// Use GPU acceleration (Metal on iOS)
  final bool useGpu;

  /// Memory limit in bytes (0 = no limit)
  final int memoryLimitBytes;

  InitVisionCommand({
    required this.modelPath,
    required this.mmprojPath,
    required this.numThreads,
    required this.contextSize,
    required this.useGpu,
    this.memoryLimitBytes = 0,
  });
}

/// Describe a single camera frame
class DescribeFrameCommand extends VisionWorkerCommand {
  /// Raw RGB pixel bytes (width * height * 3)
  final Uint8List rgbBytes;

  /// Image width in pixels
  final int width;

  /// Image height in pixels
  final int height;

  /// Prompt to guide the vision model description
  final String prompt;

  /// Maximum tokens to generate
  final int maxTokens;

  /// Sampling temperature (lower = more deterministic)
  final double temperature;

  DescribeFrameCommand({
    required this.rgbBytes,
    required this.width,
    required this.height,
    this.prompt = 'Describe what you see.',
    this.maxTokens = 100,
    this.temperature = 0.3,
  });
}

/// Dispose the vision worker and free all native resources
class DisposeVisionCommand extends VisionWorkerCommand {}

// =============================================================================
// Responses (VisionWorker Isolate -> Main Isolate)
// =============================================================================

/// Base class for all responses from the vision worker isolate
sealed class VisionWorkerResponse {}

/// Vision context initialized successfully
class VisionInitSuccessResponse extends VisionWorkerResponse {
  /// Backend being used (Metal, CPU, etc.)
  final String backend;

  VisionInitSuccessResponse({required this.backend});
}

/// Vision context initialization failed
class VisionInitErrorResponse extends VisionWorkerResponse {
  /// Error message describing the failure
  final String message;

  /// Native error code from ev_vision_init
  final int errorCode;

  VisionInitErrorResponse({required this.message, required this.errorCode});
}

/// Vision inference completed with description and timing data
class VisionResultResponse extends VisionWorkerResponse {
  /// Generated description of the image
  final String description;

  /// Model load time in milliseconds (0.0 if already loaded)
  final double modelLoadMs;

  /// Image encoding time in milliseconds
  final double imageEncodeMs;

  /// Prompt evaluation time in milliseconds
  final double promptEvalMs;

  /// Token decode time in milliseconds
  final double decodeMs;

  /// Number of prompt tokens processed
  final int promptTokens;

  /// Number of tokens generated
  final int generatedTokens;

  VisionResultResponse({
    required this.description,
    this.modelLoadMs = 0.0,
    this.imageEncodeMs = 0.0,
    this.promptEvalMs = 0.0,
    this.decodeMs = 0.0,
    this.promptTokens = 0,
    this.generatedTokens = 0,
  });
}

/// Vision inference failed
class VisionErrorResponse extends VisionWorkerResponse {
  /// Error message describing the failure
  final String message;

  /// Native error code
  final int errorCode;

  VisionErrorResponse({required this.message, required this.errorCode});
}

/// Vision worker disposed and ready to terminate
class VisionDisposedResponse extends VisionWorkerResponse {}
