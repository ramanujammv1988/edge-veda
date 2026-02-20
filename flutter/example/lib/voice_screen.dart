import 'dart:async';
import 'dart:math' show pi, sin;

import 'package:flutter/material.dart';
import 'package:edge_veda/edge_veda.dart';

import 'app_theme.dart';

/// Voice conversation demo tab with animated orb, transcript, and mic toggle.
///
/// Uses [VoicePipeline] to orchestrate the full STT -> LLM -> TTS loop.
/// The animated orb provides real-time visual feedback on pipeline state
/// (listening, thinking, speaking), and the scrolling transcript displays
/// all conversation turns.
///
/// States:
/// 1. Setup -- model download prompt if whisper/LLM not downloaded
/// 2. Idle -- static orb, hint text, mic button
/// 3. Active -- animated orb, live transcript, stop button
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({super.key});

  @override
  State<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends State<VoiceScreen>
    with TickerProviderStateMixin {
  // Pipeline
  VoicePipeline? _pipeline;
  StreamSubscription<VoicePipelineEvent>? _eventSubscription;
  VoicePipelineState _pipelineState = VoicePipelineState.idle;

  // Model setup
  bool _isCheckingModels = true;
  bool _whisperReady = false;
  bool _llmReady = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _downloadStatus = '';

  // Conversation transcript
  final List<_ConversationTurn> _transcript = [];
  String? _currentUserText;
  String? _currentAssistantText;
  bool _currentIsPartial = false;
  final ScrollController _scrollController = ScrollController();

  // Model instances (created once, reused across pipeline restarts)
  EdgeVeda? _edgeVeda;
  ChatSession? _chatSession;
  final TtsService _tts = TtsService();
  String? _whisperModelPath;

  // Orb animation
  late AnimationController _orbController;

  // App lifecycle
  AppLifecycleListener? _lifecycleListener;

  // Download subscription
  StreamSubscription<DownloadProgress>? _downloadSubscription;

  @override
  void initState() {
    super.initState();
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _lifecycleListener = AppLifecycleListener(
      onHide: _onAppHide,
      onShow: _onAppShow,
    );
    _checkModels();
  }

  @override
  void dispose() {
    _lifecycleListener?.dispose();
    _downloadSubscription?.cancel();
    _eventSubscription?.cancel();
    _pipeline?.dispose();
    _orbController.dispose();
    _scrollController.dispose();
    _edgeVeda?.dispose();
    super.dispose();
  }

  // ============================================================================
  // Model setup
  // ============================================================================

  Future<void> _checkModels() async {
    setState(() => _isCheckingModels = true);

    final mm = ModelManager();
    try {
      final whisperDownloaded =
          await mm.isModelDownloaded(ModelRegistry.whisperTinyEn.id);
      final llmDownloaded =
          await mm.isModelDownloaded(ModelRegistry.llama32_1b.id);

      if (mounted) {
        setState(() {
          _whisperReady = whisperDownloaded;
          _llmReady = llmDownloaded;
          _isCheckingModels = false;
        });
      }

      // If both ready, prepare model paths
      if (whisperDownloaded && llmDownloaded) {
        await _prepareModels(mm);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCheckingModels = false);
      }
    } finally {
      mm.dispose();
    }
  }

  Future<void> _prepareModels(ModelManager mm) async {
    _whisperModelPath =
        await mm.getModelPath(ModelRegistry.whisperTinyEn.id);

    final llmPath = await mm.getModelPath(ModelRegistry.llama32_1b.id);

    _edgeVeda = EdgeVeda();
    await _edgeVeda!.init(EdgeVedaConfig(
      modelPath: llmPath,
      useGpu: true,
      numThreads: 4,
      contextLength: 2048,
      maxMemoryMb: 1536,
      verbose: false,
    ));

    _chatSession = ChatSession(
      edgeVeda: _edgeVeda!,
      preset: SystemPromptPreset.assistant,
      templateFormat: ChatTemplateFormat.llama3Instruct,
    );
  }

  Future<void> _downloadModels() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadStatus = 'Preparing download...';
    });

    final mm = ModelManager();

    try {
      // Download whisper model if needed
      if (!_whisperReady) {
        setState(() => _downloadStatus = 'Downloading Whisper model...');

        _downloadSubscription = mm.downloadProgress.listen((progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress.progress;
              _downloadStatus =
                  'Whisper: ${progress.progressPercent}%';
            });
          }
        });

        await mm.downloadModel(ModelRegistry.whisperTinyEn);
        _downloadSubscription?.cancel();
        _downloadSubscription = null;

        if (mounted) {
          setState(() => _whisperReady = true);
        }
      }

      // Download LLM model if needed
      if (!_llmReady) {
        setState(() {
          _downloadProgress = 0.0;
          _downloadStatus = 'Downloading LLM model...';
        });

        _downloadSubscription = mm.downloadProgress.listen((progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress.progress;
              _downloadStatus =
                  'LLM: ${progress.progressPercent}%';
            });
          }
        });

        await mm.downloadModel(ModelRegistry.llama32_1b);
        _downloadSubscription?.cancel();
        _downloadSubscription = null;

        if (mounted) {
          setState(() => _llmReady = true);
        }
      }

      // Prepare model instances
      await _prepareModels(mm);

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadStatus = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadStatus = '';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    } finally {
      _downloadSubscription?.cancel();
      _downloadSubscription = null;
      mm.dispose();
    }
  }

  bool get _modelsReady => _whisperReady && _llmReady;

  // ============================================================================
  // Pipeline lifecycle
  // ============================================================================

  Future<void> _startPipeline() async {
    if (_chatSession == null || _whisperModelPath == null) return;

    // Request microphone permission
    final granted = await WhisperSession.requestMicrophonePermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission is required for voice conversations'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
      return;
    }

    // Create pipeline
    _pipeline = VoicePipeline(
      chatSession: _chatSession!,
      tts: _tts,
      whisperModelPath: _whisperModelPath!,
      config: const VoicePipelineConfig(
        systemPrompt:
            'You are a helpful voice assistant. Keep responses concise '
            'and conversational — 1-3 sentences. Be friendly and natural.',
      ),
    );

    // Subscribe to events
    _eventSubscription = _pipeline!.events.listen(_onPipelineEvent);

    // Start pipeline
    try {
      await _pipeline!.start();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start voice pipeline: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _stopPipeline() async {
    await _pipeline?.stop();
    _eventSubscription?.cancel();
    _eventSubscription = null;

    if (mounted) {
      setState(() {
        _pipelineState = VoicePipelineState.idle;
        _currentUserText = null;
        _currentAssistantText = null;
        _currentIsPartial = false;
      });
      _updateOrbAnimation(VoicePipelineState.idle);
    }
  }

  void _onPipelineEvent(VoicePipelineEvent event) {
    if (!mounted) return;

    if (event is StateChanged) {
      setState(() {
        _pipelineState = event.state;
      });
      _updateOrbAnimation(event.state);

      // When transitioning from speaking/thinking to listening, finalize current turn
      if (event.state == VoicePipelineState.listening &&
          _currentUserText != null &&
          _currentAssistantText != null &&
          !_currentIsPartial) {
        // Turn already finalized by the final TranscriptUpdated event
      }
    } else if (event is TranscriptUpdated) {
      setState(() {
        _currentUserText = event.userText;
        _currentAssistantText = event.assistantText;
        _currentIsPartial = event.isPartial;

        if (event.assistantText != null && !event.isPartial) {
          // Final transcript — commit to conversation history
          _transcript.add(_ConversationTurn(
            userText: event.userText,
            assistantText: event.assistantText!,
          ));
          _currentUserText = null;
          _currentAssistantText = null;
          _currentIsPartial = false;
        }
      });
      _scrollToBottom();
    } else if (event is PipelineError) {
      if (mounted && event.message.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(event.message),
            backgroundColor: AppTheme.danger,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ============================================================================
  // Orb animation
  // ============================================================================

  void _updateOrbAnimation(VoicePipelineState state) {
    _orbController.stop();

    switch (state) {
      case VoicePipelineState.idle:
      case VoicePipelineState.error:
        _orbController.reset();
        break;
      case VoicePipelineState.calibrating:
        _orbController.duration = const Duration(milliseconds: 3000);
        _orbController.repeat();
        break;
      case VoicePipelineState.listening:
        _orbController.duration = const Duration(milliseconds: 2000);
        _orbController.repeat();
        break;
      case VoicePipelineState.transcribing:
        _orbController.duration = const Duration(milliseconds: 1000);
        _orbController.repeat();
        break;
      case VoicePipelineState.thinking:
        _orbController.duration = const Duration(milliseconds: 2000);
        _orbController.repeat();
        break;
      case VoicePipelineState.speaking:
        _orbController.duration = const Duration(milliseconds: 1500);
        _orbController.repeat();
        break;
    }
  }

  // ============================================================================
  // App lifecycle
  // ============================================================================

  void _onAppHide() {
    _pipeline?.pause();
  }

  Future<void> _onAppShow() async {
    await _pipeline?.resume();
  }

  // ============================================================================
  // Helpers
  // ============================================================================

  String _stateLabel(VoicePipelineState state) {
    switch (state) {
      case VoicePipelineState.idle:
        return 'Ready';
      case VoicePipelineState.calibrating:
        return 'Calibrating...';
      case VoicePipelineState.listening:
        return 'Listening...';
      case VoicePipelineState.transcribing:
        return 'Transcribing...';
      case VoicePipelineState.thinking:
        return 'Thinking...';
      case VoicePipelineState.speaking:
        return 'Speaking...';
      case VoicePipelineState.error:
        return 'Error';
    }
  }

  bool get _isActive =>
      _pipelineState != VoicePipelineState.idle &&
      _pipelineState != VoicePipelineState.error;

  // ============================================================================
  // UI Builders
  // ============================================================================

  /// Setup screen shown when models are not yet downloaded.
  Widget _buildSetupScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.record_voice_over,
              size: 72,
              color: AppTheme.accent,
            ),
            const SizedBox(height: 24),
            const Text(
              'Voice Conversation',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Download the required models to start\non-device voice conversations',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            // Model status indicators
            _buildModelStatus(
              'Whisper Tiny (77 MB)',
              _whisperReady,
              Icons.mic,
            ),
            const SizedBox(height: 8),
            _buildModelStatus(
              'Llama 3.2 1B (668 MB)',
              _llmReady,
              Icons.smart_toy,
            ),
            const SizedBox(height: 32),
            if (_isDownloading) ...[
              SizedBox(
                width: 260,
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value:
                            _downloadProgress > 0 ? _downloadProgress : null,
                        color: AppTheme.accent,
                        backgroundColor: AppTheme.surfaceVariant,
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _downloadStatus,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ] else
              ElevatedButton.icon(
                onPressed: _downloadModels,
                icon: const Icon(Icons.download),
                label: const Text('Download Models'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: AppTheme.background,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelStatus(String name, bool ready, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          ready ? Icons.check_circle : Icons.radio_button_unchecked,
          color: ready ? AppTheme.success : AppTheme.textTertiary,
          size: 20,
        ),
        const SizedBox(width: 10),
        Icon(icon, color: AppTheme.textSecondary, size: 18),
        const SizedBox(width: 8),
        Text(
          name,
          style: TextStyle(
            fontSize: 14,
            color: ready ? AppTheme.textSecondary : AppTheme.textTertiary,
          ),
        ),
      ],
    );
  }

  /// Main voice UI with orb, transcript, and mic button.
  Widget _buildVoiceUI() {
    return Column(
      children: [
        // Orb area (takes flexible space)
        Expanded(
          flex: 3,
          child: Center(
            child: AnimatedBuilder(
              animation: _orbController,
              builder: (context, child) {
                return CustomPaint(
                  size: const Size(200, 200),
                  painter: _OrbPainter(
                    state: _pipelineState,
                    animationValue: _orbController.value,
                  ),
                );
              },
            ),
          ),
        ),

        // Transcript area (scrollable)
        Expanded(
          flex: 4,
          child: _buildTranscript(),
        ),

        // Mic button
        _buildMicButton(),
      ],
    );
  }

  Widget _buildTranscript() {
    final hasContent = _transcript.isNotEmpty ||
        _currentUserText != null;

    if (!hasContent) {
      return Center(
        child: Text(
          _isActive
              ? 'Speak and your conversation will appear here'
              : 'Tap the mic to start a voice conversation',
          style: const TextStyle(
            color: AppTheme.textTertiary,
            fontSize: 15,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    // Build the list of items to display
    final items = <_TranscriptItem>[];

    // Committed turns
    for (final turn in _transcript) {
      items.add(_TranscriptItem(
        text: turn.userText,
        isUser: true,
        isPartial: false,
      ));
      items.add(_TranscriptItem(
        text: turn.assistantText,
        isUser: false,
        isPartial: false,
      ));
    }

    // Current in-progress turn
    if (_currentUserText != null) {
      items.add(_TranscriptItem(
        text: _currentUserText!,
        isUser: true,
        isPartial: false,
      ));
      if (_currentAssistantText != null) {
        items.add(_TranscriptItem(
          text: _currentAssistantText!,
          isUser: false,
          isPartial: _currentIsPartial,
        ));
      }
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _buildMessageBubble(item);
      },
    );
  }

  Widget _buildMessageBubble(_TranscriptItem item) {
    final isUser = item.isUser;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? AppTheme.surfaceVariant
              : AppTheme.accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isUser)
              const Padding(
                padding: EdgeInsets.only(right: 8, top: 2),
                child: Icon(Icons.mic, size: 14, color: AppTheme.textSecondary),
              ),
            Flexible(
              child: Text(
                item.isPartial ? '${item.text}...' : item.text,
                style: TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 14,
                  height: 1.4,
                  fontStyle:
                      item.isPartial ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMicButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 16, top: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: _isActive ? _stopPipeline : _startPipeline,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _isActive ? AppTheme.danger : AppTheme.accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: (_isActive ? AppTheme.danger : AppTheme.accent)
                          .withValues(alpha: 0.4),
                      blurRadius: _isActive ? 20 : 12,
                      spreadRadius: _isActive ? 2 : 0,
                    ),
                  ],
                ),
                child: Icon(
                  _isActive ? Icons.stop : Icons.mic,
                  color: _isActive
                      ? AppTheme.textPrimary
                      : AppTheme.background,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _isActive ? 'Tap to stop' : 'Tap to start',
              style: const TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Voice',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        backgroundColor: AppTheme.background,
        actions: [
          if (_isActive)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  _stateLabel(_pipelineState),
                  style: const TextStyle(
                    color: AppTheme.textTertiary,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _isCheckingModels
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            )
          : _modelsReady
              ? _buildVoiceUI()
              : _buildSetupScreen(),
    );
  }
}

// =============================================================================
// Data classes
// =============================================================================

class _ConversationTurn {
  final String userText;
  final String assistantText;

  const _ConversationTurn({
    required this.userText,
    required this.assistantText,
  });
}

class _TranscriptItem {
  final String text;
  final bool isUser;
  final bool isPartial;

  const _TranscriptItem({
    required this.text,
    required this.isUser,
    required this.isPartial,
  });
}

// =============================================================================
// Orb painter
// =============================================================================

/// Custom painter for the animated orb that visualizes pipeline state.
///
/// Each state has a distinct visual:
/// - idle: static dim teal circle
/// - calibrating: slow breathing pulse
/// - listening: medium pulse with glow
/// - transcribing: fast pulse, teal to accent
/// - thinking: rotating gradient with concentric circles
/// - speaking: pulsing concentric rings (waveform)
/// - error: static red circle
class _OrbPainter extends CustomPainter {
  final VoicePipelineState state;
  final double animationValue;

  _OrbPainter({
    required this.state,
    required this.animationValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const baseRadius = 60.0;

    switch (state) {
      case VoicePipelineState.idle:
        _paintIdle(canvas, center, baseRadius);
        break;
      case VoicePipelineState.calibrating:
        _paintCalibrating(canvas, center, baseRadius);
        break;
      case VoicePipelineState.listening:
        _paintListening(canvas, center, baseRadius);
        break;
      case VoicePipelineState.transcribing:
        _paintTranscribing(canvas, center, baseRadius);
        break;
      case VoicePipelineState.thinking:
        _paintThinking(canvas, center, baseRadius);
        break;
      case VoicePipelineState.speaking:
        _paintSpeaking(canvas, center, baseRadius);
        break;
      case VoicePipelineState.error:
        _paintError(canvas, center, baseRadius);
        break;
    }
  }

  void _paintIdle(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..color = AppTheme.accent.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.75, paint);
  }

  void _paintCalibrating(Canvas canvas, Offset center, double radius) {
    // Slow breathing: scale 0.95 - 1.05
    final scale = 0.95 + 0.1 * sin(animationValue * 2 * pi);
    final paint = Paint()
      ..color = AppTheme.accent.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.75 * scale, paint);
  }

  void _paintListening(Canvas canvas, Offset center, double radius) {
    // Medium pulse: scale 0.9 - 1.1
    final scale = 0.9 + 0.2 * sin(animationValue * 2 * pi);
    final glowRadius = radius * 1.2 * scale;

    // Glow effect using radial gradient
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          AppTheme.accent.withValues(alpha: 0.3),
          AppTheme.accent.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: glowRadius));
    canvas.drawCircle(center, glowRadius, glowPaint);

    // Core orb
    final paint = Paint()
      ..color = AppTheme.accent.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.75 * scale, paint);
  }

  void _paintTranscribing(Canvas canvas, Offset center, double radius) {
    // Fast pulse: scale 0.85 - 1.15
    final scale = 0.85 + 0.3 * sin(animationValue * 2 * pi);

    // Transition color from teal toward a brighter accent
    final color = Color.lerp(
      AppTheme.accent,
      const Color(0xFF4DD0E1), // lighter cyan
      (sin(animationValue * 2 * pi) + 1) / 2,
    )!;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.75 * scale, paint);
  }

  void _paintThinking(Canvas canvas, Offset center, double radius) {
    // Rotating gradient with multiple concentric circles
    final rotationAngle = animationValue * 2 * pi;

    // Outer rotating ring
    for (int i = 0; i < 3; i++) {
      final phase = i * (2 * pi / 3);
      final ringRadius = radius * (0.5 + 0.2 * i);
      final opacity = 0.3 - 0.08 * i;
      final ringScale = 0.95 + 0.1 * sin(rotationAngle + phase);

      final ringPaint = Paint()
        ..color = Color.lerp(
          AppTheme.accent,
          const Color(0xFF4DD0E1),
          (sin(rotationAngle + phase) + 1) / 2,
        )!
            .withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3;
      canvas.drawCircle(center, ringRadius * ringScale, ringPaint);
    }

    // Core
    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          AppTheme.accent.withValues(alpha: 0.8),
          const Color(0xFF4DD0E1).withValues(alpha: 0.4),
        ],
        stops: const [0.3, 1.0],
        transform: GradientRotation(rotationAngle),
      ).createShader(Rect.fromCircle(center: center, radius: radius * 0.5));
    canvas.drawCircle(center, radius * 0.5, corePaint);
  }

  void _paintSpeaking(Canvas canvas, Offset center, double radius) {
    // Waveform: concentric rings pulsing outward
    for (int i = 0; i < 5; i++) {
      final phase = i * (2 * pi / 5);
      final waveValue = sin(animationValue * 2 * pi + phase);
      final ringRadius = radius * (0.4 + 0.15 * i) + 8 * waveValue;
      final opacity = (0.6 - 0.1 * i).clamp(0.1, 1.0);

      final ringPaint = Paint()
        ..color = AppTheme.accent.withValues(alpha: opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5;
      canvas.drawCircle(center, ringRadius, ringPaint);
    }

    // Inner core
    final corePaint = Paint()
      ..color = AppTheme.accent.withValues(alpha: 0.7)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.35, corePaint);
  }

  void _paintError(Canvas canvas, Offset center, double radius) {
    final paint = Paint()
      ..color = AppTheme.danger.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius * 0.75, paint);
  }

  @override
  bool shouldRepaint(covariant _OrbPainter oldDelegate) {
    return oldDelegate.state != state ||
        oldDelegate.animationValue != animationValue;
  }
}
