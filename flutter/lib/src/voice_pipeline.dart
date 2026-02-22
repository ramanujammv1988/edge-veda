/// Voice pipeline orchestrator for real-time voice conversations.
///
/// [VoicePipeline] manages the full STT -> LLM -> TTS loop with
/// energy-based VAD for turn detection and stop-mic echo prevention.
/// The pipeline is event-driven: audio frames from the microphone drive
/// state transitions through a well-defined state machine.
///
/// Audio frames are dropped (not processed) during transcribing, thinking,
/// and speaking states to prevent echo. Processing resumes with a cooldown
/// after TTS completes.
///
/// The native [AVAudioSession] is configured for simultaneous mic capture
/// and TTS playback with built-in echo cancellation before the microphone
/// starts.
///
/// Usage:
/// ```dart
/// final pipeline = VoicePipeline(
///   chatSession: chatSession,
///   tts: ttsService,
///   whisperModelPath: '/path/to/ggml-base.en.bin',
///   scheduler: scheduler,
/// );
///
/// pipeline.events.listen((event) {
///   if (event is StateChanged) print('State: ${event.state}');
///   if (event is TranscriptUpdated) print('User: ${event.userText}');
/// });
///
/// await pipeline.start();
/// // ... voice conversation happens ...
/// await pipeline.stop();
/// ```
library;

import 'dart:async';
import 'dart:math' show sqrt;
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'budget.dart';
import 'chat_session.dart';
import 'scheduler.dart';
import 'tts_service.dart';
import 'types.dart' show CancelToken, GenerateOptions;
import 'whisper_session.dart';

/// Pipeline state machine states.
///
/// Transitions:
/// - idle -> listening (on start)
/// - listening -> transcribing (after speech + silence detected)
/// - transcribing -> thinking (after transcript obtained)
/// - thinking -> speaking (after LLM response completes)
/// - speaking -> listening (after TTS finishes + cooldown)
/// - any -> error (on fatal error)
/// - any -> idle (on stop)
enum VoicePipelineState {
  /// Pipeline not running.
  idle,

  /// Waiting for user speech (mic active, VAD monitoring).
  listening,

  /// Processing speech-to-text on accumulated audio.
  transcribing,

  /// Waiting for LLM response generation.
  thinking,

  /// TTS is speaking the assistant response.
  speaking,

  /// An error occurred (pipeline must be stopped and restarted).
  error,
}

/// Events emitted by [VoicePipeline] during operation.
sealed class VoicePipelineEvent {}

/// Emitted when the pipeline transitions to a new state.
class StateChanged extends VoicePipelineEvent {
  /// The new pipeline state.
  final VoicePipelineState state;

  /// Audio level (RMS energy) during listening state, 0.0 otherwise.
  final double audioLevel;

  StateChanged(this.state, {this.audioLevel = 0.0});
}

/// Emitted when a transcript is available or updated.
class TranscriptUpdated extends VoicePipelineEvent {
  /// The user's transcribed speech.
  final String userText;

  /// The assistant's response text (null before LLM responds).
  final String? assistantText;

  /// True during streaming LLM response (partial text).
  final bool isPartial;

  TranscriptUpdated(this.userText, this.assistantText,
      {this.isPartial = false});
}

/// Emitted when an error occurs in the pipeline.
class PipelineError extends VoicePipelineEvent {
  /// Human-readable error description.
  final String message;

  /// Whether the pipeline must be stopped (non-recoverable).
  final bool fatal;

  PipelineError(this.message, {this.fatal = false});
}

/// Configuration for [VoicePipeline] with sensible defaults.
///
/// All durations and thresholds are based on research recommendations
/// for on-device voice conversation loops.
class VoicePipelineConfig {
  /// Duration of silence after speech to trigger end-of-turn.
  /// 10 frames at 100ms each = 1 second.
  final Duration silenceDuration;

  /// VAD threshold multiplier: threshold = mean + (multiplier * stddev).
  /// 2.5 provides good speech/silence separation without false triggers.
  final double thresholdMultiplier;

