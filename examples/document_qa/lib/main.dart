import 'dart:math' show sin, pi;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'services/pdf_service.dart';
import 'services/rag_service.dart';
import 'theme.dart';
import 'widgets/message_bubble.dart';

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

/// Home screen: setup -> ready -> chat.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _ScreenPhase { setup, ready, chat }

class _HomeScreenState extends State<HomeScreen> {
  final RagService _ragService = RagService();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  _ScreenPhase _phase = _ScreenPhase.setup;
  String _statusMessage = 'Ready to get started';
  double _progress = 0.0;
  bool _isDownloading = false;
  bool _isIndexing = false;
  int _indexingCurrent = 0;
  int _indexingTotal = 0;
  final List<Map<String, String>> _messages = [];
  bool _isStreaming = false;
  String _streamingText = '';

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _ragService.dispose();
    super.dispose();
  }

  Future<void> _startSetup() async {
    setState(() { _isDownloading = true; _statusMessage = 'Preparing...'; _progress = 0.0; });
    try {
      await _ragService.init(
        onStatus: (s) { if (mounted) setState(() => _statusMessage = s); },
        onProgress: (p) { if (mounted) setState(() => _progress = p); },
      );
      if (mounted) setState(() => _phase = _ScreenPhase.ready);
    } catch (e) {
      if (mounted) setState(() { _isDownloading = false; _statusMessage = 'Error: $e'; });
    }
  }

  Future<void> _pickAndIndexDocument() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['pdf', 'txt', 'md'],
    );
    if (result == null || result.files.single.path == null) return;
    final filePath = result.files.single.path!;
    final fileName = result.files.single.name;
    setState(() { _isIndexing = true; _indexingCurrent = 0; _indexingTotal = 0; });
    try {
      final text = await PdfService.extractText(filePath);
      if (text.trim().isEmpty) {
        if (mounted) { _showError('Document is empty'); setState(() => _isIndexing = false); }
        return;
      }
      await _ragService.indexDocument(text, fileName, onChunkProgress: (c, t) {
        if (mounted) setState(() { _indexingCurrent = c; _indexingTotal = t; });
      });
      if (mounted) setState(() { _isIndexing = false; _messages.clear(); _phase = _ScreenPhase.chat; });
    } catch (e) {
      if (mounted) { _showError('Failed to index: $e'); setState(() => _isIndexing = false); }
    }
  }

  Future<void> _sendMessage(String question) async {
    if (question.trim().isEmpty || _isStreaming) return;
    _textController.clear();
    setState(() { _messages.add({'role': 'user', 'content': question}); _isStreaming = true; _streamingText = ''; });
    _scrollToBottom();
    try {
      await for (final chunk in _ragService.query(question)) {
        if (!mounted) break;
        setState(() => _streamingText += chunk.token);
        _scrollToBottom();
      }
      if (mounted) {
        setState(() { _messages.add({'role': 'assistant', 'content': _streamingText}); _streamingText = ''; _isStreaming = false; });
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) setState(() { _messages.add({'role': 'assistant', 'content': 'Error: $e'}); _streamingText = ''; _isStreaming = false; });
    }
  }

  void _removeDocument() {
    _ragService.removeDocument();
    setState(() { _messages.clear(); _streamingText = ''; _isStreaming = false; _phase = _ScreenPhase.ready; });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut,
        );
      }
    });
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      switch (_phase) {
        _ScreenPhase.setup => _buildSetupScreen(),
        _ScreenPhase.ready => _buildReadyScreen(),
        _ScreenPhase.chat => _buildChatScreen(),
      },
      if (_isIndexing) _buildIndexingOverlay(),
    ]);
  }

  // -- Phase A: Setup -------------------------------------------------------

  Widget _buildSetupScreen() {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_download_outlined, size: 64, color: AppTheme.accent),
            const SizedBox(height: 24),
            Text('Document Q&A', style: Theme.of(context).textTheme.headlineLarge),
            const SizedBox(height: 8),
            const Text('Ask questions about any document, 100% offline',
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary), textAlign: TextAlign.center),
            const SizedBox(height: 32),
            if (_isDownloading) ...[
              Text(_statusMessage, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(
                value: _progress, minHeight: 6, backgroundColor: AppTheme.surface,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent))),
              const SizedBox(height: 8),
              Text('${(_progress * 100).toInt()}%', style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary)),
            ] else
              ElevatedButton(onPressed: _startSetup, child: const Text('Get Started')),
          ]),
        ),
      ),
    );
  }

  // -- Phase B: Ready -------------------------------------------------------

  Widget _buildReadyScreen() {
    return Scaffold(
      appBar: AppBar(title: const Text('Document Q&A')),
      body: const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.description_outlined, size: 64, color: AppTheme.accent),
        SizedBox(height: 16),
        Text('Attach a document to get started', style: TextStyle(fontSize: 16)),
        SizedBox(height: 8),
        Text('Supports PDF and text files', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
      ])),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickAndIndexDocument, backgroundColor: AppTheme.accent,
        child: const Icon(Icons.attach_file, color: Colors.white)),
    );
  }

  // -- Phase C: Chat --------------------------------------------------------

  Widget _buildChatScreen() {
    return Scaffold(
      appBar: AppBar(
        title: Text(_ragService.documentName ?? 'Chat', overflow: TextOverflow.ellipsis),
        actions: [IconButton(icon: const Icon(Icons.close), tooltip: 'Remove document', onPressed: _removeDocument)],
      ),
      body: Column(children: [
        // Document info chip
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12)),
              child: Text('${_ragService.chunkCount} chunks indexed',
                style: const TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.w500)),
            ),
          ]),
        ),
        // Messages
        Expanded(child: _messages.isEmpty && !_isStreaming ? _buildEmptyChat() : _buildMessageList()),
        // Input
        _buildInputArea(),
      ]),
    );
  }

  Widget _buildEmptyChat() {
    return Center(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.question_answer_outlined, size: 48, color: AppTheme.textTertiary),
        const SizedBox(height: 16),
        const Text('Ask anything about your document',
          style: TextStyle(fontSize: 16, color: AppTheme.textSecondary)),
        const SizedBox(height: 20),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          _suggestionChip('What is this about?'),
          _suggestionChip('Summarize the key points'),
          _suggestionChip('What are the main conclusions?'),
        ]),
      ]),
    ));
  }

  Widget _suggestionChip(String text) => ActionChip(
    label: Text(text, style: const TextStyle(fontSize: 13, color: AppTheme.accent)),
    backgroundColor: AppTheme.accent.withValues(alpha: 0.1),
    side: BorderSide(color: AppTheme.accent.withValues(alpha: 0.3)),
    onPressed: () => _sendMessage(text));

  Widget _buildMessageList() {
    final count = _messages.length + (_isStreaming ? 1 : 0);
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: count,
      itemBuilder: (context, i) {
        if (i < _messages.length) {
          final msg = _messages[i];
          return MessageBubble(text: msg['content'] ?? '', isUser: msg['role'] == 'user', showSource: msg['role'] == 'assistant');
        }
        // Streaming bubble
        if (_streamingText.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(children: [SizedBox(width: 26), _TypingIndicator()]));
        }
        return MessageBubble(text: _streamingText, isUser: false, showSource: true);
      },
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.only(left: 12, right: 8, top: 8, bottom: MediaQuery.of(context).padding.bottom + 8),
      decoration: const BoxDecoration(
        color: AppTheme.surface, border: Border(top: BorderSide(color: AppTheme.border, width: 0.5))),
      child: Row(children: [
        Expanded(child: TextField(
          controller: _textController, enabled: !_isStreaming,
          decoration: InputDecoration(
            hintText: 'Ask about your document...', hintStyle: const TextStyle(color: AppTheme.textTertiary),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
            filled: true, fillColor: AppTheme.surfaceVariant,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
          style: const TextStyle(fontSize: 14), maxLines: 3, minLines: 1,
          textInputAction: TextInputAction.send, onSubmitted: _sendMessage)),
        const SizedBox(width: 4),
        IconButton(
          icon: Icon(Icons.send, color: _isStreaming ? AppTheme.textTertiary : AppTheme.accent),
          onPressed: _isStreaming ? null : () => _sendMessage(_textController.text)),
      ]),
    );
  }

  Widget _buildIndexingOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accent)),
        const SizedBox(height: 24),
        Text(_indexingTotal > 0 ? 'Indexing chunk $_indexingCurrent of $_indexingTotal' : 'Reading document...',
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
        const SizedBox(height: 8),
        if (_indexingTotal > 0)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 64), child: ClipRRect(
            borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(
              value: _indexingCurrent / _indexingTotal, minHeight: 4, backgroundColor: AppTheme.surface,
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent)))),
      ])),
    );
  }
}

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
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(animation: _ctrl, builder: (context, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final t = (_ctrl.value - i * 0.2).clamp(0.0, 1.0);
        return Padding(padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Opacity(opacity: 0.3 + 0.7 * (0.5 + 0.5 * sin(t * 2 * pi)), child: const _Dot()));
      })));
  }
}

class _Dot extends StatelessWidget {
  const _Dot();
  @override
  Widget build(BuildContext context) {
    return Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.accent, shape: BoxShape.circle));
  }
}
