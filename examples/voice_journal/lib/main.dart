import 'dart:async';

import 'package:flutter/material.dart';
import 'package:edge_veda/edge_veda.dart';

import 'screens/journal_list_screen.dart';
import 'screens/record_screen.dart';
import 'screens/entry_detail_screen.dart';
import 'services/stt_service.dart';
import 'services/summary_service.dart';
import 'services/journal_db.dart';
import 'services/search_service.dart';
import 'models/journal_entry.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VoiceJournalApp());
}

class VoiceJournalApp extends StatelessWidget {
  const VoiceJournalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voice Journal',
      theme: AppTheme.themeData,
      home: const AppShell(),
    );
  }
}

/// Root widget that manages setup state and service lifecycle.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  // Services
  final SttService _sttService = SttService();
  final SummaryService _summaryService = SummaryService();
  final SearchService _searchService = SearchService();
  final JournalDb _journalDb = JournalDb();

  // Setup state
  bool _isSetup = false;
  bool _isSettingUp = false;
  String _statusMessage = '';
  double _progress = 0.0;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkModelsReady();
  }

  @override
  void dispose() {
    _sttService.dispose();
    _summaryService.dispose();
    _searchService.dispose();
    super.dispose();
  }

  /// Check if all 3 models are already downloaded.
  Future<void> _checkModelsReady() async {
    final mm = ModelManager();
    final whisperReady =
        await mm.isModelDownloaded(ModelRegistry.whisperBaseEn.id);
    final chatReady =
        await mm.isModelDownloaded(ModelRegistry.llama32_1b.id);
    final embedReady =
        await mm.isModelDownloaded(ModelRegistry.allMiniLmL6V2.id);

    if (whisperReady && chatReady && embedReady) {
      await _initServices();
    }
  }

  /// Download all 3 models and initialize services.
  Future<void> _setup() async {
    setState(() {
      _isSettingUp = true;
      _errorMessage = null;
      _progress = 0.0;
    });

    try {
      // Step 1: Download whisper-base model
      await _downloadModel(
        ModelRegistry.whisperBaseEn,
        'Downloading speech model...',
        0.0,
        0.33,
      );

      // Step 2: Download llama32_1b model
      await _downloadModel(
        ModelRegistry.llama32_1b,
        'Downloading chat model...',
        0.33,
        0.66,
      );

      // Step 3: Download allMiniLmL6V2 embedding model
      await _downloadModel(
        ModelRegistry.allMiniLmL6V2,
        'Downloading embedding model...',
        0.66,
        1.0,
      );

      // Step 4: Initialize services
      await _initServices();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSettingUp = false;
          _errorMessage = 'Setup failed: $e';
        });
      }
    }
  }

  Future<void> _downloadModel(
    ModelInfo model,
    String status,
    double progressStart,
    double progressEnd,
  ) async {
    if (mounted) {
      setState(() => _statusMessage = status);
    }

    final mm = ModelManager();
    final isDownloaded = await mm.isModelDownloaded(model.id);
    if (isDownloaded) {
      if (mounted) {
        setState(() => _progress = progressEnd);
      }
      mm.dispose();
      return;
    }

    final sub = mm.downloadProgress.listen((p) {
      if (mounted) {
        final range = progressEnd - progressStart;
        setState(() {
          _progress = progressStart + p.progress * range;
        });
      }
    });

    try {
      await mm.downloadModel(model);
    } finally {
      await sub.cancel();
      mm.dispose();
    }

    if (mounted) {
      setState(() => _progress = progressEnd);
    }
  }

  Future<void> _initServices() async {
    if (mounted) {
      setState(() {
        _statusMessage = 'Initializing services...';
        _isSettingUp = true;
      });
    }

    await _sttService.init(
      onStatus: (s) {
        if (mounted) setState(() => _statusMessage = s);
      },
    );

    await _summaryService.init(
      onStatus: (s) {
        if (mounted) setState(() => _statusMessage = s);
      },
    );

    await _searchService.init(
      onStatus: (s) {
        if (mounted) setState(() => _statusMessage = s);
      },
    );

    if (mounted) {
      setState(() {
        _isSetup = true;
        _isSettingUp = false;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Navigation helpers
  // ---------------------------------------------------------------------------

  void _openRecordScreen() {
    Navigator.of(context)
        .push<JournalEntry>(
      MaterialPageRoute(
        builder: (_) => RecordScreen(
          sttService: _sttService,
          summaryService: _summaryService,
          journalDb: _journalDb,
          searchService: _searchService,
        ),
      ),
    )
        .then((_) {
      // Refresh list when returning
      setState(() {});
    });
  }

  void _openDetailScreen(JournalEntry entry) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EntryDetailScreen(
          entry: entry,
          journalDb: _journalDb,
          searchService: _searchService,
        ),
      ),
    ).then((_) {
      // Refresh list when returning (entry may have been deleted)
      setState(() {});
    });
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  Widget _buildSetupScreen() {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.mic,
                  size: 64,
                  color: AppTheme.accent,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Voice Journal',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Record, transcribe, summarize, search\n-- all on device',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 40),
                if (_errorMessage != null) ...[
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.danger,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (_isSettingUp) ...[
                  SizedBox(
                    width: 260,
                    child: Column(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _progress > 0 ? _progress : null,
                            color: AppTheme.accent,
                            backgroundColor: AppTheme.surfaceVariant,
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${(_progress * 100).toInt()}%',
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _statusMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else
                  ElevatedButton.icon(
                    onPressed: _setup,
                    icon: const Icon(Icons.download),
                    label: const Text('Get Started'),
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSetup) return _buildSetupScreen();

    return JournalListScreen(
      journalDb: _journalDb,
      searchService: _searchService,
      onRecord: _openRecordScreen,
      onOpenEntry: _openDetailScreen,
    );
  }
}
