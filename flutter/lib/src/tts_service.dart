import 'dart:async';

import 'package:flutter/services.dart';

/// State of the TTS engine.
enum TtsState {
  /// Not speaking.
  idle,

  /// Currently speaking an utterance.
  speaking,

  /// Speech paused mid-utterance.
  paused,
}

/// Type of TTS event received from the platform.
enum TtsEventType {
  /// Utterance started speaking.
  start,

  /// Utterance finished speaking (reached end of text).
  finish,

  /// Utterance was cancelled before finishing.
  cancel,

  /// About to speak a specific word (provides character range).
  wordBoundary,
}

/// An event from the iOS AVSpeechSynthesizer.
///
/// For [TtsEventType.wordBoundary] events, [wordStart], [wordLength], and
/// [word] describe the word about to be spoken.
class TtsEvent {
  /// The type of event.
  final TtsEventType type;

  /// Character offset of the word in the original text (wordBoundary only).
  final int? wordStart;

  /// Character length of the word (wordBoundary only).
  final int? wordLength;

  /// The word text itself (wordBoundary only).
  final String? word;

  const TtsEvent({
    required this.type,
    this.wordStart,
    this.wordLength,
    this.word,
  });

  /// Parse a platform event map into a [TtsEvent].
  factory TtsEvent.fromMap(Map<String, dynamic> map) {
    final typeStr = map['type'] as String;
    final type = switch (typeStr) {
      'start' => TtsEventType.start,
      'finish' => TtsEventType.finish,
      'cancel' => TtsEventType.cancel,
      'wordBoundary' => TtsEventType.wordBoundary,
      _ => TtsEventType.start,
    };

    return TtsEvent(
      type: type,
      wordStart: map['start'] as int?,
      wordLength: map['length'] as int?,
      word: map['text'] as String?,
    );
  }

  @override
  String toString() =>
      'TtsEvent($type${word != null ? ', word: "$word"' : ''})';
}

/// A voice available on the device for text-to-speech.
class TtsVoice {
  /// Platform voice identifier (e.g., "com.apple.voice.enhanced.en-US.Samantha").
  final String id;

  /// Human-readable voice name (e.g., "Samantha").
  final String name;

  /// BCP-47 language tag (e.g., "en-US").
  final String language;

  /// Voice quality level (2 = enhanced, 3 = premium).
  final int quality;

  const TtsVoice({
    required this.id,
    required this.name,
    required this.language,
    required this.quality,
  });

  @override
  String toString() => 'TtsVoice($name, $language, quality=$quality)';
}

/// Text-to-Speech service using iOS AVSpeechSynthesizer via platform channels.
///
/// Provides speak/stop/pause/resume controls, voice selection, and real-time
/// word boundary event streaming. Zero additional binary size -- uses built-in
/// iOS neural voices.
///
/// Usage:
/// ```dart
/// final tts = TtsService();
/// final voices = await tts.availableVoices();
/// await tts.speak('Hello world', voiceId: voices.first.id);
///
/// tts.events.listen((event) {
///   if (event.type == TtsEventType.wordBoundary) {
///     print('Speaking: ${event.word}');
///   }
/// });
/// ```
class TtsService {
  static const _methodChannel =
      MethodChannel('com.edgeveda.edge_veda/telemetry');
  static const _eventChannel =
      EventChannel('com.edgeveda.edge_veda/tts_events');

  Stream<TtsEvent>? _eventStream;
  TtsState _state = TtsState.idle;

  /// Current state of the TTS engine.
  TtsState get state => _state;

  /// Speak the given [text] aloud and wait for speech to finish.
  ///
  /// Returns when the utterance finishes or is cancelled. This blocking
  /// behavior is essential for the voice pipeline -- callers need to know
  /// when TTS is done before resuming the microphone.
  ///
  /// Optional parameters:
  /// - [voiceId]: Platform voice identifier from [availableVoices].
  /// - [rate]: Speech rate 0.0 to 1.0 (default: system default ~0.5).
  /// - [pitch]: Pitch multiplier 0.5 to 2.0 (default: 1.0).
  /// - [volume]: Volume 0.0 to 1.0 (default: 1.0).
  Future<void> speak(
    String text, {
    String? voiceId,
    double? rate,
    double? pitch,
    double? volume,
  }) async {
    try {
      // Set up a completer that resolves when TTS finishes or is cancelled.
      // Must subscribe to events BEFORE invoking speak to avoid race where
      // the finish event fires before we start listening.
      final completer = Completer<void>();
      StreamSubscription<TtsEvent>? subscription;

      subscription = events.listen((event) {
        if (event.type == TtsEventType.finish ||
            event.type == TtsEventType.cancel) {
          subscription?.cancel();
          if (!completer.isCompleted) {
            completer.complete();
          }
        }
      });

      await _methodChannel.invokeMethod('tts_speak', {
        'text': text,
        'voiceId': voiceId,
        'rate': rate,
        'pitch': pitch,
        'volume': volume,
      });

      // Wait for TTS to finish speaking (or be cancelled).
      await completer.future;
    } on MissingPluginException {
      // Non-iOS platform -- silently ignore.
    }
  }

  /// Stop speaking immediately.
  Future<void> stop() async {
    try {
      await _methodChannel.invokeMethod('tts_stop');
      _state = TtsState.idle;
    } on MissingPluginException {
      // Non-iOS platform.
    }
  }

  /// Pause speaking at the current word boundary.
  Future<void> pause() async {
    try {
      await _methodChannel.invokeMethod('tts_pause');
    } on MissingPluginException {
      // Non-iOS platform.
    }
  }

  /// Resume speaking after a pause.
  Future<void> resume() async {
    try {
      await _methodChannel.invokeMethod('tts_resume');
    } on MissingPluginException {
      // Non-iOS platform.
    }
  }

  /// List available voices on the device.
  ///
  /// Returns only enhanced/premium quality voices when available.
  /// Returns an empty list on non-iOS platforms.
  Future<List<TtsVoice>> availableVoices() async {
    try {
      final result = await _methodChannel.invokeMethod<List<dynamic>>('tts_voices');
      if (result == null) return [];

      return result
          .cast<Map<dynamic, dynamic>>()
          .map((map) => TtsVoice(
                id: map['id'] as String,
                name: map['name'] as String,
                language: map['language'] as String,
                quality: map['quality'] as int,
              ))
          .toList();
    } on MissingPluginException {
      return [];
    }
  }

  /// Stream of TTS events from the platform.
  ///
  /// Events include [TtsEventType.start], [TtsEventType.finish],
  /// [TtsEventType.cancel], and [TtsEventType.wordBoundary] with
  /// character range information for word highlighting.
  ///
  /// The stream is broadcast -- multiple listeners are supported.
  /// Internally updates [state] based on events received.
  Stream<TtsEvent> get events {
    _eventStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((dynamic event) {
          final map = Map<String, dynamic>.from(event as Map);
          final ttsEvent = TtsEvent.fromMap(map);

          // Update internal state.
          switch (ttsEvent.type) {
            case TtsEventType.start:
              _state = TtsState.speaking;
              break;
            case TtsEventType.finish:
            case TtsEventType.cancel:
              _state = TtsState.idle;
              break;
            case TtsEventType.wordBoundary:
              // No state change for word boundaries.
              break;
          }

          return ttsEvent;
        })
        .asBroadcastStream();
    return _eventStream!;
  }
}
