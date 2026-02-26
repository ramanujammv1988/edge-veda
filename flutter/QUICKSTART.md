# Edge Veda iOS Quickstart

From zero to on-device AI in 15 minutes. By the end of this guide you will have a Flutter app running streaming LLM inference entirely on your iPhone -- no server, no API key, no cloud dependency.

This guide covers **iOS only**. Android support is scaffolded but not yet validated.

For the full SDK reference, see the [README](README.md).

---

## Prerequisites

Before you start, confirm you have:

- **Flutter SDK >= 3.16.0** -- check with `flutter --version`
- **Xcode** (latest stable) -- check with `xcode-select -p`
- **CocoaPods** -- check with `pod --version`, install with `gem install cocoapods` if missing
- **Apple Developer account** -- free works for development, paid for App Store distribution
- **iOS Developer Mode enabled** on your test device -- go to Settings > Privacy & Security > Developer Mode and toggle it on. This is required for deploying debug builds to physical devices.
- **Code signing configured** -- open `ios/Runner.xcworkspace` in Xcode, select the Runner target, go to Signing & Capabilities, and select your personal team. Auto-signing with a free Apple ID is sufficient for development.
- **Physical iPhone recommended** -- iPhone 12 or later with 4 GB+ RAM. The iOS Simulator works but runs CPU-only and is significantly slower than a real device with Metal GPU.

---

## Step 1: Create Project and Install

```bash
flutter create my_ai_app
cd my_ai_app
```

Add Edge Veda to `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  edge_veda: ^2.4.2
```

Install:

```bash
flutter pub get
```

### Podfile Setup

Open `ios/Podfile` and ensure the minimum deployment target is set:

```ruby
platform :ios, '13.0'
```

The SDK works with both `use_frameworks!` and `use_modular_headers!` -- no special Podfile configuration is needed beyond the platform version.

Install the native pods:

```bash
cd ios && pod install && cd ..
```

The native XCFramework (~31 MB, containing llama.cpp + whisper.cpp + stable-diffusion.cpp with Metal GPU support) is automatically downloaded from GitHub Releases during `pod install`. No manual download or build step is needed.

---

## Step 2: Choose and Download a Model

This is where most developers get stuck. Edge Veda provides three approaches to get a model onto the device.

### Option A: Use ModelAdvisor (Recommended)

`ModelAdvisor` detects your device hardware and recommends the best model for your use case:

```dart
import 'package:edge_veda/edge_veda.dart';

final device = DeviceProfile.detect();
print('Device: ${device.deviceName}, ${device.totalRamGB}GB, ${device.chipName}');

final rec = ModelAdvisor.recommend(
  device: device,
  useCase: UseCase.chat,
);

if (rec.bestMatch != null) {
  print('Recommended: ${rec.bestMatch!.model.name}');
  print('Score: ${rec.bestMatch!.finalScore}/100');
  print('Fits: ${rec.bestMatch!.fits}');
}
```

Before downloading, you can check if the model fits in memory and if there is enough disk space:

```dart
final canRun = ModelAdvisor.canRun(model: ModelRegistry.llama32_1b);
print('Can run: $canRun');

final storage = await ModelAdvisor.checkStorageAvailability(
  model: ModelRegistry.llama32_1b,
);
if (!storage.hasSufficientSpace) {
  print(storage.warning);
}
```

### Option B: Direct Download from ModelRegistry

When you already know which model you want:

```dart
final modelManager = ModelManager();
final modelPath = await modelManager.downloadModel(
  ModelRegistry.llama32_1b,
);
```

Monitor download progress:

```dart
modelManager.downloadProgress.listen((progress) {
  print('${progress.progressPercent}% - '
      '${progress.estimatedSecondsRemaining}s remaining');
});
```

Downloads automatically resume if interrupted. The SDK uses HTTP byte-range requests to pick up where you left off -- no wasted bandwidth.

### Option C: Import a Local Model

For pre-downloaded or bundled GGUF files:

```dart
final modelManager = ModelManager();
final modelPath = await modelManager.importModel(
  ModelRegistry.llama32_1b,
  sourcePath: '/path/to/your/model.gguf',
  onProgress: (bytesCopied, totalBytes) {
    print('Copying: ${(bytesCopied / totalBytes * 100).toStringAsFixed(0)}%');
  },
);
```

`importModel()` copies atomically -- if interrupted, no corrupt files are left. The source file is validated against the expected size and optionally verified with a SHA256 checksum before the atomic rename.

### Which Model to Start With

