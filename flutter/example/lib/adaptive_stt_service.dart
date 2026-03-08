import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:edge_veda/edge_veda.dart';

/// Which STT engine is currently active.
enum SttEngine { whisper, systemStt }

/// Adaptive STT decision engine.
///
/// Manages automatic fallback between on-device Whisper and Android's built-in
/// SpeechRecognizer. On low-end devices where Whisper repeatedly times out,
/// automatically switches to system STT to maintain usability.
///
/// Usage:
/// ```dart
/// final service = AdaptiveSttService();
/// await service.init();
///
/// // Get device-aware Whisper config
/// final config = service.getWhisperConfig();
/// session = WhisperSession(
///   chunkSizeMs: config.chunkSizeMs,
///   transcriptionTimeout: config.timeout,
///   onFallbackNeeded: service.handleWhisperFallback,
/// );
///
/// // Listen for engine changes
/// service.onEngineChanged.listen((engine) {
///   // Update UI indicator
/// });
///
/// // Listen for system STT segments
/// service.onSegment.listen((segment) {
///   // Process transcription result
/// });
/// ```
class AdaptiveSttService {
  static const _channel = MethodChannel('com.edgeveda.edge_veda/telemetry');
  static const _speechChannel =
      EventChannel('com.edgeveda.edge_veda/speech_recognition');

  SttEngine _currentEngine = SttEngine.whisper;
  SttEngine? _engineOverride;
  bool _systemSttAvailable = false;
  StreamSubscription<dynamic>? _speechSubscription;

  final _engineController = StreamController<SttEngine>.broadcast();
  final _segmentController = StreamController<WhisperSegment>.broadcast();

  /// Current active STT engine.
  SttEngine get currentEngine => _currentEngine;

  /// Whether system STT (SpeechRecognizer) is available on this device.
  bool get isSystemSttAvailable => _systemSttAvailable;

  /// Stream of engine changes (for UI indicator).
  Stream<SttEngine> get onEngineChanged => _engineController.stream;

  /// Stream of transcription segments from whichever engine is active.
  ///
  /// When system STT is active, results are wrapped as [WhisperSegment]
  /// for compatibility with existing transcript display code.
  Stream<WhisperSegment> get onSegment => _segmentController.stream;

  /// Check whether system STT is available and cache the result.
  Future<void> init() async {
    _systemSttAvailable = await checkSystemSttAvailable();
  }

  /// Query Android SpeechRecognizer availability.
  Future<bool> checkSystemSttAvailable() async {
    try {
      final result =
          await _channel.invokeMethod<bool>('speechRecognizer_isAvailable');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Returns device-tier appropriate Whisper configuration.
  ///
  /// - minimum tier: 2000ms chunks, 90s timeout
  /// - low tier: 2000ms chunks, 60s timeout
  /// - medium+ tier: 3000ms chunks, 30s timeout
  ({int chunkSizeMs, Duration timeout}) getWhisperConfig() {
    final tier = DeviceProfile.detect().tier;
    return switch (tier) {
      DeviceTier.minimum => (
        chunkSizeMs: 2000,
        timeout: const Duration(seconds: 90),
      ),
      DeviceTier.low => (
        chunkSizeMs: 2000,
        timeout: const Duration(seconds: 60),
      ),
      _ => (
        chunkSizeMs: 3000,
        timeout: const Duration(seconds: 30),
      ),
    };
  }

  /// Called by WhisperSession's onFallbackNeeded callback.
  ///
  /// When Whisper has failed [consecutiveFailures] times in a row,
  /// this checks if system STT is available and switches to it.
  /// Respects manual engine override.
  void handleWhisperFallback(int consecutiveFailures) {
    // Don't switch if user has forced Whisper
    if (_engineOverride == SttEngine.whisper) return;

    if (_systemSttAvailable) {
      _switchEngine(SttEngine.systemStt);
      startSystemStt();
    } else {
      // No fallback available — stay on Whisper with extended timeout.
      // The WhisperSession will continue retrying.
      debugPrint(
        'EdgeVeda: Whisper failing ($consecutiveFailures failures) '
        'but system STT unavailable — staying on Whisper',
      );
    }
  }

  /// Start the Android SpeechRecognizer and subscribe to results.
  Future<void> startSystemStt() async {
    try {
      await _channel.invokeMethod<bool>('speechRecognizer_start');
    } catch (e) {
      debugPrint('EdgeVeda: Failed to start system STT: $e');
      return;
    }

    _speechSubscription?.cancel();
    _speechSubscription = _speechChannel.receiveBroadcastStream().listen(
      (event) {
        if (event is! Map) return;
        final type = event['type'] as String?;
        if (type == 'result') {
          final text = event['text'] as String? ?? '';
          final isFinal = event['isFinal'] as bool? ?? false;
          if (text.isNotEmpty && isFinal) {
            // Wrap as WhisperSegment for unified transcript handling
            final now = DateTime.now().millisecondsSinceEpoch;
            _segmentController.add(WhisperSegment(
              text: text,
              startMs: now - 3000, // approximate
              endMs: now,
            ));
          }
        }
      },
      onError: (error) {
        debugPrint('EdgeVeda: System STT stream error: $error');
      },
    );
  }

  /// Stop the Android SpeechRecognizer.
  Future<void> stopSystemStt() async {
    _speechSubscription?.cancel();
    _speechSubscription = null;
    try {
      await _channel.invokeMethod<bool>('speechRecognizer_stop');
    } catch (_) {}
  }

  /// Set manual engine override.
  ///
  /// - `SttEngine.whisper` — force Whisper (no auto-fallback)
  /// - `SttEngine.systemStt` — force system STT
  /// - `null` — automatic (allow fallback)
  void setEngineOverride(SttEngine? engine) {
    _engineOverride = engine;
    if (engine != null && engine != _currentEngine) {
      _switchEngine(engine);
    }
  }

  void _switchEngine(SttEngine engine) {
    if (engine == _currentEngine) return;
    _currentEngine = engine;
    _engineController.add(engine);
    debugPrint('EdgeVeda: STT engine switched to ${engine.name}');
  }

  /// Dispose all resources.
  Future<void> dispose() async {
    await stopSystemStt();
    _engineController.close();
    _segmentController.close();
  }
}
