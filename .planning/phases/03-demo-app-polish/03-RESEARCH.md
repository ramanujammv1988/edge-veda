# Phase 3: Demo App + Polish - Research

**Researched:** 2026-02-04
**Domain:** Flutter example app development, lifecycle handling, performance benchmarking, UI patterns
**Confidence:** HIGH

## Summary

Phase 3 creates a production-quality example Flutter app that demonstrates all capabilities of the Edge Veda SDK. The critical challenges are: (1) implementing proper iOS lifecycle handling to cancel generation on backgrounding (App Store requirement); (2) displaying real-time performance metrics (tok/sec, TTFT, memory) to validate the >15 tok/sec target; (3) ensuring memory stays under 1.2GB during sustained usage.

The existing codebase has a basic example app (`flutter/example/lib/main.dart`) with model download, initialization, and chat UI scaffolded. However, it references unimplemented APIs (`generateStream()`, `getMemoryUsageMb()`) from Phase 2. This phase must implement: WidgetsBindingObserver for lifecycle, real-time metrics display, graceful backgrounding, and comprehensive README documentation.

The research reveals that Flutter's recommended 2026 architecture uses MVVM with clear separation of concerns, WidgetsBindingObserver (or newer AppLifecycleListener) for lifecycle events, and StreamBuilder/FutureBuilder patterns for async UI updates. For cancellation, CancellableOperation or custom CancelToken patterns are standard.

**Primary recommendation:** Implement WidgetsBindingObserver.didChangeAppLifecycleState to detect AppLifecycleState.paused and immediately cancel ongoing generation. This is non-negotiable for App Store approval (Pitfall 5 - Critical).

## Standard Stack

The established libraries/tools for this domain:

### Core (Already in pubspec.yaml)
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| flutter | SDK | UI framework | Official Flutter framework |
| edge_veda | local | LLM inference SDK | Project's own SDK (Phase 2 output) |
| path_provider | ^2.1.0 | App directories | Official plugin for sandbox-safe paths |

### Supporting (for Example App)
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| N/A - Use built-in widgets | - | State management | StatefulWidget sufficient for example app |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| StatefulWidget | Riverpod 3.0 | Riverpod is 2026 best practice for complex state, but example app is simple enough for StatefulWidget |
| Manual cancellation | CancellableOperation package | `async` package provides CancellableOperation, but custom CancelToken already exists in EdgeVeda SDK |
| WidgetsBindingObserver | AppLifecycleListener (Flutter 3.13+) | AppLifecycleListener is newer API, but WidgetsBindingObserver is more widely documented and compatible |

**Installation:**
```bash
# No additional dependencies needed - all required packages already in pubspec.yaml
cd flutter/example
flutter pub get
```

## Architecture Patterns

### Recommended Project Structure (Example App)
```
flutter/example/
├── lib/
│   ├── main.dart              # App entry point, MaterialApp
│   └── screens/
│       ├── chat_screen.dart   # Main chat interface
│       └── settings_screen.dart # Model selection, config (optional)
├── pubspec.yaml              # Dependencies (references ../pubspec.yaml)
└── README.md                 # Setup instructions, usage, performance
```

For the example app, a simple single-file or two-file structure is acceptable. Full MVVM is overkill for a demo.

### Pattern 1: WidgetsBindingObserver for Lifecycle
**What:** Mix in WidgetsBindingObserver to detect app backgrounding
**When to use:** MANDATORY - Cancel generation when user leaves app
**Why:** iOS kills apps that run CPU-intensive tasks in background (Pitfall 5)

**Example:**
```dart
// Source: https://api.flutter.dev/flutter/widgets/WidgetsBindingObserver-class.html
class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  EdgeVeda? _edgeVeda;
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // Register observer
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // CRITICAL: Unregister
    _edgeVeda?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused) {
      // App going to background - CANCEL generation immediately
      if (_isGenerating) {
        _cancelGeneration();
        _showSnackBar('Generation cancelled - app backgrounded');
      }
    } else if (state == AppLifecycleState.resumed) {
      // App back to foreground - could resume if needed
    }
  }

  void _cancelGeneration() {
    // If using streaming, cancel stream subscription
    _streamSubscription?.cancel();
    setState(() => _isGenerating = false);
  }
}
```

