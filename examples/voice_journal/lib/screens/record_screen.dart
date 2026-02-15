import 'dart:async';

import 'package:flutter/material.dart';

import '../models/journal_entry.dart';
import '../services/stt_service.dart';
import '../services/summary_service.dart';
import '../services/journal_db.dart';
import '../services/search_service.dart';
import '../theme.dart';

/// Recording screen with live STT transcription and post-recording processing.
///
/// Two phases:
/// 1. Recording: pulsing mic, live transcript, duration timer
/// 2. Processing: summarize, tag, index, save
class RecordScreen extends StatefulWidget {
  final SttService sttService;
  final SummaryService summaryService;
  final JournalDb journalDb;
  final SearchService searchService;

  const RecordScreen({
    super.key,
    required this.sttService,
    required this.summaryService,
    required this.journalDb,
    required this.searchService,
  });

  @override
  State<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends State<RecordScreen>
    with SingleTickerProviderStateMixin {
  // Recording state
  bool _isRecording = false;
  bool _isProcessing = false;
  String _liveTranscript = '';
  String? _micError;
  Duration _duration = Duration.zero;
  Timer? _durationTimer;

  // Processing state
  int _processingStep = 0; // 0=not started, 1=transcribed, 2=summarizing, 3=indexing, 4=done
  String? _summary;
  String? _tags;

  // Animation
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // Subscriptions
  StreamSubscription<String>? _transcriptSub;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _pulseController.dispose();
    _transcriptSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Recording
  // ---------------------------------------------------------------------------

  Future<void> _startRecording() async {
    setState(() {
      _micError = null;
      _liveTranscript = '';
      _duration = Duration.zero;
    });

    // Listen for transcript updates
    _transcriptSub = widget.sttService.onTranscript.listen(
      (text) {
        if (mounted) {
          setState(() => _liveTranscript = text);
          // Auto-scroll to bottom
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
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _micError = error.toString();
            _isRecording = false;
          });
          _durationTimer?.cancel();
        }
      },
    );

    final error = await widget.sttService.startRecording();
    if (error != null) {
      _transcriptSub?.cancel();
      _transcriptSub = null;
      if (mounted) {
        setState(() => _micError = error);
      }
      return;
    }

