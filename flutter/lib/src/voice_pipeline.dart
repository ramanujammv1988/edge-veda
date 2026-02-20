/// Voice pipeline orchestrator for real-time voice conversations.
///
/// [VoicePipeline] manages the full STT -> LLM -> TTS loop with
/// energy-based VAD for turn detection, adaptive threshold calibration,
/// and interruptible TTS. The pipeline is event-driven: audio frames
/// from the microphone drive state transitions through a well-defined
/// state machine.
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
/// - idle -> calibrating (on start)
/// - calibrating -> listening (after calibration completes)
/// - listening -> transcribing (after speech + silence detected)
/// - transcribing -> thinking (after transcript obtained)
/// - thinking -> speaking (after LLM response completes)
/// - thinking -> listening (on user interruption or empty response)
/// - speaking -> listening (after TTS finishes or user interrupts)
/// - any -> error (on fatal error)
/// - any -> idle (on stop)
enum VoicePipelineState {
  /// Pipeline not running.
  idle,

  /// Collecting ambient noise samples for adaptive VAD threshold.
  calibrating,

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
  StateChanged(this.state);
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

  /// Duration of ambient noise collection for threshold calibration.
  /// 20 frames at 100ms each = 2 seconds.
  final Duration calibrationDuration;

  /// VAD threshold multiplier: threshold = mean + (multiplier * stddev).
  /// 2.5 provides good speech/silence separation without false triggers.
  final double thresholdMultiplier;

  /// TTS threshold multiplier applied during speaking state.
  /// 1.5x mild elevation prevents echo from triggering interruption.
  /// NOT 3x like RunAnywhere -- that misses real interruptions.
  final double ttsThresholdMultiplier;

  /// Cooldown after TTS finishes before re-enabling VAD at normal threshold.
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
    this.calibrationDuration = const Duration(milliseconds: 2000),
    this.thresholdMultiplier = 2.5,
    this.ttsThresholdMultiplier = 1.5,
    this.ttsCooldown = const Duration(milliseconds: 300),
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
/// 1. Calibrates the VAD threshold from ambient noise
/// 2. Listens for speech using energy-based VAD
/// 3. Transcribes speech via WhisperSession
/// 4. Streams LLM response via ChatSession.sendStream() with CancelToken
/// 5. Speaks the response via TtsService
/// 6. Returns to listening for the next turn
///
/// Supports interruption: user speech during thinking or speaking states
/// cancels the current operation and starts a new listening turn. Post-TTS
/// cooldown prevents residual audio from triggering false speech detection.
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
  double _threshold = 0.015; // Default until calibrated
  final List<double> _calibrationRmsValues = [];
  int _silentFrameCount = 0;
  int _totalSilentFrameCount = 0;
  bool _speechDetected = false;

  // Conversation loop guards
  bool _isProcessingTurn = false;
  bool _isCoolingDown = false;
  Timer? _cooldownTimer;

  // Conversation transcript tracking
  final List<({String user, String assistant})> _turns = [];

  // App lifecycle state
  VoicePipelineState? _pausedFromState;

  // Audio frame constants
  static const int _frameSizeMs = 100;
  static const int _sampleRate = 16000;
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

  /// Active VAD threshold, elevated during speaking state and cooldown
  /// to prevent echo from triggering false interruption detection.
  double get _activeThreshold {
    if (_state == VoicePipelineState.speaking || _isCoolingDown) {
      return _threshold * config.ttsThresholdMultiplier;
    }
    return _threshold;
  }

  /// Start the voice pipeline.
  ///
  /// Configures the native audio session for simultaneous mic + speaker,
  /// creates a WhisperSession, registers with the Scheduler, subscribes
  /// to TTS events, starts the microphone, and begins calibration.
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

