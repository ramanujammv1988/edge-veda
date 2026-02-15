import 'package:edge_veda/edge_veda.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'services/health_rag_service.dart';
import 'theme.dart';
import 'widgets/message_bubble.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HealthAdvisorApp());
}

class HealthAdvisorApp extends StatelessWidget {
  const HealthAdvisorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Health Advisor',
      theme: AppTheme.themeData,
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// ---------------------------------------------------------------------------
// Home Screen -- three phases: Setup, Ready, Chat
// ---------------------------------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final HealthRagService _ragService = HealthRagService();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Phase tracking
  bool _modelsReady = false;
  bool _isDownloading = false;
  double _downloadProgress = 0;
  String _statusMessage = '';

  // Document indexing
  bool _isIndexing = false;
  int _indexingDone = 0;
  int _indexingTotal = 0;

  // Chat
  final List<ChatMsg> _messages = [];
  String _streamingText = '';
  bool _isStreaming = false;
  CancelToken? _cancelToken;

  @override
  void dispose() {
    _ragService.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Model setup ───────────────────────────────────────────────────────

  Future<void> _setup() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
      _statusMessage = 'Starting...';
    });

    try {
      await _ragService.init(
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

  // ── Document loading ──────────────────────────────────────────────────

  Future<void> _pickAndIndexDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt', 'md'],
    );
    if (result == null || result.files.single.path == null) return;

    final filePath = result.files.single.path!;
    final fileName = result.files.single.name;

    setState(() {
      _isIndexing = true;
      _indexingDone = 0;
      _indexingTotal = 0;
      _statusMessage = 'Reading document...';
    });

    try {
      await _ragService.indexDocument(
        filePath,
        fileName,
        onProgress: (done, total) {
          setState(() {
            _indexingDone = done;
            _indexingTotal = total;
          });
        },
      );
      setState(() => _statusMessage = 'Document indexed');
    } catch (e) {
      _showError('Indexing failed: $e');
    } finally {
      setState(() => _isIndexing = false);
    }
  }

  void _removeDocument() {
    _ragService.removeDocument();
    setState(() {
      _messages.clear();
      _streamingText = '';
    });
  }

  // ── Chat ──────────────────────────────────────────────────────────────

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty || _isStreaming) return;

    final prompt = text.trim();
    _inputController.clear();

    setState(() {
      _messages.add(ChatMsg(role: 'user', content: prompt));
      _isStreaming = true;
      _streamingText = '';
      _cancelToken = CancelToken();
    });
    _scrollToBottom();

    final buffer = StringBuffer();
    int tokenCount = 0;

    try {
      final stream = _ragService.query(prompt);

      await for (final chunk in stream) {
        if (_cancelToken?.isCancelled == true) break;
        if (chunk.token.isEmpty) continue;

        buffer.write(chunk.token);
        tokenCount++;

        if (tokenCount == 1 || tokenCount % 3 == 0 || chunk.token.contains('\n')) {
          setState(() => _streamingText = buffer.toString());
          _scrollToBottom();
        }
      }

      // Finalize
      final responseText = buffer.toString();
      final confidence = _ragService.lastConfidence;

      setState(() {
        _streamingText = '';
        if (responseText.isNotEmpty) {
          _messages.add(ChatMsg(
            role: 'assistant',
            content: responseText,
            avgConfidence: confidence.avgConfidence,
            needsHandoff: confidence.needsHandoff,
          ));
        }
      });
      _scrollToBottom();
    } catch (e) {
      _showError('Query failed: $e');
    } finally {
      setState(() => _isStreaming = false);
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

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade700),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_modelsReady) return _buildSetupScreen();
    if (!_ragService.isReady) return _buildReadyScreen();
    return _buildChatScreen();
  }

  // ── Phase A: Setup Screen ─────────────────────────────────────────────

  Widget _buildSetupScreen() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.local_hospital,
                size: 64,
                color: AppTheme.accent,
              ),
              const SizedBox(height: 16),
              const Text(
                'Health Advisor',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Your private health knowledge base. 100% on-device.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 24),

              // Privacy callout
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shield_outlined, color: AppTheme.accent, size: 20),
                    const SizedBox(width: 10),
                    const Text(
                      'Your data never leaves this device',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Download progress or Get Started button
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
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${(_downloadProgress * 100).toInt()}%',
                      style: TextStyle(
                        color: AppTheme.accent,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
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

  // ── Phase B: Ready Screen (models loaded, no document) ────────────────

  Widget _buildReadyScreen() {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Health Advisor',
          style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold),
        ),
      ),
      body: _isIndexing
          ? _buildIndexingOverlay()
          : Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.medical_information_outlined,
                      size: 64,
                      color: AppTheme.accent,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Load your health documents',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Add medical PDFs, lab results, or health notes',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
      floatingActionButton: _isIndexing
          ? null
          : FloatingActionButton(
              onPressed: _pickAndIndexDocument,
              backgroundColor: AppTheme.accent,
              child: const Icon(Icons.add, color: Colors.black),
            ),
    );
  }

  Widget _buildIndexingOverlay() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppTheme.accent),
            const SizedBox(height: 24),
            Text(
              _statusMessage,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
              ),
            ),
            if (_indexingTotal > 0) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: _indexingDone / _indexingTotal,
                color: AppTheme.accent,
                backgroundColor: AppTheme.surface,
              ),
              const SizedBox(height: 8),
              Text(
                'Embedding $_indexingDone / $_indexingTotal chunks',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Phase C: Chat Screen ──────────────────────────────────────────────

  Widget _buildChatScreen() {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _ragService.documentName ?? 'Health Advisor',
          style: const TextStyle(fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            tooltip: 'Remove document',
            onPressed: _removeDocument,
          ),
        ],
      ),
      body: Column(
        children: [
          // Document info chip
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_ragService.chunkCount} chunks indexed',
                    style: TextStyle(
                      color: AppTheme.accent,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Message list
          Expanded(
            child: _messages.isEmpty && !_isStreaming
                ? _buildEmptyChat()
                : _buildMessageList(),
          ),

          // Disclaimer
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
            child: Text(
              'This app provides information only. Always consult a healthcare professional.',
              style: TextStyle(
                color: AppTheme.textTertiary,
                fontSize: 10,
              ),
              textAlign: TextAlign.center,
            ),
          ),

          // Input area
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildEmptyChat() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.health_and_safety_outlined,
              size: 48,
              color: AppTheme.accent.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              'Ask a question about your document',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 20),

            // Example question chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _questionChip('What are the key findings?'),
                _questionChip('Are there any risk factors?'),
                _questionChip('Summarize my results'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _questionChip(String text) {
    return ActionChip(
      label: Text(text, style: const TextStyle(fontSize: 12)),
      backgroundColor: AppTheme.surface,
      side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.3)),
      onPressed: () => _sendMessage(text),
    );
  }

  Widget _buildMessageList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _messages.length + (_isStreaming ? 1 : 0),
      itemBuilder: (context, index) {
        // Streaming bubble
        if (index == _messages.length && _isStreaming) {
          if (_streamingText.isEmpty) {
            return Align(
              alignment: Alignment.centerLeft,
              child: Padding(
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
            );
          }
          return MessageBubble(
            message: ChatMsg(role: 'assistant', content: _streamingText),
          );
        }
        return MessageBubble(message: _messages[index]);
      },
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
                  hintText: 'Ask a health question...',
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
                onSubmitted: _sendMessage,
                textInputAction: TextInputAction.send,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(Icons.send, color: AppTheme.accent),
              onPressed: () => _sendMessage(_inputController.text),
            ),
          ],
        ),
      ),
    );
  }
}
