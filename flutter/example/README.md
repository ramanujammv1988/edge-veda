# Edge Veda Example App

A demonstration Flutter app showcasing the Edge Veda SDK for on-device LLM inference on iOS.

## Features

- **Fast On-Device Inference** - Llama 3.2 1B model running locally with Metal GPU acceleration
- **Real-Time Metrics** - Live display of tokens/sec, TTFT, and memory usage
- **Chat Interface** - Simple conversational UI for testing prompts
- **Automatic Model Download** - First-run download with progress tracking
- **Lifecycle Handling** - Proper iOS backgrounding behavior (App Store compliant)
- **Benchmark Mode** - Performance testing with 10+ consecutive generations

## Prerequisites

### Required

- **macOS** (for iOS development)
- **Xcode 14.0+** with Command Line Tools
- **Flutter 3.16.0+** (stable channel recommended)
- **iOS 13.0+ device** (iPhone 12 or newer recommended)

### Build Dependencies

The Edge Veda SDK requires native C++ libraries. Before running the example app, you must build the iOS XCFramework:

```bash
# From project root
./scripts/build-ios.sh --clean --release
```

This builds `EdgeVedaCore.xcframework` with llama.cpp and the C++ inference engine.

> **Note:** Xcode installation is required for iOS builds. Command Line Tools alone are insufficient.

### Storage Requirements

- **Initial app size:** ~15-20 MB
- **Model download:** ~650 MB (Llama 3.2 1B Q4_K_M)
- **Runtime memory:** 600-1300 MB during inference
- **Total storage needed:** ~1 GB

## Getting Started

### 1. Clone and Setup

```bash
# Clone the repository
git clone https://github.com/edgeveda/edge-veda-sdk.git
cd edge/flutter/example

# Install Flutter dependencies
flutter pub get
```

### 2. Build Native Libraries

```bash
# Build iOS XCFramework (from project root)
cd ../..
./scripts/build-ios.sh --clean --release
```

Verify the build succeeded:
```bash
ls flutter/ios/Frameworks/EdgeVedaCore.xcframework/ios-arm64/libedge_veda_full.a
# Should show the static library file
```

### 3. Connect iOS Device

The example app requires a **real iOS device** (iPhone 12+ recommended). The iOS Simulator uses Mac's GPU and gives misleading performance results.

```bash
# List connected devices
flutter devices

# Example output:
# iPhone 12 (mobile) • 00008030-XXXXX • ios • iOS 15.0
```

### 4. Run the App

```bash
# Run in release mode for accurate performance
flutter run --release -d <device-id>

# Or simply (if only one device connected)
flutter run --release
```

### 5. First Launch

On first launch, the app will:

1. **Download the model** (~650 MB) - Takes 2-5 minutes on WiFi
   - Progress bar shows download percentage
   - Model caches in app support directory

2. **Prompt for initialization** - Tap "Initialize" button
   - Loads model into memory (~600 MB)
   - Tests inference with Metal GPU
   - Shows "Ready to chat!" when complete

3. **Ready to use** - Type a prompt and tap send

> **Tip:** Keep device plugged in during first run. Model download and initial load are resource-intensive.

## Using the Example App

### Chat Interface

1. **Type a prompt** in the text field at the bottom
2. **Tap send icon** to generate a response
3. **View response** in the chat bubble
4. **Monitor metrics** in the top bar:
   - **TTFT:** Time to First Token (latency)
   - **Speed:** Tokens per second
   - **Memory:** Current memory usage

### Performance Metrics

The metrics bar updates after each generation:

- **TTFT (Time to First Token):** How quickly the model starts generating (lower is better)
- **Speed (tok/s):** Generation throughput (higher is better)
- **Memory (MB):** Current memory usage (should stay <1200 MB)

**Target Performance:**
- Speed: >15 tok/s on iPhone 12
- Memory: <1200 MB peak usage

See [BENCHMARK.md](./BENCHMARK.md) for detailed performance results on iPhone 12.

### Info Dialog

Tap the **info icon** in the AppBar to see:
- Current memory usage and percentage
- Memory pressure status (warning if high)
- Last generation performance metrics

### Benchmark Mode

Tap the **assessment icon** (chart) to run a 10-test benchmark:

1. Runs 10 consecutive generations with varied prompts
2. Measures avg tok/s, TTFT, and peak memory
3. Shows results in dialog and logs to console
4. Takes ~2-3 minutes to complete

Results help validate SDK performance on your specific device and iOS version.

## iOS Backgrounding Behavior

**Important:** The example app cancels generation when you background the app (press home button or switch apps).

### Why?

iOS requires apps to stop CPU-intensive tasks when backgrounded. Running inference in the background causes:
- App Store rejection
- System termination (jetsam kills)
- Poor user experience (battery drain)

### What Happens?

