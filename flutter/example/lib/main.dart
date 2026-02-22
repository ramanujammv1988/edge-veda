import 'dart:async';
import 'dart:convert';
import 'dart:io' show File, Platform;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:edge_veda/edge_veda.dart';

import 'app_theme.dart';
import 'image_screen.dart';
import 'model_selection_modal.dart';
import 'performance_trackers.dart';
import 'settings_screen.dart';
import 'vision_screen.dart';
import 'voice_screen.dart';
import 'welcome_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EdgeVedaExampleApp());
}

class EdgeVedaExampleApp extends StatelessWidget {
  const EdgeVedaExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Veda',
      theme: AppTheme.themeData,
      home: const HomeScreen(),
    );
  }
}

/// Home screen with tab navigation between Chat and Vision
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  bool _showWelcome = true;

  @override
  Widget build(BuildContext context) {
    if (_showWelcome) {
      return WelcomeScreen(
        onGetStarted: () => setState(() => _showWelcome = false),
      );
    }

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: [
          const ChatScreen(),
          VisionScreen(isActive: _currentIndex == 1),
          const VoiceScreen(),
          const ImageScreen(),
          const SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        backgroundColor: AppTheme.background,
        indicatorColor: AppTheme.accent.withValues(alpha: 0.15),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chat',
          ),
          NavigationDestination(
            icon: Icon(Icons.camera_alt_outlined),
            selectedIcon: Icon(Icons.camera_alt),
            label: 'Vision',
          ),
          NavigationDestination(
            icon: Icon(Icons.record_voice_over_outlined),
            selectedIcon: Icon(Icons.record_voice_over),
            label: 'Voice',
          ),
          NavigationDestination(
            icon: Icon(Icons.image_outlined),
            selectedIcon: Icon(Icons.image),
            label: 'Image',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
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

  // Memory pressure EventChannel (Android + iOS)
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
  bool _toolsEnabled = false;
  bool _isSwitchingModel = false;
  String? _qwenModelPath; // Cached path for Qwen3 model

  // Streaming state
  bool _isStreaming = false;
  CancelToken? _cancelToken;
  int _streamingTokenCount = 0;
  String _streamingText = ''; // Accumulates tokens during streaming
  double _downloadProgress = 0.0;
  String? _modelPath;
  String _statusMessage = 'Ready to initialize';

  // RAG document state
  RagPipeline? _ragPipeline;
  VectorIndex? _vectorIndex;
  EdgeVeda? _ragEmbedder; // Separate EdgeVeda for embedding model
  String? _attachedDocName; // Display name of attached document
  int _attachedChunkCount = 0;
  bool _isIndexingDocument = false;
  int _indexingProgress = 0; // Current chunk being embedded
  int _indexingTotal = 0; // Total chunks to embed
  String? _embeddingModelPath; // Cached path to embedding model
  final List<ChatMessage> _ragMessages = [];

  // ChatSession state
  ChatSession? _session;
  SystemPromptPreset _selectedPreset = SystemPromptPreset.assistant;
  bool _showSummarizationIndicator = false;

  // Demo tool definitions for function calling
  List<ToolDefinition> get _demoTools => [
    ToolDefinition(
      name: 'get_time',
      description:
          'Get the current date and time for a location. Pass the city or region name exactly as the user said it.',
      parameters: {
        'type': 'object',
        'properties': {
          'location': {
            'type': 'string',
            'description':
                'City or region name (e.g., "San Francisco", "London", "Tokyo", "Bali", "New York")',
          },
        },
        'required': ['location'],
      },
    ),
    ToolDefinition(
      name: 'calculate',
      description: 'Perform a math calculation',
      parameters: {
        'type': 'object',
        'properties': {
          'expression': {
            'type': 'string',
            'description':
                'Math expression to evaluate (e.g., "2+2", "sqrt(16)")',
          },
        },
        'required': ['expression'],
      },
    ),
  ];

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
  int? _timeToFirstTokenMs;
  double? _tokensPerSecond;
  double? _memoryMb;
  double? _lastConfidence;
  bool _lastNeedsCloudHandoff = false;
  final _stopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    // Register lifecycle observer for iOS background handling (Pitfall 5 - Critical)
    WidgetsBinding.instance.addObserver(this);
    _setupMemoryPressureListener();
    _checkAndDownloadModel();
  }

  /// Set up memory pressure listener via EventChannel (Android + iOS)
  /// Android: receives onTrimMemory events from EdgeVedaPlugin.kt
  /// iOS: receives UIApplicationDidReceiveMemoryWarningNotification from EdgeVedaPlugin.m
  void _setupMemoryPressureListener() {
    if (Platform.isAndroid || Platform.isIOS) {
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
                  backgroundColor: AppTheme.warning,
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
    _ragEmbedder?.dispose();
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
  /// On Android, inference can continue in the background safely, so we
  /// only cancel on iOS to avoid the OS terminating the app.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Only cancel on iOS — Android handles background CPU work fine,
      // and cancelling causes race conditions with _isStreaming state.
      if (Platform.isIOS && (_isGenerating || _isStreaming)) {
        _cancelToken?.cancel();
        _isGenerating = false;
        setState(() {
          _isLoading = false;
          _isStreaming = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Generation cancelled - app backgrounded'),
              backgroundColor: AppTheme.warning,
              duration: Duration(seconds: 2),
            ),
          );
        }
        debugPrint('EdgeVeda: Generation cancelled due to app backgrounding');
      }
    } else if (state == AppLifecycleState.resumed) {
      debugPrint('EdgeVeda: App resumed');
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
          final speedStr = progress.speedBytesPerSecond != null
              ? ' @ ${_formatBytes(progress.speedBytesPerSecond!.round())}/s'
              : '';
          final etaStr = progress.estimatedSecondsRemaining != null
              ? ' ~${progress.estimatedSecondsRemaining}s left'
              : '';
          setState(() {
            _downloadProgress = progress.progress;
            _statusMessage =
                'Downloading: ${progress.progressPercent}% (${_formatBytes(progress.downloadedBytes)}/${_formatBytes(progress.totalBytes)})$speedStr$etaStr';
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
      _statusMessage = 'Initializing Veda...';
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

      // Create ChatSession after successful initialization
      // Always use Llama 3.2 Instruct at init time. Tools toggle handles Qwen3 model switch.
      _session = ChatSession(
        edgeVeda: _edgeVeda,
        preset: _selectedPreset,
        templateFormat: ChatTemplateFormat.llama3Instruct,
      );

      setState(() {
        _isInitialized = true;
        _isLoading = false;
        _statusMessage = 'Ready to chat!';
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = 'Initialization failed';
      });
      _showError('Failed to initialize: ${e.toString()}');
    }
  }

  /// Split text into chunks for embedding, respecting paragraph boundaries.
  /// ~500 chars per chunk with 50-char overlap for context continuity.
  static List<String> _chunkText(String text,
      {int maxChars = 500, int overlap = 50}) {
    final chunks = <String>[];
    // Normalize whitespace
    text = text.replaceAll('\r\n', '\n').trim();
    if (text.isEmpty) return chunks;

    int start = 0;
    while (start < text.length) {
      int end = start + maxChars;
      if (end >= text.length) {
        final chunk = text.substring(start).trim();
        if (chunk.isNotEmpty) chunks.add(chunk);
        break;
      }
      // Try to break at paragraph boundary
      int breakPoint = text.lastIndexOf('\n\n', end);
      if (breakPoint <= start) {
        // Try sentence boundary
        breakPoint = text.lastIndexOf('. ', end);
        if (breakPoint > start) breakPoint += 2;
      }
      if (breakPoint <= start) {
        breakPoint = end;
      }
      final chunk = text.substring(start, breakPoint).trim();
      if (chunk.isNotEmpty) chunks.add(chunk);
      // Always advance forward — overlap only if we advanced enough
      final nextStart = breakPoint - overlap;
      start = nextStart > start ? nextStart : breakPoint;
    }
    return chunks;
  }

  /// Pick a text file, chunk it, embed each chunk, build RAG pipeline.
  Future<void> _pickAndIndexDocument() async {
    final pipelineSw = Stopwatch()..start();

    // Step 1: Pick file
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
    );
    if (result == null || result.files.single.path == null) return;

    final filePath = result.files.single.path!;
    final fileName = result.files.single.name;
    final fileSize = result.files.single.size;

    setState(() {
      _isIndexingDocument = true;
      _indexingProgress = 0;
      _indexingTotal = 0;
      _statusMessage = 'Reading document...';
    });

    try {
      // Step 2: Read file as text (try UTF-8, fall back to Latin-1)
      final readSw = Stopwatch()..start();
      String text;
      String encoding = 'UTF-8';
      try {
        text = await File(filePath).readAsString();
      } catch (_) {
        try {
          final bytes = await File(filePath).readAsBytes();
          text = latin1.decode(bytes);
          encoding = 'Latin-1';
        } catch (e) {
          _showError('Cannot read file — only text-based files are supported');
          setState(() => _isIndexingDocument = false);
          return;
        }
      }
      readSw.stop();
      if (text.trim().isEmpty) {
        _showError('Document is empty');
        setState(() => _isIndexingDocument = false);
        return;
      }

      // Step 3: Chunk text
      final chunkSw = Stopwatch()..start();
      final chunks = _chunkText(text);
      chunkSw.stop();
      if (chunks.isEmpty) {
        _showError('Could not extract text chunks from document');
        setState(() => _isIndexingDocument = false);
        return;
      }
      final avgChunkSize = text.length ~/ chunks.length;

      setState(() {
        _indexingTotal = chunks.length;
        _statusMessage = 'Downloading embedding model...';
      });

      // Step 4: Ensure embedding model is downloaded
      final downloadSw = Stopwatch()..start();
      bool wasDownloaded = true;
      if (_embeddingModelPath == null) {
        final embModel = ModelRegistry.allMiniLmL6V2;
        final isDownloaded = await _modelManager.isModelDownloaded(embModel.id);
        wasDownloaded = isDownloaded;
        if (!isDownloaded) {
          _embeddingModelPath = await _modelManager.downloadModel(embModel);
        } else {
          _embeddingModelPath = await _modelManager.getModelPath(embModel.id);
        }
      }
      downloadSw.stop();

      setState(() => _statusMessage = 'Initializing embedding model...');

      // Step 5: Create embedder instance
      final initSw = Stopwatch()..start();
      _ragEmbedder?.dispose();
      _ragEmbedder = EdgeVeda();
      await _ragEmbedder!.init(EdgeVedaConfig(
        modelPath: _embeddingModelPath!,
        useGpu: true,
        numThreads: 4,
        contextLength: 512,
        maxMemoryMb: 256,
        verbose: false,
      ));
      initSw.stop();

      // Step 6: Batch-embed all chunks (single model load)
      setState(() =>
          _statusMessage = 'Embedding ${chunks.length} chunks...');

      final embedSw = Stopwatch()..start();
      final embeddings = await _ragEmbedder!.embedBatch(chunks);
      embedSw.stop();

      // Step 7: Build vector index
      final indexSw = Stopwatch()..start();
      _vectorIndex = VectorIndex(dimensions: 384);
      for (int i = 0; i < chunks.length; i++) {
        _vectorIndex!.add(
          'chunk_$i',
          embeddings[i].embedding,
          metadata: {'text': chunks[i]},
        );
      }
      indexSw.stop();

      setState(() {
        _indexingProgress = chunks.length;
        _indexingTotal = chunks.length;
      });

      // Step 8: Create RAG pipeline
      _ragPipeline = RagPipeline.withModels(
        embedder: _ragEmbedder!,
        generator: _edgeVeda,
        index: _vectorIndex!,
      );

      pipelineSw.stop();

      // ── INDEXING METRICS ──────────────────────────────────────────
      final perChunkMs = embedSw.elapsedMilliseconds / chunks.length;
      final embedChunksPerSec = chunks.length / (embedSw.elapsedMilliseconds / 1000);
      final embedKbPerSec = (text.length / 1024) / (embedSw.elapsedMilliseconds / 1000);
      final totalTokens = embeddings.fold<int>(0, (sum, e) => sum + e.tokenCount);
      final processingMs = readSw.elapsedMilliseconds +
          chunkSw.elapsedMilliseconds +
          initSw.elapsedMilliseconds +
          embedSw.elapsedMilliseconds +
          indexSw.elapsedMilliseconds;
      debugPrint('');
      debugPrint('╔══════════════════════════════════════════════════════════════╗');
      debugPrint('║              RAG INDEXING METRICS                           ║');
      debugPrint('╠══════════════════════════════════════════════════════════════╣');
      debugPrint('║ Document                                                    ║');
      debugPrint('║   File:            $fileName');
      debugPrint('║   Size:            ${(fileSize / 1024).toStringAsFixed(1)} KB ($encoding)');
      debugPrint('║   Chunks:          ${chunks.length} (avg ${avgChunkSize} chars/chunk)');
      debugPrint('║   Tokens:          $totalTokens');
      debugPrint('║                                                             ║');
      debugPrint('║ Throughput (size-independent)                               ║');
      debugPrint('║   Embed Speed:     ${perChunkMs.toStringAsFixed(1).padLeft(6)} ms/chunk');
      debugPrint('║   Embed Rate:      ${embedChunksPerSec.toStringAsFixed(0).padLeft(6)} chunks/sec');
      debugPrint('║   Embed Rate:      ${embedKbPerSec.toStringAsFixed(1).padLeft(6)} KB/sec');
      debugPrint('║   Vector Insert:   ${(indexSw.elapsedMilliseconds / chunks.length).toStringAsFixed(2).padLeft(6)} ms/vector');
      debugPrint('║                                                             ║');
      debugPrint('║ Latency Breakdown                                           ║');
      debugPrint('║   File Read:       ${readSw.elapsedMilliseconds.toString().padLeft(6)} ms');
      debugPrint('║   Chunking:        ${chunkSw.elapsedMilliseconds.toString().padLeft(6)} ms');
      if (!wasDownloaded) {
        debugPrint('║   Model Download:  ${downloadSw.elapsedMilliseconds.toString().padLeft(6)} ms  ← one-time cost');
      }
      debugPrint('║   Embedder Init:   ${initSw.elapsedMilliseconds.toString().padLeft(6)} ms');
      debugPrint('║   Batch Embed:     ${embedSw.elapsedMilliseconds.toString().padLeft(6)} ms');
      debugPrint('║   Index Build:     ${indexSw.elapsedMilliseconds.toString().padLeft(6)} ms');
      debugPrint('║   ──────────────────────────────');
      debugPrint('║   Processing:      ${processingMs.toString().padLeft(6)} ms  (excl. download)');
      debugPrint('║   Wall Clock:      ${pipelineSw.elapsedMilliseconds.toString().padLeft(6)} ms');
      debugPrint('║                                                             ║');
      debugPrint('║ Embedding Model: all-MiniLM-L6-v2 (F16, 384d, 46MB)        ║');
      debugPrint('║ Hardware: Apple A18 Pro GPU (Metal), on-device              ║');
      debugPrint('╚══════════════════════════════════════════════════════════════╝');
      debugPrint('');

      setState(() {
        _attachedDocName = fileName;
        _attachedChunkCount = chunks.length;
        _isIndexingDocument = false;
        _statusMessage = 'Document loaded! Ask questions about it.';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$fileName indexed (${chunks.length} chunks)'),
            backgroundColor: AppTheme.success,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      _ragEmbedder?.dispose();
      _ragEmbedder = null;
      setState(() {
        _isIndexingDocument = false;
        _statusMessage = 'Document loading failed';
      });
      _showError('Failed to load document: ${e.toString()}');
      debugPrint('EdgeVeda: Document indexing error: $e');
    }
  }

  /// Remove the attached document and return to normal chat mode.
  void _removeDocument() {
    _ragEmbedder?.dispose(); // Free embedding model memory
    _ragEmbedder = null;
    setState(() {
      _ragPipeline = null;
      _vectorIndex = null;
      _attachedDocName = null;
      _attachedChunkCount = 0;
      _statusMessage = 'Ready to chat!';
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Document removed'),
          backgroundColor: AppTheme.accentDim,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Send a query via RAG pipeline (streaming) using the attached document context.
  Future<void> _sendWithRag(String prompt) async {
    final querySw = Stopwatch()..start();

    setState(() {
      _isStreaming = true;
      _isLoading = true;
      _isGenerating = true;
      _cancelToken = CancelToken();
      _streamingTokenCount = 0;
      _streamingText = '';
      _timeToFirstTokenMs = null;
      _tokensPerSecond = null;
      _statusMessage = 'Searching document...';
    });

    // Add user message for display
    _ragMessages.add(ChatMessage(
      role: ChatRole.user,
      content: prompt,
      timestamp: DateTime.now(),
    ));

    final buffer = StringBuffer();
    final genSw = Stopwatch();
    bool receivedFirstToken = false;

    try {
      // Retrieve relevant chunks and stream response
      setState(() => _statusMessage = 'Retrieving relevant context...');

      final stream = _ragPipeline!.queryStream(
        prompt,
        options: const GenerateOptions(
          maxTokens: 512,
          temperature: 0.7,
          topP: 0.9,
        ),
        cancelToken: _cancelToken,
      );

      setState(() => _statusMessage = 'Generating answer from document...');

      await for (final chunk in stream) {
        if (_cancelToken?.isCancelled == true) {
          setState(() =>
              _statusMessage = 'Cancelled ($_streamingTokenCount tokens)');
          break;
        }

        if (chunk.isFinal) {
          genSw.stop();
          querySw.stop();
          _tokensPerSecond = _streamingTokenCount > 0
              ? _streamingTokenCount / (genSw.elapsedMilliseconds / 1000)
              : 0;
          setState(() {
            _statusMessage =
                'Complete ($_streamingTokenCount tokens, ${_tokensPerSecond?.toStringAsFixed(1)} tok/s)';
          });
          break;
        }

        if (chunk.token.isEmpty) continue;

        if (!receivedFirstToken) {
          _timeToFirstTokenMs = querySw.elapsedMilliseconds;
          genSw.start(); // Start generation timer from first token
          receivedFirstToken = true;
        }

        buffer.write(chunk.token);
        _streamingTokenCount++;

        if (_streamingTokenCount == 1 ||
            _streamingTokenCount % 3 == 0 ||
            chunk.token.contains('\n')) {
          setState(() {
            _statusMessage =
                'Streaming from document... ($_streamingTokenCount tokens)';
            _streamingText = buffer.toString();
          });
          _scrollToBottom();
        }
      }

      // Finalize
      final responseText = buffer.toString();
      setState(() => _streamingText = '');

      // Add assistant response to RAG messages
      if (responseText.isNotEmpty) {
        _ragMessages.add(ChatMessage(
          role: ChatRole.assistant,
          content: responseText,
          timestamp: DateTime.now(),
        ));
      }

      // NOTE: Deliberately skip getMemoryStats() here. It creates a full
      // model context in a new isolate (~600MB spike) just to read stats,
      // which doubles memory temporarily and triggers iOS jetsam crashes.

      // ── QUERY METRICS ───────────────────────────────────────────
      if (!querySw.isRunning) {
        final genMs = genSw.elapsedMilliseconds;
        final totalMs = querySw.elapsedMilliseconds;
        final ttft = (_timeToFirstTokenMs ?? totalMs);
        final tokSec = _tokensPerSecond ?? 0;
        final msPerTok = _streamingTokenCount > 0
            ? genMs / _streamingTokenCount
            : 0.0;
        final responseChars = buffer.length;
        debugPrint('');
        debugPrint('╔══════════════════════════════════════════════════════════════╗');
        debugPrint('║              RAG QUERY METRICS                              ║');
        debugPrint('╠══════════════════════════════════════════════════════════════╣');
        debugPrint('║ Query: "${prompt.length > 50 ? '${prompt.substring(0, 50)}...' : prompt}"');
        debugPrint('║                                                             ║');
        debugPrint('║ Throughput (size-independent)                               ║');
        debugPrint('║   Generation:     ${tokSec.toStringAsFixed(1).padLeft(6)} tok/s  (${msPerTok.toStringAsFixed(1)} ms/tok)');
        debugPrint('║   TTFT (warm):    ${ttft.toString().padLeft(6)} ms');
        debugPrint('║   Vector Search:       <1 ms');
        debugPrint('║                                                             ║');
        debugPrint('║ This Query                                                  ║');
        debugPrint('║   Retrieval:      ${ttft.toString().padLeft(6)} ms  (embed + search + build)');
        debugPrint('║   Generation:     ${genMs.toString().padLeft(6)} ms  ($_streamingTokenCount tokens, $responseChars chars)');
        debugPrint('║   ──────────────────────────────');
        debugPrint('║   End-to-End:     ${totalMs.toString().padLeft(6)} ms');
        debugPrint('║                                                             ║');
        debugPrint('║ Models: all-MiniLM-L6-v2 (embed) + Llama 3.2 1B (gen)      ║');
        debugPrint('║ Hardware: Apple A18 Pro GPU (Metal)                         ║');
        debugPrint('╚══════════════════════════════════════════════════════════════╝');
        debugPrint('');
      }
    } catch (e) {
      querySw.stop();
      setState(() {
        _statusMessage = 'RAG query error';
        _streamingText = '';
      });
      _showError('RAG query failed: ${e.toString()}');
      debugPrint('EdgeVeda: RAG query error: $e');
    } finally {
      _isGenerating = false;
      setState(() {
        _isStreaming = false;
        _isLoading = false;
        _cancelToken = null;
      });
    }
  }

  /// Send a message via ChatSession (streaming or tool-calling)
  Future<void> _sendMessage() async {
    if (!_isInitialized || _session == null) {
      _showError('Please initialize Veda first');
      return;
    }

    if (_isStreaming) return; // Already streaming

    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      _showError('Please enter a prompt');
      return;
    }

    _promptController.clear();

    // Route to RAG if document is attached
    if (_attachedDocName != null && _ragPipeline != null) {
      await _sendWithRag(prompt);
      return;
    }

    if (_toolsEnabled) {
      await _sendWithToolCalling(prompt);
    } else {
      await _sendStreaming(prompt);
    }
  }

  /// Send with tool calling (non-streaming, uses sendWithTools)
  Future<void> _sendWithToolCalling(String prompt) async {
    setState(() {
      _isStreaming = true;
      _isLoading = true;
      _isGenerating = true;
      _statusMessage = 'Sending with tools...';
    });

    final stopwatch = Stopwatch()..start();

    try {
      final reply = await _session!.sendWithTools(
        prompt,
        onToolCall: _handleToolCall,
        options: const GenerateOptions(
          maxTokens: 256,
          temperature: 0.7,
          topP: 0.9,
        ),
      );

      stopwatch.stop();
      final latencyMs = stopwatch.elapsedMilliseconds;

      // Get memory stats (may timeout if worker is busy)
      try {
        final memStats = await _edgeVeda.getMemoryStats();
        _memoryMb = memStats.currentBytes / (1024 * 1024);
      } catch (_) {
        // Worker may still be busy; skip memory update
      }

      setState(() {
        _statusMessage = 'Complete (${latencyMs}ms)';
      });
      _scrollToBottom();

      debugPrint('EdgeVeda: Tool calling complete - ${latencyMs}ms, reply: ${reply.content.length} chars');
    } catch (e) {
      stopwatch.stop();
      setState(() {
        _statusMessage = 'Tool calling error';
      });
      _showError('Tool calling failed: ${e.toString()}');
      debugPrint('EdgeVeda: Tool calling error: $e');
    } finally {
      _isGenerating = false;
      setState(() {
        _isStreaming = false;
        _isLoading = false;
      });
    }
  }

  /// Send with streaming (existing behavior)
  Future<void> _sendStreaming(String prompt) async {
    // Check if summarization might trigger
    final usageBefore = _session!.contextUsage;
    if (usageBefore > 0.7) {
      setState(() {
        _showSummarizationIndicator = true;
      });
    }

    setState(() {
      _isStreaming = true;
      _isLoading = true;
      _isGenerating = true;
      _cancelToken = CancelToken();
      _streamingTokenCount = 0;
      _streamingText = '';
      _timeToFirstTokenMs = null;
      _tokensPerSecond = null;
      _lastConfidence = null;
      _lastNeedsCloudHandoff = false;
      _statusMessage = 'Initializing streaming worker (first call loads model)...';
    });

    final buffer = StringBuffer();
    final stopwatch = Stopwatch()..start();
    bool receivedFirstToken = false;

    try {
      setState(() => _statusMessage = 'Creating stream...');

      final stream = _session!.sendStream(
        prompt,
        options: const GenerateOptions(
          maxTokens: 256,
          temperature: 0.7,
          topP: 0.9,
        ),
        cancelToken: _cancelToken,
      );

      setState(() => _statusMessage = 'Loading model in worker isolate (30-60s first time)...');

      // Check if summarization happened
      if (_session!.isSummarizing) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Summarizing older messages...'),
              backgroundColor: AppTheme.accentDim,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }

      await for (final chunk in stream) {
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
          _tokensPerSecond = _streamingTokenCount > 0
              ? _streamingTokenCount / (stopwatch.elapsedMilliseconds / 1000)
              : 0;

          setState(() {
            _statusMessage = 'Complete (${_streamingTokenCount} tokens, ${_tokensPerSecond?.toStringAsFixed(1)} tok/s)';
          });
          // Don't break here - let the stream close naturally so
          // ChatSession.sendStream() can add the assistant message to history.
          // Falls through to 'if (chunk.token.isEmpty) continue;' below.
        }

        // Skip empty tokens
        if (chunk.token.isEmpty) continue;

        // Record TTFT on first actual content token
        if (!receivedFirstToken) {
          _timeToFirstTokenMs = stopwatch.elapsedMilliseconds;
          receivedFirstToken = true;
        }

        buffer.write(chunk.token);
        _streamingTokenCount++;

        // Track confidence and cloud handoff from token chunks
        if (chunk.confidence != null) {
          _lastConfidence = chunk.confidence;
        }
        if (chunk.needsCloudHandoff) {
          _lastNeedsCloudHandoff = true;
        }

        // Update UI on first token, then every 3 tokens or on newlines
        if (_streamingTokenCount == 1 || _streamingTokenCount % 3 == 0 || chunk.token.contains('\n')) {
          setState(() {
            _statusMessage = 'Streaming... (${_streamingTokenCount} tokens)';
            _streamingText = buffer.toString();
          });
          _scrollToBottom();
        }
      }

      // Final update
      setState(() {
        _streamingText = '';
      });

      // Show summarization completion if it was triggered
      if (_showSummarizationIndicator) {
        setState(() {
          _showSummarizationIndicator = false;
        });
        if (mounted && usageBefore > 0.7) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Context summarized -- conversation continues'),
              backgroundColor: AppTheme.success,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }

      // Record latency for PerformanceTrackers
      if (stopwatch.elapsedMilliseconds > 0) {
        PerformanceTrackers.latency.add(stopwatch.elapsedMilliseconds.toDouble());
      }

      // Get memory stats after streaming (may timeout if worker is still busy)
      try {
        final memStats = await _edgeVeda.getMemoryStats();
        _memoryMb = memStats.currentBytes / (1024 * 1024);
      } catch (_) {
        // Worker may still be busy; skip memory update
      }
      debugPrint('EdgeVeda: Streaming complete - ${_streamingTokenCount} tokens');
      debugPrint('EdgeVeda: TTFT: ${_timeToFirstTokenMs}ms, ${_tokensPerSecond?.toStringAsFixed(1)} tok/s');
    } catch (e) {
      stopwatch.stop();
      setState(() {
        _statusMessage = 'Stream error';
        _streamingText = '';
      });
      _showError('Streaming failed: ${e.toString()}');
      debugPrint('EdgeVeda: Streaming error: $e');
    } finally {
      _isGenerating = false;
      setState(() {
        _isStreaming = false;
        _isLoading = false;
        _cancelToken = null;
        _showSummarizationIndicator = false;
      });
    }
  }

  /// Cancel the current streaming generation
  void _cancelGeneration() {
    if (_isStreaming && _cancelToken != null) {
      _cancelToken!.cancel();
      debugPrint('EdgeVeda: Cancellation requested');
    }
  }

  /// Start a new chat session, clearing history
  void _resetChat() {
    if (_session == null) return;
    _session!.reset();
    // Clear any attached document silently
    _ragEmbedder?.dispose();
    _ragEmbedder = null;
    _ragPipeline = null;
    _vectorIndex = null;
    _attachedDocName = null;
    _attachedChunkCount = 0;
    _ragMessages.clear();
    setState(() {
      _streamingText = '';
      _timeToFirstTokenMs = null;
      _tokensPerSecond = null;
      _memoryMb = null;
      _statusMessage = 'Ready to chat!';
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('New chat started'),
          backgroundColor: AppTheme.accentDim,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  /// Change the persona preset and create a new session
  void _changePreset(SystemPromptPreset preset) {
    if (preset == _selectedPreset && _session != null) return;
    setState(() {
      _selectedPreset = preset;
    });
    if (_isInitialized) {
      _session = ChatSession(
        edgeVeda: _edgeVeda,
        preset: preset,
        templateFormat: _toolsEnabled
            ? ChatTemplateFormat.qwen3
            : ChatTemplateFormat.llama3Instruct,
        tools: _toolsEnabled ? ToolRegistry(_demoTools) : null,
      );
      setState(() {
        _streamingText = '';
        _statusMessage = 'Ready to chat!';
      });
    }
  }

  /// Toggle tool calling mode on/off, switching between Qwen3 and Llama 3.2 models.
  ///
  /// EdgeVeda.init() throws if already initialized, so we must dispose() before
  /// re-initializing with a different model. Only one model can be loaded at a time.
  Future<void> _toggleTools() async {
    if (!_isInitialized || _isSwitchingModel) return;

    final enablingTools = !_toolsEnabled;

    setState(() {
      _isSwitchingModel = true;
      _isLoading = true;
      _statusMessage = enablingTools
          ? 'Checking Qwen3 model...'
          : 'Switching to Llama 3.2...';
    });

    try {
      if (enablingTools) {
        // --- Enabling tools: switch to Qwen3 ---

        // Check if Qwen3 is downloaded
        if (_qwenModelPath == null) {
          final isDownloaded = await _modelManager
              .isModelDownloaded(ModelRegistry.qwen3_06b.id);

          if (!isDownloaded) {
            setState(() {
              _statusMessage = 'Downloading Qwen3 model (~397 MB)...';
            });

            // Listen to download progress
            final sub = _modelManager.downloadProgress.listen((progress) {
              if (mounted) {
                setState(() {
                  _downloadProgress = progress.progress;
                  _statusMessage =
                      'Downloading Qwen3: ${progress.progressPercent}% (${_formatBytes(progress.downloadedBytes)}/${_formatBytes(progress.totalBytes)})';
                });
              }
            });

            try {
              await _modelManager.downloadModel(ModelRegistry.qwen3_06b);
            } finally {
              await sub.cancel();
            }
          }

          _qwenModelPath =
              await _modelManager.getModelPath(ModelRegistry.qwen3_06b.id);
        }

        setState(() {
          _statusMessage = 'Loading Qwen3 model...';
        });

        // Dispose current Llama model and re-init with Qwen3
        await _edgeVeda.dispose();
        await _edgeVeda.init(EdgeVedaConfig(
          modelPath: _qwenModelPath!,
          useGpu: true,
          numThreads: 4,
          contextLength: 2048,
          maxMemoryMb: 1536,
          verbose: true,
        ));

        // Create new ChatSession with Qwen3 template and tools
        _session = ChatSession(
          edgeVeda: _edgeVeda,
          preset: _selectedPreset,
          templateFormat: ChatTemplateFormat.qwen3,
          tools: ToolRegistry(_demoTools),
        );

        setState(() {
          _toolsEnabled = true;
          _isInitialized = true;
          _isSwitchingModel = false;
          _isLoading = false;
          _streamingText = '';
          _statusMessage = 'Tools enabled (Qwen3 -- get_time, calculate)';
        });
      } else {
        // --- Disabling tools: switch back to Llama 3.2 ---

        // Dispose current Qwen3 model and re-init with Llama
        await _edgeVeda.dispose();
        await _edgeVeda.init(EdgeVedaConfig(
          modelPath: _modelPath!,
          useGpu: true,
          numThreads: 4,
          contextLength: 2048,
          maxMemoryMb: 1536,
          verbose: true,
        ));

        // Create new ChatSession with Llama template, no tools
        _session = ChatSession(
          edgeVeda: _edgeVeda,
          preset: _selectedPreset,
          templateFormat: ChatTemplateFormat.llama3Instruct,
        );

        setState(() {
          _toolsEnabled = false;
          _isInitialized = true;
          _isSwitchingModel = false;
          _isLoading = false;
          _streamingText = '';
          _statusMessage = 'Ready to chat!';
        });
      }
    } catch (e) {
      // Try to restore previous model state
      setState(() {
        _isSwitchingModel = false;
        _isLoading = false;
        _statusMessage = 'Model switch failed: ${e.toString()}';
      });
      _showError('Failed to switch model: ${e.toString()}');
      debugPrint('EdgeVeda: Model switch error: $e');

      // Attempt to restore the model that was loaded before the switch
      try {
        final restorePath = enablingTools ? _modelPath : _qwenModelPath;
        if (restorePath != null) {
          await _edgeVeda.dispose();
          await _edgeVeda.init(EdgeVedaConfig(
            modelPath: restorePath,
            useGpu: true,
            numThreads: 4,
            contextLength: 2048,
            maxMemoryMb: 1536,
            verbose: true,
          ));
          _session = ChatSession(
            edgeVeda: _edgeVeda,
            preset: _selectedPreset,
            templateFormat: enablingTools
                ? ChatTemplateFormat.llama3Instruct
                : ChatTemplateFormat.qwen3,
            tools: enablingTools ? null : ToolRegistry(_demoTools),
          );
          setState(() {
            _isInitialized = true;
            _statusMessage = 'Restored previous model';
          });
        }
      } catch (restoreError) {
        debugPrint('EdgeVeda: Failed to restore model: $restoreError');
        setState(() {
          _isInitialized = false;
          _statusMessage = 'Model unloaded -- tap Initialize to restart';
        });
      }
    }
  }

  /// Handle a tool call from the model during sendWithTools
  Future<ToolResult> _handleToolCall(ToolCall call) async {
    switch (call.name) {
      case 'get_time':
        final location =
            (call.arguments['location'] as String? ?? 'UTC').toLowerCase();
        // Map location keywords to UTC offset hours
        const locationOffsets = <String, double>{
          // Americas
          'new york': -5, 'nyc': -5, 'boston': -5, 'miami': -5,
          'washington': -5, 'atlanta': -5, 'est': -5,
          'chicago': -6, 'houston': -6, 'dallas': -6, 'cst': -6,
          'denver': -7, 'phoenix': -7, 'mst': -7,
          'san francisco': -8, 'los angeles': -8, 'la': -8,
          'seattle': -8, 'portland': -8, 'pst': -8,
          'anchorage': -9, 'hawaii': -10, 'honolulu': -10,
          'sao paulo': -3, 'rio': -3, 'buenos aires': -3,
          'mexico city': -6, 'bogota': -5, 'lima': -5,
          // Europe
          'london': 0, 'uk': 0, 'dublin': 0, 'lisbon': 0, 'gmt': 0,
          'paris': 1, 'berlin': 1, 'rome': 1, 'madrid': 1,
          'amsterdam': 1, 'brussels': 1, 'vienna': 1, 'cet': 1,
          'athens': 2, 'istanbul': 3, 'moscow': 3,
          'helsinki': 2, 'warsaw': 1, 'prague': 1,
          // Asia
          'dubai': 4, 'abu dhabi': 4,
          'mumbai': 5.5, 'delhi': 5.5, 'india': 5.5, 'bangalore': 5.5,
          'colombo': 5.5, 'kathmandu': 5.75,
          'dhaka': 6, 'bangkok': 7, 'jakarta': 7,
          'singapore': 8, 'kuala lumpur': 8, 'hong kong': 8,
          'beijing': 8, 'shanghai': 8, 'taipei': 8,
          'bali': 8, 'denpasar': 8,
          'tokyo': 9, 'osaka': 9, 'seoul': 9,
          // Oceania
          'sydney': 11, 'melbourne': 11, 'brisbane': 10,
          'perth': 8, 'auckland': 13, 'wellington': 13,
          // Africa
          'cairo': 2, 'johannesburg': 2, 'nairobi': 3, 'lagos': 1,
          // Default
          'utc': 0,
        };
        // Find matching location by substring
        double offset = 0;
        String matched = 'UTC';
        for (final entry in locationOffsets.entries) {
          if (location.contains(entry.key)) {
            offset = entry.value;
            matched = entry.key;
            break;
          }
        }
        final utcNow = DateTime.now().toUtc();
        final local =
            utcNow.add(Duration(minutes: (offset * 60).round()));
        final hours = local.hour;
        final minutes = local.minute;
        final ampm = hours >= 12 ? 'PM' : 'AM';
        final h12 = hours == 0 ? 12 : (hours > 12 ? hours - 12 : hours);
        final sign = offset >= 0 ? '+' : '';
        return ToolResult.success(
          toolCallId: call.id,
          data: {
            'local_time':
                '${h12.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')} $ampm',
            'date':
                '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}',
            'location': matched,
            'utc_offset': '${sign}${offset}',
          },
        );
      case 'calculate':
        final expr = call.arguments['expression'] as String? ?? '';
        return ToolResult.success(
          toolCallId: call.id,
          data: {
            'result': 'Calculation not implemented -- demo only',
            'expression': expr,
          },
        );
      default:
        return ToolResult.failure(
          toolCallId: call.id,
          error: 'Unknown tool: ${call.name}',
        );
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
      debugPrint('');
      debugPrint('=== BENCHMARK RESULTS ===');
      debugPrint('Device: iPhone (iOS)');
      debugPrint('Model: Llama 3.2 1B Q4_K_M');
      debugPrint('Tests: 10 runs');
      debugPrint('');
      debugPrint('Speed: ${avgTokensPerSec.toStringAsFixed(1)} tok/s (avg)');
      debugPrint('  Min: ${minTokensPerSec.toStringAsFixed(1)} tok/s');
      debugPrint('  Max: ${maxTokensPerSec.toStringAsFixed(1)} tok/s');
      debugPrint('TTFT: ${avgTTFT}ms (avg)');
      debugPrint('Latency: ${avgLatency}ms (avg)');
      debugPrint('Peak Memory: ${peakMemory.toStringAsFixed(0)} MB');
      debugPrint('=========================');
      debugPrint('');

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
        backgroundColor: AppTheme.surface,
        title: const Text(
          'Benchmark Results',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Avg Speed: ${avgTokensPerSec.toStringAsFixed(1)} tok/s',
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
            Text(
              '  Range: ${minTPS.toStringAsFixed(1)} - ${maxTPS.toStringAsFixed(1)}',
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
            Text(
              'Avg TTFT: ${avgTTFT}ms',
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
            Text(
              'Avg Latency: ${avgLatency}ms',
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
            Text(
              'Peak Memory: ${peakMemory.toStringAsFixed(0)} MB',
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 12),
            Text(
              avgTokensPerSec >= 15
                  ? 'Meets >15 tok/s target'
                  : 'Below 15 tok/s target',
              style: TextStyle(
                color: avgTokensPerSec >= 15 ? AppTheme.success : AppTheme.warning,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              peakMemory <= 1200
                  ? 'Under 1.2GB memory limit'
                  : 'Exceeds 1.2GB memory limit',
              style: TextStyle(
                color: peakMemory <= 1200 ? AppTheme.success : AppTheme.warning,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'OK',
              style: TextStyle(color: AppTheme.accent),
            ),
          ),
        ],
      ),
    );
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
        backgroundColor: AppTheme.danger,
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

  /// Build the context indicator bar showing turn count and context usage
  Widget _buildContextIndicator() {
    if (_session == null) return const SizedBox.shrink();

    final turnCount = _session!.turnCount;
    final usage = _session!.contextUsage;
    final usagePercent = (usage * 100).toInt().clamp(0, 100);
    final isHighUsage = usage > 0.8;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.memory,
            size: 14,
            color: isHighUsage ? AppTheme.warning : AppTheme.accent,
          ),
          const SizedBox(width: 4),
          Text(
            '$turnCount ${turnCount == 1 ? 'turn' : 'turns'}',
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_showSummarizationIndicator) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: AppTheme.accent,
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              'Summarizing...',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.accent,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          if (_toolsEnabled) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.build_outlined, size: 10, color: AppTheme.accent),
                  SizedBox(width: 3),
                  Text(
                    'Tools',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_attachedDocName != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.search, size: 10, color: AppTheme.accent),
                  SizedBox(width: 3),
                  Text(
                    'RAG',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),
          Text(
            '$usagePercent%',
            style: TextStyle(
              fontSize: 11,
              color: isHighUsage ? AppTheme.warning : AppTheme.textTertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 60,
            height: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: usage.clamp(0.0, 1.0),
                color: isHighUsage ? AppTheme.warning : AppTheme.accent,
                backgroundColor: AppTheme.surfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 1),
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
          if (_lastConfidence != null)
            _buildMetricChip(
              label: 'Confidence',
              value: '${(_lastConfidence! * 100).toStringAsFixed(0)}%',
              icon: Icons.psychology,
            ),
          if (_lastNeedsCloudHandoff)
            const _CloudHandoffBadge(),
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
            Icon(icon, size: 14, color: AppTheme.accent),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.textTertiary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  /// Build persona picker chips for fresh sessions (no messages yet)
  Widget _buildPersonaPicker() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Choose a persona',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textTertiary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: SystemPromptPreset.values.map((preset) {
              final isSelected = preset == _selectedPreset;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(_presetLabel(preset)),
                  selected: isSelected,
                  onSelected: (_) => _changePreset(preset),
                  selectedColor: AppTheme.accent.withValues(alpha: 0.2),
                  backgroundColor: AppTheme.surfaceVariant,
                  labelStyle: TextStyle(
                    color: isSelected ? AppTheme.accent : AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  side: BorderSide(
                    color: isSelected ? AppTheme.accent : AppTheme.border,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _presetLabel(SystemPromptPreset preset) {
    switch (preset) {
      case SystemPromptPreset.assistant:
        return 'Assistant';
      case SystemPromptPreset.coder:
        return 'Coder';
      case SystemPromptPreset.creative:
        return 'Creative';
    }
  }

  /// Get the combined list of messages for display:
  /// session messages + streaming text (if currently streaming)
  List<ChatMessage> get _displayMessages {
    // RAG mode: use _ragMessages
    if (_attachedDocName != null) {
      if (_isStreaming && _streamingText.isNotEmpty) {
        return [
          ..._ragMessages,
          ChatMessage(
            role: ChatRole.assistant,
            content: _streamingText,
            timestamp: DateTime.now(),
          ),
        ];
      }
      return _ragMessages;
    }
    // Normal mode: use session messages
    final sessionMessages = _session?.messages ?? [];
    if (_isStreaming && _streamingText.isNotEmpty) {
      return [
        ...sessionMessages,
        ChatMessage(
          role: ChatRole.assistant,
          content: _streamingText,
          timestamp: DateTime.now(),
        ),
      ];
    }
    return sessionMessages;
  }

  /// Whether the session has any messages (for showing persona picker vs context indicator)
  bool get _hasMessages {
    if (_attachedDocName != null) {
      return _ragMessages.isNotEmpty || _isStreaming;
    }
    final msgs = _session?.messages ?? [];
    return msgs.isNotEmpty || _isStreaming;
  }

  /// Build document indicator chip showing filename, chunk count, and remove button.
  Widget _buildDocumentChip() {
    if (_attachedDocName == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 1),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.description, size: 16, color: AppTheme.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$_attachedDocName  \u00B7  $_attachedChunkCount chunks',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          InkWell(
            onTap: _removeDocument,
            borderRadius: BorderRadius.circular(12),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 16, color: AppTheme.textTertiary),
            ),
          ),
        ],
      ),
    );
  }

  /// Build indexing progress overlay shown during document embedding.
  Widget _buildIndexingOverlay() {
    if (!_isIndexingDocument) return const SizedBox.shrink();

    final progress =
        _indexingTotal > 0 ? _indexingProgress / _indexingTotal : 0.0;

    return Container(
      color: Colors.black.withValues(alpha: 0.7),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(40),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.description, size: 48, color: AppTheme.accent),
              const SizedBox(height: 16),
              const Text(
                'Indexing Document',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _statusMessage,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              if (_indexingTotal > 0) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    color: AppTheme.accent,
                    backgroundColor: AppTheme.surfaceVariant,
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '$_indexingProgress / $_indexingTotal chunks',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textTertiary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ] else
                const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppTheme.accent,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = _displayMessages;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Veda',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        backgroundColor: AppTheme.background,
        actions: [
          // New Chat button
          if (_isInitialized)
            IconButton(
              icon: const Icon(Icons.add_comment_outlined, color: AppTheme.textSecondary),
              tooltip: 'New Chat',
              onPressed: (!_isStreaming && !_isLoading) ? _resetChat : null,
            ),
          // Tools toggle
          if (_isInitialized)
            IconButton(
              icon: Icon(
                Icons.build_outlined,
                color: _toolsEnabled ? AppTheme.accent : AppTheme.textSecondary,
              ),
              tooltip: _toolsEnabled ? 'Disable Tools' : 'Enable Tools',
              onPressed: (!_isStreaming && !_isLoading && !_isSwitchingModel)
                  ? _toggleTools
                  : null,
            ),
          IconButton(
            icon: const Icon(Icons.layers_outlined, color: AppTheme.textSecondary),
            tooltip: 'Models',
            onPressed: () => ModelSelectionModal.show(context, _modelManager),
          ),
          if (_isInitialized && !_runningBenchmark)
            IconButton(
              icon: const Icon(Icons.assessment, color: AppTheme.textSecondary),
              tooltip: 'Run Benchmark',
              onPressed: _runBenchmark,
            ),
          if (_isInitialized)
            IconButton(
              icon: const Icon(Icons.info_outline, color: AppTheme.textSecondary),
              onPressed: () async {
                MemoryStats? memStats;
                double memoryMb = 0;
                String usagePercent = '0.0';
                try {
                  memStats = await _edgeVeda.getMemoryStats();
                  memoryMb = memStats.currentBytes / (1024 * 1024);
                  usagePercent = (memStats.usagePercent * 100).toStringAsFixed(1);
                } catch (_) {
                  // Worker busy during inference; show what we have
                }

                if (!mounted) return;

                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    backgroundColor: AppTheme.surface,
                    title: const Text(
                      'Performance Info',
                      style: TextStyle(color: AppTheme.textPrimary),
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Platform info
                        Text(
                          'Platform: ${Platform.isAndroid ? "Android" : Platform.isIOS ? "iOS" : "Other"}',
                          style: const TextStyle(color: AppTheme.textPrimary),
                        ),
                        Text(
                          'Backend: ${Platform.isAndroid ? "CPU" : "Metal GPU"}',
                          style: const TextStyle(color: AppTheme.textPrimary),
                        ),
                        const Divider(color: AppTheme.border),
                        Text(
                          'Memory: ${memoryMb.toStringAsFixed(1)} MB',
                          style: const TextStyle(color: AppTheme.textPrimary),
                        ),
                        Text(
                          'Usage: $usagePercent%',
                          style: const TextStyle(color: AppTheme.textPrimary),
                        ),
                        if (memStats != null && memStats.isHighPressure)
                          const Text(
                            'High memory pressure',
                            style: TextStyle(color: AppTheme.warning),
                          ),
                        if (_memoryPressureLevel != null)
                          Text(
                            'System pressure: $_memoryPressureLevel',
                            style: const TextStyle(color: AppTheme.warning),
                          ),
                        const SizedBox(height: 8),
                        if (_tokensPerSecond != null)
                          Text(
                            'Last Speed: ${_tokensPerSecond!.toStringAsFixed(1)} tok/s',
                            style: const TextStyle(color: AppTheme.textPrimary),
                          ),
                        if (_timeToFirstTokenMs != null)
                          Text(
                            'Last TTFT: ${_timeToFirstTokenMs}ms',
                            style: const TextStyle(color: AppTheme.textPrimary),
                          ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'OK',
                          style: TextStyle(color: AppTheme.accent),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              // Status bar
              Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: AppTheme.surface,
              border: Border(
                bottom: BorderSide(color: AppTheme.border, width: 1),
              ),
            ),
            child: Row(
              children: [
                if (_isDownloading || _isLoading)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accent,
                    ),
                  ),
                if (_isDownloading || _isLoading) const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: TextStyle(
                      color: _isInitialized ? AppTheme.success : AppTheme.warning,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (!_isInitialized && !_isLoading && !_isDownloading && _modelPath != null)
                  ElevatedButton(
                    onPressed: _initializeEdgeVeda,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: AppTheme.background,
                    ),
                    child: const Text('Initialize'),
                  ),
              ],
            ),
          ),

          // Download progress
          if (_isDownloading)
            LinearProgressIndicator(
              value: _downloadProgress,
              color: AppTheme.accent,
              backgroundColor: AppTheme.surfaceVariant,
            ),

          // Metrics bar (only visible after initialization)
          if (_isInitialized) _buildMetricsBar(),

          // Persona picker (shown on fresh session with no messages)
          if (_isInitialized && !_hasMessages)
            _buildPersonaPicker(),

          // Context indicator (shown when conversation has messages)
          if (_isInitialized && _hasMessages)
            _buildContextIndicator(),

          // Document indicator chip (shown when document is attached)
          if (_isInitialized) _buildDocumentChip(),

          // Messages list
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _attachedDocName != null
                              ? Icons.description_outlined
                              : Icons.chat_bubble_outline,
                          size: 64,
                          color: AppTheme.border,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _attachedDocName != null
                              ? 'Ask a question about your document'
                              : 'Start a conversation',
                          style: const TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _attachedDocName != null
                              ? 'Answers are generated from the attached file.'
                              : 'Ask anything. It runs on your device.',
                          style: const TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      return MessageBubble(message: messages[index]);
                    },
                  ),
          ),

          // Input area
          Container(
            decoration: BoxDecoration(
              color: AppTheme.background,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SafeArea(
              child: Row(
                children: [
                  // Attach document button
                  if (_isInitialized &&
                      !_isStreaming &&
                      !_isIndexingDocument)
                    IconButton(
                      icon: Icon(
                        Icons.attach_file,
                        color: _attachedDocName != null
                            ? AppTheme.accent
                            : AppTheme.textSecondary,
                      ),
                      tooltip: 'Attach document',
                      onPressed: _pickAndIndexDocument,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 40, minHeight: 40),
                    ),
                  Expanded(
                    child: TextField(
                      controller: _promptController,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        hintText: _attachedDocName != null
                            ? 'Ask about the document...'
                            : 'Message...',
                        hintStyle: const TextStyle(color: AppTheme.textTertiary),
                        filled: true,
                        fillColor: AppTheme.surfaceVariant,
                        border: OutlineInputBorder(
                          borderSide: const BorderSide(color: AppTheme.border),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: AppTheme.border),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: AppTheme.accent),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      enabled: _isInitialized && !_isLoading && !_isStreaming,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Single send/stop button
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Material(
                      color: _isStreaming ? AppTheme.danger : AppTheme.accent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _isStreaming
                            ? _cancelGeneration
                            : (_isInitialized && !_isLoading
                                ? _sendMessage
                                : null),
                        child: Icon(
                          _isStreaming ? Icons.stop : Icons.arrow_upward,
                          color: _isStreaming ? AppTheme.textPrimary : AppTheme.background,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
            ],
          ),
          // Indexing overlay
          _buildIndexingOverlay(),
        ],
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    // System and summary messages rendered as centered chips
    if (message.role == ChatRole.system || message.role == ChatRole.summary) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.surfaceVariant,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message.role == ChatRole.summary
                  ? '[Context summary] ${message.content}'
                  : message.content,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
        ),
      );
    }

    // Tool call messages
    if (message.role == ChatRole.toolCall) {
      return _buildToolMessage(
        icon: Icons.build_outlined,
        iconColor: AppTheme.accent,
        label: 'Tool Call',
        content: message.content,
      );
    }

    // Tool result messages
    if (message.role == ChatRole.toolResult) {
      return _buildToolMessage(
        icon: Icons.check_circle_outline,
        iconColor: AppTheme.success,
        label: 'Tool Result',
        content: message.content,
      );
    }

    final isUser = message.role == ChatRole.user;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            const CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.surfaceVariant,
              child: Icon(Icons.auto_awesome, color: AppTheme.accent, size: 18),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isUser ? AppTheme.userBubble : AppTheme.assistantBubble,
                borderRadius: BorderRadius.circular(20),
                border: isUser
                    ? null
                    : Border.all(color: AppTheme.border, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message.content,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  height: 1.4,
                ),
              ),
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            const CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.surfaceVariant,
              child: Icon(Icons.person, color: AppTheme.accent, size: 18),
            ),
          ],
        ],
      ),
    );
  }

  /// Build a compact tool call or tool result message chip
  Widget _buildToolMessage({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String content,
  }) {
    // Try to format the JSON content for readability
    String displayContent;
    try {
      final parsed = jsonDecode(content);
      displayContent = const JsonEncoder.withIndent('  ').convert(parsed);
    } catch (_) {
      displayContent = content;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: iconColor.withValues(alpha: 0.15),
            child: Icon(icon, color: iconColor, size: 14),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: iconColor.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      color: iconColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    displayContent,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textSecondary,
                      fontFamily: 'monospace',
                      height: 1.3,
                    ),
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

/// Small badge shown in the metrics bar when the model recommends cloud handoff.
class _CloudHandoffBadge extends StatelessWidget {
  const _CloudHandoffBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_upload_outlined, size: 12, color: AppTheme.warning),
          SizedBox(width: 3),
          Text(
            'Cloud',
            style: TextStyle(
              fontSize: 10,
              color: AppTheme.warning,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
