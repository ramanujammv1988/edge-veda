import 'package:flutter/material.dart';
import 'package:edge_veda/edge_veda.dart';

void main() {
  runApp(const EdgeVedaExampleApp());
}

class EdgeVedaExampleApp extends StatelessWidget {
  const EdgeVedaExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Edge Veda Example',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: const ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final EdgeVeda _edgeVeda = EdgeVeda();
  final ModelManager _modelManager = ModelManager();
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isInitialized = false;
  bool _isLoading = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _modelPath;
  String _statusMessage = 'Ready to initialize';

  // Performance metrics tracking
  int _tokenCount = 0;
  int? _timeToFirstTokenMs;
  double? _tokensPerSecond;
  double? _memoryMb;
  final _stopwatch = Stopwatch();

  final List<ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    _checkAndDownloadModel();
  }

  @override
  void dispose() {
    _edgeVeda.dispose();
    _modelManager.dispose();
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _checkAndDownloadModel() async {
    setState(() {
      _isDownloading = true;
      _statusMessage = 'Checking for model...';
    });

    try {
      final model = ModelRegistry.llama32_1b;
      final isDownloaded = await _modelManager.isModelDownloaded(model.id);

      if (!isDownloaded) {
        setState(() {
          _statusMessage = 'Downloading model (${model.name})...';
        });

        // Listen to download progress
        _modelManager.downloadProgress.listen((progress) {
          setState(() {
            _downloadProgress = progress.progress;
            _statusMessage =
                'Downloading: ${progress.progressPercent}% (${_formatBytes(progress.downloadedBytes)}/${_formatBytes(progress.totalBytes)})';
          });
        });

        _modelPath = await _modelManager.downloadModel(model);
      } else {
        _modelPath = await _modelManager.getModelPath(model.id);
      }

      setState(() {
        _isDownloading = false;
        _statusMessage = 'Model ready. Tap "Initialize" to start.';
      });
    } catch (e) {
      setState(() {
        _isDownloading = false;
        _statusMessage = 'Error: ${e.toString()}';
      });
    }
  }

  Future<void> _initializeEdgeVeda() async {
    if (_modelPath == null) {
      _showError('Model not available. Please download first.');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Initializing Edge Veda...';
    });

    try {
      await _edgeVeda.init(EdgeVedaConfig(
        modelPath: _modelPath!,
        useGpu: true,
        numThreads: 4,
        contextLength: 2048,
        maxMemoryMb: 1536,
        verbose: true,
      ));

      setState(() {
        _isInitialized = true;
        _isLoading = false;
        _statusMessage = 'Ready to chat!';
      });

      _addSystemMessage('Edge Veda initialized successfully. Start chatting!');
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Initialization failed';
      });
      _showError('Failed to initialize: ${e.toString()}');
    }
  }

  Future<void> _sendMessage() async {
    if (!_isInitialized) {
      _showError('Please initialize Edge Veda first');
      return;
    }

    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    _promptController.clear();
    _addUserMessage(prompt);

    setState(() {
      _isLoading = true;
      _tokenCount = 0;
      _timeToFirstTokenMs = null;
      _tokensPerSecond = null;
    });

    _stopwatch.reset();
    _stopwatch.start();

    try {
      // Non-streaming generation with metrics tracking
      final response = await _edgeVeda.generate(
        prompt,
        options: const GenerateOptions(
          maxTokens: 256,
          temperature: 0.7,
          topP: 0.9,
        ),
      );

      // Calculate TTFT (time to first token - for non-streaming, use latency)
      _timeToFirstTokenMs = _stopwatch.elapsedMilliseconds;

      // Estimate token count from response length
      // Simple heuristic: ~4 chars per token for English text
      _tokenCount = (response.text.length / 4).round();

      // Calculate tokens per second
      _tokensPerSecond = _tokenCount / (_stopwatch.elapsedMilliseconds / 1000);

      _stopwatch.stop();

      // Get memory stats
      final memStats = await _edgeVeda.getMemoryStats();
      _memoryMb = memStats.currentBytes / (1024 * 1024);

      // Check for memory warning (approaching 1.2GB limit)
      if (_memoryMb != null && _memoryMb! > 1000) {
        _statusMessage = 'Memory high: ${_memoryMb!.toStringAsFixed(0)}MB / 1200MB';
      }

      _addAssistantMessage(response.text);

      setState(() {
        _isLoading = false;
      });

      print('Memory usage: ${_memoryMb?.toStringAsFixed(1)} MB');
      print('Tokens/sec: ${_tokensPerSecond?.toStringAsFixed(1)}');
    } catch (e) {
      _stopwatch.stop();
      setState(() {
        _isLoading = false;
      });
      _showError('Generation failed: ${e.toString()}');
    }
  }

  void _addUserMessage(String text) {
    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: true,
        timestamp: DateTime.now(),
      ));
    });
    _scrollToBottom();
  }

  void _addAssistantMessage(String text) {
    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: false,
        timestamp: DateTime.now(),
      ));
    });
    _scrollToBottom();
  }

  void _addSystemMessage(String text) {
    setState(() {
      _messages.add(ChatMessage(
        text: text,
        isUser: false,
        isSystem: true,
        timestamp: DateTime.now(),
      ));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Widget _buildMetricsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMetricChip(
            label: 'TTFT',
            value: _timeToFirstTokenMs != null
                ? '${_timeToFirstTokenMs}ms'
                : '-',
            icon: Icons.timer,
          ),
          _buildMetricChip(
            label: 'Speed',
            value: _tokensPerSecond != null
                ? '${_tokensPerSecond!.toStringAsFixed(1)} tok/s'
                : '-',
            icon: Icons.speed,
          ),
          _buildMetricChip(
            label: 'Memory',
            value: _memoryMb != null
                ? '${_memoryMb!.toStringAsFixed(0)} MB'
                : '-',
            icon: Icons.memory,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricChip({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Colors.blue[700]),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.blue[900],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edge Veda Chat'),
        actions: [
          if (_isInitialized)
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () async {
                final memStats = await _edgeVeda.getMemoryStats();
                final memoryMb = memStats.currentBytes / (1024 * 1024);
                final usagePercent = (memStats.usagePercent * 100).toStringAsFixed(1);

                if (!mounted) return;

                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Performance Info'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Memory: ${memoryMb.toStringAsFixed(1)} MB'),
                        Text('Usage: $usagePercent%'),
                        if (memStats.isHighPressure)
                          const Text(
                            'High memory pressure',
                            style: TextStyle(color: Colors.orange),
                          ),
                        const SizedBox(height: 8),
                        if (_tokensPerSecond != null)
                          Text('Last Speed: ${_tokensPerSecond!.toStringAsFixed(1)} tok/s'),
                        if (_timeToFirstTokenMs != null)
                          Text('Last TTFT: ${_timeToFirstTokenMs}ms'),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Status bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: _isInitialized ? Colors.green[50] : Colors.orange[50],
            child: Row(
              children: [
                if (_isDownloading || _isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                if (_isDownloading || _isLoading) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: TextStyle(
                      color: _isInitialized ? Colors.green[900] : Colors.orange[900],
                      fontSize: 12,
                    ),
                  ),
                ),
                if (!_isInitialized && !_isLoading && !_isDownloading && _modelPath != null)
                  ElevatedButton(
                    onPressed: _initializeEdgeVeda,
                    child: const Text('Initialize'),
                  ),
              ],
            ),
          ),

          // Download progress
          if (_isDownloading)
            LinearProgressIndicator(value: _downloadProgress),

          // Metrics bar (only visible after initialization)
          if (_isInitialized) _buildMetricsBar(),

          // Messages list
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No messages yet',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      return MessageBubble(message: _messages[index]);
                    },
                  ),
          ),

          // Input area
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(8),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _promptController,
                      decoration: const InputDecoration(
                        hintText: 'Type a message...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      enabled: _isInitialized && !_isLoading,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.send),
                    onPressed: _isInitialized && !_isLoading ? _sendMessage : null,
                    color: Theme.of(context).primaryColor,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isSystem;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.isSystem = false,
    required this.timestamp,
  });
}

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message.text,
              style: TextStyle(
                color: Colors.grey[700],
                fontSize: 12,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            CircleAvatar(
              backgroundColor: Colors.blue[100],
              child: const Icon(Icons.smart_toy, color: Colors.blue),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: message.isUser ? Colors.blue : Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                message.text,
                style: TextStyle(
                  color: message.isUser ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ),
          if (message.isUser) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: Colors.green[100],
              child: const Icon(Icons.person, color: Colors.green),
            ),
          ],
        ],
      ),
    );
  }
}
