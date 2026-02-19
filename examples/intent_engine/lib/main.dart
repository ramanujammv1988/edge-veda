import 'dart:math' show sin, pi;

import 'package:flutter/material.dart' hide LockState;

import 'models/home_state.dart';
import 'services/intent_service.dart';
import 'theme.dart';
import 'widgets/action_log_panel.dart';
import 'widgets/device_card.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const IntentEngineApp());
}

/// Intent Engine demo app -- on-device smart home control via LLM tool calling.
class IntentEngineApp extends StatelessWidget {
  const IntentEngineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Home',
      theme: AppTheme.themeData,
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// =============================================================================
// Home Screen
// =============================================================================

enum _ScreenPhase { setup, dashboard }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final HomeState _homeState = HomeState();
  late final IntentService _intentService;
  final TextEditingController _textController = TextEditingController();

  _ScreenPhase _phase = _ScreenPhase.setup;
  String _statusMessage = 'Ready to get started';
  double _progress = 0.0;
  bool _isDownloading = false;

  bool _isProcessing = false;
  String _lastAssistantMessage = '';
  bool _showActionLog = false;
  bool _showSuggestions = true;

  @override
  void initState() {
    super.initState();
    _intentService = IntentService(homeState: _homeState);
    _homeState.addListener(_onHomeStateChanged);
  }

  @override
  void dispose() {
    _homeState.removeListener(_onHomeStateChanged);
    _textController.dispose();
    _intentService.dispose();
    _homeState.dispose();
    super.dispose();
  }

  void _onHomeStateChanged() {
    if (mounted) setState(() {});
  }

  // -- Setup ------------------------------------------------------------------