Use **Llama 3.2 1B Instruct** (`ModelRegistry.llama32_1b`) as your starting model:

- 668 MB download (Q4_K_M quantization)
- Fits on all iPhones 12 and later
- Fast inference even on older devices
- Good quality for a 1B parameter model
- Supports chat and instruction following

---

## Step 3: First Inference

Replace the contents of `lib/main.dart` with this complete working example:

```dart
import 'package:edge_veda/edge_veda.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Edge Veda Quickstart',
      home: ChatScreen(),
    );
  }
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _edgeVeda = EdgeVeda();
  final _modelManager = ModelManager();
  String _output = 'Initializing...';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  Future<void> _setup() async {
    try {
      // 1. Download model (returns immediately if already cached)
      setState(() { _output = 'Downloading model...'; });
      final modelPath = await _modelManager.downloadModel(
        ModelRegistry.llama32_1b,
      );
      if (!mounted) return;

      // 2. Get device-optimized config
      final device = DeviceProfile.detect();
      final scored = ModelAdvisor.score(
        model: ModelRegistry.llama32_1b,
        device: device,
        useCase: UseCase.chat,
      );
      final config = EdgeVedaConfig(
        modelPath: modelPath,
        contextLength: scored.recommendedConfig.contextLength,
        numThreads: scored.recommendedConfig.numThreads,
        useGpu: true,
      );

      // 3. Initialize the inference engine
      setState(() { _output = 'Loading model...'; });
      await _edgeVeda.init(config);
      if (!mounted) return;
      setState(() { _isLoading = false; _output = 'Ready! Tap Generate.'; });
    } catch (e) {
      setState(() { _output = 'Error: $e'; _isLoading = false; });
    }
  }

  Future<void> _generate() async {
    setState(() { _output = ''; _isLoading = true; });

    try {
      await for (final chunk in _edgeVeda.generateStream(
        'Explain what on-device AI means in two sentences.',
      )) {
        if (!chunk.isFinal) {
          setState(() { _output += chunk.token; });
        }
      }
    } catch (e) {
      setState(() { _output = 'Generation error: $e'; });
    }

    if (!mounted) return;
    setState(() { _isLoading = false; });
  }

  @override
  void dispose() {
    _edgeVeda.dispose();
    _modelManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edge Veda Quickstart')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _output,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _generate,
              child: Text(_isLoading ? 'Working...' : 'Generate'),
            ),
          ],
        ),
      ),
    );
  }
}
```

---

## Step 4: Run It

```bash
# On physical device (RECOMMENDED for real performance)
flutter run --release

# On simulator (slower, CPU-only, no Metal GPU)
flutter run
```

The first run triggers a 668 MB model download (over WiFi). After that, the model is cached and subsequent launches skip the download.

Model loading takes 30-60 seconds the first time the inference engine initializes. The model stays loaded in memory for subsequent generation calls.

---

## Debug vs Release: Why It Matters

**Your first run will be SLOW if you use debug mode. This is normal.**

| Mode | Optimizations | Metal GPU | Inference Speed |
|------|--------------|-----------|-----------------|
| Debug | None (assertions enabled) | Overhead | ~5 tok/s |
| Profile | Release optimizations + DevTools | Full speed | ~35 tok/s |
| Release | Full LTO | Full speed | ~42 tok/s |

Concrete example: **Llama 3.2 1B on iPhone 14 Pro: ~5 tok/s in debug vs ~42 tok/s in release mode.** That is an 8x difference.

Why debug mode is slow:

- No compiler optimizations -- Dart and native code run without LTO or inlining
- Assertions enabled -- extra runtime checks on every operation
- Metal GPU has debug overhead -- shader compilation and validation layers active

Rules for performance testing:

1. **Always use `flutter run --release` or `flutter run --profile`** for any performance measurement
2. **Never judge SDK speed from debug mode** -- it is not representative of production performance
3. **Profile mode** is a good middle ground: release-level optimizations with DevTools debugging still available

Model load time: approximately 30-60 seconds on first call (loads weights into memory). Subsequent `generateStream` and `generate` calls reuse the loaded model -- no reload overhead.

---

## Troubleshooting

### `ModelLoadException: Model file not found`

**Cause:** The model path is wrong, the model has not been downloaded yet, or the app sandbox location changed after reinstall.

**Fix:** Always use `ModelManager` to get the correct path:

```dart
final modelManager = ModelManager();
final modelPath = await modelManager.getModelPath('llama-3.2-1b-instruct-q4');
final isDownloaded = await modelManager.isModelDownloaded('llama-3.2-1b-instruct-q4');
```

