# Edge-Veda

**A managed on-device AI runtime for Flutter — text, vision, speech, and RAG running sustainably on real phones under real constraints. Private by default.**

`~21,300 LOC | 40 C API functions | 31 Dart SDK files | 0 cloud dependencies`

[![Version](https://img.shields.io/badge/version-2.0.0-blue)](https://github.com/ramanujammv1988/edge-veda)
[![Platform](https://img.shields.io/badge/platform-iOS-lightgrey)](https://github.com/ramanujammv1988/edge-veda)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

---

## Why Edge-Veda Exists

Modern on-device AI demos break instantly in real usage:

- Thermal throttling collapses throughput
- Memory spikes cause silent crashes
- Sessions longer than ~60 seconds become unstable
- Developers have no visibility into runtime behavior
- Debugging failures is nearly impossible

Edge-Veda exists to make on-device AI **predictable, observable, and sustainable** — not just runnable.

---

## What Edge-Veda Is

Edge-Veda is a **supervised on-device AI runtime** that:

- Runs **text, vision, and speech models fully on device**
- Keeps models **alive across long sessions**
- Adapts automatically to **thermal, memory, and battery pressure**
- Applies **runtime policies** instead of crashing
- Provides **structured observability** for debugging and analysis
- Supports **structured output, function calling, embeddings, and RAG**
- Is **private by default** (no network calls during inference)

---

## What Makes Edge-Veda Different

Edge-Veda is designed for **behavior over time**, not benchmark bursts.

- A long-lived runtime with persistent workers
- A system that supervises AI under physical device limits
- A runtime that degrades gracefully instead of failing
- An observable, debuggable on-device AI layer
- A complete on-device AI stack: inference, speech, tools, and retrieval

---

## Current Capabilities

### Core Inference
- Persistent **text and vision inference workers** (models load once, stay in memory)
- **Streaming token generation** with pull-based architecture
- Multi-turn **chat session management** with auto-summarization at context overflow
- Chat templates: Llama 3 Instruct, ChatML, Qwen3/Hermes, generic

### Speech-to-Text
- **On-device speech recognition** via whisper.cpp (Metal GPU accelerated)
- Real-time streaming transcription in 3-second chunks
- 48kHz native audio capture with automatic downsampling to 16kHz
- WhisperWorker isolate for non-blocking transcription
- ~670ms per chunk on iPhone with Metal GPU (whisper-tiny.en, 77MB)

### Structured Output & Function Calling
- **GBNF grammar-constrained generation** for structured JSON output
- **Tool/function calling** with ToolDefinition, ToolRegistry, and schema validation
- Multi-round tool chains with configurable max rounds
- `sendWithTools()` for automatic tool call/result cycling
- `sendStructured()` for grammar-constrained generation

### Embeddings & RAG
- **Text embeddings** via ev_embed() with L2 normalization
- **Per-token confidence scoring** from softmax entropy
- **Cloud handoff signal** when average confidence drops below threshold
- **VectorIndex** — pure Dart HNSW with cosine similarity and JSON persistence
- **RagPipeline** — end-to-end embed, search, inject, generate

### Runtime Supervision
- **Compute budget contracts** — declare p95 latency, battery drain, thermal, and memory ceilings
- **Adaptive budget profiles** — auto-calibrate to measured device performance
- **Central scheduler** arbitrates concurrent workloads with priority-based degradation
- **Thermal, memory, and battery-aware runtime policy** with hysteresis
- Backpressure-controlled frame processing (drop-newest, not queue-forever)
- Structured **performance tracing** (JSONL) with offline analysis tooling
- Long-session stability validated on-device (12+ minutes, 0 crashes, 0 model reloads)

---

## Architecture

```
Flutter App (Dart)
    |
    +-- ChatSession ---------- Chat templates, context summarization, tool calling
    +-- WhisperSession ------- Streaming STT with 3s audio chunks
    +-- RagPipeline ---------- Embed → search → inject → generate
    +-- VectorIndex ---------- HNSW-backed vector search with persistence
    |
    +-- EdgeVeda ------------- generate(), generateStream(), embed(), describeImage()
    |
    +-- StreamingWorker ------ Persistent isolate, keeps text model loaded
    +-- VisionWorker --------- Persistent isolate, keeps VLM loaded (~600MB)
    +-- WhisperWorker -------- Persistent isolate, keeps whisper model loaded
    |
    +-- Scheduler ------------ Central budget enforcer, priority-based degradation
    +-- EdgeVedaBudget ------- Declarative constraints (p95, battery, thermal, memory)
    +-- RuntimePolicy -------- Thermal/battery/memory QoS with hysteresis
    +-- TelemetryService ----- iOS thermal, battery, memory polling
    +-- FrameQueue ----------- Drop-newest backpressure for camera frames
    +-- PerfTrace ------------ JSONL flight recorder for offline analysis
    |
    +-- FFI Bindings --------- 40 C functions via DynamicLibrary.process()
         |
    XCFramework (libedge_veda_full.a)
    +-- engine.cpp ----------- Text inference + embeddings + confidence (wraps llama.cpp)
    +-- vision_engine.cpp ---- Vision inference (wraps libmtmd)
    +-- whisper_engine.cpp --- Speech-to-text (wraps whisper.cpp)
    +-- memory_guard.cpp ----- Cross-platform RSS monitoring, pressure callbacks
    +-- llama.cpp b7952 ------ Metal GPU, ARM NEON, GGUF models (unmodified)
    +-- whisper.cpp v1.8.3 --- Metal GPU, shared ggml backend (unmodified)
```

**Key design constraint:** Dart FFI is synchronous — calling llama.cpp directly would freeze the UI. All inference runs in background isolates. Native pointers never cross isolate boundaries. Workers maintain persistent contexts so models load once and stay in memory across the entire session.

---

## Quick Start

### Installation

```yaml
# pubspec.yaml
dependencies:
  edge_veda: ^2.0.0
```

### Text Generation

```dart
final edgeVeda = EdgeVeda();

await edgeVeda.init(EdgeVedaConfig(
  modelPath: modelPath,
  contextLength: 2048,
  useGpu: true,
));

// Streaming
await for (final chunk in edgeVeda.generateStream('Explain recursion briefly')) {
  stdout.write(chunk.token);
}

// Blocking
final response = await edgeVeda.generate('Hello from on-device AI');
print(response.text);
```

### Multi-Turn Conversation

```dart
final session = ChatSession(
  edgeVeda: edgeVeda,
  preset: SystemPromptPreset.coder,
);

await for (final chunk in session.sendStream('Write hello world in Python')) {
  stdout.write(chunk.token);
}

// Model remembers the conversation
await for (final chunk in session.sendStream('Now convert it to Rust')) {
  stdout.write(chunk.token);
}

print('Turns: ${session.turnCount}');
print('Context: ${(session.contextUsage * 100).toInt()}%');
```

### Function Calling

```dart
final tools = ToolRegistry([
  ToolDefinition(
    name: 'get_time',
    description: 'Get the current time',
    parameters: {
      'type': 'object',
      'properties': {
        'timezone': {'type': 'string', 'enum': ['UTC', 'EST', 'PST']},
      },
      'required': ['timezone'],
    },
  ),
]);

final session = ChatSession(
  edgeVeda: edgeVeda,
  tools: tools,
  templateFormat: ChatTemplateFormat.qwen3,
);

final response = await session.sendWithTools(
  'What time is it in UTC?',
  onToolCall: (call) async {
    if (call.name == 'get_time') {
      return ToolResult.success(
        toolCallId: call.id,
        data: {'time': DateTime.now().toIso8601String()},
      );
    }
    return ToolResult.failure(toolCallId: call.id, error: 'Unknown tool');
  },
);
```

### Speech-to-Text

```dart
final session = WhisperSession(modelPath: whisperModelPath);
await session.start();

// Listen for transcription segments
session.onSegment.listen((segment) {
  print('[${segment.startMs}ms] ${segment.text}');
});

// Feed audio from microphone
final audioSub = WhisperSession.microphone().listen((samples) {
  session.feedAudio(samples);
});

// Stop and get full transcript
await session.flush();
await session.stop();
print(session.transcript);
```

### Embeddings & RAG

```dart
// Generate embeddings
final result = await edgeVeda.embed('On-device AI is the future');
print('Dimensions: ${result.embedding.length}');

// Build a vector index
final index = VectorIndex(dimensions: result.embedding.length);
index.add('doc1', result.embedding, metadata: {'source': 'readme'});
await index.save('/path/to/index.json');

// RAG pipeline
final rag = RagPipeline(
  edgeVeda: edgeVeda,
  index: index,
  config: RagConfig(topK: 3),
);
final answer = await rag.query('What is Edge-Veda?');
print(answer.text);
```

### Continuous Vision Inference

```dart
final visionWorker = VisionWorker();
await visionWorker.spawn();
await visionWorker.initVision(
  modelPath: vlmModelPath,
  mmprojPath: mmprojPath,
  numThreads: 4,
  contextSize: 2048,
  useGpu: true,
);

// Process camera frames — model stays loaded across all calls
final result = await visionWorker.describeFrame(
  rgbBytes, width, height,
  prompt: 'Describe what you see.',
  maxTokens: 100,
);
print(result.description);
```

---

## Runtime Supervision

Edge-Veda continuously monitors:

- Device thermal state (nominal / fair / serious / critical)
- Available memory (`os_proc_available_memory`)
- Battery level and Low Power Mode

Based on these signals, it dynamically adjusts:

| QoS Level | FPS | Resolution | Tokens | Trigger |
|-----------|-----|------------|--------|---------|
| Full | 2 | 640px | 100 | No pressure |
| Reduced | 1 | 480px | 75 | Thermal warning, battery <15%, memory <200MB |
| Minimal | 1 | 320px | 50 | Thermal serious, battery <5%, memory <100MB |
| Paused | 0 | -- | 0 | Thermal critical, memory <50MB |

**Escalation is immediate.** Thermal spikes are dangerous and must be responded to without delay.

**Restoration requires cooldown** (60s per level) and happens one level at a time. Full recovery from paused to full takes 3 minutes. This prevents oscillation where the system rapidly alternates between high and low quality.

---

## Compute Budget Contracts

Declare runtime guarantees. The Scheduler enforces them.

```dart
// Option 1: Adaptive — auto-calibrates to this device's actual performance
final scheduler = Scheduler(telemetry: TelemetryService());
scheduler.setBudget(EdgeVedaBudget.adaptive(BudgetProfile.balanced));

// Option 2: Static — explicit values
scheduler.setBudget(const EdgeVedaBudget(
  p95LatencyMs: 3000,
  batteryDrainPerTenMinutes: 5.0,
  maxThermalLevel: 2,
));

// Register workloads with priorities
scheduler.registerWorkload(WorkloadId.vision, priority: WorkloadPriority.high);
scheduler.registerWorkload(WorkloadId.text, priority: WorkloadPriority.low);
scheduler.registerWorkload(WorkloadId.stt, priority: WorkloadPriority.low);
scheduler.start();

// React to violations
scheduler.onBudgetViolation.listen((v) {
  print('${v.constraint}: ${v.currentValue} > ${v.budgetValue}');
});
```

**Adaptive profiles** resolve against measured device performance after warm-up:

| Profile | p95 Multiplier | Battery | Thermal | Use Case |
|---------|---------------|---------|---------|----------|
| Conservative | 2.0x | 0.6x (strict) | Floor 1 | Background workloads |
| Balanced | 1.5x | 1.0x (match) | Floor 2 | Default for most apps |
| Performance | 1.1x | 1.5x (generous) | Allow 3 | Latency-sensitive apps |

---

## Performance

### Vision (Soak Test — iPhone, Metal GPU)

| Metric | Value |
|--------|-------|
| Sustained runtime | 12.6 minutes |
| Frames processed | 254 |
| p50 latency | 1,412 ms |
| p95 latency | 2,283 ms |
| p99 latency | 2,597 ms |
| Model reloads | 0 |
| Crashes | 0 |
| Memory stability | No growth over session |

### Speech-to-Text (iPhone, Metal GPU, whisper-tiny.en)

| Metric | Value |
|--------|-------|
| Model size | 77 MB |
| Chunk size | 3 seconds (48,000 samples at 16kHz) |
| Transcription latency (p50) | ~670 ms per chunk |
| First chunk latency | ~2,200 ms (includes Metal shader compilation) |
| Audio capture format | 48kHz native, downsampled to 16kHz mono |
| Streaming | Real-time, segments emitted as processed |

### Observability

Built-in performance flight recorder writes per-frame JSONL traces:

- Per-stage timing (image encode / prompt eval / decode)
- Runtime policy transitions (QoS level changes)
- Frame drop statistics
- Memory and thermal telemetry

Traces are analyzed offline using `tools/analyze_trace.py` (p50/p95/p99 stats, throughput charts, thermal overlays).

---

## Supported Models

Pre-configured in `ModelRegistry` with download URLs and SHA-256 checksums:

| Model | Size | Type | Use Case |
|-------|------|------|----------|
| Llama 3.2 1B Instruct | 668 MB | Text (Q4_K_M) | General chat, instruction following |
| Phi 3.5 Mini Instruct | 2.3 GB | Text (Q4_K_M) | Reasoning, longer context |
| Gemma 2 2B Instruct | 1.6 GB | Text (Q4_K_M) | General purpose |
| TinyLlama 1.1B Chat | 669 MB | Text (Q4_K_M) | Lightweight, fast inference |
| SmolVLM2 500M | 417 MB + 190 MB | Vision (Q8_0 + F16) | Image description |
| Whisper Tiny English | 77 MB | Speech (F16) | Speech-to-text transcription |

Any GGUF model compatible with llama.cpp can be loaded by file path.

---

## Platform Status

| Platform | GPU | Status |
|----------|-----|--------|
| iOS (device) | Metal | Fully validated on-device |
| iOS (simulator) | CPU | Working (Metal stubs, no mic) |
| Android | CPU | Scaffolded, validation pending |
| Android (Vulkan) | -- | Planned |

---

## Project Structure

```
edge-veda/
+-- core/
|   +-- include/edge_veda.h       C API (40 functions, 846 LOC)
|   +-- src/engine.cpp            Text inference + embeddings (1,173 LOC)
|   +-- src/vision_engine.cpp     Vision inference (484 LOC)
|   +-- src/whisper_engine.cpp    Speech-to-text (290 LOC)
|   +-- src/memory_guard.cpp      Memory monitoring (625 LOC)
|   +-- third_party/llama.cpp/    llama.cpp b7952 (git submodule)
|   +-- third_party/whisper.cpp/  whisper.cpp v1.8.3 (git submodule)
+-- flutter/
|   +-- lib/                      Dart SDK (31 files, 10,590 LOC)
|   +-- ios/                      Podspec + XCFramework
|   +-- android/                  Android plugin (scaffolded)
|   +-- example/                  Demo app (8 files, 5,153 LOC)
|   +-- test/                     Unit tests (253 LOC, 14 tests)
+-- scripts/
|   +-- build-ios.sh              XCFramework build pipeline (406 LOC)
+-- tools/
|   +-- analyze_trace.py          Soak test JSONL analysis (1,797 LOC)
```

---

## Building

### Prerequisites

- macOS with Xcode 15+ (tested with Xcode 26.1)
- Flutter 3.16+ (tested with 3.38.9)
- CMake 3.21+

### Build XCFramework

```bash
./scripts/build-ios.sh --clean --release
```

Compiles llama.cpp + whisper.cpp + Edge Veda C code for device (arm64) and simulator (arm64), merges static libraries into a single XCFramework.

### Run Demo App

```bash
cd flutter/example
flutter run
```

The demo app includes Chat (multi-turn with tool calling), Vision (continuous camera scanning), STT (live microphone transcription), and Settings (model management, device info).

---

## Roadmap (Directional)

- Android sustained runtime validation (CPU + Vulkan GPU)
- Long-horizon memory management
- Semantic perception APIs (event-driven vision)
- Observability dashboard (localhost trace viewer)
- Text-to-speech integration
- Embedding model registry and on-device RAG demo

---

## Who This Is For

Edge-Veda is designed for teams building:

- On-device AI assistants
- Continuous perception apps
- Privacy-sensitive AI systems
- Long-running edge agents
- Voice-first applications
- Regulated or offline-first applications

---

## Contributing

Contributions are welcome. Here's how to get started:

### Areas of Interest

- **Platform validation** — Android CPU/Vulkan testing on real devices
- **Runtime policy** — New QoS strategies, thermal adaptation improvements
- **Trace analysis** — Visualization tools, anomaly detection, regression tracking
- **Model support** — Testing additional GGUF models, quantization profiles
- **Example apps** — Minimal examples for specific use cases (document scanner, voice assistant, visual QA)

### Development Workflow

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/your-feature`)
3. Make changes and verify with `dart analyze` (SDK) and `flutter analyze` (demo app)
4. Run tests: `cd flutter && flutter test`
5. Commit with descriptive messages
6. Open a Pull Request with a summary of what changed and why

### Code Standards

- Dart: follow standard `dart format` conventions
- C++: match existing style in `core/src/`
- All FFI calls must run in isolates (never on main thread)
- New C API functions must be added to the podspec symbol whitelist

---

## License

[Apache 2.0](LICENSE)

---

Built on [llama.cpp](https://github.com/ggml-org/llama.cpp) and [whisper.cpp](https://github.com/ggerganov/whisper.cpp) by Georgi Gerganov and contributors.
