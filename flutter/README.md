# Edge Veda SDK for Flutter

On-device AI inference for Flutter applications. Run LLMs, Speech-to-Text, and Text-to-Speech directly on mobile devices with hardware acceleration.

## Features

- **On-Device LLM Inference**: Run large language models locally with llama.cpp
- **Hardware Acceleration**: Metal (iOS), Vulkan (Android) for optimal performance
- **Streaming Support**: Real-time token-by-token generation
- **Model Management**: Download, verify, and cache models automatically
- **Memory Safe**: Configurable memory limits with watchdog protection
- **Privacy First**: 100% on-device processing, zero data transmission
- **Offline Ready**: Works without internet connectivity

## Performance

- **Latency**: Sub-200ms time-to-first-token on modern devices
- **Throughput**: >15 tokens/sec for 1B parameter models
- **Memory**: Optimized for 4GB devices with 1.5GB safe limit
- **Battery**: GPU acceleration for efficient long-form generation

## Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  edge_veda: ^0.1.0
```

Run:

```bash
flutter pub get
```

## Platform Requirements

### iOS
- iOS 13.0+
- Metal-compatible device (iPhone 6s or later)
- Xcode 14.0+

### Android
- Android API 24+ (Android 7.0)
- ARM64 or ARMv7 device
- Vulkan 1.0+ support (optional but recommended)

## Quick Start

### 1. Download a Model

```dart
import 'package:edge_veda/edge_veda.dart';

final modelManager = ModelManager();

// Download Llama 3.2 1B (recommended for most use cases)
final modelPath = await modelManager.downloadModel(
  ModelRegistry.llama32_1b,
);

// Monitor download progress
modelManager.downloadProgress.listen((progress) {
  print('Downloading: ${progress.progressPercent}%');
});
```

### 2. Initialize Edge Veda

```dart
final edgeVeda = EdgeVeda();

await edgeVeda.init(EdgeVedaConfig(
  modelPath: modelPath,
  useGpu: true,              // Enable hardware acceleration
  numThreads: 4,             // CPU threads for inference
  contextLength: 2048,       // Max context window
  maxMemoryMb: 1536,         // Memory safety limit
  verbose: true,             // Enable logging
));
```

### 3. Generate Text

**Synchronous Generation:**

```dart
final response = await edgeVeda.generate(
  'What is the capital of France?',
  options: GenerateOptions(
    maxTokens: 100,
    temperature: 0.7,
    topP: 0.9,
    systemPrompt: 'You are a helpful assistant.',
  ),
);

print(response.text);
print('Tokens/sec: ${response.tokensPerSecond}');
```

**Streaming Generation:**

```dart
final stream = edgeVeda.generateStream(
  'Tell me a story about a robot',
  options: GenerateOptions(
    maxTokens: 256,
    temperature: 0.8,
  ),
);

await for (final chunk in stream) {
  if (!chunk.isFinal) {
    print(chunk.token); // Print each token as it arrives
  }
}
```

### 4. Clean Up

```dart
await edgeVeda.dispose();
modelManager.dispose();
```

## Available Models

### Llama 3.2 1B Instruct (Recommended)
- **Size**: 668 MB
- **Speed**: Very fast
- **Quality**: Excellent for most tasks
- **Use Case**: General chat, Q&A, summarization

```dart
ModelRegistry.llama32_1b
```

### Phi 3.5 Mini Instruct
- **Size**: 2.3 GB
- **Speed**: Fast
- **Quality**: Superior reasoning
- **Use Case**: Complex reasoning, coding, math

```dart
ModelRegistry.phi35_mini
```

### Gemma 2 2B Instruct
- **Size**: 1.6 GB
- **Speed**: Fast
- **Quality**: High quality
- **Use Case**: Versatile general-purpose

```dart
ModelRegistry.gemma2_2b
```

### TinyLlama 1.1B Chat
- **Size**: 669 MB
- **Speed**: Ultra fast
- **Quality**: Good for simple tasks
- **Use Case**: Resource-constrained devices

```dart
ModelRegistry.tinyLlama
```

## Configuration Options

### EdgeVedaConfig

```dart
EdgeVedaConfig(
  modelPath: '/path/to/model.gguf',  // Required
  numThreads: 4,                      // Default: 4
  contextLength: 2048,                // Default: 2048
  useGpu: true,                       // Default: true
  maxMemoryMb: 1536,                  // Default: 1536
  verbose: false,                     // Default: false
)
```

### GenerateOptions

```dart
GenerateOptions(
  systemPrompt: null,                 // Optional system context
  maxTokens: 512,                     // Default: 512
  temperature: 0.7,                   // Default: 0.7 (0.0-1.0)
  topP: 0.9,                         // Default: 0.9
  topK: 40,                          // Default: 40
  repeatPenalty: 1.1,                // Default: 1.1
  stopSequences: [],                 // Optional stop strings
  jsonMode: false,                   // Default: false
)
```

## Model Management

### Check if Model is Downloaded

```dart
final isDownloaded = await modelManager.isModelDownloaded('llama-3.2-1b-instruct-q4');
```

### List Downloaded Models

```dart
final models = await modelManager.getDownloadedModels();
print('Downloaded models: $models');
```

### Get Total Storage Usage

```dart
final totalBytes = await modelManager.getTotalModelsSize();
print('Storage used: ${totalBytes / (1024 * 1024)} MB');
```

### Delete a Model

```dart
await modelManager.deleteModel('llama-3.2-1b-instruct-q4');
```

### Clear All Models

```dart
await modelManager.clearAllModels();
```

## Error Handling

```dart
try {
  await edgeVeda.init(config);
} on InitializationException catch (e) {
  print('Init failed: ${e.message}');
} on ModelLoadException catch (e) {
  print('Model load failed: ${e.message}');
} on MemoryException catch (e) {
  print('Out of memory: ${e.message}');
} on EdgeVedaException catch (e) {
  print('Edge Veda error: ${e.message}');
}
```

## Memory Management

Monitor memory usage to prevent crashes:

```dart
// Get current memory usage
final memoryBytes = edgeVeda.getMemoryUsage();
final memoryMb = edgeVeda.getMemoryUsageMb();