**Critical notes:**
- Must call `removeObserver()` in dispose() or memory leak occurs
- `paused` state means app is in background or screen locked
- `resumed` state means app is visible again
- iOS does NOT allow background inference - this is App Store policy

### Pattern 2: Real-Time Metrics Display with Stopwatch
**What:** Measure and display tok/sec, TTFT, memory using Dart's Stopwatch
**When to use:** Performance benchmarking and validation
**Why:** User needs to verify >15 tok/sec target, memory <1.2GB

**Example:**
```dart
// Source: Flutter performance docs + Dart Stopwatch API
class PerformanceMetrics {
  int tokensGenerated = 0;
  int? timeToFirstTokenMs;
  int? totalLatencyMs;
  double? tokensPerSecond;
  int? memoryBytes;

  double get memoryMb => (memoryBytes ?? 0) / (1024 * 1024);
}

Future<void> _generateWithMetrics(String prompt) async {
  final metrics = PerformanceMetrics();
  final stopwatch = Stopwatch()..start();

  setState(() {
    _isGenerating = true;
    _currentMetrics = metrics;
  });

  try {
    // Get memory before generation
    final memStats = await _edgeVeda.getMemoryStats();
    metrics.memoryBytes = memStats.currentBytes;

    bool firstToken = true;

    await for (final chunk in _edgeVeda.generateStream(prompt)) {
      if (firstToken) {
        metrics.timeToFirstTokenMs = stopwatch.elapsedMilliseconds;
        firstToken = false;
      }

      if (!chunk.isFinal) {
        metrics.tokensGenerated++;

        // Update metrics in real-time
        setState(() {
          metrics.tokensPerSecond =
            metrics.tokensGenerated / (stopwatch.elapsedMilliseconds / 1000);
        });
      }
    }

    metrics.totalLatencyMs = stopwatch.elapsedMilliseconds;

    // Get memory after generation
    final memStatsAfter = await _edgeVeda.getMemoryStats();
    metrics.memoryBytes = memStatsAfter.currentBytes;

  } finally {
    stopwatch.stop();
    setState(() => _isGenerating = false);
  }
}

// Display in UI
Widget _buildMetricsBar() {
  return Container(
    padding: EdgeInsets.all(8),
    color: Colors.blue[50],
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _metricChip('TTFT', '${_metrics?.timeToFirstTokenMs ?? 0}ms'),
        _metricChip('Speed', '${_metrics?.tokensPerSecond?.toStringAsFixed(1) ?? '0'} tok/s'),
        _metricChip('Memory', '${_metrics?.memoryMb.toStringAsFixed(0) ?? '0'}MB'),
      ],
    ),
  );
}
```

### Pattern 3: StreamBuilder for Real-Time Updates
**What:** Use StreamBuilder to rebuild UI as tokens arrive
**When to use:** Displaying streaming generation in chat bubbles
**Why:** Standard Flutter pattern for async data display

**Example:**
```dart
// Source: https://docs.flutter.dev/ui/widgets/async
StreamBuilder<TokenChunk>(
  stream: _edgeVeda.generateStream(prompt),
  builder: (context, snapshot) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return CircularProgressIndicator();
    }

    if (snapshot.hasError) {
      return Text('Error: ${snapshot.error}');
    }

    if (snapshot.hasData) {
      final chunk = snapshot.data!;
      if (!chunk.isFinal) {
        // Append token to buffer and display
        _responseBuffer.write(chunk.token);
        return MessageBubble(text: _responseBuffer.toString());
      }
    }

    return SizedBox.shrink();
  },
)
```

**Alternative pattern:** Manual stream subscription with setState (more control)
```dart
StreamSubscription? _streamSubscription;

void _startGeneration(String prompt) {
  _streamSubscription = _edgeVeda.generateStream(prompt).listen(
    (chunk) {
      if (!chunk.isFinal) {
        setState(() {
          _responseBuffer.write(chunk.token);
        });
      }
    },
    onError: (error) {
      _showError('Generation failed: $error');
    },
    onDone: () {
      setState(() => _isGenerating = false);
    },
  );
}

void _cancelGeneration() {
  _streamSubscription?.cancel();
  _streamSubscription = null;
}
```

