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
import 'package:flutter/services.dart';

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

  // Guard against re-entrant _processChunk calls.
  // Only one transcription can be in-flight at a time because
  // WhisperWorker.transcribeChunk uses a broadcast stream pattern
  // that races when multiple callers listen concurrently.
  bool _isProcessing = false;

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

  // =========================================================================
  // Static helpers for microphone audio capture
  // =========================================================================

  /// Create a stream of PCM audio from the device microphone.
  ///
  /// Returns [Float32List] chunks of 16kHz mono audio captured via
  /// AVAudioEngine on iOS. The EventChannel is managed by
  /// [EVAudioCaptureHandler] in EdgeVedaPlugin.m.
  ///
  /// Call [Stream.listen] to start capture, cancel the subscription to stop.
  static Stream<Float32List> microphone() {
    const channel = EventChannel('com.edgeveda.edge_veda/audio_capture');
    return channel.receiveBroadcastStream().map((data) {
      if (data is Float32List) return data;
      // FlutterStandardTypedData comes as Float64List on some platforms
      if (data is List<double>) return Float32List.fromList(data);
      return Float32List(0);
    });
  }

  /// Request microphone recording permission.
  ///
  /// Returns true if permission was granted, false otherwise.
  /// On iOS this triggers the system permission dialog on first call.
  static Future<bool> requestMicrophonePermission() async {
    const channel = MethodChannel('com.edgeveda.edge_veda/telemetry');
    final result =
        await channel.invokeMethod<bool>('requestMicrophonePermission');
    return result ?? false;
  }

  // =========================================================================

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

  // Counter for periodic feed logging
  int _feedCount = 0;

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
    _feedCount++;

    // Log every ~1 second (every 3rd callback at ~300ms intervals)
    if (_feedCount % 3 == 0) {
      debugPrint('[WhisperSession] feedAudio #$_feedCount: '
          '+${samples.length} samples, '
          'buffer=${_audioBuffer.length}/$_chunkSizeSamples'
          '${_isProcessing ? " (processing)" : ""}');
    }

    // Process when we have enough for a chunk.
    // Skip if another _processChunk is already in-flight to avoid
    // broadcast stream race condition in WhisperWorker.
    if (_audioBuffer.length >= _chunkSizeSamples && !_isProcessing) {
      _processChunk();
    }
  }

  /// Force transcription of any remaining buffered audio.
  ///
  /// Useful when recording stops and you want the last partial chunk.
  /// Waits for any in-flight transcription to complete first.
  Future<void> flush() async {
    if (!_isActive || _audioBuffer.isEmpty) return;
    // Wait for in-flight transcription to complete before flushing
    while (_isProcessing) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (_audioBuffer.isNotEmpty) {
      await _processChunk();
    }
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

    _isProcessing = true;

    // Take up to chunkSizeSamples from buffer
    final chunkLen = _audioBuffer.length < _chunkSizeSamples
        ? _audioBuffer.length
        : _chunkSizeSamples;
    final chunk = Float32List.fromList(_audioBuffer.sublist(0, chunkLen));

    // Remove processed samples from buffer
    _audioBuffer.removeRange(0, chunkLen);

    debugPrint('[WhisperSession] Transcribing chunk: $chunkLen samples, '
        '${(chunkLen / _sampleRate * 1000).round()}ms of audio, '
        'buffer remaining: ${_audioBuffer.length}');

    try {
      final stopwatch = Stopwatch()..start();
      final response = await _worker!.transcribeChunk(
        chunk,
        language: language,
      );
      stopwatch.stop();

      debugPrint('[WhisperSession] Transcription complete: '
          '${response.segments.length} segments in '
          '${stopwatch.elapsedMilliseconds}ms');

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
    } finally {
      _isProcessing = false;

      // If audio accumulated while we were processing, kick off next chunk.
      if (_isActive && _audioBuffer.length >= _chunkSizeSamples) {
        _processChunk();
      }
    }
  }

  /// Stop the transcription session and release resources.
  ///
  /// Flushes any remaining audio before stopping. Unregisters
  /// [WorkloadId.stt] from the [Scheduler].
  Future<void> stop() async {
    if (!_isActive) return;

    // Note: flush() should be called before stop() to process remaining
    // audio. We set _isActive = false here which prevents further
    // processing. The caller (stt_screen) calls flush() then stop().
    _isActive = false;
    _isProcessing = false;

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
