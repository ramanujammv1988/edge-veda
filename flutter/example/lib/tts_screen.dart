import 'dart:async';

import 'package:flutter/material.dart';
import 'package:edge_veda/edge_veda.dart';

import 'app_theme.dart';

/// TTS (Text-to-Speech) demo tab with voice selection, rate/pitch control,
/// and real-time word highlighting.
///
/// Uses [TtsService] which wraps iOS AVSpeechSynthesizer via platform channels.
/// Neural voices are built into iOS 16+ at no additional binary cost.
///
/// States:
/// 1. Idle -- text input, voice picker, sliders, play button
/// 2. Speaking -- word highlighting overlay, pause/stop controls
/// 3. Paused -- resume/stop controls
class TtsScreen extends StatefulWidget {
  const TtsScreen({super.key});

  @override
  State<TtsScreen> createState() => _TtsScreenState();
}

class _TtsScreenState extends State<TtsScreen> {
  final TtsService _tts = TtsService();
  final TextEditingController _textController = TextEditingController(
    text:
        'The Edge Veda SDK enables on-device AI inference, bringing powerful '
        'language models directly to your iPhone. No cloud, no latency, '
        'complete privacy.',
  );

  List<TtsVoice> _voices = [];
  TtsVoice? _selectedVoice;
  TtsState _state = TtsState.idle;
  double _rate = 0.5;
  double _pitch = 1.0;

  // Word highlighting
  int? _highlightStart;
  int? _highlightLength;

  StreamSubscription<TtsEvent>? _eventSubscription;

  @override
  void initState() {
    super.initState();
    _loadVoices();
    _subscribeToEvents();
  }

  @override
  void dispose() {
    _eventSubscription?.cancel();
    _tts.stop();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _loadVoices() async {
    final voices = await _tts.availableVoices();
    if (!mounted) return;
    setState(() {
      _voices = voices;
      // Default to first English voice
      _selectedVoice = voices.isEmpty
          ? null
          : voices.firstWhere(
              (v) => v.language.startsWith('en'),
              orElse: () => voices.first,
            );
    });
  }

  void _subscribeToEvents() {
    _eventSubscription = _tts.events.listen((event) {
      if (!mounted) return;
      setState(() {
        switch (event.type) {
          case TtsEventType.start:
            _state = TtsState.speaking;
            _highlightStart = null;
            _highlightLength = null;
            break;
          case TtsEventType.finish:
          case TtsEventType.cancel:
            _state = TtsState.idle;
            _highlightStart = null;
            _highlightLength = null;
            break;
          case TtsEventType.wordBoundary:
            _highlightStart = event.wordStart;
            _highlightLength = event.wordLength;
            break;
        }
      });
    });
  }

  void _speak() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    _tts.speak(
      text,
      voiceId: _selectedVoice?.id,
      rate: _rate,
      pitch: _pitch,
    );
  }

  void _stop() {
    _tts.stop();
    setState(() {
      _state = TtsState.idle;
      _highlightStart = null;
      _highlightLength = null;
    });
  }

  void _pause() {
    _tts.pause();
    setState(() => _state = TtsState.paused);
  }

  void _resume() {
    _tts.resume();
    setState(() => _state = TtsState.speaking);
  }

  String _rateLabel(double rate) {
    if (rate < 0.3) return 'Slow';
    if (rate > 0.6) return 'Fast';
    return 'Normal';
  }

  // ============================================================================
  // UI Builders
  // ============================================================================