  /// Cooldown after TTS finishes before resuming microphone.
  /// Prevents residual audio from triggering false speech detection.
  final Duration ttsCooldown;

  /// Auto-stop pipeline after this much continuous silence.
  /// 30 seconds prevents battery drain from forgotten sessions.
  final Duration silenceTimeout;

  /// TTS voice identifier (platform-specific).
  final String? voiceId;

  /// TTS speech rate (0.0 to 1.0).
  final double ttsRate;

  /// Maximum tokens for LLM response generation.
  final int maxResponseTokens;

  /// Optional system prompt for the ChatSession.
  final String? systemPrompt;

  const VoicePipelineConfig({
    this.silenceDuration = const Duration(milliseconds: 1000),
    this.thresholdMultiplier = 2.5,
    this.ttsCooldown = const Duration(milliseconds: 800),
    this.silenceTimeout = const Duration(seconds: 30),
    this.voiceId,
    this.ttsRate = 0.5,
    this.maxResponseTokens = 256,
    this.systemPrompt,
  });
}

/// Voice conversation pipeline: STT -> LLM -> TTS with energy-based VAD.
///
/// Manages the full voice conversation loop. Audio frames from the
/// microphone drive state transitions through a well-defined state
/// machine. The pipeline:
///
/// 1. Starts listening immediately (no calibration phase)
/// 2. Listens for speech using energy-based VAD
/// 3. Transcribes speech via WhisperSession
/// 4. Streams LLM response via ChatSession.sendStream() with CancelToken
/// 5. Speaks the response via TtsService
/// 6. Returns to listening for the next turn
///
/// Drops audio frames during transcribing, thinking, and speaking states
/// to prevent echo. Resumes processing with a cooldown after TTS completes.
///
/// App lifecycle: call [pause] when going to background, [resume] when
/// returning to foreground. The microphone subscription is paused (not
/// cancelled) and the audio session is reconfigured on resume.
class VoicePipeline {
  final ChatSession _chatSession;
  final TtsService _tts;
  final String _whisperModelPath;
  final Scheduler? _scheduler;
  final VoicePipelineConfig config;

  static const _methodChannel =
      MethodChannel('com.edgeveda.edge_veda/telemetry');

  // State machine
  VoicePipelineState _state = VoicePipelineState.idle;
  final StreamController<VoicePipelineEvent> _eventController =
      StreamController<VoicePipelineEvent>.broadcast();

  // Sessions and subscriptions
  WhisperSession? _whisperSession;
  StreamSubscription<Float32List>? _micSubscription;
  StreamSubscription<TtsEvent>? _ttsSubscription;
  CancelToken? _llmCancelToken;

  // VAD state
  /// Fixed VAD threshold. No calibration needed -- 0.03 works well across
  /// typical environments.
  final double _threshold = 0.03;
  int _silentFrameCount = 0;
  int _totalSilentFrameCount = 0;
  bool _speechDetected = false;
  int _speechFrameCount = 0;

  // Conversation loop guards
  bool _isProcessingTurn = false;

  // Mic gating flag: when false, _onAudioFrame drops all frames.
  // We do NOT use StreamSubscription.pause()/resume() for turn-cycle
  // mic control because Dart broadcast stream subscriptions buffer events
  // during pause. On resume, the entire backlog (containing TTS speaker
  // audio picked up by the mic) would be delivered at once and fed to
  // Whisper, causing the assistant's response to spill over as the next
  // "user" transcript. Instead, the subscription runs continuously and
  // this flag gates processing.
  bool _micListening = false;

  // Conversation transcript tracking
  final List<({String user, String assistant})> _turns = [];

  // App lifecycle state
  VoicePipelineState? _pausedFromState;

  // Audio frame constants
  static const int _frameSizeMs = 100;
  static const int _frameSizeSamples = 1600; // 100ms at 16kHz

  // Internal buffer for chunking incoming audio into fixed-size frames
  final List<double> _frameBuffer = [];

