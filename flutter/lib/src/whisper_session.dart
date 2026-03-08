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
import 'dart:typed_data';

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

  /// Duration of each audio chunk in milliseconds.
  ///
  /// Defaults to 3000ms (3 seconds). On low-end devices, shorter chunks
  /// (e.g. 2000ms) reduce per-chunk inference time at the cost of more
  /// frequent transcription calls.
  final int chunkSizeMs;

  /// Timeout for each transcription call.
  ///
  /// Defaults to 30 seconds. On slow (CPU-only) devices, increase to
  /// 60-90 seconds to avoid premature timeout during inference.
  final Duration transcriptionTimeout;

  /// Callback fired when consecutive transcription failures suggest
  /// the device cannot keep up with Whisper inference.
  ///
  /// The parameter is the current consecutive failure count. Fires at
  /// 2 failures (before [onError] fires at 3) to give the caller time
  /// to switch to a fallback STT engine.
  final void Function(int consecutiveFailures)? onFallbackNeeded;

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
  late final int _chunkSizeSamples = _sampleRate * chunkSizeMs ~/ 1000;

  // Guard against re-entrant _processChunk calls.
  // Only one transcription can be in-flight at a time because
  // WhisperWorker.transcribeChunk uses a broadcast stream pattern
  // that races when multiple callers listen concurrently.
  bool _isProcessing = false;

  // Track consecutive transcription failures so callers can surface errors.
  int _consecutiveFailures = 0;
  static const int _maxConsecutiveFailures = 3;

  final StreamController<WhisperSegment> _segmentController =
      StreamController<WhisperSegment>.broadcast();

  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  /// Whether the session is active and ready for audio input.
  bool get isActive => _isActive;

  /// Stream of transcription segments as they are produced.
  Stream<WhisperSegment> get onSegment => _segmentController.stream;

  /// Stream of transcription error messages.
  Stream<String> get onError => _errorController.stream;

  /// Number of consecutive transcription failures.
  int get consecutiveFailures => _consecutiveFailures;

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
    int frameCount = 0;
    return channel
        .receiveBroadcastStream()
        .map((data) {
          frameCount++;
          if (frameCount % 10 == 0) {
            debugPrint(
              'EdgeVeda: Received audio frame $frameCount, type: ${data.runtimeType}',
            );
          }
          return _decodeAudioSamples(data);
        })
        .where((samples) => samples.isNotEmpty);
  }

  static Float32List _decodeAudioSamples(dynamic data) {
    if (data is Float32List) return data;

    if (data is Float64List) {
      return Float32List.fromList(data);
    }

    if (data is List) {
      final numeric = data.whereType<num>().toList(growable: false);
      if (numeric.length == data.length) {
        return Float32List.fromList(
          numeric.map((n) => n.toDouble()).toList(growable: false),
        );
      }
    }

    ByteBuffer? buffer;
    int offsetInBytes = 0;
    int lengthInBytes = 0;

    if (data is Uint8List) {
      buffer = data.buffer;
      offsetInBytes = data.offsetInBytes;
      lengthInBytes = data.lengthInBytes;
    } else if (data is ByteData) {
      buffer = data.buffer;
      offsetInBytes = data.offsetInBytes;
      lengthInBytes = data.lengthInBytes;
    }

    if (buffer != null && lengthInBytes >= 4) {
      final sampleCount = lengthInBytes ~/ 4;
      final bytesLength = sampleCount * 4;
      if (sampleCount == 0) return Float32List(0);

      if (offsetInBytes % 4 == 0) {
        return Float32List.view(buffer, offsetInBytes, sampleCount);
      }

      final byteView = Uint8List.view(buffer, offsetInBytes, bytesLength);
      final byteData = ByteData.sublistView(byteView);
      final out = Float32List(sampleCount);
      for (int i = 0; i < sampleCount; i++) {
        out[i] = byteData.getFloat32(i * 4, Endian.little);
      }
      return out;
    }

    debugPrint(
      'EdgeVeda: Unsupported microphone payload type ${data.runtimeType}',
    );
    return Float32List(0);
  }

  /// Request microphone recording permission.
  ///
  /// Returns true if permission was granted, false otherwise.
  /// On iOS this triggers the system permission dialog on first call.
  static Future<bool> requestMicrophonePermission() async {
    const channel = MethodChannel('com.edgeveda.edge_veda/telemetry');
    final result = await channel.invokeMethod<bool>(
      'requestMicrophonePermission',
    );
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
    this.chunkSizeMs = 3000,
    this.transcriptionTimeout = const Duration(seconds: 30),
    this.onFallbackNeeded,
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
    scheduler?.registerWorkload(WorkloadId.stt, priority: WorkloadPriority.low);

    _isActive = true;
  }

  /// Feed raw PCM audio samples for transcription.
  ///
  /// Samples must be 16kHz mono float32 (values between -1.0 and 1.0).
  /// Audio is accumulated internally and transcribed in [chunkSizeMs]-ms chunks.
  /// If the Scheduler has paused the STT workload, audio is buffered but
  /// not transcribed until QoS is restored.
  void feedAudio(Float32List samples) {
    if (!_isActive) return;

    // Accumulate samples
    _audioBuffer.addAll(samples);

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
  /// Waits up to [timeout] for any in-flight transcription to complete.
  Future<void> flush({Duration timeout = const Duration(seconds: 5)}) async {
    if (!_isActive || _audioBuffer.isEmpty) return;
    // Wait for in-flight transcription to complete, with a hard timeout
    // to prevent the stop button from hanging indefinitely.
    final deadline = DateTime.now().add(timeout);
    while (_isProcessing && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    if (_isProcessing) {
      debugPrint('EdgeVeda: flush() timed out waiting for in-flight transcription');
      _isProcessing = false;
    }
    if (_isActive && _audioBuffer.isNotEmpty) {
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
        return; // QoS paused -- buffer audio but don't transcribe
      }
    }

    _isProcessing = true;

    // Take up to chunkSizeSamples from buffer
    final chunkLen =
        _audioBuffer.length < _chunkSizeSamples
            ? _audioBuffer.length
            : _chunkSizeSamples;
    final chunk = Float32List.fromList(_audioBuffer.sublist(0, chunkLen));

    // Remove processed samples from buffer
    _audioBuffer.removeRange(0, chunkLen);

    try {
      final stopwatch = Stopwatch()..start();
      final response = await _worker!.transcribeChunk(
        chunk,
        language: language,
        timeout: transcriptionTimeout,
      );
      stopwatch.stop();

      // Report latency to Scheduler for p95 tracking
      scheduler?.reportLatency(
        WorkloadId.stt,
        stopwatch.elapsedMilliseconds.toDouble(),
      );

      _consecutiveFailures = 0; // Reset on success
      for (final segment in response.segments) {
        _segments.add(segment);
        _segmentController.add(segment);
      }
    } catch (e) {
      _consecutiveFailures++;
      final msg = 'Whisper transcription failed: $e';
      debugPrint('EdgeVeda: $msg (failure $_consecutiveFailures/$_maxConsecutiveFailures)');
      // Fire fallback hint at 2 failures (before error stream fires at 3)
      if (_consecutiveFailures == 2 && onFallbackNeeded != null) {
        onFallbackNeeded!(_consecutiveFailures);
      }
      if (_consecutiveFailures >= _maxConsecutiveFailures) {
        _errorController.add(msg);
      }
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
  /// Immediately cancels any in-flight work and disposes the worker.
  /// The caller should call [flush] before [stop] if they want to
  /// process remaining audio; [stop] itself will not wait.
  Future<void> stop() async {
    if (!_isActive) return;

    _isActive = false;
    _isProcessing = false;
    _consecutiveFailures = 0;
    _audioBuffer.clear();

    // Unregister STT workload from Scheduler
    scheduler?.unregisterWorkload(WorkloadId.stt);

    // Dispose worker with a safety timeout so stop() never hangs
    // even if the native whisper context is stuck.
    try {
      await _worker?.dispose().timeout(const Duration(seconds: 3));
    } catch (_) {
      debugPrint('EdgeVeda: Worker dispose timed out, force-killing isolate');
      _worker = null;
    }
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
    _errorController.close();
  }
}
