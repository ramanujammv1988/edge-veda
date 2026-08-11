import 'package:edge_veda/edge_veda.dart';
import 'package:flutter/material.dart';

import 'services/extraction_service.dart';
import 'theme.dart';
import 'widgets/extraction_card.dart';
import 'widgets/privacy_banner.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MedicalExtractApp());
}

class MedicalExtractApp extends StatelessWidget {
  const MedicalExtractApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Medical Extract',
      theme: AppTheme.themeData,
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ---------------------------------------------------------------------------
// Home Screen
// ---------------------------------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final ExtractionService _service = ExtractionService();
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _docController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late TabController _tabController;

  // Setup
  bool _modelsReady = false;
  bool _isDownloading = false;
  double _downloadProgress = 0;
  String _statusMessage = '';

  // Extraction
  bool _isExtracting = false;
  Map<String, dynamic>? _extractionResult;
  ExtractionMode _currentMode = ExtractionMode.prescription;

  // Follow-up chat
  final List<_ChatMsg> _messages = [];
  String _streamingText = '';
  bool _isStreaming = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      setState(() {
        _currentMode = _tabController.index == 0
            ? ExtractionMode.prescription
            : ExtractionMode.labReport;
      });
    });
  }

  @override
  void dispose() {
    _service.dispose();
    _inputController.dispose();
    _docController.dispose();
    _scrollController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ── Setup ──────────────────────────────────────────────────────────────

  Future<void> _setup() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _statusMessage = 'Starting...';
    });

    try {
      await _service.init(
        onStatus: (s) => setState(() => _statusMessage = s),
        onProgress: (p) => setState(() => _downloadProgress = p),
      );
      setState(() => _modelsReady = true);
    } catch (e) {
      _showError('Setup failed: $e');
    } finally {
      setState(() => _isDownloading = false);
    }
  }

  // ── Extraction ─────────────────────────────────────────────────────────

  Future<void> _extractDocument() async {
    final text = _docController.text.trim();
    if (text.isEmpty) {
      _showError('Paste or enter document text first');
      return;
    }

    setState(() {
      _isExtracting = true;
      _extractionResult = null;
      _messages.clear();
    });

    try {
      final result = await _service.extract(text, _currentMode);
      setState(() => _extractionResult = result);
    } catch (e) {
      _showError('Extraction failed: $e');
    } finally {
      setState(() => _isExtracting = false);
    }
  }

  // ── Follow-up Q&A ─────────────────────────────────────────────────────

  Future<void> _askQuestion(String text) async {
    if (text.trim().isEmpty || _isStreaming) return;
    final question = text.trim();
    _inputController.clear();

    setState(() {
      _messages.add(_ChatMsg(role: 'user', content: question));
      _isStreaming = true;
      _streamingText = '';
    });

    final buffer = StringBuffer();
    try {
      await for (final chunk in _service.askFollowUp(question)) {
        if (chunk.token.isEmpty) continue;
        buffer.write(chunk.token);
        setState(() => _streamingText = buffer.toString());
      }
      setState(() {
        _streamingText = '';
        _messages.add(_ChatMsg(role: 'assistant', content: buffer.toString()));
      });
    } catch (e) {
      _showError('Query failed: $e');
    } finally {
      setState(() => _isStreaming = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_modelsReady) return _buildSetupScreen();
    return _buildMainScreen();
  }

  // ── Setup Screen ───────────────────────────────────────────────────────

  Widget _buildSetupScreen() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_hospital, size: 64, color: AppTheme.accent),
              const SizedBox(height: 16),
              const Text(
                'Medical Extract',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Extract structured data from prescriptions & lab reports.\n100% on-device. HIPAA-friendly by design.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 4),
              const Text(
                'First run downloads ~1.7 GB of AI models',
                style: TextStyle(fontSize: 12, color: AppTheme.textTertiary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              const PrivacyBanner(),
              const SizedBox(height: 32),
              if (_isDownloading) ...[
                LinearProgressIndicator(
                  value: _downloadProgress > 0 ? _downloadProgress : null,
                  color: AppTheme.accent,
                  backgroundColor: AppTheme.surface,
                ),
                const SizedBox(height: 12),
                Text(
                  _statusMessage,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
                if (_downloadProgress > 0)
                  Text(
                    '${(_downloadProgress * 100).toInt()}%',
                    style: TextStyle(
                      color: AppTheme.accent,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ] else
                SizedBox(
                  width: 200,
                  child: ElevatedButton(
                    onPressed: _setup,
                    child: const Text('Get Started'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Main Screen ────────────────────────────────────────────────────────

  Widget _buildMainScreen() {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Medical Extract',
          style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.accent,
          labelColor: AppTheme.accent,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: const [
            Tab(icon: Icon(Icons.medication), text: 'Prescriptions'),
            Tab(icon: Icon(Icons.biotech), text: 'Lab Reports'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Document input
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _docController,
              maxLines: 6,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
              ),
              decoration: InputDecoration(
                hintText: _currentMode == ExtractionMode.prescription
                    ? 'Paste prescription text here...\n\nExample:\nDr. Smith\nDate: 2026-03-15\nRx: Amoxicillin 500mg\nSig: Take 1 capsule 3 times daily for 10 days'
                    : 'Paste lab report text here...\n\nExample:\nComplete Blood Count\nWBC: 7.2 x10^3/uL (4.5-11.0) Normal\nRBC: 4.8 x10^6/uL (4.7-6.1) Normal\nHemoglobin: 14.2 g/dL (14.0-18.0) Normal',
                hintStyle: const TextStyle(
                  color: AppTheme.textTertiary,
                  fontSize: 12,
                ),
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
                  borderSide: BorderSide(color: AppTheme.accent),
                ),
                filled: true,
                fillColor: AppTheme.surface,
              ),
            ),
          ),

          // Extract button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isExtracting ? null : _extractDocument,
                icon: _isExtracting
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.accent,
                        ),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(_isExtracting ? 'Extracting...' : 'Extract'),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Results + Q&A
          Expanded(
            child: _extractionResult != null
                ? _buildResults()
                : Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _currentMode == ExtractionMode.prescription
                              ? Icons.medication_outlined
                              : Icons.biotech_outlined,
                          size: 48,
                          color: AppTheme.accent.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Paste document text above and tap Extract',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),

          const DisclaimerBanner(),

          // Follow-up input
          if (_extractionResult != null) _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildResults() {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        // Extraction cards
        if (_currentMode == ExtractionMode.prescription)
          PrescriptionCard(data: _extractionResult!)
        else ...[
          final tests = (_extractionResult!['tests'] as List<dynamic>?) ?? [];
          for (final test in tests)
            LabReportCard(data: test as Map<String, dynamic>),
        ],

        const SizedBox(height: 16),

        // Follow-up messages
        if (_messages.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'Follow-up Q&A',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final msg in _messages) _buildMessageBubble(msg),
          if (_isStreaming && _streamingText.isNotEmpty)
            _buildMessageBubble(
              _ChatMsg(role: 'assistant', content: _streamingText),
            ),
          if (_isStreaming && _streamingText.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.accent,
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildMessageBubble(_ChatMsg msg) {
    final isUser = msg.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.accent.withValues(alpha: 0.2) : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isUser
                ? AppTheme.accent.withValues(alpha: 0.3)
                : AppTheme.border,
          ),
        ),
        child: Text(
          msg.content,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        color: AppTheme.background,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                ),
                decoration: InputDecoration(
                  hintText: 'Ask about your results...',
                  hintStyle: const TextStyle(color: AppTheme.textTertiary),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: AppTheme.accent),
                  ),
                  filled: true,
                  fillColor: AppTheme.surface,
                ),
                onSubmitted: _askQuestion,
                textInputAction: TextInputAction.send,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.send, color: AppTheme.accent),
              onPressed: () => _askQuestion(_inputController.text),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatMsg {
  final String role;
  final String content;
  _ChatMsg({required this.role, required this.content});
}