### Pattern 4: FutureBuilder for Model Download Progress
**What:** Display download progress with FutureBuilder + StreamBuilder combo
**When to use:** Initial model download on first launch
**Why:** User needs feedback during long download (500MB-2GB files)

**Example:**
```dart
// Source: Flutter async widgets docs
class ModelDownloadScreen extends StatelessWidget {
  final ModelManager modelManager;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DownloadProgress>(
      stream: modelManager.downloadProgress,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return CircularProgressIndicator();
        }

        final progress = snapshot.data!;
        return Column(
          children: [
            LinearProgressIndicator(value: progress.progress),
            Text('${progress.progressPercent}%'),
            Text('${_formatBytes(progress.downloadedBytes)} / ${_formatBytes(progress.totalBytes)}'),
            if (progress.speedBytesPerSecond != null)
              Text('${_formatSpeed(progress.speedBytesPerSecond!)}'),
            if (progress.estimatedSecondsRemaining != null)
              Text('ETA: ${_formatTime(progress.estimatedSecondsRemaining!)}'),
          ],
        );
      },
    );
  }
}
```

### Anti-Patterns to Avoid
- **Not implementing lifecycle observer:** App Store rejection, poor UX
- **Blocking UI thread during generation:** Covered in Phase 2, but verify with Isolate.run()
- **Not displaying metrics:** Cannot validate performance requirements
- **Using global state without dispose:** Memory leaks in example app
- **Forgetting to cancel stream subscriptions:** Memory leaks, unexpected behavior after navigation

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Lifecycle detection | Manual platform channels | WidgetsBindingObserver mixin | Built into Flutter, handles all platforms |
| Time measurement | DateTime.now() arithmetic | Stopwatch class | More accurate, designed for performance measurement |
| Progress indicators | Custom animation | CircularProgressIndicator, LinearProgressIndicator | Material Design standard, accessible |
| Byte formatting | String interpolation | Helper function with KB/MB/GB logic | Consistent display, handles edge cases |
| App state persistence | SharedPreferences for everything | WidgetsBinding for lifecycle only | Simpler for demo app, no persistence needed |

**Key insight:** Flutter provides excellent built-in widgets for async operations (FutureBuilder, StreamBuilder) and lifecycle (WidgetsBindingObserver). Don't rebuild these - they handle edge cases and accessibility.

## Common Pitfalls

### Pitfall 1: Forgetting to Unregister WidgetsBindingObserver
**What goes wrong:** Developer adds `addObserver()` but forgets `removeObserver()` in dispose(). Observer stays alive, causes memory leak and unexpected callbacks on destroyed widget.
**Why it happens:** Easy to forget the cleanup step; no compiler warning
**How to avoid:**
1. Always pair `addObserver()` in initState() with `removeObserver()` in dispose()
2. Add code review checklist item
3. Test by hot restarting app multiple times - leaks compound
**Warning signs:**
- "setState() called after dispose()" errors
- Memory usage grows after navigating away and back
- Duplicate log messages from lifecycle callbacks

**Code pattern:**
```dart
class _MyWidgetState extends State<MyWidget> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // ADD
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // REMOVE - CRITICAL
    super.dispose();
  }
}
```

### Pitfall 2: Not Cancelling Stream Subscription
**What goes wrong:** Start generation, navigate away, stream continues in background. Tokens write to disposed widget, setState crashes, memory leak.
**Why it happens:** Streams don't auto-cancel on widget disposal
**How to avoid:**
1. Store StreamSubscription in state
2. Cancel in dispose() AND in lifecycle paused state
3. Use `mounted` check before setState
**Warning signs:**
- "setState() called after dispose()" errors during navigation
- Generation continues after leaving screen
- Random crashes when backgrounding during generation

**Code pattern:**
```dart
StreamSubscription<TokenChunk>? _subscription;

void _startGeneration() {
  _subscription = _edgeVeda.generateStream(prompt).listen((chunk) {
    if (mounted) { // Check mounted before setState
      setState(() { /* update UI */ });
    }
  });
}

@override
void dispose() {
  _subscription?.cancel(); // CRITICAL
  _subscription = null;
  super.dispose();
}

@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) {
    _subscription?.cancel(); // Cancel when backgrounding
  }
}
```

