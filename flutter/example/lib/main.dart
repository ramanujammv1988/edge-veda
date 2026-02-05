import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final EdgeVeda _edgeVeda = EdgeVeda();
  final ModelManager _modelManager = ModelManager();
  final TextEditingController _promptController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // Android memory pressure EventChannel
  static const _memoryPressureChannel = EventChannel(
    'com.edgeveda.edge_veda/memory_pressure',
  );
  StreamSubscription<dynamic>? _memorySubscription;
  String? _memoryPressureLevel;

  bool _isInitialized = false;
  bool _isLoading = false;
  bool _isGenerating = false; // Track active generation for lifecycle cancellation
  bool _isDownloading = false;
  bool _runningBenchmark = false;

  // Streaming state
  bool _isStreaming = false;
  CancelToken? _cancelToken;
  int _streamingTokenCount = 0;
  double _downloadProgress = 0.0;
  String? _modelPath;
  String _statusMessage = 'Ready to initialize';

  // Benchmark test prompts - varying complexity for realistic testing
  final List<String> _benchmarkPrompts = [
    'What is the capital of France?',
    'Explain quantum computing in simple terms.',
    'Write a haiku about nature.',
    'What are the benefits of exercise?',
    'Describe the solar system.',
    'What is machine learning?',
    'Tell me about the ocean.',
    'Explain photosynthesis.',
    'What is artificial intelligence?',
    'Describe the water cycle.',
  ];

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
    // Register lifecycle observer for iOS background handling (Pitfall 5 - Critical)
    WidgetsBinding.instance.addObserver(this);
    _setupMemoryPressureListener();
    _checkAndDownloadModel();
  }

  /// Set up Android memory pressure listener via EventChannel
  /// This receives onTrimMemory events from EdgeVedaPlugin.kt
  void _setupMemoryPressureListener() {
    if (Platform.isAndroid) {
      _memorySubscription = _memoryPressureChannel
          .receiveBroadcastStream()
          .listen((event) {
        if (event is Map) {
          final level = event['pressureLevel'] as String?;
          debugPrint('EdgeVeda: Memory pressure event: $level');

          setState(() {
            _memoryPressureLevel = level;
          });

          // Show warning for critical memory pressure
          if (level == 'critical' || level == 'running_critical') {
            setState(() {
              _statusMessage = 'Memory pressure: $level - consider restarting';
            });

            // Show snackbar warning
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Memory pressure: $level'),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
          }
        }
      }, onError: (error) {
        debugPrint('EdgeVeda: Memory pressure stream error: $error');
      });
    }
  }

  @override
  void dispose() {
    // CRITICAL: Remove observer FIRST to prevent callbacks after disposal
    WidgetsBinding.instance.removeObserver(this);
    _memorySubscription?.cancel();
    _edgeVeda.dispose();
    _modelManager.dispose();
    _promptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Handle app lifecycle changes - MANDATORY for App Store approval
  ///
  /// iOS kills apps that run CPU-intensive tasks in the background.
  /// This implements Pitfall 5 (Critical) from research: background handling.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // App is being backgrounded - cancel any active generation
      if (_isGenerating) {
        _isGenerating = false;
        setState(() {
          _isLoading = false;
        });
        // Show user-friendly message about cancellation
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Generation cancelled - app backgrounded'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
        print('EdgeVeda: Generation cancelled due to app backgrounding');
      }
    } else if (state == AppLifecycleState.resumed) {
      // App is foregrounded again - no action needed, user can start new generation
      print('EdgeVeda: App resumed');
    }
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
      _isGenerating = true; // Track for lifecycle cancellation
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

      // Check if generation was cancelled while backgrounded
      if (!_isGenerating) {
        print('EdgeVeda: Generation completed but was cancelled by backgrounding');
        return;
      }

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
    } finally {
      _isGenerating = false; // Always clear generation flag
    }
  }

  /// Streaming generation with progressive token display
  ///
  /// Uses generateStream() to receive tokens one-by-one and display them
  /// progressively. Supports cancellation via the Stop button.
  Future<void> _generateStreaming() async {
    if (!_isInitialized) {
      _showError('Please initialize Edge Veda first');
      return;
    }

    if (_isStreaming) {
      return; // Already streaming
    }

    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      _showError('Please enter a prompt');
      return;
    }

    _promptController.clear();
    _addUserMessage(prompt);

    setState(() {
      _isStreaming = true;
      _isLoading = true;
      _cancelToken = CancelToken();
      _streamingTokenCount = 0;
      _timeToFirstTokenMs = null;
      _tokensPerSecond = null;
      _statusMessage = 'Starting stream...';
    });

    final buffer = StringBuffer();
    final stopwatch = Stopwatch()..start();
    bool receivedFirstToken = false;

    try {
      await for (final chunk in _edgeVeda.generateStream(
        prompt,
        options: const GenerateOptions(
          maxTokens: 256,
          temperature: 0.7,
          topP: 0.9,
        ),
        cancelToken: _cancelToken,
      )) {
        // Check if cancelled
        if (_cancelToken?.isCancelled == true) {
          setState(() {
            _statusMessage = 'Cancelled (${_streamingTokenCount} tokens)';
          });
          break;
        }

        if (chunk.isFinal) {
          // Stream completed naturally
          stopwatch.stop();
          _tokensPerSecond = _streamingTokenCount / (stopwatch.elapsedMilliseconds / 1000);

          setState(() {
            _statusMessage = 'Complete (${_streamingTokenCount} tokens, ${_tokensPerSecond?.toStringAsFixed(1)} tok/s)';
          });
          break;
        }

        // Record TTFT on first token
        if (!receivedFirstToken) {
          _timeToFirstTokenMs = stopwatch.elapsedMilliseconds;
          receivedFirstToken = true;
        }

        buffer.write(chunk.token);
        _streamingTokenCount++;

        // Update UI every few tokens to avoid excessive rebuilds
        if (_streamingTokenCount % 3 == 0 || chunk.token.contains('\n')) {
          setState(() {
            _statusMessage = 'Streaming... (${_streamingTokenCount} tokens)';
          });
          // Update the last assistant message in-place
          _updateStreamingMessage(buffer.toString());
        }
      }

      // Final update with complete text
      if (buffer.isNotEmpty) {
        _updateStreamingMessage(buffer.toString());
      }

      // Get memory stats after streaming
      final memStats = await _edgeVeda.getMemoryStats();
      _memoryMb = memStats.currentBytes / (1024 * 1024);
      _tokenCount = _streamingTokenCount;

      print('EdgeVeda: Streaming complete - ${_streamingTokenCount} tokens');
      print('EdgeVeda: TTFT: ${_timeToFirstTokenMs}ms, ${_tokensPerSecond?.toStringAsFixed(1)} tok/s');
    } catch (e) {
      stopwatch.stop();
      setState(() {
        _statusMessage = 'Stream error';
      });
      _showError('Streaming failed: ${e.toString()}');
      print('EdgeVeda: Streaming error: $e');
    } finally {
      setState(() {
        _isStreaming = false;
        _isLoading = false;
        _cancelToken = null;
      });
    }
  }

  /// Update or add the streaming response message
  void _updateStreamingMessage(String text) {
    setState(() {
      // Find the last assistant message (non-system, non-user)
      final lastIndex = _messages.lastIndexWhere(
        (m) => !m.isUser && !m.isSystem,
      );

      if (lastIndex >= 0 && _isStreaming) {
        // Update existing message
        _messages[lastIndex] = ChatMessage(
          text: text,
          isUser: false,
          timestamp: _messages[lastIndex].timestamp,
        );
      } else {
        // Add new message
        _messages.add(ChatMessage(
          text: text,
          isUser: false,
          timestamp: DateTime.now(),
        ));
      }
    });
    _scrollToBottom();
  }

  /// Cancel the current streaming generation
  void _cancelGeneration() {
    if (_isStreaming && _cancelToken != null) {
      _cancelToken!.cancel();
      print('EdgeVeda: Cancellation requested');
    }
  }

  /// Run benchmark: 10 consecutive generations with metrics logging
  Future<void> _runBenchmark() async {
    if (!_isInitialized) {
      _showError('Initialize SDK first');
      return;
    }

    setState(() {
      _runningBenchmark = true;
      _statusMessage = 'Running benchmark (10 tests)...';
    });

    final List<double> tokenRates = [];
    final List<int> ttfts = [];
    final List<double> memoryMbs = [];
    final List<int> latencies = [];

    try {
      for (int i = 0; i < 10; i++) {
        setState(() {
          _statusMessage = 'Benchmark ${i + 1}/10...';
        });

        final prompt = _benchmarkPrompts[i % _benchmarkPrompts.length];

        _stopwatch.reset();
        _stopwatch.start();

        final response = await _edgeVeda.generate(
          prompt,
          options: const GenerateOptions(
            maxTokens: 100, // Consistent token limit for fair comparison
            temperature: 0.7,
            topP: 0.9,
          ),
        );

        _stopwatch.stop();

        // Calculate metrics
        final latencyMs = _stopwatch.elapsedMilliseconds;
        final tokenCount = (response.text.length / 4).round(); // Estimate ~4 chars/token
        final tokensPerSec = tokenCount / (latencyMs / 1000);

        // TTFT approximation (can't measure precisely without streaming)
        final ttftMs = (latencyMs * 0.2).round(); // Assume 20% is prompt processing

        // Get memory
        final memStats = await _edgeVeda.getMemoryStats();
        final memoryMb = memStats.currentBytes / (1024 * 1024);

        tokenRates.add(tokensPerSec);
        ttfts.add(ttftMs);
        memoryMbs.add(memoryMb);
        latencies.add(latencyMs);

        // Brief pause between tests to prevent thermal throttling
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Calculate summary statistics
      final avgTokensPerSec = tokenRates.reduce((a, b) => a + b) / tokenRates.length;
      final avgTTFT = ttfts.reduce((a, b) => a + b) ~/ ttfts.length;
      final peakMemory = memoryMbs.reduce((a, b) => a > b ? a : b);
      final minTokensPerSec = tokenRates.reduce((a, b) => a < b ? a : b);
      final maxTokensPerSec = tokenRates.reduce((a, b) => a > b ? a : b);
      final avgLatency = latencies.reduce((a, b) => a + b) ~/ latencies.length;

      // Print results to console (visible in Xcode logs)
      print('');
      print('=== BENCHMARK RESULTS ===');
      print('Device: iPhone (iOS)');
      print('Model: Llama 3.2 1B Q4_K_M');
      print('Tests: 10 runs');
      print('');
      print('Speed: ${avgTokensPerSec.toStringAsFixed(1)} tok/s (avg)');
      print('  Min: ${minTokensPerSec.toStringAsFixed(1)} tok/s');
      print('  Max: ${maxTokensPerSec.toStringAsFixed(1)} tok/s');
      print('TTFT: ${avgTTFT}ms (avg)');
      print('Latency: ${avgLatency}ms (avg)');
      print('Peak Memory: ${peakMemory.toStringAsFixed(0)} MB');
      print('=========================');
      print('');

      setState(() {
        _runningBenchmark = false;
        _statusMessage = 'Benchmark complete - check console';
      });

      _showBenchmarkDialog(
        avgTokensPerSec: avgTokensPerSec,
        avgTTFT: avgTTFT,
        peakMemory: peakMemory,
        minTPS: minTokensPerSec,
        maxTPS: maxTokensPerSec,
        avgLatency: avgLatency,
      );
    } catch (e) {
      setState(() {
        _runningBenchmark = false;
        _statusMessage = 'Benchmark failed';
      });
      _showError('Benchmark error: $e');
    }
  }

  void _showBenchmarkDialog({
    required double avgTokensPerSec,
    required int avgTTFT,
    required double peakMemory,
    required double minTPS,
    required double maxTPS,
    required int avgLatency,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Benchmark Results'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Avg Speed: ${avgTokensPerSec.toStringAsFixed(1)} tok/s'),
            Text('  Range: ${minTPS.toStringAsFixed(1)} - ${maxTPS.toStringAsFixed(1)}'),
            Text('Avg TTFT: ${avgTTFT}ms'),
            Text('Avg Latency: ${avgLatency}ms'),
            Text('Peak Memory: ${peakMemory.toStringAsFixed(0)} MB'),
            const SizedBox(height: 12),
            Text(
              avgTokensPerSec >= 15
                  ? '✓ Meets >15 tok/s target'
                  : '⚠ Below 15 tok/s target',
              style: TextStyle(
                color: avgTokensPerSec >= 15 ? Colors.green : Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              peakMemory <= 1200
                  ? '✓ Under 1.2GB memory limit'
                  : '⚠ Exceeds 1.2GB memory limit',
              style: TextStyle(
                color: peakMemory <= 1200 ? Colors.green : Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
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
          if (_isInitialized && !_runningBenchmark)
            IconButton(
              icon: const Icon(Icons.assessment),
              tooltip: 'Run Benchmark',
              onPressed: _runBenchmark,
            ),
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
                        // Platform info
                        Text('Platform: ${Platform.isAndroid ? "Android" : Platform.isIOS ? "iOS" : "Other"}'),
                        Text('Backend: ${Platform.isAndroid ? "CPU" : "Metal GPU"}'),
                        const Divider(),
                        Text('Memory: ${memoryMb.toStringAsFixed(1)} MB'),
                        Text('Usage: $usagePercent%'),
                        if (memStats.isHighPressure)
                          const Text(
                            'High memory pressure',
                            style: TextStyle(color: Colors.orange),
                          ),
                        if (_memoryPressureLevel != null)
                          Text(
                            'System pressure: $_memoryPressureLevel',
                            style: const TextStyle(color: Colors.orange),
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
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(8),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
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
                          onSubmitted: (_) => _generateStreaming(),
                          enabled: _isInitialized && !_isLoading && !_isStreaming,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Non-streaming generate button
                      ElevatedButton.icon(
                        icon: const Icon(Icons.send, size: 18),
                        label: const Text('Generate'),
                        onPressed: _isInitialized && !_isLoading && !_isStreaming
                            ? _sendMessage
                            : null,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                      // Streaming generate button
                      ElevatedButton.icon(
                        icon: const Icon(Icons.stream, size: 18),
                        label: const Text('Generate (Stream)'),
                        onPressed: _isInitialized && !_isLoading && !_isStreaming
                            ? _generateStreaming
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                      // Stop button (only enabled during streaming)
                      ElevatedButton.icon(
                        icon: const Icon(Icons.stop, size: 18),
                        label: const Text('Stop'),
                        onPressed: _isStreaming ? _cancelGeneration : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
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