  Future<void> _startSetup() async {
    setState(() {
      _isDownloading = true;
      _statusMessage = 'Preparing...';
      _progress = 0.0;
    });
    try {
      await _intentService.init(
        onStatus: (s) {
          if (mounted) setState(() => _statusMessage = s);
        },
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) setState(() => _phase = _ScreenPhase.dashboard);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _statusMessage = 'Error: $e';
        });
      }
    }
  }

  // -- Intent processing ------------------------------------------------------

  Future<void> _sendCommand(String text) async {
    if (text.trim().isEmpty || _isProcessing) return;
    _textController.clear();

    setState(() {
      _isProcessing = true;
      _showSuggestions = false;
    });

    try {
      final result = await _intentService.processIntent(text);
      if (mounted) {
        setState(() {
          _lastAssistantMessage = result.message;
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _lastAssistantMessage = 'Error: $e';
          _isProcessing = false;
        });
        _showError('Command failed: $e');
      }
    }
  }

  void _resetConversation() {
    _intentService.reset();
    setState(() {
      _lastAssistantMessage = '';
      _showSuggestions = true;
    });
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800),
    );
  }

  // -- Build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _ScreenPhase.setup => _buildSetupScreen(),
      _ScreenPhase.dashboard => _buildDashboardScreen(),
    };
  }

  // -- Setup Screen -----------------------------------------------------------

  Widget _buildSetupScreen() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.home_outlined, size: 64, color: AppTheme.accent),
              const SizedBox(height: 24),
              Text(
                'Smart Home',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Control your home with natural language, 100% offline',
                style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'First run downloads ~397 MB AI model',
                style: TextStyle(fontSize: 12, color: AppTheme.textTertiary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (_isDownloading) ...[
                Text(
                  _statusMessage,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progress,
                    minHeight: 6,
                    backgroundColor: AppTheme.surface,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppTheme.accent,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(_progress * 100).toInt()}%',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ] else
                ElevatedButton(
                  onPressed: _startSetup,
                  child: const Text('Get Started'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // -- Dashboard Screen -------------------------------------------------------

  Widget _buildDashboardScreen() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Smart Home'),
        actions: [
          IconButton(
            icon: Icon(
              Icons.receipt_long,
              color: _showActionLog ? AppTheme.accent : AppTheme.textSecondary,
            ),
            tooltip: 'Toggle action log',
            onPressed: () => setState(() => _showActionLog = !_showActionLog),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'New conversation',
            onPressed: _resetConversation,
          ),
        ],
      ),
      body: Column(
        children: [
          // Dashboard area
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(
                left: 12,
                right: 12,
                top: 4,
                bottom: 8,
              ),
              children: [
                for (final room in _homeState.rooms) ...[
                  _buildRoomHeader(room),
                  _buildDeviceGrid(room),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),

          // Action log panel (conditionally visible)
          if (_showActionLog) ...[
            Container(
              decoration: const BoxDecoration(
                color: AppTheme.surface,
                border: Border(
                  top: BorderSide(color: AppTheme.border, width: 0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 12, top: 8),
                    child: Text(
                      'Action Log',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ),
                  ActionLogPanel(entries: _homeState.actionLog),
                ],
              ),
            ),
          ],

          // Assistant response area
          if (_lastAssistantMessage.isNotEmpty || _isProcessing)
            _buildAssistantResponse(),

          // Suggestion chips
          if (_showSuggestions && !_isProcessing) _buildSuggestionChips(),

          // Chat input
          _buildChatInput(),
        ],
      ),
    );
  }

  // -- Room header ------------------------------------------------------------

  Widget _buildRoomHeader(Room room) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6, left: 4),
      child: Text(
        room.name,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }

  // -- Device grid ------------------------------------------------------------

  Widget _buildDeviceGrid(Room room) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 400 ? 3 : 2;
        const spacing = 8.0;
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final device in room.devices)
              SizedBox(width: cardWidth, child: DeviceCard(device: device)),
          ],
        );
      },
    );
  }

  // -- Assistant response -----------------------------------------------------

  Widget _buildAssistantResponse() {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          border: Border(
            top: BorderSide(color: AppTheme.border, width: 0.5),
          ),
        ),
        child: _isProcessing
            ? const Row(
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: AppTheme.accent),
                  SizedBox(width: 8),
                  _TypingIndicator(),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: AppTheme.accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 300),
                      opacity: 1.0,
                      child: Text(
                        _lastAssistantMessage,
                        style: const TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: AppTheme.textSecondary,
                          height: 1.3,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // -- Suggestion chips -------------------------------------------------------

  Widget _buildSuggestionChips() {
    const suggestions = [
      "I'm heading to bed",
      "It's movie time",
      "I'm leaving the house",
      "It's too bright in here",
      "Make it cozy",
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final text in suggestions) ...[
              ActionChip(
                label: Text(
                  text,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.accent,
                  ),
                ),
                backgroundColor: AppTheme.accent.withValues(alpha: 0.1),
                side: BorderSide(
                  color: AppTheme.accent.withValues(alpha: 0.3),
                ),
                onPressed: () => _sendCommand(text),
              ),
              const SizedBox(width: 6),
            ],
          ],
        ),
      ),
    );
  }

  // -- Chat input -------------------------------------------------------------

  Widget _buildChatInput() {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              enabled: !_isProcessing,
              decoration: InputDecoration(
                hintText: "Try: I'm heading to bed...",
                hintStyle: const TextStyle(color: AppTheme.textTertiary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppTheme.surfaceVariant,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
              ),
              style: const TextStyle(fontSize: 14),
              maxLines: 2,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: _sendCommand,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(
              Icons.send,
              color:
                  _isProcessing ? AppTheme.textTertiary : AppTheme.accent,
            ),
            onPressed: _isProcessing
                ? null
                : () => _sendCommand(_textController.text),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Typing Indicator
// =============================================================================

/// Animated typing indicator (three pulsing dots).
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          final t = (_ctrl.value - i * 0.2).clamp(0.0, 1.0);
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Opacity(
              opacity: 0.3 + 0.7 * (0.5 + 0.5 * sin(t * 2 * pi)),
              child: Container(
                width: 6,
                height: 6,
                decoration: const BoxDecoration(
                  color: AppTheme.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