  /// Create a voice pipeline.
  ///
  /// [chatSession] provides the LLM conversation backend.
  /// [tts] provides text-to-speech output.
  /// [whisperModelPath] is the path to a Whisper GGUF model for STT.
  /// [scheduler] is optional for budget enforcement.
  /// [config] provides tuning parameters with sensible defaults.
  VoicePipeline({
    required ChatSession chatSession,
    required TtsService tts,
    required String whisperModelPath,
    Scheduler? scheduler,
    this.config = const VoicePipelineConfig(),
  })  : _chatSession = chatSession,
        _tts = tts,
        _whisperModelPath = whisperModelPath,
        _scheduler = scheduler;

  /// Broadcast event stream for pipeline state changes, transcripts, and errors.
  Stream<VoicePipelineEvent> get events => _eventController.stream;

  /// Current pipeline state.
  VoicePipelineState get state => _state;

  /// Whether the pipeline is currently active (not idle or error).
  bool get isActive =>
      _state != VoicePipelineState.idle &&
      _state != VoicePipelineState.error;

  /// All completed conversation turns.
  ///
  /// Each turn is a (user, assistant) record of the user's transcribed speech
  /// and the assistant's response. Independent of ChatSession's internal
  /// history which may have summarization/rollback.
  List<({String user, String assistant})> get turns =>
      List.unmodifiable(_turns);

  /// Start the voice pipeline.
  ///
  /// Configures the native audio session for simultaneous mic + speaker,
  /// creates a WhisperSession, registers with the Scheduler, subscribes
  /// to TTS events, starts the microphone, and begins listening.
  ///
  /// Throws [StateError] if the pipeline is already running.
  Future<void> start() async {
    if (_state != VoicePipelineState.idle) {
      throw StateError(
          'VoicePipeline.start() called in state $_state (expected idle)');
    }

    try {
      // Configure native audio session: PlayAndRecord + VoiceChat + echo cancellation
      await _configureAudioSession();

      // Create and start WhisperSession (no scheduler -- pipeline manages its own)
      _whisperSession = WhisperSession(modelPath: _whisperModelPath);
      await _whisperSession!.start();

      // Register voice pipeline workload with Scheduler at high priority
      _scheduler?.registerWorkload(WorkloadId.voicePipeline,
          priority: WorkloadPriority.high);

      // Subscribe to TTS events for state transitions on finish/cancel
      _ttsSubscription = _tts.events.listen(_onTtsEvent);

      // Start microphone -- called ONCE, never restarted
      _micSubscription = WhisperSession.microphone().listen(_onAudioFrame);

      // Begin listening immediately (no calibration phase)
      _silentFrameCount = 0;
      _totalSilentFrameCount = 0;
      _speechDetected = false;
      _speechFrameCount = 0;
      _frameBuffer.clear();
      _micListening = true;
      _setState(VoicePipelineState.listening);
    } catch (e) {
      _setState(VoicePipelineState.error);
      _emit(PipelineError('Failed to start pipeline: $e',
          fatal: true));
      // Clean up any partially initialized resources
      await _cleanup();
      rethrow;
    }
  }

  /// Core audio frame processing callback.
  ///
  /// Runs on every microphone delivery (~300ms at a time from native).
  /// Gated by [_micListening] -- frames are dropped when not listening
  /// to avoid processing stale buffered audio from during TTS playback.
  /// Chunks into 100ms (1600 sample) frames, calculates RMS energy,
  /// and dispatches to the current state handler.
  void _onAudioFrame(Float32List samples) {
    if (!_micListening) return;

    // Accumulate into frame buffer
    for (int i = 0; i < samples.length; i++) {
      _frameBuffer.add(samples[i]);
    }

    // Process complete frames
    while (_frameBuffer.length >= _frameSizeSamples) {
      // Extract one frame
      final frame = Float32List(_frameSizeSamples);
      for (int i = 0; i < _frameSizeSamples; i++) {
        frame[i] = _frameBuffer[i];
      }
      _frameBuffer.removeRange(0, _frameSizeSamples);

      // Calculate RMS energy
      double sumSquares = 0.0;
      for (int i = 0; i < frame.length; i++) {
        sumSquares += frame[i] * frame[i];
      }
      final rms = sqrt(sumSquares / frame.length);

      // Dispatch to state-specific handler
      switch (_state) {
        case VoicePipelineState.listening:
          _handleListening(rms, frame);
        // Not listening -- _micListening gate should prevent reaching here,
        // but defense-in-depth: drop frames in non-listening states.
        case VoicePipelineState.transcribing:
        case VoicePipelineState.thinking:
        case VoicePipelineState.speaking:
          break;
        case VoicePipelineState.idle:
        case VoicePipelineState.error:
          break;
      }
    }
  }

