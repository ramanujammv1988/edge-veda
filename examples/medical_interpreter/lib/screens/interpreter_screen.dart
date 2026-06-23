import 'dart:async';

import 'package:flutter/material.dart';
import 'package:edge_veda/edge_veda.dart';

import '../models/conversation.dart';
import '../services/interpreter_service.dart';
import '../services/stt_service.dart';
import '../widgets/message_bubble.dart';
import '../theme.dart';

class InterpreterScreen extends StatefulWidget {
  const InterpreterScreen({
    super.key,
    required this.interpreterService,
    required this.sttService,
  });

  final InterpreterService interpreterService;
  final SttService sttService;

  @override
  State<InterpreterScreen> createState() => _InterpreterScreenState();
}

class _InterpreterScreenState extends State<InterpreterScreen> {
  AppLanguage _providerLang = AppLanguage.english;
  AppLanguage _patientLang = AppLanguage.spanish;

  final List<ConversationMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final TtsService _tts = TtsService();

  bool _isRecording = false;
  bool _isTranslating = false;
  Speaker? _currentSpeaker;
  String _liveTranscript = '';
  StreamSubscription<String>? _transcriptSub;

  // TTS voice cache
  List<TtsVoice> _voices = [];

  @override
  void initState() {
    super.initState();
    _loadVoices();
  }

