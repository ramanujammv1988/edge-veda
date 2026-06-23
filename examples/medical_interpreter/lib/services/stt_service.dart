import 'dart:async';
import 'dart:typed_data';

import 'package:edge_veda/edge_veda.dart';

/// Multilingual speech-to-text service using Whisper Small Multilingual.
///
/// Wraps [WhisperSession] for voice recording with live transcription
/// in 50+ languages. Handles model init, microphone capture,
/// segment accumulation, and graceful error handling.
class SttService {
  WhisperSession? _session;
  StreamSubscription<Float32List>? _audioSubscription;
  StreamSubscription<WhisperSegment>? _segmentSubscription;

  final StreamController<String> _transcriptController =
      StreamController<String>.broadcast();

  String _fullTranscript = '';
  bool _isRecording = false;
  bool _isReady = false;

  bool get isReady => _isReady;
  bool get isRecording => _isRecording;
  Stream<String> get onTranscript => _transcriptController.stream;
  String get fullTranscript => _fullTranscript;

  /// Initialize with Whisper Small Multilingual model.
  Future<void> init({void Function(String)? onStatus}) async {
    onStatus?.call('Loading multilingual speech model...');

    final mm = ModelManager();
    final modelPath = await mm.getModelPath(ModelRegistry.whisperSmall.id);

    _session = WhisperSession(modelPath: modelPath);
    await _session!.start();

    _isReady = true;
    onStatus?.call('Speech model ready');
  }

  /// Start recording from the microphone with live transcription.
  ///
  /// Returns null on success, or an error message on failure.
  Future<String?> startRecording() async {
    if (!_isReady || _isRecording) return 'Service not ready';

    final granted = await WhisperSession.requestMicrophonePermission();
    if (!granted) return 'Microphone permission denied';

    _fullTranscript = '';
    _session?.resetTranscript();

    _segmentSubscription = _session!.onSegment.listen((segment) {
      _fullTranscript = _session!.transcript;
      _transcriptController.add(_fullTranscript);
    });

    try {
      _audioSubscription = WhisperSession.microphone().listen(
        (samples) {
          _session?.feedAudio(samples);
        },
        onError: (error) {
          _isRecording = false;
          _transcriptController.addError('Microphone unavailable: $error');
        },
      );
    } catch (e) {
      _segmentSubscription?.cancel();
      _segmentSubscription = null;
      return 'Microphone error: $e';
    }

    _isRecording = true;
    return null;
  }

  /// Stop recording and return the final transcript.
  Future<String> stopRecording() async {
    _isRecording = false;

    await _audioSubscription?.cancel();
    _audioSubscription = null;

    await _session?.flush();

    _segmentSubscription?.cancel();
    _segmentSubscription = null;

    if (_session != null) {
      _fullTranscript = _session!.transcript;
    }

    return _fullTranscript;
  }

  void dispose() {
    _audioSubscription?.cancel();
    _segmentSubscription?.cancel();
    _session?.dispose();
    _transcriptController.close();
  }
}