  /// Listening: detect speech onset and end-of-speech silence.
  void _handleListening(double rms, Float32List frame) {
    // Emit audio level every frame for UI visualization
    _emit(StateChanged(VoicePipelineState.listening, audioLevel: rms));

    if (rms > _threshold) {
      // Speech detected
      _speechDetected = true;
      _speechFrameCount++;
      _silentFrameCount = 0;
      _totalSilentFrameCount = 0;
    } else {
      // Silence
      _silentFrameCount++;
      _totalSilentFrameCount++;

      // Check 30s silence timeout
      final timeoutFrames =
          config.silenceTimeout.inMilliseconds ~/ _frameSizeMs;
      if (_totalSilentFrameCount >= timeoutFrames) {
        stop();
        return;
      }

      // Check end-of-speech (only if not already processing a turn)
      final silenceFrames =
          config.silenceDuration.inMilliseconds ~/ _frameSizeMs;
      if (_speechDetected &&
          _silentFrameCount >= silenceFrames &&
          !_isProcessingTurn) {
        // Minimum buffer check: discard short utterances under 0.8s
        // (8 frames at 100ms each)
        if (_speechFrameCount < 8) {
          _speechDetected = false;
          _silentFrameCount = 0;
          _speechFrameCount = 0;
          _whisperSession?.resetTranscript();
          return;
        }

        // Stop processing mic frames before handling turn
        _micListening = false;
        _speechDetected = false;
        _silentFrameCount = 0;
        _speechFrameCount = 0;
        _setState(VoicePipelineState.transcribing);
        // Fire-and-forget with error handling
        _processUserSpeech().catchError((Object e) {
          _emit(PipelineError('Speech processing error: $e'));
          if (_state == VoicePipelineState.transcribing ||
              _state == VoicePipelineState.thinking) {
            _frameBuffer.clear();
            _whisperSession?.resetTranscript();
            _micListening = true;
            _setState(VoicePipelineState.listening);
            _speechDetected = false;
            _silentFrameCount = 0;
            _speechFrameCount = 0;
          }
        });
        return;
      }

      // Reset speech frame count when speech ends without triggering processing
      if (!_speechDetected) {
        _speechFrameCount = 0;
      }
    }

    // Feed audio to WhisperSession ONLY during listening state
    _whisperSession?.feedAudio(frame);
  }

