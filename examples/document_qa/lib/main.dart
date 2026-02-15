import 'package:flutter/material.dart';

import 'services/rag_service.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DocumentQAApp());
}

class DocumentQAApp extends StatelessWidget {
  const DocumentQAApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Document Q&A',
      theme: AppTheme.themeData,
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

/// Home screen with 3 phases: setup, ready, chat.
///
/// - Setup: Download models with progress UI.
/// - Ready: Pick a document to index.
/// - Chat: Ask questions about the indexed document.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Screen phase for the home screen.
enum _ScreenPhase { setup, ready, chat }

class _HomeScreenState extends State<HomeScreen> {
  final RagService _ragService = RagService();

  _ScreenPhase _phase = _ScreenPhase.setup;
  String _statusMessage = 'Ready to get started';
  double _progress = 0.0;
  bool _isDownloading = false;

  @override
  void dispose() {
    _ragService.dispose();
    super.dispose();
  }

  Future<void> _startSetup() async {
    setState(() {
      _isDownloading = true;
      _statusMessage = 'Preparing...';
      _progress = 0.0;
    });

    try {
      await _ragService.init(
        onStatus: (status) {
          if (mounted) setState(() => _statusMessage = status);
        },
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
      );
      if (mounted) {
        setState(() => _phase = _ScreenPhase.ready);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _statusMessage = 'Error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _ScreenPhase.setup:
        return _buildSetupScreen();
      case _ScreenPhase.ready:
        return _buildReadyScreen();
      case _ScreenPhase.chat:
        return _buildChatScreen();
    }
  }

  // -- Phase A: Setup Screen ------------------------------------------------

  Widget _buildSetupScreen() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.cloud_download_outlined,
                size: 64,
                color: AppTheme.accent,
              ),
              const SizedBox(height: 24),
              Text(
                'Document Q&A',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Ask questions about any document, 100% offline',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
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
              ] else ...[
                ElevatedButton(
                  onPressed: _startSetup,
                  child: const Text('Get Started'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // -- Phase B: Ready Screen (placeholder -- completed in Task 2) -----------

  Widget _buildReadyScreen() {
    return Scaffold(
      appBar: AppBar(title: const Text('Document Q&A')),
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.description_outlined,
              size: 64,
              color: AppTheme.accent,
            ),
            SizedBox(height: 16),
            Text('Attach a document to get started'),
            SizedBox(height: 8),
            Text(
              'Supports PDF and text files',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -- Phase C: Chat Screen (placeholder -- completed in Task 2) ------------

  Widget _buildChatScreen() {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: const Center(child: Text('Chat screen placeholder')),
    );
  }
}