      // Begin calibration
      _calibrationRmsValues.clear();
      _silentFrameCount = 0;
      _totalSilentFrameCount = 0;
      _speechDetected = false;
      _frameBuffer.clear();
      _setState(VoicePipelineState.calibrating);
    } catch (e) {
      _setState(VoicePipelineState.error);
      _eventController.add(PipelineError('Failed to start pipeline: $e',
          fatal: true));
      // Clean up any partially initialized resources
      await _cleanup();
      rethrow;
    }
  }

  /// Core audio frame processing callback.
  ///
  /// Runs on every microphone delivery (~300ms at a time from native).
  /// Chunks into 100ms (1600 sample) frames, calculates RMS energy,
  /// and dispatches to the current state handler.
  void _onAudioFrame(Float32List samples) {
    if (_state == VoicePipelineState.idle ||
        _state == VoicePipelineState.error) {
      return;
    }

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
        case VoicePipelineState.calibrating:
          _handleCalibrating(rms);
        case VoicePipelineState.listening:
          _handleListening(rms, frame);
        case VoicePipelineState.thinking:
          _handleThinking(rms, frame);
        case VoicePipelineState.speaking:
          _handleSpeaking(rms, frame);
        case VoicePipelineState.transcribing:
          // Buffer audio but do NOT feed to WhisperSession (it is processing)
          break;
        case VoicePipelineState.idle:
        case VoicePipelineState.error:
          break;
      }
    }
  }

  /// Calibration: collect ambient noise RMS values to set adaptive threshold.
  void _handleCalibrating(double rms) {
    _calibrationRmsValues.add(rms);

    final requiredFrames =
        config.calibrationDuration.inMilliseconds ~/ _frameSizeMs;

    if (_calibrationRmsValues.length >= requiredFrames) {
      // Calculate mean
      double sum = 0.0;
      for (final v in _calibrationRmsValues) {
        sum += v;
      }
      final mean = sum / _calibrationRmsValues.length;

      // Calculate standard deviation
      double varianceSum = 0.0;
      for (final v in _calibrationRmsValues) {
        varianceSum += (v - mean) * (v - mean);
      }
      final stddev = sqrt(varianceSum / _calibrationRmsValues.length);

      // Set threshold: mean + multiplier * stddev
      _threshold = mean + (config.thresholdMultiplier * stddev);

      // Clamp minimum to avoid threshold being too low in very quiet rooms
      if (_threshold < 0.005) _threshold = 0.005;

      // Reset counters and transition to listening
      _silentFrameCount = 0;
      _totalSilentFrameCount = 0;
      _speechDetected = false;
      _setState(VoicePipelineState.listening);
    }
  }

  /// Listening: detect speech onset and end-of-speech silence.
  void _handleListening(double rms, Float32List frame) {
    if (rms > _activeThreshold) {
      // Speech detected
      _speechDetected = true;
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
        _setState(VoicePipelineState.transcribing);
        _speechDetected = false;
        _silentFrameCount = 0;
        // Fire-and-forget with error handling
        _processUserSpeech().catchError((Object e) {
          _eventController.add(PipelineError('Speech processing error: $e'));
          if (_state == VoicePipelineState.transcribing ||
              _state == VoicePipelineState.thinking) {
            _setState(VoicePipelineState.listening);
            _speechDetected = false;
            _silentFrameCount = 0;
          }
        });
        return;
      }
    }

    // Feed audio to WhisperSession ONLY during listening state
    // NOT during speaking/thinking -- echo prevention per research
    _whisperSession?.feedAudio(frame);
  }

  /// Thinking: VAD active for interruption detection during LLM generation.
  void _handleThinking(double rms, Float32List frame) {
    if (rms > _activeThreshold) {
      // User interrupted during LLM generation
      _llmCancelToken?.cancel();
      _whisperSession?.resetTranscript();
      _speechDetected = true;
      _silentFrameCount = 0;
      _totalSilentFrameCount = 0;
      _setState(VoicePipelineState.listening);
      // Feed the interrupting audio to WhisperSession
      _whisperSession?.feedAudio(frame);
    }
  }

  /// Speaking: VAD active with elevated threshold for TTS interruption.
  void _handleSpeaking(double rms, Float32List frame) {
    if (rms > _activeThreshold) {
      // User interrupted TTS -- stop immediately (fire-and-forget)
      _tts.stop();
      // Start cooldown to keep threshold elevated while residual TTS fades
      _startCooldown();
      _whisperSession?.resetTranscript();
      _speechDetected = true;
      _silentFrameCount = 0;
      _totalSilentFrameCount = 0;
      _setState(VoicePipelineState.listening);
      // Feed the interrupting audio to WhisperSession
      _whisperSession?.feedAudio(frame);
    }
  }

  /// Update state and emit StateChanged event.
  void _setState(VoicePipelineState newState) {
    _state = newState;
    _eventController.add(StateChanged(newState));
  }

  /// Handle TTS events for state transitions.
  void _onTtsEvent(TtsEvent event) {
    if (_state != VoicePipelineState.speaking) return;

    if (event.type == TtsEventType.finish) {
      // Natural finish -- cooldown then transition to listening.
      // Cooldown prevents the last bit of TTS audio from being detected
      // as user speech after the speaker stops.
      _startCooldown();
      Future<void>.delayed(config.ttsCooldown).then((_) {
        if (_state == VoicePipelineState.speaking) {
          _silentFrameCount = 0;
          _totalSilentFrameCount = 0;
          _speechDetected = false;
          _setState(VoicePipelineState.listening);
        }
      });
    }
    // TtsEventType.cancel is handled by _handleSpeaking -- the interruption
    // handler already transitions to listening. No cooldown needed since
    // the user is actively speaking.
  }

  /// Start the post-TTS cooldown period.
  ///
  /// During cooldown, [_activeThreshold] stays elevated to prevent
  /// residual TTS audio from being detected as user speech.
  void _startCooldown() {
    _cooldownTimer?.cancel();
    _isCoolingDown = true;
    _cooldownTimer = Timer(config.ttsCooldown, () {
      _isCoolingDown = false;
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
  /// Supports interruption at every stage:
  /// - During thinking: CancelToken cancels LLM generation
  /// - During speaking: TtsService.stop() cancels TTS playback
  /// - Re-entrancy guard prevents concurrent calls
  Future<void> _processUserSpeech() async {
    if (_isProcessingTurn) return;
    _isProcessingTurn = true;

    try {
      // Step 1: Flush WhisperSession to get final transcription
      await _whisperSession?.flush();
      final text = _whisperSession?.transcript.trim() ?? '';
      _whisperSession?.resetTranscript();

      if (text.isEmpty) {
        _setState(VoicePipelineState.listening);
        _speechDetected = false;
        _silentFrameCount = 0;
        return;
      }

      // Step 2: Emit user transcript event
      _eventController.add(TranscriptUpdated(text, null));

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
          _eventController.add(
              PipelineError('Voice pipeline paused by scheduler'));
          _setState(VoicePipelineState.listening);
          _speechDetected = false;
          _silentFrameCount = 0;
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
          // Emit partial transcript for UI updates during streaming
          _eventController.add(TranscriptUpdated(
            text,
            responseBuffer.toString(),
            isPartial: true,
          ));
        }
      } catch (e) {
        // CancelToken cancellation throws GenerationException.
        // ChatSession.sendStream() rolls back the user message on error.
        wasCancelled = _llmCancelToken?.isCancelled ?? false;
        if (!wasCancelled) {
          // Real error, not cancellation
          _eventController
              .add(PipelineError('LLM generation failed: $e'));
          _setState(VoicePipelineState.listening);
          _speechDetected = false;
          _silentFrameCount = 0;
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

      // If cancelled (user interrupted during thinking), we are already in
      // listening state (set by _handleThinking). Don't proceed to speaking.
      // Note: ChatSession.sendStream() rolls back the user message on
      // cancellation. The partial response is emitted via TranscriptUpdated
      // events so the UI can still display it.
      if (wasCancelled || _state != VoicePipelineState.thinking) {
        return;
      }

      final responseText = responseBuffer.toString().trim();
      if (responseText.isEmpty) {
        _setState(VoicePipelineState.listening);
        _speechDetected = false;
        _silentFrameCount = 0;
        return;
      }

      // Step 5: Emit final transcript
      _eventController.add(TranscriptUpdated(text, responseText));

      // Step 6: Record conversation turn
      _turns.add((user: text, assistant: responseText));

      // Step 7: Transition to speaking state and start TTS
      _setState(VoicePipelineState.speaking);
      await _tts.speak(
        responseText,
        voiceId: config.voiceId,
        rate: config.ttsRate,
      );
    } catch (e) {
      _eventController.add(PipelineError('Voice pipeline error: $e'));
      if (_state != VoicePipelineState.idle) {
        _setState(VoicePipelineState.listening);
        _speechDetected = false;
        _silentFrameCount = 0;
      }
    } finally {
      _isProcessingTurn = false;
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
    // Pause mic by pausing the subscription (native stream stays alive)
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
    _micSubscription?.resume();
    _setState(VoicePipelineState.listening);
    _speechDetected = false;
    _silentFrameCount = 0;
    _totalSilentFrameCount = 0;
    _isProcessingTurn = false;
    _pausedFromState = null;
  }

  /// Configure native audio session for voice pipeline.
  ///
  /// Sets PlayAndRecord category with VoiceChat mode and echo cancellation.
  /// Used by both [start] and [resume] to ensure correct audio configuration.
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
    _calibrationRmsValues.clear();
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    _isCoolingDown = false;
    _isProcessingTurn = false;
    _pausedFromState = null;
  }

  /// Dispose the pipeline and close the event stream.
  ///
  /// Call this when the pipeline will no longer be used.
  Future<void> dispose() async {
    await stop();
    await _eventController.close();
  }
}
