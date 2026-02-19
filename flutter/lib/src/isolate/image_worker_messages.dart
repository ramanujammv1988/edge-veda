/// Typed message classes for ImageWorker isolate communication
///
/// Uses sealed classes for exhaustive pattern matching on message types.
/// All messages are simple data classes with primitive/serializable fields
/// that can safely cross isolate boundaries.
///
/// See also: [whisper_worker_messages.dart] for the whisper equivalent.
library;

import 'dart:typed_data';

// =============================================================================
// Commands (Main Isolate -> ImageWorker Isolate)
// =============================================================================

/// Base class for all commands sent to the image worker isolate
sealed class ImageWorkerCommand {}

/// Initialize image generation context with model path and options
class InitImageCommand extends ImageWorkerCommand {
  /// Path to Stable Diffusion GGUF model file
  final String modelPath;

  /// Number of CPU threads for inference (0 = auto-detect)
  final int numThreads;

  /// Use GPU acceleration (Metal on iOS/macOS)
  final bool useGpu;

  InitImageCommand({
    required this.modelPath,
    this.numThreads = 0,
    this.useGpu = true,
  });
}

/// Generate an image from a text prompt
class GenerateImageCommand extends ImageWorkerCommand {
  /// Text prompt describing desired image
  final String prompt;

  /// Negative prompt to avoid certain features (null = none)
  final String? negativePrompt;

  /// Image width in pixels
  final int width;

  /// Image height in pixels
  final int height;

  /// Number of denoising steps
  final int steps;

  /// Classifier-free guidance scale
  final double cfgScale;

  /// Random seed (-1 = random)
  final int seed;

  /// Sampler type (maps to ev_image_sampler_t enum)
  final int sampler;

  /// Schedule type (maps to ev_image_schedule_t enum)
  final int schedule;

  GenerateImageCommand({
    required this.prompt,
    this.negativePrompt,
    this.width = 512,
    this.height = 512,
    this.steps = 4,
    this.cfgScale = 1.0,
    this.seed = -1,
    this.sampler = 0,
    this.schedule = 0,
  });
}

/// Dispose the image worker and free all native resources
class DisposeImageCommand extends ImageWorkerCommand {}

// =============================================================================
// Responses (ImageWorker Isolate -> Main Isolate)
// =============================================================================

/// Base class for all responses from the image worker isolate
sealed class ImageWorkerResponse {}

/// Image generation context initialized successfully
class ImageInitSuccessResponse extends ImageWorkerResponse {
  /// Backend being used (Metal, CPU, etc.)
  final String backend;

  ImageInitSuccessResponse({required this.backend});
}

/// Image generation context initialization failed
class ImageInitErrorResponse extends ImageWorkerResponse {
  /// Error message describing the failure
  final String message;

  /// Native error code from ev_image_init
  final int errorCode;

  ImageInitErrorResponse({required this.message, required this.errorCode});
}

/// Progress update during image generation (one per denoising step)
class ImageProgressResponse extends ImageWorkerResponse {
  /// Current step number (1-based)
  final int step;

  /// Total number of steps
  final int totalSteps;

  /// Elapsed time in seconds since generation started
  final double elapsedSeconds;

  ImageProgressResponse({
    required this.step,
    required this.totalSteps,
    required this.elapsedSeconds,
  });
}

/// Image generation completed successfully
class ImageCompleteResponse extends ImageWorkerResponse {
  /// Raw pixel data (RGB, width * height * channels bytes)
  final Uint8List pixelData;

  /// Image width in pixels
  final int width;

  /// Image height in pixels
  final int height;

  /// Number of channels (3 for RGB)
  final int channels;

  /// Total generation time in milliseconds
  final double generationTimeMs;

  ImageCompleteResponse({
    required this.pixelData,
    required this.width,
    required this.height,
    required this.channels,
    required this.generationTimeMs,
  });
}

/// Image generation failed
class ImageErrorResponse extends ImageWorkerResponse {
  /// Error message describing the failure
  final String message;

  /// Native error code
  final int errorCode;

  ImageErrorResponse({required this.message, required this.errorCode});
}

/// Image worker disposed and ready to terminate
class ImageDisposedResponse extends ImageWorkerResponse {}