    // Start duration timer
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _isRecording) {
        setState(() {
          _duration = Duration(
            seconds: widget.sttService.recordingDurationSeconds,
          );
        });
      }
    });

    setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    _durationTimer?.cancel();
    _durationTimer = null;

    final transcript = await widget.sttService.stopRecording();

    _transcriptSub?.cancel();
    _transcriptSub = null;

    if (mounted) {
      setState(() {
        _isRecording = false;
        _liveTranscript = transcript;
      });
    }

    if (transcript.trim().isNotEmpty) {
      await _processEntry(transcript);
    }
  }

  void _cancelRecording() {
    _durationTimer?.cancel();
    _transcriptSub?.cancel();
    widget.sttService.stopRecording();
    Navigator.of(context).pop();
  }

  // ---------------------------------------------------------------------------
  // Processing
  // ---------------------------------------------------------------------------

  Future<void> _processEntry(String transcript) async {
    setState(() {
      _isProcessing = true;
      _processingStep = 1; // Transcription complete
    });

    // Step 1: Save entry to database (transcript only)
    final entry = JournalEntry(
      createdAt: DateTime.now(),
      transcript: transcript,
      durationSeconds: _duration.inSeconds,
    );
    final id = await widget.journalDb.insertEntry(entry);
    final savedEntry = entry.copyWith(id: id);

    // Step 2: Generate summary + tags
    setState(() => _processingStep = 2);
    try {
      final result = await widget.summaryService.summarize(transcript);
      _summary = result.summary;
      _tags = result.tags;

      // Update entry with summary and tags
      final updatedEntry = savedEntry.copyWith(
        summary: _summary,
        tags: _tags,
      );
      await widget.journalDb.updateEntry(updatedEntry);

      // Step 3: Index for search
      setState(() => _processingStep = 3);
      await widget.searchService.indexEntry(updatedEntry);
    } catch (_) {
      // Summarization or indexing failed -- entry is still saved with transcript
    }

    // Step 4: Done
    setState(() => _processingStep = 4);

    // Auto-navigate back after delay
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (mounted) {
      Navigator.of(context).pop(savedEntry);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildRecordingPhase() {
    return Column(
      children: [
        const SizedBox(height: 40),

        // Pulsing mic icon
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (_, __) => Transform.scale(
            scale: _isRecording ? _pulseAnimation.value : 1.0,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRecording
                    ? AppTheme.recording.withValues(alpha: 0.2)
                    : AppTheme.accent.withValues(alpha: 0.1),
              ),
              child: Icon(
                Icons.mic,
                size: 40,
                color: _isRecording ? AppTheme.recording : AppTheme.accent,
              ),
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Duration timer
        if (_isRecording)
          Text(
            _formatDuration(_duration),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w300,
              color: AppTheme.textPrimary,
              fontFamily: 'monospace',
            ),
          ),

        const SizedBox(height: 24),

        // Live transcript area
        Expanded(
          child: _liveTranscript.isEmpty && !_isRecording
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_micError != null) ...[
                        const Icon(Icons.mic_off, size: 48,
                            color: AppTheme.danger),
                        const SizedBox(height: 12),
                        Text(
                          _micError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppTheme.danger,
                            fontSize: 14,
                          ),
                        ),
                      ] else ...[
                        const Text(
                          'Tap Start Recording to begin',
                          style: TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              : Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    child: Text(
                      _liveTranscript.isEmpty
                          ? 'Listening...'
                          : _liveTranscript,
                      style: TextStyle(
                        color: _liveTranscript.isEmpty
                            ? AppTheme.textTertiary
                            : AppTheme.textPrimary,
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
        ),

        const SizedBox(height: 16),

        // Buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          child: _isRecording
              ? Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: _cancelRecording,
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: AppTheme.textTertiary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _stopRecording,
                        icon: const Icon(Icons.stop),
                        label: const Text('Stop'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.recording,
                          foregroundColor: AppTheme.textPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _micError != null ? null : _startRecording,
                    icon: const Icon(Icons.mic),
                    label: const Text('Start Recording'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: AppTheme.background,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildProcessingStep(int step, String label, {bool active = false}) {
    final bool complete = _processingStep > step;
    final bool isCurrent = _processingStep == step;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          if (complete)
            const Icon(Icons.check_circle, color: AppTheme.success, size: 24)
          else if (isCurrent || active)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.accent,
              ),
            )
          else
            const Icon(Icons.circle_outlined,
                color: AppTheme.textTertiary, size: 24),
          const SizedBox(width: 12),
          Text(
            complete
                ? label.replaceFirst('...', '')
                : label,
            style: TextStyle(
              color: complete
                  ? AppTheme.success
                  : (isCurrent ? AppTheme.textPrimary : AppTheme.textTertiary),
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessingPhase() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                'Processing your entry...',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 32),

            _buildProcessingStep(1, 'Transcription complete'),
            _buildProcessingStep(2, 'Generating summary...'),
            _buildProcessingStep(3, 'Indexing for search...'),

            if (_processingStep >= 4) ...[
              const SizedBox(height: 24),
              const Center(
                child: Column(
                  children: [
                    Icon(Icons.check_circle, color: AppTheme.success, size: 48),
                    SizedBox(height: 12),
                    Text(
                      'Entry saved!',
                      style: TextStyle(
                        color: AppTheme.success,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isProcessing ? 'Processing' : 'New Entry'),
        leading: _isProcessing
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  if (_isRecording) {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Discard recording?'),
                        content: const Text(
                          'Your current recording will be lost.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Continue Recording'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _cancelRecording();
                            },
                            child: const Text(
                              'Discard',
                              style: TextStyle(color: AppTheme.danger),
                            ),
                          ),
                        ],
                      ),
                    );
                  } else {
                    Navigator.of(context).pop();
                  }
                },
              ),
      ),
      body: SafeArea(
        child: _isProcessing ? _buildProcessingPhase() : _buildRecordingPhase(),
      ),
    );
  }
}