  /// Safely emit an event, guarding against closed controller.
  ///
  /// During dispose(), the event controller may close while async operations
  /// (_processUserSpeech's finally block) are still completing. Adding to a
  /// closed StreamController throws StateError. This guard prevents that.
  void _emit(VoicePipelineEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  /// Update state and emit StateChanged event.
  void _setState(VoicePipelineState newState, {double audioLevel = 0.0}) {
    _state = newState;
    _emit(StateChanged(newState, audioLevel: audioLevel));
  }

  /// Handle TTS events for state transitions.
  ///
  /// The [_processUserSpeech] finally block handles mic resume and state
  /// transition after TTS completes (since `await _tts.speak()` returns
  /// when TTS finishes). This handler is kept for potential future use.
  void _onTtsEvent(TtsEvent event) {
    // No-op: mic resume and state transition handled by _processUserSpeech
    // finally block after await _tts.speak() returns.
  }

  /// Immediately flush accumulated audio and process as speech.
  ///
  /// Push-to-talk: call this when the user presses a button to force
  /// processing regardless of VAD silence detection. Pauses the mic
  /// and triggers the full STT -> LLM -> TTS pipeline.
  Future<void> sendNow() async {
    if (_state != VoicePipelineState.listening) return;
    _micListening = false;
    _speechDetected = false;
    _silentFrameCount = 0;
    _speechFrameCount = 0;
    _setState(VoicePipelineState.transcribing);
    await _processUserSpeech().catchError((Object e) {
      _emit(PipelineError('Speech processing error: $e'));
      if (_state != VoicePipelineState.idle &&
          _state != VoicePipelineState.error) {
        _frameBuffer.clear();
        _whisperSession?.resetTranscript();
        _micListening = true;
        _setState(VoicePipelineState.listening);
      }
    });
  }

  /// Process user speech: flush WhisperSession, stream LLM response, speak via TTS.
  ///
  /// Implements the full conversation loop:
  /// 1. Flush WhisperSession to get final transcription
  /// 2. Send transcript to ChatSession.sendStream() for streaming LLM generation
  /// 3. Accumulate tokens with partial TranscriptUpdated events
  /// 4. Speak the complete response via TtsService
  ///
  /// Mic audio processing is gated off for the entire duration. It resumes
  /// with a cooldown after TTS finishes to prevent residual audio from
  /// triggering false speech detection.
  Future<void> _processUserSpeech() async {
    if (_isProcessingTurn) return;
    _isProcessingTurn = true;

    // NOTE: Do NOT set _micListening here -- callers (_handleListening,
    // sendNow) already set it to false before calling this method.

    bool ttsPlayed = false;

    try {
      // Step 1: Flush WhisperSession to get final transcription
      await _whisperSession?.flush();
      final text = _whisperSession?.transcript.trim() ?? '';
      _whisperSession?.resetTranscript();

      if (text.isEmpty) return;

      // Step 2: Emit user transcript event
      _emit(TranscriptUpdated(text, null));

      // Step 3: Transition to thinking state
      _setState(VoicePipelineState.thinking);

      // Step 3b: Check Scheduler QoS before LLM generation
      int maxTokens = config.maxResponseTokens;
      final scheduler = _scheduler;
      if (scheduler != null) {
        final knobs =
            scheduler.getKnobsForWorkload(WorkloadId.voicePipeline);
        if (knobs.maxFps == 0) {
          // QoS paused -- don't generate, just listen
          _emit(
              PipelineError('Voice pipeline paused by scheduler'));
          return;
        }
        // At reduced QoS, use scheduler's maxTokens limit if lower
        if (knobs.maxTokens < maxTokens && knobs.maxTokens > 0) {
          maxTokens = knobs.maxTokens;
        }
      }

      // Step 4: Stream LLM response
      _llmCancelToken = CancelToken();
      final responseBuffer = StringBuffer();
      bool wasCancelled = false;
      final stopwatch = Stopwatch()..start();

      try {
        await for (final chunk in _chatSession.sendStream(
          text,
          options: GenerateOptions(maxTokens: maxTokens),
          cancelToken: _llmCancelToken,
        )) {
          if (chunk.isFinal) break;
          responseBuffer.write(chunk.token);
          // Emit partial transcript for UI updates during streaming.
          // Clean special tokens from the partial text to prevent
          // Llama 3 / ChatML tags from appearing in the UI.
          final partialClean = cleanResponseText(responseBuffer.toString());
          _emit(TranscriptUpdated(
            text,
            partialClean,
            isPartial: true,
          ));
        }
      } catch (e) {
        // CancelToken cancellation throws GenerationException.
        // ChatSession.sendStream() rolls back the user message on error.
        wasCancelled = _llmCancelToken?.isCancelled ?? false;
        if (!wasCancelled) {
          // Real error, not cancellation
          _emit(PipelineError('LLM generation failed: $e'));
          return;
        }
      }

      stopwatch.stop();

      // Report LLM latency to Scheduler for p95 tracking
      _scheduler?.reportLatency(
        WorkloadId.voicePipeline,
        stopwatch.elapsedMilliseconds.toDouble(),
      );

      _llmCancelToken = null;

      // If cancelled, don't proceed to speaking.
      if (wasCancelled || _state != VoicePipelineState.thinking) {
        return;
      }

      // Clean special tokens (Llama 3, ChatML, Gemma) from response
      // before displaying in UI or sending to TTS. Tags like <|eot_id|>
      // confuse AVSpeechSynthesizer and look bad in the transcript.
      final responseText = cleanResponseText(responseBuffer.toString());
      if (responseText.isEmpty) return;

      // Step 5: Emit final transcript
      _emit(TranscriptUpdated(text, responseText));

      // Step 6: Record conversation turn
      _turns.add((user: text, assistant: responseText));

      // Step 7: Transition to speaking state and start TTS
      _setState(VoicePipelineState.speaking);
      await _tts.speak(
        responseText,
        voiceId: config.voiceId,
        rate: config.ttsRate,
      );
      ttsPlayed = true;
    } catch (e) {
      _emit(PipelineError('Voice pipeline error: $e'));
    } finally {
      _isProcessingTurn = false;
      // Resume mic processing. Apply cooldown only when TTS actually
      // played -- the 800ms prevents residual reverb/echo from triggering
      // false speech detection. Early returns (empty transcript, QoS
      // paused, LLM error) skip the cooldown for instant mic re-enable.
      if (_state != VoicePipelineState.idle && _state != VoicePipelineState.error) {
        if (ttsPlayed) {
          await Future<void>.delayed(config.ttsCooldown);
        }
        // Clear all audio state to ensure a clean slate for the next turn
        _frameBuffer.clear();
        _whisperSession?.resetTranscript();
        _speechDetected = false;
        _silentFrameCount = 0;
        _speechFrameCount = 0;
        _totalSilentFrameCount = 0;
        // Re-check state: stop() or pause() may have been called during the
        // cooldown delay above, changing state to idle. Only re-enable mic
        // processing if the pipeline is still active.
        if (_state != VoicePipelineState.idle && _state != VoicePipelineState.error) {
          // Re-enable mic processing -- only frames arriving AFTER this
          // point will be processed. No buffered backlog exists because
          // we use a flag gate instead of StreamSubscription.pause().
          _micListening = true;
          _setState(VoicePipelineState.listening);
        }
      }
    }
  }

  /// Pause the pipeline when app goes to background.
  ///
  /// Stops microphone capture and cancels any in-progress work (LLM
  /// generation, TTS speaking). Call [resume] when app returns to
  /// foreground to restart listening.
  void pause() {
    if (_state == VoicePipelineState.idle) return;
    _pausedFromState = _state;
    // Cancel any in-progress work
    _llmCancelToken?.cancel();
    _tts.stop();
    // Gate off mic processing and pause subscription to save battery
    _micListening = false;
    _micSubscription?.pause();
    _setState(VoicePipelineState.idle);
  }

  /// Resume the pipeline after returning from background.
  ///
  /// Reconfigures the audio session (may have been deactivated by iOS)
  /// and returns to listening state with reset counters.
  Future<void> resume() async {
    if (_pausedFromState == null) return;
    // Reconfigure audio session (may have been deactivated by iOS)
    await _configureAudioSession();
    // Clear any stale audio that may have been buffered during pause.
    // Broadcast stream subscriptions buffer events when paused, so we
    // must discard them before processing new audio.
    _frameBuffer.clear();
    _whisperSession?.resetTranscript();
    _micSubscription?.resume();
    _micListening = true;
    _setState(VoicePipelineState.listening);
    _speechDetected = false;
    _silentFrameCount = 0;
    _speechFrameCount = 0;
    _totalSilentFrameCount = 0;
    _isProcessingTurn = false;
    _pausedFromState = null;
  }

  /// Configure native audio session for voice pipeline.
  ///
  /// Sets PlayAndRecord category with Default mode and echo cancellation.
  /// Used by both [start] and [resume] to ensure correct audio configuration.
  ///
  // TODO: Native side should observe AVAudioSessionInterruptionNotification
  // and AVAudioSessionRouteChangeNotification, forwarding events to Dart so
  // the pipeline can gracefully handle phone calls, Siri, Bluetooth
  // disconnect, and headphone plug/unplug during active voice sessions.
  Future<void> _configureAudioSession() async {
    await _methodChannel.invokeMethod<bool>('configureVoicePipelineAudio');
  }

  /// Stop the voice pipeline and release all resources.
  ///
  /// Cancels any in-progress LLM, stops TTS, cancels mic subscription,
  /// disposes WhisperSession, unregisters from Scheduler, and resets
  /// the native audio session.
  Future<void> stop() async {
    if (_state == VoicePipelineState.idle) return;

    // Cancel any in-progress LLM generation
    _llmCancelToken?.cancel();

    // Stop TTS
    await _tts.stop();

    await _cleanup();

    _setState(VoicePipelineState.idle);
  }

  /// Internal cleanup of subscriptions and sessions.
  Future<void> _cleanup() async {
    // Cancel mic subscription
    await _micSubscription?.cancel();
    _micSubscription = null;

    // Stop and dispose WhisperSession
    await _whisperSession?.dispose();
    _whisperSession = null;

    // Cancel TTS subscription
    await _ttsSubscription?.cancel();
    _ttsSubscription = null;

    // Unregister from Scheduler
    _scheduler?.unregisterWorkload(WorkloadId.voicePipeline);

    // Reset native audio session
    try {
      await _methodChannel.invokeMethod<bool>('resetAudioSession');
    } catch (_) {
      // Best effort -- don't fail stop() if audio session reset fails
    }

    // Clear internal state
    _llmCancelToken = null;
    _frameBuffer.clear();
    _micListening = false;
    _isProcessingTurn = false;
    _speechFrameCount = 0;
    _pausedFromState = null;
  }

  /// Dispose the pipeline and close the event stream.
  ///
  /// Call this when the pipeline will no longer be used.
  Future<void> dispose() async {
    await stop();
    await _eventController.close();
  }

  // =========================================================================
  // Text cleaning
  // =========================================================================

  /// Pattern matching Llama 3, ChatML, and Gemma special tokens that
  /// may leak into generated text. These tokens are meaningful to
  /// llama.cpp's tokenizer but should never appear in user-facing text.
  static final _specialTokenPattern = RegExp(
    // Match full Llama 3 header blocks: <|start_header_id|>role<|end_header_id|>
    // This catches leaked next-turn headers like "assistant", "user", "system"
    // that would otherwise be left as orphaned text after stripping tags.
    r'<\|start_header_id\|>[^<]*<\|end_header_id\|>'
    // Individual special tokens (Llama 3, ChatML, Gemma)
    r'|<\|(?:begin_of_text|end_of_text|start_header_id|end_header_id|eot_id|'
    r'im_start|im_end|finetune_right_pad|reserved_special_token_\d+)\|>'
    // ChatML role headers: <|im_start|>role\n or <|im_end|>
    r'|<\|im_start\|>\w*\n?'
    // Gemma turn markers
    r'|<(?:start_of_turn|end_of_turn)>\s*\w*\n?',
    caseSensitive: false,
  );

  /// Strip special tokens and template artifacts from LLM response text.
  ///
  /// Llama 3.x, ChatML, and Gemma models may emit special tokens as
  /// literal text (e.g., `<|eot_id|>`, `<|im_end|>`). These must be
  /// removed before displaying or speaking the response. Also strips
  /// complete header blocks like `<|start_header_id|>assistant<|end_header_id|>`
  /// that would otherwise leave the role name ("assistant") as orphaned text.
  static String cleanResponseText(String text) {
    return text
        .replaceAll(_specialTokenPattern, '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n') // Collapse excessive newlines
        .trim();
  }
}
