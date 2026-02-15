import 'dart:async';
import 'dart:typed_data';

import 'package:edge_veda/edge_veda.dart';

/// Wraps [WhisperSession] for voice recording with live transcription.
///
/// Handles model initialization, microphone capture, segment accumulation,
/// and graceful error handling (e.g., simulator with no microphone).
class SttService {
  WhisperSession? _session;
  StreamSubscription<Float32List>? _audioSubscription;
  StreamSubscription<WhisperSegment>? _segmentSubscription;

  final StreamController<String> _transcriptController =
      StreamController<String>.broadcast();

  String _fullTranscript = '';
  bool _isRecording = false;
  bool _isReady = false;
  DateTime? _recordingStart;

  /// Whether the whisper model is loaded and ready.
  bool get isReady => _isReady;

  /// Whether currently recording audio.
  bool get isRecording => _isRecording;

  /// Stream of transcript updates (full accumulated text).
  Stream<String> get onTranscript => _transcriptController.stream;

  /// The full accumulated transcript.
  String get fullTranscript => _fullTranscript;

  /// Recording duration in seconds (0 if not recording).
  int get recordingDurationSeconds {
    if (_recordingStart == null) return 0;
    return DateTime.now().difference(_recordingStart!).inSeconds;
  }

  /// Initialize the service: download/locate whisper model and create session.
  Future<void> init({
    void Function(String)? onStatus,
  }) async {
    onStatus?.call('Loading speech model...');

    final mm = ModelManager();
    final modelPath =
        await mm.getModelPath(ModelRegistry.whisperBaseEn.id);

    _session = WhisperSession(modelPath: modelPath);
    await _session!.start();

    _isReady = true;
    onStatus?.call('Speech model ready');
  }

  /// Start recording from the microphone with live transcription.
  ///
  /// Returns null on success, or an error message if microphone is unavailable.
  Future<String?> startRecording() async {
    if (!_isReady || _isRecording) return 'Service not ready';

    // Request microphone permission
    final granted = await WhisperSession.requestMicrophonePermission();
    if (!granted) return 'Microphone permission denied';

    // Reset state
    _fullTranscript = '';
    _session?.resetTranscript();
    _recordingStart = DateTime.now();

    // Listen for transcription segments
    _segmentSubscription = _session!.onSegment.listen((segment) {
      _fullTranscript = _session!.transcript;
      _transcriptController.add(_fullTranscript);
    });

    // Start microphone audio capture.
    // On simulator, microphone() emits an error (sampleRate=0).
    try {
      _audioSubscription = WhisperSession.microphone().listen(
        (samples) {
          _session?.feedAudio(samples);
        },
        onError: (error) {
          // Microphone unavailable (e.g., simulator). Stop gracefully.
          _isRecording = false;
          _transcriptController.addError(
            'Microphone unavailable: $error',
          );
        },
      );
    } catch (e) {
      _segmentSubscription?.cancel();
      _segmentSubscription = null;
      return 'Microphone error: $e';
    }

    _isRecording = true;
    return null; // success
  }

  /// Stop recording and return the final transcript.
  Future<String> stopRecording() async {
    _isRecording = false;

    // Stop audio capture
    await _audioSubscription?.cancel();
    _audioSubscription = null;

    // Flush remaining audio for transcription
    await _session?.flush();
    // Note: stop() is not called here because we want to reuse the session.
    // WhisperSession.stop() would unload the model.

    _segmentSubscription?.cancel();
    _segmentSubscription = null;

    // Update final transcript
    if (_session != null) {
      _fullTranscript = _session!.transcript;
    }

    return _fullTranscript;
  }

  /// Dispose the service and release resources.
  void dispose() {
    _audioSubscription?.cancel();
    _segmentSubscription?.cancel();
    _session?.dispose();
    _transcriptController.close();
  }
}
