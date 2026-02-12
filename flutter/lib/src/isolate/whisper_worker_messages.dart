/// Typed message classes for WhisperWorker isolate communication
///
/// Uses sealed classes for exhaustive pattern matching on message types.
/// All messages are simple data classes with primitive/serializable fields
/// that can safely cross isolate boundaries.
///
/// See also: [vision_worker_messages.dart] for the vision equivalent.
library;

import 'dart:typed_data';

// =============================================================================
// Commands (Main Isolate -> WhisperWorker Isolate)
// =============================================================================

/// Base class for all commands sent to the whisper worker isolate
sealed class WhisperWorkerCommand {}

/// Initialize whisper context with model path and inference options
class InitWhisperCommand extends WhisperWorkerCommand {
  /// Path to Whisper GGUF model file
  final String modelPath;

  /// Number of CPU threads for inference (0 = auto-detect)
  final int numThreads;

  /// Use GPU acceleration (Metal on iOS/macOS)
  final bool useGpu;

  InitWhisperCommand({
    required this.modelPath,
    this.numThreads = 4,
    this.useGpu = true,
  });
}

/// Transcribe a chunk of PCM audio samples
class TranscribeChunkCommand extends WhisperWorkerCommand {
  /// Raw PCM audio samples (16kHz mono float32, values between -1.0 and 1.0)
  final Float32List pcmSamples;

  /// Language code: "en", "auto", etc.
  final String language;

  /// Translate to English (true = translate, false = transcribe only)
  final bool translate;

  TranscribeChunkCommand({
    required this.pcmSamples,
    this.language = 'en',
    this.translate = false,
  });
}

/// Dispose the whisper worker and free all native resources
class DisposeWhisperCommand extends WhisperWorkerCommand {}

// =============================================================================
// Responses (WhisperWorker Isolate -> Main Isolate)
// =============================================================================

/// Base class for all responses from the whisper worker isolate
sealed class WhisperWorkerResponse {}

/// Whisper context initialized successfully
class WhisperInitSuccessResponse extends WhisperWorkerResponse {
  /// Backend being used (Metal, CPU, etc.)
  final String backend;

  WhisperInitSuccessResponse({required this.backend});
}

/// Whisper context initialization failed
class WhisperInitErrorResponse extends WhisperWorkerResponse {
  /// Error message describing the failure
  final String message;

  /// Native error code from ev_whisper_init
  final int errorCode;

  WhisperInitErrorResponse({required this.message, required this.errorCode});
}

/// Transcription completed with segments and timing
class WhisperTranscribeResponse extends WhisperWorkerResponse {
  /// Transcription segments with text and timing
  final List<WhisperSegment> segments;

  /// Total processing time in milliseconds
  final double processTimeMs;

  WhisperTranscribeResponse({
    required this.segments,
    required this.processTimeMs,
  });
}

/// Transcription failed
class WhisperErrorResponse extends WhisperWorkerResponse {
  /// Error message describing the failure
  final String message;

  /// Native error code
  final int errorCode;

  WhisperErrorResponse({required this.message, required this.errorCode});
}

/// Whisper worker disposed and ready to terminate
class WhisperDisposedResponse extends WhisperWorkerResponse {}

// =============================================================================
// Data Classes
// =============================================================================

/// A single transcription segment with timing information.
///
/// Represents a contiguous piece of transcribed text with start and end
/// timestamps relative to the audio input.
class WhisperSegment {
  /// Transcribed text for this segment
  final String text;

  /// Segment start time in milliseconds
  final int startMs;

  /// Segment end time in milliseconds
  final int endMs;

  const WhisperSegment({
    required this.text,
    required this.startMs,
    required this.endMs,
  });

  @override
  String toString() => 'WhisperSegment("$text", ${startMs}ms-${endMs}ms)';
}