  Widget _buildHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Text-to-Speech',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Powered by iOS Neural Voices',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Text input with optional word-highlighting overlay during speech.
  Widget _buildTextInput() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Text',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          if (_state == TtsState.speaking || _state == TtsState.paused)
            _buildHighlightedText()
          else
            TextField(
              controller: _textController,
              maxLines: 5,
              minLines: 3,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 15,
                height: 1.5,
              ),
              cursorColor: AppTheme.accent,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppTheme.surfaceVariant,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.accent),
                ),
                contentPadding: const EdgeInsets.all(14),
              ),
            ),
        ],
      ),
    );
  }

  /// RichText overlay with highlighted current word during speech.
  Widget _buildHighlightedText() {
    final fullText = _textController.text;
    final start = _highlightStart;
    final length = _highlightLength;

    List<TextSpan> spans;
    if (start != null && length != null && start >= 0 && start + length <= fullText.length) {
      spans = [
        TextSpan(
          text: fullText.substring(0, start),
          style: const TextStyle(color: AppTheme.textPrimary),
        ),
        TextSpan(
          text: fullText.substring(start, start + length),
          style: TextStyle(
            color: AppTheme.background,
            backgroundColor: AppTheme.accent.withValues(alpha: 0.85),
            fontWeight: FontWeight.w600,
          ),
        ),
        TextSpan(
          text: fullText.substring(start + length),
          style: const TextStyle(color: AppTheme.textPrimary),
        ),
      ];
    } else {
      spans = [
        TextSpan(
          text: fullText,
          style: const TextStyle(color: AppTheme.textPrimary),
        ),
      ];
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 15, height: 1.5),
          children: spans,
        ),
      ),
    );
  }

  Widget _buildVoicePicker() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Voice',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<TtsVoice>(
            initialValue: _selectedVoice,
            isExpanded: true,
            dropdownColor: AppTheme.surfaceVariant,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 14,
            ),
            decoration: InputDecoration(
              filled: true,
              fillColor: AppTheme.surfaceVariant,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            items: _voices.map((voice) {
              return DropdownMenuItem<TtsVoice>(
                value: voice,
                child: Text(
                  '${voice.name} (${voice.language})',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: _state != TtsState.idle
                ? null
                : (voice) {
                    setState(() => _selectedVoice = voice);
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildRateSlider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Rate',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${_rate.toStringAsFixed(2)} - ${_rateLabel(_rate)}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ),
          Slider(
            value: _rate,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            activeColor: AppTheme.accent,
            inactiveColor: AppTheme.surfaceVariant,
            onChanged: _state != TtsState.idle
                ? null
                : (value) => setState(() => _rate = value),
          ),
        ],
      ),
    );
  }

  Widget _buildPitchSlider() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Pitch',
                style: TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                _pitch.toStringAsFixed(2),
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ),
          Slider(
            value: _pitch,
            min: 0.5,
            max: 2.0,
            divisions: 15,
            activeColor: AppTheme.accent,
            inactiveColor: AppTheme.surfaceVariant,
            onChanged: _state != TtsState.idle
                ? null
                : (value) => setState(() => _pitch = value),
          ),
        ],
      ),
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_state == TtsState.speaking) ...[
                // Pause button
                _buildControlButton(
                  icon: Icons.pause,
                  color: AppTheme.accent,
                  size: 48,
                  onTap: _pause,
                ),
                const SizedBox(width: 24),
                // Stop button (primary)
                _buildPrimaryButton(
                  icon: Icons.stop,
                  color: AppTheme.brandRed,
                  onTap: _stop,
                ),
                const SizedBox(width: 24),
                // Spacer for symmetry
                const SizedBox(width: 48),
              ] else if (_state == TtsState.paused) ...[
                // Resume button
                _buildControlButton(
                  icon: Icons.play_arrow,
                  color: AppTheme.accent,
                  size: 48,
                  onTap: _resume,
                ),
                const SizedBox(width: 24),
                // Stop button (primary)
                _buildPrimaryButton(
                  icon: Icons.stop,
                  color: AppTheme.brandRed,
                  onTap: _stop,
                ),
                const SizedBox(width: 24),
                const SizedBox(width: 48),
              ] else ...[
                // Play button (primary)
                _buildPrimaryButton(
                  icon: Icons.play_arrow,
                  color: AppTheme.accent,
                  onTap: _textController.text.trim().isEmpty ? null : _speak,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          // Status text
          Text(
            _state == TtsState.speaking
                ? 'Speaking...'
                : _state == TtsState.paused
                    ? 'Paused'
                    : 'Ready',
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Large primary action button (64x64 circle).
  Widget _buildPrimaryButton({
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: onTap == null ? color.withValues(alpha: 0.3) : color,
          shape: BoxShape.circle,
          boxShadow: onTap == null
              ? null
              : [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 16,
                    spreadRadius: 1,
                  ),
                ],
        ),
        child: Icon(
          icon,
          color: onTap == null
              ? AppTheme.textTertiary
              : AppTheme.background,
          size: 32,
        ),
      ),
    );
  }

  /// Secondary control button (smaller circle).
  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required double size,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          shape: BoxShape.circle,
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Icon(
          icon,
          color: color,
          size: size * 0.5,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Text-to-Speech',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        backgroundColor: AppTheme.background,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            _buildTextInput(),
            const SizedBox(height: 8),
            _buildVoicePicker(),
            const SizedBox(height: 4),
            _buildRateSlider(),
            _buildPitchSlider(),
            _buildControls(),
          ],
        ),
      ),
    );
  }
}