If the model is not downloaded, call `modelManager.downloadModel(ModelRegistry.llama32_1b)` first.

### `InitializationException: Initialization failed`

**Cause:** The model is too large for the device's available memory, or the file is in the wrong format (not GGUF).

**Fix:** Check device RAM and model compatibility before loading:

```dart
final device = DeviceProfile.detect();
final canRun = ModelAdvisor.canRun(model: ModelRegistry.llama32_1b);
if (!canRun) {
  print('Model too large for ${device.deviceName} (${device.totalRamGB}GB RAM)');
}
```

### `Signing for "Runner" requires a development team`

**Cause:** Xcode code signing is not configured.

**Fix:** Open `ios/Runner.xcworkspace` (not `.xcodeproj`) in Xcode. Select the Runner target, go to Signing & Capabilities, and choose your development team. A free Apple ID personal team is sufficient for development.

### `CocoaPods could not find compatible versions for pod "EdgeVedaCore"`

**Cause:** Stale CocoaPods cache or outdated pod specs.

**Fix:**

```bash
cd ios && pod deintegrate && pod install && cd ..
```

If that does not resolve it, clear the global cache:

```bash
pod cache clean --all
cd ios && pod install && cd ..
```

### `No such module 'edge_veda'`

**Cause:** The Xcode workspace was not used, or `pod install` was not run after adding the dependency.

**Fix:** Close any `.xcodeproj` file. Always open `ios/Runner.xcworkspace` instead. If the workspace was already open, run `pod install` and reopen:

```bash
cd ios && pod install && cd ..
# Then open ios/Runner.xcworkspace in Xcode
```

### Slow inference (< 10 tok/s on a modern iPhone)

**Cause:** Running in debug mode.

**Fix:** Use release or profile mode:

```bash
flutter run --release    # Full speed
flutter run --profile    # Full speed + DevTools
```

See the "Debug vs Release" section above for the full explanation.

### App crashes after ~30 seconds of inference

**Cause:** Memory pressure on devices with 4 GB RAM. iOS terminates apps that exceed their memory budget (jetsam).

**Fix:** Reduce context length to lower memory usage, or use a smaller model:

```dart
final config = EdgeVedaConfig(
  modelPath: modelPath,
  contextLength: 1024, // Reduced from default 2048
  useGpu: true,
);
```

On 4 GB devices, avoid models larger than 1 GB (stick with Llama 3.2 1B or Qwen3 0.6B).

### `DownloadException: Insufficient disk space`

**Cause:** Not enough free storage on the device for the model file.

**Fix:** Free up device storage or choose a smaller model. Check available space before downloading:

```dart
final storage = await ModelAdvisor.checkStorageAvailability(
  model: ModelRegistry.llama32_1b,
);
if (!storage.hasSufficientSpace) {
  print(storage.warning);
}
```

### Download stalls or fails mid-way

**Cause:** Network interruption (WiFi dropout, server timeout).

**Fix:** Downloads resume automatically on retry. The SDK uses HTTP byte-range requests, so retrying `downloadModel()` picks up from where it left off -- no re-downloading of already-fetched bytes. Check your network connection and call `downloadModel()` again.

---

## Next Steps

Once you have streaming inference working, explore the full SDK capabilities:

- **Multi-turn chat** -- use `ChatSession` with `sendStream()` for conversations that maintain context across turns. See the Chat section in the [README](README.md).

- **Function calling** -- define tools with `ToolDefinition` and use `ChatSession.sendWithTools()` to let the model invoke functions. Requires Qwen3 0.6B or another tool-capable model.

- **On-device RAG** -- embed documents with `VectorIndex` and query with `RagPipeline` for retrieval-augmented generation grounded in your own data.

- **Vision inference** -- use `VisionWorker` with SmolVLM2 500M to describe images and analyze camera frames in real time.

- **Speech-to-text** -- use `WhisperWorker` with Whisper models for real-time audio transcription, entirely on device.

- **Compute budgets** -- use `Scheduler` with `EdgeVedaBudget` to enforce p95 latency, battery drain, and thermal constraints automatically.

For the full API reference, example app, and architecture details:

- [README](README.md) -- complete SDK documentation
- [API Reference](https://pub.dev/documentation/edge_veda/latest/) -- generated Dart docs
- [Example App](https://github.com/ramanujammv1988/edge-veda/tree/main/flutter/example) -- full-featured demo with chat, vision, STT, TTS, and image generation
- [Discord](https://discord.gg/rv8qZMGC) -- community support