- **You send a prompt** - Generation starts
- **You press home** - Generation immediately cancels
- **Status bar shows** "Generation cancelled - app backgrounded"
- **You return to app** - Send a new prompt to continue

This is expected behavior and required for App Store approval.

## Troubleshooting

### Model Download Issues

**Problem:** Download fails or stalls

**Solutions:**
- Ensure stable WiFi connection
- Check available storage (need 1 GB free)
- Restart app to retry download
- Check console for error messages

### Memory Warnings

**Problem:** "High memory pressure" warning appears

**Solutions:**
- Close other apps to free memory
- Restart the device
- Note: 1 GB usage is normal during inference
- Memory should stabilize after a few generations

### Initialization Fails

**Problem:** "Initialization failed" error

**Solutions:**
1. Verify XCFramework is built:
   ```bash
   ls ../ios/Frameworks/EdgeVedaCore.xcframework/ios-arm64/libedge_veda_full.a
   ```
2. Rebuild if missing:
   ```bash
   cd ../../.. && ./scripts/build-ios.sh --clean --release
   ```
3. Clean and rebuild app:
   ```bash
   flutter clean && flutter pub get && flutter run --release
   ```

### Slow Performance

**Problem:** Speed <15 tok/s on iPhone 12

**Possible Causes:**
- **Thermal throttling:** Device is hot, CPU/GPU throttled for cooling
- **Low power mode:** iOS reduces performance to save battery
- **Background apps:** Other apps consuming resources
- **Debug mode:** Run with `--release` flag, not debug

**Solutions:**
- Let device cool down
- Disable Low Power Mode (Settings > Battery)
- Close background apps
- Ensure running in release mode

### "setState() after dispose()" Errors

**Problem:** Hot reload causes crash with lifecycle errors

**Solutions:**
- This is expected with hot reload and FFI
- **Hot restart** instead of hot reload: Press 'R' in terminal
- Full rebuild: `flutter run --release` again

## Performance Expectations

Based on benchmarks from iPhone 12 (see [BENCHMARK.md](./BENCHMARK.md)):

| Metric | iPhone 12 | Target | Notes |
|--------|-----------|--------|-------|
| Avg Speed | 42.9 tok/s | >15 tok/s | 2.86x target |
| Min Speed | 25.4 tok/s | - | Varies by prompt |
| Max Speed | 52.0 tok/s | - | Peak performance |
| TTFT | 516 ms | <500 ms | Prompt processing |
| Peak Memory | 1316 MB | <1200 MB | Slightly over limit |

**Device Variations:**
- **iPhone 13+:** Expect 20-30% faster (better GPU)
- **iPhone 11/SE:** Expect 20-30% slower (older GPU)
- **iPad:** Similar to comparable iPhone generation

**Thermal Throttling:**
After 5+ minutes of continuous inference, performance may drop 10-30% as device heats up. This is normal iOS behavior.

## Project Structure

```
lib/
  main.dart              # App entry point and ChatScreen

ios/
  Podfile                # CocoaPods configuration
  Runner.xcworkspace     # Xcode workspace

BENCHMARK.md             # Performance benchmark results
README.md                # This file
pubspec.yaml             # Dependencies
```

## SDK Usage Reference

The example app demonstrates core SDK functionality:

```dart
import 'package:edge_veda/edge_veda.dart';

// Initialize SDK
final edgeVeda = EdgeVeda();
final modelManager = ModelManager();

// Download model (with progress tracking)
final modelPath = await modelManager.downloadModel(ModelRegistry.llama32_1b);

// Initialize inference engine
await edgeVeda.init(EdgeVedaConfig(
  modelPath: modelPath,
  useGpu: true,
  numThreads: 4,
  contextLength: 2048,
));

// Generate text
final response = await edgeVeda.generate(
  'Your prompt here',
  options: GenerateOptions(
    maxTokens: 256,
    temperature: 0.7,
  ),
);

print(response.text);

// Monitor memory
final stats = await edgeVeda.getMemoryStats();
print('Memory: ${stats.currentBytes / (1024 * 1024)} MB');

// Cleanup
edgeVeda.dispose();
```

See the [main SDK README](../../README.md) for full API documentation.

## Known Limitations (v1)

- **No streaming:** v1 uses synchronous generation. Streaming support planned for v2.
- **Foreground only:** Generation must run while app is visible (iOS requirement).
- **Single concurrent generation:** Starting a new generation cancels the previous one.
- **Fixed model:** v1 includes only Llama 3.2 1B Q4_K_M. More models in v2.

## Contributing

This is an example app demonstrating SDK capabilities. For SDK issues or feature requests, please file issues in the main repository.

## License

See [LICENSE](../../LICENSE) file in the repository root.

---

**SDK Version:** 1.0.0
**Flutter Version:** 3.16.0+
**iOS Version:** 13.0+
**Last Updated:** 2026-02-04