// Check if limit exceeded
if (edgeVeda.isMemoryLimitExceeded()) {
  print('Warning: Memory limit exceeded!');
  // Consider disposing and reinitializing
}
```

## Best Practices

1. **Initialize Once**: Initialize EdgeVeda once per app session, reuse the instance
2. **Memory Monitoring**: Check memory usage periodically, especially on low-end devices
3. **Model Selection**: Start with Llama 3.2 1B for best balance of speed and quality
4. **GPU Acceleration**: Always enable `useGpu: true` unless testing CPU-only
5. **Context Management**: Keep context length at 2048 or lower for optimal performance
6. **Error Handling**: Always wrap operations in try-catch blocks
7. **Resource Cleanup**: Call `dispose()` when done to free native memory

## Example App

See the [example](example/) directory for a complete chat application demonstrating:
- Model downloading with progress tracking
- SDK initialization
- Streaming text generation
- Memory monitoring
- Error handling

Run the example:

```bash
cd example
flutter run
```

## Architecture

Edge Veda uses a layered architecture:

```
┌─────────────────────────────────┐
│     Flutter Application         │
├─────────────────────────────────┤
│     edge_veda.dart (Public API) │
├─────────────────────────────────┤
│  Dart FFI Bindings              │
├─────────────────────────────────┤
│  Native C++ Core (llama.cpp)    │
├─────────────────────────────────┤
│  Hardware Acceleration          │
│  Metal (iOS) / Vulkan (Android) │
└─────────────────────────────────┘
```

## Limitations

- **Model Format**: Only GGUF format supported
- **Platforms**: iOS and Android only (Web/Desktop coming soon)
- **Model Size**: Limited by device storage and RAM
- **Context Length**: Maximum 32K tokens (recommended: 2048)

## Troubleshooting

### iOS Build Issues

```bash
cd ios
pod install
cd ..
flutter clean
flutter build ios
```

### Android Build Issues

```bash
flutter clean
cd android
./gradlew clean
cd ..
flutter build apk
```

### Model Download Fails

- Check internet connectivity
- Verify sufficient storage space
- Try again (downloads are resumable)

### Out of Memory

- Reduce `contextLength`
- Lower `maxMemoryMb` threshold
- Use a smaller model (TinyLlama)
- Close other apps

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](../CONTRIBUTING.md)

## License

MIT License - see [LICENSE](../LICENSE)

## Support

- Issues: [GitHub Issues](https://github.com/edgeveda/edge-veda-sdk/issues)
- Discussions: [GitHub Discussions](https://github.com/edgeveda/edge-veda-sdk/discussions)
- Email: support@edgeveda.com

## Roadmap

- [ ] Flutter Web support (WASM + WebGPU)
- [ ] Speech-to-Text (Whisper)
- [ ] Text-to-Speech (Kokoro-82M)
- [ ] Voice Activity Detection
- [ ] Prompt caching
- [ ] LoRA adapter support
- [ ] Custom model fine-tuning
