import 'package:flutter/material.dart';
import 'package:edge_veda/edge_veda.dart';

import 'services/interpreter_service.dart';
import 'services/stt_service.dart';
import 'screens/interpreter_screen.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MedicalInterpreterApp());
}

class MedicalInterpreterApp extends StatelessWidget {
  const MedicalInterpreterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Medical Interpreter',
      theme: AppTheme.themeData,
      debugShowCheckedModeBanner: false,
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final InterpreterService _interpreterService = InterpreterService();
  final SttService _sttService = SttService();

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
    _interpreterService.dispose();
    _sttService.dispose();
    super.dispose();
  }

  /// Check if both models are already downloaded.
  Future<void> _checkModelsReady() async {
    final mm = ModelManager();
    final medgemmaReady =
        await mm.isModelDownloaded(ModelRegistry.medgemma15_4b.id);
    final whisperReady =
        await mm.isModelDownloaded(ModelRegistry.whisperSmall.id);

    if (medgemmaReady && whisperReady) {
      // Show loading UI before heavy model init
      if (mounted) {
        setState(() {
          _isSettingUp = true;
          _statusMessage = 'Loading models...';
          _progress = 1.0;
        });
      }
      // Yield a frame so the setup screen paints before blocking init
      await Future<void>.delayed(Duration.zero);
      await _initServices();
    }
  }

  Future<void> _setup() async {
    setState(() {
      _isSettingUp = true;
      _errorMessage = null;
      _progress = 0.0;
    });

    try {
      // Step 1: Download MedGemma (2.49 GB)
      await _downloadModel(
        ModelRegistry.medgemma15_4b,
        'Downloading MedGemma 1.5 4B (2.49 GB)...',
        0.0,
        0.85,
      );

      // Step 2: Download Whisper Small Multilingual (244 MB)
      await _downloadModel(
        ModelRegistry.whisperSmall,
        'Downloading Whisper Multilingual (244 MB)...',
        0.85,
        1.0,
      );

      // Step 3: Initialize services
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
      if (mounted) setState(() => _progress = progressEnd);
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

    if (mounted) setState(() => _progress = progressEnd);
  }

  Future<void> _initServices() async {
    if (mounted) {
      setState(() {
        _statusMessage = 'Initializing models...';
        _isSettingUp = true;
      });
    }

    try {
      // Download-only — MedGemma GPU init is deferred to first translate()
      // to avoid OOM when both MedGemma + Whisper are loaded simultaneously
      await _interpreterService.ensureDownloaded(
        onStatus: (s) {
          if (mounted) setState(() => _statusMessage = s);
        },
        onProgress: (_) {},
      );

      await _sttService.init(
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
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSettingUp = false;
          _errorMessage = 'Init failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSetup) return _buildSetupScreen();

    return InterpreterScreen(
      interpreterService: _interpreterService,
      sttService: _sttService,
    );
  }

  Widget _buildSetupScreen() {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.translate, size: 64, color: AppTheme.accent),
                const SizedBox(height: 24),
                const Text(
                  'Medical Interpreter',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Private on-device medical translation\n50+ languages supported',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textSecondary,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'First run downloads ~1.8 GB of AI models',
                  style: TextStyle(fontSize: 12, color: AppTheme.textTertiary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Privacy callout
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        color: AppTheme.accent,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'HIPAA-friendly: data never leaves device',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),

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
}