  @override
  void dispose() {
    _transcriptSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadVoices() async {
    _voices = await _tts.availableVoices();
  }

  /// Find a TTS voice matching the target language locale.
  String? _voiceForLanguage(AppLanguage lang) {
    // Prefer enhanced/premium voices matching the language prefix
    final prefix = lang.code;
    final match = _voices.where((v) => v.language.startsWith(prefix)).toList();
    if (match.isEmpty) return null;
    // Prefer highest quality
    match.sort((a, b) => b.quality.compareTo(a.quality));
    return match.first.id;
  }

  Future<void> _startRecording(Speaker speaker) async {
    if (_isRecording || _isTranslating) return;

    setState(() {
      _currentSpeaker = speaker;
      _isRecording = true;
      _liveTranscript = '';
    });

    _transcriptSub = widget.sttService.onTranscript.listen((text) {
      setState(() => _liveTranscript = text);
      _scrollToBottom();
    });

    final error = await widget.sttService.startRecording();
    if (error != null) {
      _transcriptSub?.cancel();
      setState(() {
        _isRecording = false;
        _currentSpeaker = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    _transcriptSub?.cancel();
    _transcriptSub = null;

    final text = await widget.sttService.stopRecording();
    final speaker = _currentSpeaker!;

    setState(() {
      _isRecording = false;
      _liveTranscript = '';
    });

    if (text.trim().isEmpty) {
      setState(() => _currentSpeaker = null);
      return;
    }

    // Translate
    setState(() => _isTranslating = true);
    _scrollToBottom();

    final sourceLang =
        speaker == Speaker.provider ? _providerLang : _patientLang;
    final targetLang =
        speaker == Speaker.provider ? _patientLang : _providerLang;

    try {
      final translation = await widget.interpreterService.translate(
        text,
        sourceLang,
        targetLang,
      );

      final msg = ConversationMessage(
        speaker: speaker,
        originalText: text.trim(),
        translatedText: translation,
        originalLanguage: sourceLang,
        targetLanguage: targetLang,
        timestamp: DateTime.now(),
      );

      setState(() {
        _messages.add(msg);
        _isTranslating = false;
        _currentSpeaker = null;
      });
      _scrollToBottom();

      // TTS: read translation in target language
      final voiceId = _voiceForLanguage(targetLang);
      await _tts.speak(translation, voiceId: voiceId);
    } catch (e) {
      setState(() {
        _isTranslating = false;
        _currentSpeaker = null;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Translation failed: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  void _clearConversation() {
    setState(() {
      _messages.clear();
      _liveTranscript = '';
    });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.translate, color: AppTheme.accent, size: 22),
            const SizedBox(width: 8),
            const Text(
              'Medical Interpreter',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          if (_messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: 'Clear conversation',
              onPressed: _clearConversation,
            ),
        ],
      ),
      body: Column(
        children: [
          // Language selector row
          _buildLanguageBar(),

          // Messages
          Expanded(
            child: _messages.isEmpty && !_isRecording && !_isTranslating
                ? _buildEmptyState()
                : _buildMessageList(),
          ),

          // Disclaimer
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Text(
              'For informational use only. Always verify with a qualified medical interpreter.',
              style: TextStyle(color: AppTheme.textTertiary, fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ),

          // Mic buttons
          _buildMicBar(),
        ],
      ),
    );
  }

  Widget _buildLanguageBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          // Provider language
          Expanded(
            child: _languageDropdown(
              label: 'Provider',
              icon: Icons.medical_services_outlined,
              color: AppTheme.providerAccent,
              value: _providerLang,
              onChanged: (v) => setState(() => _providerLang = v!),
            ),
          ),

          // Swap arrow
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: IconButton(
              icon: Icon(Icons.swap_horiz, color: AppTheme.accent, size: 24),
              onPressed: () {
                setState(() {
                  final tmp = _providerLang;
                  _providerLang = _patientLang;
                  _patientLang = tmp;
                });
              },
              tooltip: 'Swap languages',
            ),
          ),

          // Patient language
          Expanded(
            child: _languageDropdown(
              label: 'Patient',
              icon: Icons.person_outlined,
              color: AppTheme.patientAccent,
              value: _patientLang,
              onChanged: (v) => setState(() => _patientLang = v!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _languageDropdown({
    required String label,
    required IconData icon,
    required Color color,
    required AppLanguage value,
    required ValueChanged<AppLanguage?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        DropdownButton<AppLanguage>(
          value: value,
          isExpanded: true,
          dropdownColor: AppTheme.surfaceVariant,
          underline: const SizedBox(),
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 14,
          ),
          icon: Icon(Icons.arrow_drop_down, color: color, size: 20),
          items: AppLanguage.values.map((lang) {
            return DropdownMenuItem(
              value: lang,
              child: Text(lang.displayName),
            );
          }).toList(),
          onChanged: _isRecording || _isTranslating ? null : onChanged,
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.record_voice_over_outlined,
            size: 48,
            color: AppTheme.accent.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          const Text(
            'Tap a mic button to start interpreting',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 15),
          ),
          const SizedBox(height: 8),
          const Text(
            'Provider (left) or Patient (right)',
            style: TextStyle(color: AppTheme.textTertiary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    final itemCount = _messages.length +
        (_isRecording || _isTranslating ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        // Live transcript / translating indicator
        if (index == _messages.length) {
          if (_isTranslating) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Translating...',
                    style: TextStyle(
                      color: AppTheme.accent,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            );
          }

          if (_isRecording && _liveTranscript.isNotEmpty) {
            final isProvider = _currentSpeaker == Speaker.provider;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Align(
                alignment: isProvider
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.85,
                  ),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: (isProvider
                            ? AppTheme.providerBubble
                            : AppTheme.patientBubble)
                        .withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: (isProvider
                              ? AppTheme.providerAccent
                              : AppTheme.patientAccent)
                          .withValues(alpha: 0.3),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: isProvider
                                  ? AppTheme.providerAccent
                                  : AppTheme.patientAccent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Listening...',
                            style: TextStyle(
                              fontSize: 11,
                              color: isProvider
                                  ? AppTheme.providerAccent
                                  : AppTheme.patientAccent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _liveTranscript,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          return const SizedBox.shrink();
        }

        return MessageBubble(message: _messages[index]);
      },
    );
  }

  Widget _buildMicBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Provider mic
            Expanded(
              child: _micButton(
                speaker: Speaker.provider,
                label: 'Provider',
                icon: Icons.medical_services_outlined,
                activeColor: AppTheme.providerAccent,
                bgColor: AppTheme.providerBubble,
              ),
            ),
            const SizedBox(width: 16),
            // Patient mic
            Expanded(
              child: _micButton(
                speaker: Speaker.patient,
                label: 'Patient',
                icon: Icons.person_outlined,
                activeColor: AppTheme.patientAccent,
                bgColor: AppTheme.patientBubble,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _micButton({
    required Speaker speaker,
    required String label,
    required IconData icon,
    required Color activeColor,
    required Color bgColor,
  }) {
    final isActive = _isRecording && _currentSpeaker == speaker;
    final isDisabled =
        (_isRecording && _currentSpeaker != speaker) || _isTranslating;

    return GestureDetector(
      onTap: isDisabled
          ? null
          : () {
              if (isActive) {
                _stopRecording();
              } else {
                _startRecording(speaker);
              }
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withValues(alpha: 0.2)
              : isDisabled
                  ? AppTheme.surfaceVariant.withValues(alpha: 0.5)
                  : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isActive
                ? activeColor
                : isDisabled
                    ? AppTheme.border.withValues(alpha: 0.3)
                    : AppTheme.border,
            width: isActive ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? Icons.stop_circle_outlined : Icons.mic,
              size: 32,
              color: isActive
                  ? activeColor
                  : isDisabled
                      ? AppTheme.textTertiary
                      : activeColor,
            ),
            const SizedBox(height: 6),
            Text(
              isActive ? 'Tap to stop' : label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isActive
                    ? activeColor
                    : isDisabled
                        ? AppTheme.textTertiary
                        : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
