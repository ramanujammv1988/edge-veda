# Edge Veda

**On-device LLM inference for Flutter. Text and vision. Private by default.**

[![Version](https://img.shields.io/badge/version-1.1.0-blue)](https://github.com/ramanujammv1988/edge-veda)
[![Platform](https://img.shields.io/badge/platform-iOS-lightgrey)](https://github.com/ramanujammv1988/edge-veda)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

---

## What This Is

Edge Veda is a Flutter SDK that runs LLMs directly on mobile devices. No servers, no API keys, no data leaving the phone. Built on [llama.cpp](https://github.com/ggml-org/llama.cpp) with Metal GPU acceleration on iOS.

**Current state:** iOS is fully working and validated on-device. Android is scaffolded but not yet validated.

### Capabilities

| Capability | Status | Details |
|-----------|--------|---------|
| Text generation | Shipping | Blocking and streaming, with cancellation |
| Vision (VLM) | Shipping | Camera-to-text via SmolVLM2-500M |
| Multi-turn chat | Shipping | Context management, auto-summarization, chat templates |
| Model management | Shipping | Download, cache, verify (SHA-256), delete |
| Runtime adaptation | Shipping | Thermal/battery/memory-aware QoS with hysteresis |
| Android | In progress | CPU build scaffolded, Vulkan GPU planned |

---

## Why On-Device

Running inference on-device instead of calling a cloud API changes what's possible:

- **Privacy** — User data never leaves the device. No terms of service, no data processing agreements, no breach risk.
- **Latency** — No network round-trip. Streaming tokens appear immediately.
- **Cost** — Zero per-token cost. Zero server infrastructure.
- **Offline** — Works in airplane mode, underground, rural areas.
- **Compliance** — Simplifies HIPAA, GDPR, SOC 2 by eliminating data transmission.

The tradeoff is model size and capability. On-device models (1B–3B parameters) are less capable than cloud models (70B+), but for many use cases — summarization, structured extraction, image description, conversational Q&A — they're sufficient.

---

## Quick Start

```dart
import 'package:edge_veda/edge_veda.dart';

final edgeVeda = EdgeVeda();

// Initialize with a GGUF model
await edgeVeda.init(EdgeVedaConfig(
  modelPath: modelPath,
  contextLength: 2048,
  useGpu: true,
));

// Stream a response
await for (final chunk in edgeVeda.generateStream('Explain recursion briefly')) {
  stdout.write(chunk.token);
}

await edgeVeda.dispose();
```

### Multi-Turn Conversation

```dart
final session = ChatSession(
  edgeVeda: edgeVeda,
  preset: SystemPromptPreset.coder,
);

// Streaming conversation with context management
await for (final chunk in session.sendStream('Write hello world in Python')) {
  stdout.write(chunk.token);
}

// Model remembers the conversation
await for (final chunk in session.sendStream('Now convert it to Rust')) {
  stdout.write(chunk.token);
}

print('Turns: ${session.turnCount}');
print('Context used: ${(session.contextUsage * 100).toInt()}%');
```

### Vision (Camera to Text)

```dart
await edgeVeda.initVision(VisionConfig(
  modelPath: vlmModelPath,
  mmprojPath: mmprojPath,
));

// Describe a camera frame
final rgb = CameraUtils.convertBgraToRgb(frame.planes[0].bytes, 640, 480);
final description = await edgeVeda.describeImage(rgb, width: 640, height: 480);
```

---

## Architecture

```
Flutter App (Dart)
    │
    ├── ChatSession ─── Chat templates, context summarization, presets
    │
    ├── EdgeVeda ─────── generate(), generateStream(), describeImage()
    │
    ├── StreamingWorker ── Persistent isolate, keeps model loaded
    ├── VisionWorker ───── Persistent isolate, keeps VLM loaded
    │
    └── FFI Bindings ──── 37 C functions via DynamicLibrary.process()
         │
    XCFramework (libedge_veda_full.a)
    ├── engine.cpp ─────── Text inference (wraps llama.cpp)
    ├── vision_engine.cpp ─ Vision inference (wraps libmtmd)
    ├── memory_guard.cpp ── RSS monitoring, pressure callbacks
    └── llama.cpp b7952 ── Metal GPU, GGUF models
```

**Key design constraint:** Dart FFI is synchronous — calling llama.cpp directly would freeze the UI. All inference runs in background isolates. Native pointers never cross isolate boundaries. The `StreamingWorker` and `VisionWorker` maintain persistent contexts so models load once and stay in memory.

---

## On-Device Performance

### Soak Test (Vision, Physical iPhone)

Continuous vision inference over 12.6 minutes on a physical iPhone:

| Metric | Value |
|--------|-------|
| Duration | 12.6 minutes |
| Frames processed | 254 |
| p50 latency | 1,412 ms/frame |
| Crashes | 0 |
| Model reloads | 0 |
| Memory stability | No growth over session |

### Text Inference

Demo app benchmark targets (Llama 3.2 1B Q4_K_M on iPhone with Metal):

| Metric | Target |
|--------|--------|
| Throughput | > 15 tokens/sec |
| Peak memory | < 1.2 GB |

### Runtime Adaptation

The SDK monitors thermal state, battery level, and available memory, then adjusts vision inference parameters:

| QoS Level | FPS | Resolution | Tokens | Trigger |
|-----------|-----|------------|--------|---------|
| Full | 2 | 640px | 100 | No pressure |
| Reduced | 1 | 480px | 75 | Thermal warning, low battery, low memory |
| Minimal | 1 | 320px | 50 | Thermal serious, very low battery |
| Paused | 0 | — | 0 | Thermal critical, memory critical |

Escalation is immediate. Restoration requires 60s cooldown per level to prevent oscillation.

---

## Supported Models

Pre-configured in `ModelRegistry` with download URLs and SHA-256 checksums:

| Model | Size | Quantization | Use Case |
|-------|------|-------------|----------|
| Llama 3.2 1B Instruct | 668 MB | Q4_K_M | General chat, instruction following |
| Phi 3.5 Mini Instruct | 2.3 GB | Q4_K_M | Reasoning, longer context |
| Gemma 2 2B Instruct | 1.6 GB | Q4_K_M | General purpose |
| TinyLlama 1.1B Chat | 669 MB | Q4_K_M | Lightweight, fast inference |
| SmolVLM2 500M | 417 MB | Q8_0 | Vision / image description |

Any GGUF model compatible with llama.cpp can be loaded by file path.

---

## SDK API Surface

### Core

| Method | Description |
|--------|-------------|
| `EdgeVeda.init()` | Load model with config (threads, context length, GPU) |
| `EdgeVeda.generate()` | Blocking text generation |
| `EdgeVeda.generateStream()` | Streaming token-by-token with `CancelToken` |
| `EdgeVeda.initVision()` | Load VLM + mmproj for image inference |
| `EdgeVeda.describeImage()` | Generate text description from RGB bytes |
| `EdgeVeda.getMemoryStats()` | Current RSS, peak, available memory |
| `EdgeVeda.dispose()` | Free all native resources |

### Chat Session

| Method | Description |
|--------|-------------|
| `ChatSession.send()` | Send message, get complete response |
| `ChatSession.sendStream()` | Send message, stream response tokens |
| `ChatSession.reset()` | Clear history, keep model loaded |
| `ChatSession.messages` | Read-only conversation history |
| `ChatSession.turnCount` | Number of user turns |
| `ChatSession.contextUsage` | Estimated context window usage (0.0–1.0) |

Context overflow triggers automatic summarization at 70% capacity — older messages are condensed by the model, keeping the last 2 turns intact.

### Model Management

| Method | Description |
|--------|-------------|
| `ModelManager.downloadModel()` | Download with progress stream |
| `ModelManager.isModelDownloaded()` | Check if cached locally |
| `ModelManager.deleteModel()` | Remove from device storage |
| `ModelManager.verifyModelChecksum()` | SHA-256 verification |

### Production Runtime

| Class | Purpose |
|-------|---------|
| `VisionWorker` | Persistent isolate for vision inference (model loads once) |
| `FrameQueue` | Drop-newest backpressure for camera frames |
| `TelemetryService` | iOS thermal, battery, memory polling |
| `RuntimePolicy` | QoS adaptation with hysteresis |
| `PerfTrace` | JSONL performance trace logger |

---

## Project Structure

```
edge-veda/
├── core/
│   ├── include/edge_veda.h      # C API (37 functions)
│   ├── src/engine.cpp           # Text inference
│   ├── src/vision_engine.cpp    # Vision inference
│   ├── src/memory_guard.cpp     # Memory monitoring
│   └── third_party/llama.cpp/   # llama.cpp b7952 (submodule)
├── flutter/
│   ├── lib/                     # Dart SDK (18 files, ~6,200 LOC)
│   ├── ios/                     # Podspec + XCFramework
│   ├── android/                 # Android plugin (scaffolded)
│   ├── example/                 # Demo app (7 files, ~3,900 LOC)
│   └── test/                    # Unit tests
├── scripts/
│   └── build-ios.sh             # XCFramework build pipeline
└── TECHNICAL_AUDIT.md           # Full technical audit
```

Total: ~14,700 LOC across 32 source files.

---

## Building

### Prerequisites

- macOS with Xcode 15+ (Xcode 26 tested)
- Flutter 3.16+
- CMake 3.21+

### Build XCFramework

```bash
./scripts/build-ios.sh --clean --release
```

This compiles llama.cpp + Edge Veda C code for device (arm64) and simulator (arm64), merges 7 static libraries into a single XCFramework.

### Run Demo App

```bash
cd flutter/example
flutter run
```

The demo app includes Chat (multi-turn with ChatSession), Vision (continuous camera scanning), Settings (model management, device info), and a Soak Test screen for automated benchmarking.

---

## Platform Status

| Platform | GPU | Status |
|----------|-----|--------|
| iOS (device) | Metal | Validated on iPhone, iOS 26.2 |
| iOS (simulator) | CPU | Working (Metal stubs) |
| Android | CPU | Scaffolded, APK not yet validated |
| Android (Vulkan) | Vulkan | Planned |

---

## North Star

Ship a production-quality SDK that lets any Flutter developer add private, on-device AI to their app in under 10 lines of code — text and vision, iOS and Android, no server required.

**Near-term:**
- Validate Android CPU build and ship APK
- Add Vulkan GPU acceleration for Android
- Publish to pub.dev with full documentation

**Medium-term:**
- Speech-to-text (Whisper) and text-to-speech integration
- Background inference support
- Model fine-tuning and LoRA adapters

---

## Technical Audit

See [TECHNICAL_AUDIT.md](TECHNICAL_AUDIT.md) for a comprehensive review of the codebase — architecture, API surfaces, performance data, dependencies, and known limitations.

---

## License

[Apache 2.0](LICENSE)

## Acknowledgments

Built on [llama.cpp](https://github.com/ggml-org/llama.cpp) by Georgi Gerganov and contributors.
