/// High-level streaming transcription session.
///
/// [WhisperSession] manages a [WhisperWorker] and provides a simple API
/// for feeding audio chunks and receiving transcription segments.
/// Integrates with [Scheduler] for budget enforcement -- STT workload
/// is registered on start and governed by the same QoS degradation
/// logic as vision and text workloads.
///
/// Usage:
/// ```dart
/// final session = WhisperSession(modelPath: '/path/to/ggml-tiny.en.bin');
/// await session.start();
///
/// // Feed audio chunks as they arrive from microphone
/// session.feedAudio(pcmSamples);
///
/// // Listen for transcription results
/// session.onSegment.listen((segment) {
///   print('${segment.text} [${segment.startMs}-${segment.endMs}]');
/// });
///
/// await session.stop();
/// ```
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'budget.dart';
import 'isolate/whisper_worker.dart';
import 'isolate/whisper_worker_messages.dart';
import 'scheduler.dart';

/// High-level streaming transcription session with Scheduler integration.
///
/// Wraps [WhisperWorker] with audio accumulation, chunked processing, and
/// budget-aware QoS gating. Audio is accumulated in an internal buffer and
/// transcribed in 3-second chunks. When the [Scheduler] pauses the STT
/// workload (e.g., thermal critical), audio is buffered but not transcribed
/// until QoS is restored.
class WhisperSession {
  /// Path to the Whisper GGUF model file.
  final String modelPath;

  /// Number of CPU threads for inference.
  final int numThreads;

  /// Use GPU acceleration (Metal on iOS/macOS).
  final bool useGpu;

  /// Language code for transcription: "en", "auto", etc.
  final String language;

  /// Optional Scheduler for budget enforcement.
  ///
  /// When provided, STT workload is registered on [start] and
  /// unregistered on [stop]. The Scheduler manages QoS levels
  /// (full/reduced/minimal/paused) across all concurrent workloads.
  final Scheduler? scheduler;

  WhisperWorker? _worker;
  bool _isActive = false;

  // Audio accumulation buffer
  final List<double> _audioBuffer = [];
  static const int _sampleRate = 16000;
  static const int _chunkSizeMs = 3000; // 3 seconds per chunk
  static const int _chunkSizeSamples =
      _sampleRate * _chunkSizeMs ~/ 1000; // 48000 samples

  final StreamController<WhisperSegment> _segmentController =
      StreamController<WhisperSegment>.broadcast();

  /// Whether the session is active and ready for audio input.
  bool get isActive => _isActive;

  /// Stream of transcription segments as they are produced.
  Stream<WhisperSegment> get onSegment => _segmentController.stream;

  /// Accumulated full transcript (all segments concatenated).
  String get transcript => _segments.map((s) => s.text).join(' ').trim();

  final List<WhisperSegment> _segments = [];

  /// All segments produced so far.
  List<WhisperSegment> get segments => List.unmodifiable(_segments);

  /// Creates a new [WhisperSession].
  ///
  /// The [modelPath] must point to a valid Whisper GGUF model file.
  /// The [scheduler] is optional -- when provided, STT workload is
  /// registered for budget enforcement alongside vision/text workloads.
  WhisperSession({
    required this.modelPath,
    this.numThreads = 4,
    this.useGpu = true,
    this.language = 'en',
    this.scheduler,
  });

  /// Start the transcription session.
  ///
  /// Spawns [WhisperWorker], loads the model, and registers
  /// [WorkloadId.stt] with the [Scheduler] (if provided) for budget
  /// enforcement. Throws if model loading fails.
  Future<void> start() async {
    if (_isActive) throw StateError('WhisperSession already started');

    _worker = WhisperWorker();
    await _worker!.spawn();
    await _worker!.initWhisper(
      modelPath: modelPath,
      numThreads: numThreads,
      useGpu: useGpu,
    );

    // Register STT workload with Scheduler for budget enforcement.
    // Priority is low by default -- vision and text are typically more
    // important than background transcription. The Scheduler will degrade
    // STT first when thermal/battery/latency budgets are violated.
    scheduler?.registerWorkload(WorkloadId.stt,
        priority: WorkloadPriority.low);

    _isActive = true;
  }

  /// Feed raw PCM audio samples for transcription.
  ///
  /// Samples must be 16kHz mono float32 (values between -1.0 and 1.0).
  /// Audio is accumulated internally and transcribed in 3-second chunks.
  /// If the Scheduler has paused the STT workload, audio is buffered but
  /// not transcribed until QoS is restored.
  void feedAudio(Float32List samples) {
    if (!_isActive) return;

    // Accumulate samples
    _audioBuffer.addAll(samples);

    // Process when we have enough for a chunk
    if (_audioBuffer.length >= _chunkSizeSamples) {
      _processChunk();
    }
  }

  /// Force transcription of any remaining buffered audio.
  ///
  /// Useful when recording stops and you want the last partial chunk.
  Future<void> flush() async {
    if (!_isActive || _audioBuffer.isEmpty) return;
    await _processChunk();
  }

  Future<void> _processChunk() async {
    if (_worker == null || !_isActive) return;

    // Check Scheduler QoS level -- skip transcription if paused.
    // The Scheduler manages QoS levels generically across all workloads.
    // When STT is paused (e.g., thermal critical), we buffer audio but
    // don't send it for inference, avoiding additional compute load.
    if (scheduler != null) {
      final knobs = scheduler!.getKnobsForWorkload(WorkloadId.stt);
      if (knobs.maxFps == 0) {
        // QoS paused -- buffer audio but don't transcribe
        debugPrint('[WhisperSession] STT paused by Scheduler, buffering audio');
        return;
      }
    }

    // Take up to chunkSizeSamples from buffer
    final chunkLen = _audioBuffer.length < _chunkSizeSamples
        ? _audioBuffer.length
        : _chunkSizeSamples;
    final chunk = Float32List.fromList(
        _audioBuffer.sublist(0, chunkLen).map((d) => d.toDouble()).toList());

    // Remove processed samples from buffer
    _audioBuffer.removeRange(0, chunkLen);

    try {
      final stopwatch = Stopwatch()..start();
      final response = await _worker!.transcribeChunk(
        chunk,
        language: language,
      );
      stopwatch.stop();

      // Report latency to Scheduler for p95 tracking
      scheduler?.reportLatency(
          WorkloadId.stt, stopwatch.elapsedMilliseconds.toDouble());

      for (final segment in response.segments) {
        _segments.add(segment);
        _segmentController.add(segment);
      }
    } catch (e) {
      // Log but don't crash -- audio capture should continue
      debugPrint('[WhisperSession] Transcription error: $e');
    }
  }

  /// Stop the transcription session and release resources.
  ///
  /// Flushes any remaining audio before stopping. Unregisters
  /// [WorkloadId.stt] from the [Scheduler].
  Future<void> stop() async {
    if (!_isActive) return;
    _isActive = false;

    // Flush remaining audio
    if (_audioBuffer.isNotEmpty && _worker != null) {
      try {
        await _processChunk();
      } catch (_) {}
    }

    _audioBuffer.clear();

    // Unregister STT workload from Scheduler
    scheduler?.unregisterWorkload(WorkloadId.stt);

    await _worker?.dispose();
    _worker = null;
  }

  /// Reset the session (clear transcript but keep model loaded).
  void resetTranscript() {
    _segments.clear();
    _audioBuffer.clear();
  }

  /// Dispose the session and close streams.
  Future<void> dispose() async {
    await stop();
    _segmentController.close();
  }
}