### Pitfall 3: Metrics Not Updating in Real-Time
**What goes wrong:** Metrics only show final values, not live updates. User thinks app is frozen.
**Why it happens:** Only calling setState after stream completes, not per-token
**How to avoid:**
1. Call setState in the stream's listen() callback for each token
2. Throttle updates (every 3-5 tokens) if setState is expensive
3. Use StreamBuilder which auto-rebuilds
**Warning signs:**
- Tok/sec shows 0 during generation, jumps to final value
- UI appears frozen during inference

**Code pattern:**
```dart
int _tokenCount = 0;
final _stopwatch = Stopwatch();

void _startGeneration() {
  _stopwatch.start();
  _tokenCount = 0;

  _edgeVeda.generateStream(prompt).listen((chunk) {
    _tokenCount++;

    // Update UI every token (or throttle every N tokens)
    setState(() {
      _tokensPerSecond = _tokenCount / (_stopwatch.elapsedMilliseconds / 1000);
    });
  });
}
```

### Pitfall 4: Memory Stats API Not Implemented Yet
**What goes wrong:** Example app tries to call `_edgeVeda.getMemoryStats()` but Phase 2 only implemented scaffold.
**Why it happens:** Example app was written before Phase 2 completion
**How to avoid:**
1. Verify EdgeVeda.getMemoryStats() exists and returns real data
2. Add fallback display if API not ready: "Memory: (not available)"
3. Test on real device, not just simulator
**Warning signs:**
- NoSuchMethodError on getMemoryStats()
- Memory always shows 0 MB
- "Not implemented" exceptions

**Code pattern:**
```dart
Future<void> _updateMemoryStats() async {
  try {
    final stats = await _edgeVeda.getMemoryStats();
    setState(() {
      _memoryMb = stats.currentBytes / (1024 * 1024);
      _memoryPercent = stats.usagePercent;
    });
  } catch (e) {
    // API not implemented yet - fail gracefully
    setState(() {
      _memoryMb = null; // Show "N/A" in UI
    });
  }
}
```

### Pitfall 5: Testing Only on Simulator (CRITICAL from Phase Brief)
**What goes wrong:** App runs great on iOS Simulator (Mac GPU), terrible on real iPhone (mobile GPU). Metrics misleading.
**Why it happens:** Simulator uses Mac's Metal GPU, not representative of iPhone performance
**How to avoid:**
1. ALWAYS benchmark on real device (iPhone 12 as specified in PRD)
2. Document simulator vs device performance difference in README
3. Add device info to metrics display (iOS version, device model)
**Warning signs:**
- Simulator shows 50+ tok/s, device shows 10 tok/s
- Memory usage vastly different
- Users report "slower than expected" despite good simulator performance

**Code pattern:**
```dart
import 'dart:io';

String _getDeviceInfo() {
  // On iOS, use platform channel to get device model
  // For example app, showing iOS version is sufficient
  return 'iOS ${Platform.operatingSystemVersion}';
}

// Display in metrics or README
Text('Tested on: iPhone 12, iOS 15.0 - 18 tok/s average')
```

### Pitfall 6: Not Handling Model Download Failures
**What goes wrong:** Model download fails (network issue, disk full), app stuck in loading state forever
**Why it happens:** Download is async, no timeout, no retry, no error UI
**How to avoid:**
1. Show error dialog with retry button
2. Implement timeout (e.g., 5 minutes for large model)
3. Check free disk space before download
4. Handle cancellation gracefully
**Warning signs:**
- App shows "Downloading..." forever
- No way to recover from failed download

**Code pattern:**
```dart
Future<void> _downloadModel() async {
  try {
    final modelPath = await modelManager.downloadModel(
      ModelRegistry.llama32_1b,
    ).timeout(Duration(minutes: 5));

    setState(() => _modelPath = modelPath);
  } on TimeoutException {
    _showErrorDialog('Download timed out. Please check your internet connection.');
  } on DownloadException catch (e) {
    _showErrorDialog('Download failed: ${e.message}', showRetry: true);
  }
}
```

## Code Examples

Verified patterns for Phase 3 implementation:

