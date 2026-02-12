import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:edge_veda/edge_veda.dart';

import 'app_theme.dart';

/// STT (Speech-to-Text) demo tab with live microphone transcription.
///
/// Uses [WhisperSession] for on-device speech recognition via whisper.cpp.
/// Audio is captured from the device microphone, fed to the whisper model
/// in 3-second chunks, and transcription segments appear in real time.
///
/// States:
/// 1. Model not downloaded -- shows download button for whisper-tiny.en
/// 2. Ready -- large mic button, tap to start recording
/// 3. Recording -- pulsing indicator, live transcript, stop button
/// 4. Transcript -- segment list with timestamps, copy button
class SttScreen extends StatefulWidget {
  const SttScreen({super.key});

  @override
  State<SttScreen> createState() => _SttScreenState();
}

class _SttScreenState extends State<SttScreen>
    with SingleTickerProviderStateMixin {
  // Model state
  bool _isModelDownloaded = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;

  // Recording state
  bool _isRecording = false;
  bool _isInitializing = false;
  String _transcript = '';
  final List<WhisperSegment> _segments = [];

  // Recording duration tracking
  DateTime? _recordingStartTime;
  Timer? _durationTimer;
  Duration _recordingDuration = Duration.zero;

  // Session and subscriptions
  WhisperSession? _session;
  StreamSubscription<Float32List>? _audioSubscription;
  StreamSubscription<WhisperSegment>? _segmentSubscription;
  StreamSubscription<DownloadProgress>? _downloadSubscription;

  // Pulsing animation for recording indicator
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _checkModel();
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _pulseController.dispose();
    _downloadSubscription?.cancel();
    _stopRecording();
    _session?.dispose();
    super.dispose();
  }

  Future<void> _checkModel() async {
    final mm = ModelManager();
    final downloaded =
        await mm.isModelDownloaded(ModelRegistry.whisperTinyEn.id);
    if (mounted) {
      setState(() {
        _isModelDownloaded = downloaded;
      });
    }
  }

  Future<void> _downloadModel() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    final modelManager = ModelManager();

    _downloadSubscription = modelManager.downloadProgress.listen((progress) {
      if (mounted) {
        setState(() {
          _downloadProgress = progress.progress;
        });
      }
    });

    try {
      await modelManager.downloadModel(ModelRegistry.whisperTinyEn);

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _isModelDownloaded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
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
      modelManager.dispose();
    }
  }

  Future<void> _startRecording() async {
    // Request microphone permission
    final granted = await WhisperSession.requestMicrophonePermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission denied'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
      return;
    }

    setState(() {
      _isInitializing = true;
    });

    try {
      // Get model path
      final modelManager = ModelManager();
      final modelPath =
          await modelManager.getModelPath(ModelRegistry.whisperTinyEn.id);

      // Start whisper session
      _session = WhisperSession(modelPath: modelPath);
      await _session!.start();

      // Listen for segments
      _segmentSubscription = _session!.onSegment.listen((segment) {
        if (mounted) {
          setState(() {
            _segments.add(segment);
            _transcript = _session!.transcript;
          });
        }
      });

      // Start microphone audio capture.
      // When native onListen returns a FlutterError (e.g., simulator has no
      // valid audio input), receiveBroadcastStream sends it as the first
      // error event on the stream. The onError handler shows a SnackBar.
      _audioSubscription = WhisperSession.microphone().listen(
        (samples) {
          _session?.feedAudio(samples);
        },
        onError: (error) {
          if (mounted) {
            _stopRecording();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Microphone error: $error'),
                backgroundColor: AppTheme.danger,
              ),
            );
          }
        },
      );

      // Start duration timer
      _recordingStartTime = DateTime.now();
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _isRecording) {
          setState(() {
            _recordingDuration =
                DateTime.now().difference(_recordingStartTime!);
          });
        }
      });

      if (mounted) {
        setState(() {
          _isRecording = true;
          _isInitializing = false;
          _recordingDuration = Duration.zero;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to start recording: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    _durationTimer?.cancel();
    _durationTimer = null;

    _audioSubscription?.cancel();
    _audioSubscription = null;

    await _session?.flush();
    await _session?.stop();

    _segmentSubscription?.cancel();
    _segmentSubscription = null;

    if (mounted) {
      setState(() {
        _isRecording = false;
      });
    }
  }

  void _clearTranscript() {
    setState(() {
      _segments.clear();
      _transcript = '';
    });
    _session?.resetTranscript();
  }

  void _copyTranscript() {
    if (_transcript.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _transcript));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transcript copied to clipboard'),
          backgroundColor: AppTheme.accentDim,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _formatTimestamp(int ms) {
    final seconds = (ms / 1000).toStringAsFixed(1);
    return '${seconds}s';
  }

  // ===========================================================================
  // UI Builders
  // ===========================================================================

  /// Build the model-not-downloaded state
  Widget _buildDownloadState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.mic_none,
              size: 72,
              color: AppTheme.accent,
            ),
            const SizedBox(height: 24),
            const Text(
              'Speech-to-Text',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Download whisper-tiny.en (77 MB) to enable\non-device transcription',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            if (_isDownloading) ...[
              SizedBox(
                width: 240,
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _downloadProgress > 0 ? _downloadProgress : null,
                        color: AppTheme.accent,
                        backgroundColor: AppTheme.surfaceVariant,
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${(_downloadProgress * 100).toInt()}%',
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
                onPressed: _downloadModel,
                icon: const Icon(Icons.download),
                label: const Text('Download Model'),
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

  /// Build the ready/recording state with mic button
  Widget _buildRecordingState() {
    return Column(
      children: [
        // Transcript area
        Expanded(
          child: _segments.isEmpty && !_isRecording
              ? _buildEmptyTranscript()
              : _segments.isEmpty && _isRecording
                  ? _buildListeningIndicator()
                  : _buildSegmentList(),
        ),

        // Recording controls
        _buildControls(),
      ],
    );
  }

  /// Listening indicator shown during recording before first segment arrives
  Widget _buildListeningIndicator() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseController,
            builder: (_, __) => Opacity(
              opacity: 0.3 + 0.4 * _pulseController.value,
              child: const Icon(
                Icons.hearing,
                size: 48,
                color: AppTheme.accent,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Listening...',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Transcription will appear shortly',
            style: TextStyle(
              color: AppTheme.textTertiary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  /// Empty transcript placeholder
  Widget _buildEmptyTranscript() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.mic_none,
            size: 64,
            color: AppTheme.border,
          ),
          const SizedBox(height: 16),
          const Text(
            'Tap to start recording',
            style: TextStyle(
              color: AppTheme.textTertiary,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Audio is processed entirely on your device',
            style: TextStyle(
              color: AppTheme.textTertiary,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  /// Scrollable list of transcription segments with timestamps
  Widget _buildSegmentList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _segments.length,
      itemBuilder: (context, index) {
        final segment = _segments[index];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border, width: 1),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Timestamp
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${_formatTimestamp(segment.startMs)} - ${_formatTimestamp(segment.endMs)}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                // Text
                Expanded(
                  child: Text(
                    segment.text.trim(),
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Recording controls: mic button + status
  Widget _buildControls() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.background,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Recording status
              if (_isRecording) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseController,
                      builder: (_, __) => Opacity(
                        opacity: 0.4 + 0.6 * _pulseController.value,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: AppTheme.danger,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Recording  ${_formatDuration(_recordingDuration)}',
                      style: const TextStyle(
                        color: AppTheme.danger,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              if (_isInitializing) ...[
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.accent,
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Loading whisper model...',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],

              // Mic button
              GestureDetector(
                onTap: _isInitializing
                    ? null
                    : (_isRecording ? _stopRecording : _startRecording),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: _isRecording ? AppTheme.danger : AppTheme.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: (_isRecording ? AppTheme.danger : AppTheme.accent)
                            .withValues(alpha: 0.4),
                        blurRadius: _isRecording ? 20 : 12,
                        spreadRadius: _isRecording ? 2 : 0,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isRecording ? Icons.stop : Icons.mic,
                    color: _isRecording
                        ? AppTheme.textPrimary
                        : AppTheme.background,
                    size: 32,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Hint text
              Text(
                _isRecording
                    ? 'Tap to stop'
                    : (_isInitializing ? '' : 'Tap to start recording'),
                style: const TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Speech-to-Text',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        backgroundColor: AppTheme.background,
        actions: [
          // Copy transcript
          if (_transcript.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy, color: AppTheme.textSecondary),
              tooltip: 'Copy transcript',
              onPressed: _copyTranscript,
            ),
          // Clear transcript
          if (_segments.isNotEmpty && !_isRecording)
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: AppTheme.textSecondary),
              tooltip: 'Clear transcript',
              onPressed: _clearTranscript,
            ),
        ],
      ),
      body: _isModelDownloaded ? _buildRecordingState() : _buildDownloadState(),
    );
  }
}