### Complete Chat Screen with Lifecycle
```dart
// Recommended architecture for example app
import 'package:flutter/material.dart';
import 'package:edge_veda/edge_veda.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final EdgeVeda _edgeVeda = EdgeVeda();
  final ModelManager _modelManager = ModelManager();
  final TextEditingController _promptController = TextEditingController();

  bool _isInitialized = false;
  bool _isGenerating = false;
  StreamSubscription<TokenChunk>? _streamSubscription;

  // Metrics
  final _stopwatch = Stopwatch();
  int _tokenCount = 0;
  int? _timeToFirstTokenMs;
  double? _tokensPerSecond;
  double? _memoryMb;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this); // CRITICAL: Add observer
    _initializeApp();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this); // CRITICAL: Remove observer
    _streamSubscription?.cancel();
    _edgeVeda.dispose();
    _modelManager.dispose();
    _promptController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused) {
      // App going to background - cancel generation
      if (_isGenerating) {
        _cancelGeneration();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Generation cancelled - app backgrounded')),
        );
      }
    }
  }

  Future<void> _initializeApp() async {
    // Download model if needed
    final modelPath = await _modelManager.downloadModel(ModelRegistry.llama32_1b);

    // Initialize SDK
    await _edgeVeda.init(EdgeVedaConfig(
      modelPath: modelPath,
      useGpu: true,
      numThreads: 4,
      contextLength: 2048,
      maxMemoryMb: 1200, // Under 1.2GB target
    ));

    setState(() => _isInitialized = true);
  }

  Future<void> _generateResponse(String prompt) async {
    setState(() {
      _isGenerating = true;
      _tokenCount = 0;
      _timeToFirstTokenMs = null;
    });

    _stopwatch.reset();
    _stopwatch.start();

    bool firstToken = true;
    final buffer = StringBuffer();

    try {
      _streamSubscription = _edgeVeda.generateStream(
        prompt,
        options: GenerateOptions(maxTokens: 256),
      ).listen(
        (chunk) {
          if (!mounted) return; // Check mounted before setState

          if (firstToken) {
            _timeToFirstTokenMs = _stopwatch.elapsedMilliseconds;
            firstToken = false;
          }

          if (!chunk.isFinal) {
            _tokenCount++;
            buffer.write(chunk.token);

            setState(() {
              _tokensPerSecond = _tokenCount / (_stopwatch.elapsedMilliseconds / 1000);
            });
          }
        },
        onDone: () async {
          _stopwatch.stop();

          // Get final memory stats
          final memStats = await _edgeVeda.getMemoryStats();
          setState(() {
            _memoryMb = memStats.currentBytes / (1024 * 1024);
            _isGenerating = false;
          });
        },
        onError: (error) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $error')),
          );
          setState(() => _isGenerating = false);
        },
      );
    } catch (e) {
      setState(() => _isGenerating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Generation failed: $e')),
      );
    }
  }

  void _cancelGeneration() {
    _streamSubscription?.cancel();
    _streamSubscription = null;
    _stopwatch.stop();
    setState(() => _isGenerating = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edge Veda Demo'),
        actions: [
          if (_isGenerating)
            IconButton(
              icon: Icon(Icons.stop),
              onPressed: _cancelGeneration,
            ),
        ],
      ),
      body: Column(
        children: [
          // Metrics bar
          _buildMetricsBar(),

          // Chat messages
          Expanded(
            child: ListView(/* chat messages */),
          ),

          // Input field
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildMetricsBar() {
    return Container(
      padding: EdgeInsets.all(8),
      color: Colors.blue[50],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildMetric('TTFT', _timeToFirstTokenMs != null
            ? '${_timeToFirstTokenMs}ms'
            : '-'),
          _buildMetric('Speed', _tokensPerSecond != null
            ? '${_tokensPerSecond!.toStringAsFixed(1)} tok/s'
            : '-'),
          _buildMetric('Memory', _memoryMb != null
            ? '${_memoryMb!.toStringAsFixed(0)} MB'
            : '-'),
        ],
      ),
    );
  }

  Widget _buildMetric(String label, String value) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[600])),
        Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildInputBar() {
    return Container(
      padding: EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _promptController,
              decoration: InputDecoration(hintText: 'Type a message...'),
              enabled: _isInitialized && !_isGenerating,
            ),
          ),
          IconButton(
            icon: Icon(Icons.send),
            onPressed: _isInitialized && !_isGenerating
              ? () => _generateResponse(_promptController.text)
              : null,
          ),
        ],
      ),
    );
  }
}
```

### Benchmark Logging Function
```dart
// Log performance metrics for README documentation
class BenchmarkLogger {
  static String formatBenchmark({
    required String deviceModel,
    required String osVersion,
    required String modelName,
    required double avgTokensPerSec,
    required int avgTTFTMs,
    required double peakMemoryMb,
    required int numTests,
  }) {
    return '''
## Benchmark Results

**Device:** $deviceModel
**OS:** $osVersion
**Model:** $modelName
**Tests:** $numTests runs

| Metric | Value |
|--------|-------|
| Avg Speed | ${avgTokensPerSec.toStringAsFixed(1)} tok/s |
| Avg TTFT | ${avgTTFTMs}ms |
| Peak Memory | ${peakMemoryMb.toStringAsFixed(0)} MB |
''';
  }

  // Run 10+ consecutive generations and log metrics
  static Future<void> runBenchmark(EdgeVeda edgeVeda) async {
    final List<double> tokenRates = [];
    final List<int> ttfts = [];
    final List<double> memoryMbs = [];

    const numRuns = 10;

    for (int i = 0; i < numRuns; i++) {
      final stopwatch = Stopwatch()..start();
      int tokenCount = 0;
      int? ttft;
      bool firstToken = true;

      await for (final chunk in edgeVeda.generateStream('Test prompt $i')) {
        if (firstToken) {
          ttft = stopwatch.elapsedMilliseconds;
          firstToken = false;
        }
        if (!chunk.isFinal) tokenCount++;
      }

      stopwatch.stop();

      final tokensPerSec = tokenCount / (stopwatch.elapsedMilliseconds / 1000);
      tokenRates.add(tokensPerSec);
      ttfts.add(ttft ?? 0);

      final memStats = await edgeVeda.getMemoryStats();
      memoryMbs.add(memStats.currentBytes / (1024 * 1024));

      // Brief pause between generations
      await Future.delayed(Duration(milliseconds: 500));
    }

    final avgTokensPerSec = tokenRates.reduce((a, b) => a + b) / numRuns;
    final avgTTFT = ttfts.reduce((a, b) => a + b) ~/ numRuns;
    final peakMemory = memoryMbs.reduce((a, b) => a > b ? a : b);

    print(formatBenchmark(
      deviceModel: 'iPhone 12',
      osVersion: 'iOS 15.0',
      modelName: 'Llama 3.2 1B Q4',
      avgTokensPerSec: avgTokensPerSec,
      avgTTFTMs: avgTTFT,
      peakMemoryMb: peakMemory,
      numTests: numRuns,
    ));
  }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| WidgetsBindingObserver only | AppLifecycleListener (Flutter 3.13+) | 2023 | Simpler API but WidgetsBindingObserver still standard |
| Manual state management | Riverpod 3.0 | 2026 | Enterprise best practice, but StatefulWidget sufficient for examples |
| setState everywhere | Signals for surgical updates | 2026 | Performance optimization, not needed for demo app |
| FutureBuilder/StreamBuilder | BLoC with auto-mounted safety | 2026 | Mission-critical apps, overkill for examples |

**Deprecated/outdated:**
- `compute()` for isolates: Still works, but Isolate.run() is cleaner (Dart 2.19+)
- Ignoring lifecycle: App Store increasingly strict on background execution

**Current best practices (2026):**
- Use WidgetsBindingObserver or AppLifecycleListener for lifecycle
- Riverpod 3.0 for complex state (mutations, auto-mounted checks)
- Dart 3.10 improved async generator type inference
- Flutter 3.38.6 main thread merge (no impact on isolate recommendation)

## Open Questions

Things that couldn't be fully resolved:

1. **Phase 2 API Completion Status**
   - What we know: Example app calls `generateStream()`, `getMemoryStats()` which may be scaffolded but not fully implemented
   - What's unclear: Whether Phase 2 delivered working implementations or just stubs
   - Recommendation: First task in Phase 3 is to verify SDK APIs work. If not, document as blockers and implement minimal versions for example app.

2. **Device-Specific Benchmark Variability**
   - What we know: iPhone 12 target, but performance varies by iOS version, thermal throttling, background apps
   - What's unclear: What is acceptable variance? (±20%? ±50%?)
   - Recommendation: Run 10+ consecutive tests, log min/avg/max. Document that "sustained usage" means after thermal throttling kicks in (3-5 minutes of generation).

3. **Memory API Accuracy on iOS**
   - What we know: C++ layer uses `mach_task_basic_info` for resident_size
   - What's unclear: Does iOS report accurate memory to FFI layer? Does mmap'd model count against limit?
   - Recommendation: Cross-check with Xcode Instruments Memory Graph. If discrepancy >10%, document in README as "App memory vs System memory".

4. **AppLifecycleListener vs WidgetsBindingObserver**
   - What we know: AppLifecycleListener is newer (Flutter 3.13+), simpler API
   - What's unclear: Which is more reliable for detecting iOS backgrounding edge cases?
   - Recommendation: Stick with WidgetsBindingObserver (more docs, proven pattern). Note AppLifecycleListener in README as alternative.

## Sources

### Primary (HIGH confidence)
- [Flutter App Architecture Guide](https://docs.flutter.dev/app-architecture/guide) - MVVM pattern, 2026 recommendations
- [WidgetsBindingObserver API](https://api.flutter.dev/flutter/widgets/WidgetsBindingObserver-class.html) - Lifecycle methods
- [Flutter Performance Metrics](https://docs.flutter.dev/perf/metrics) - Measuring custom metrics with Stopwatch
- [Dart Package Layout Conventions](https://dart.dev/tools/pub/package-layout) - Example directory structure
- [Flutter Async Widgets](https://docs.flutter.dev/ui/widgets/async) - FutureBuilder, StreamBuilder patterns
- Edge Veda SDK: `/Users/ram/Documents/explore/edge/flutter/lib/edge_veda.dart` - API surface
- Edge Veda Example: `/Users/ram/Documents/explore/edge/flutter/example/lib/main.dart` - Existing scaffolding
- C++ API: `/Users/ram/Documents/explore/edge/core/include/edge_veda.h` - Native functions
- Phase 2 Research: `/Users/ram/Documents/explore/edge/.planning/phases/02-flutter-ffi-model-management/02-RESEARCH.md`
- Pitfalls: `/Users/ram/Documents/explore/edge/.planning/research/PITFALLS.md` - Phase 3 specific pitfalls

### Secondary (MEDIUM confidence)
- [Flutter App Architecture Recommendations](https://docs.flutter.dev/app-architecture/recommendations) - 2026 patterns
- [WidgetsBindingObserver Lifecycle Guide (Medium)](https://medium.com/@krishna.ram30/mastering-flutter-app-lifecycle-with-widgetsbindingobserver-1350319cc3fa)
- [Cancelling Async Operations in Flutter](https://medium.com/nerd-for-tech/cancelling-asynchronous-operations-in-flutter-when-and-how-its-achievable-3d9ae0606920)
- [Flutter BLoC Tutorial 2026](https://www.zignuts.com/blog/flutter-bloc-tutorial) - State management patterns
- [Flutter State Management 2026](https://www.f22labs.com/blogs/state-management-in-flutter-7-approaches-to-know-2025/) - Riverpod 3.0, Signals
- [flutter_perf_monitor package](https://pub.dev/packages/flutter_perf_monitor) - Real-time performance monitoring
- [Real-Time Flutter Performance Monitoring (Medium)](https://medium.com/@punithsuppar7795/real-time-flutter-performance-monitoring-memory-fps-firebase-elk-integration-03ea5fa9347e)

### Tertiary (LOW confidence)
- WebSearch results on 2026 Flutter best practices - verified against official docs before inclusion
- Community blogs on lifecycle handling - cross-referenced with official API docs

## Metadata

**Confidence breakdown:**
- Flutter lifecycle patterns: HIGH - Official API documentation and extensive community resources
- Performance measurement: HIGH - Dart Stopwatch is standard library, well-documented
- UI patterns (StreamBuilder, FutureBuilder): HIGH - Official Flutter widgets, stable API
- Example app architecture: MEDIUM - Based on conventions and existing scaffold, needs validation with Phase 2 API
- Benchmark methodology: MEDIUM - Standard approach, but device-specific validation needed

**Research date:** 2026-02-04
**Valid until:** 2026-03-04 (30 days - Flutter stable, patterns unlikely to change)
