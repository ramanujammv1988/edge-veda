# Edge-Veda

**A managed on-device AI runtime for Flutter — text generation, vision, speech-to-text, embeddings, RAG, and function calling, all running locally with zero cloud dependencies.**

`~22,700 LOC | 40 C API functions | 32 Dart SDK files | 0 cloud dependencies`

[![pub package](https://img.shields.io/pub/v/edge_veda.svg)](https://pub.dev/packages/edge_veda)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://github.com/ramanujammv1988/edge-veda/blob/main/LICENSE)

---

## Why Edge-Veda Exists

Modern on-device AI demos break instantly in real usage:

- Thermal throttling collapses throughput
- Memory spikes cause silent crashes
- Sessions longer than ~60 seconds become unstable
- Developers have no visibility into runtime behavior

Edge-Veda exists to make on-device AI **predictable, observable, and sustainable** — not just runnable.

---

## What Edge-Veda Is

A **supervised on-device AI runtime** that:

- Runs **text, vision, speech, and embedding models fully on device**
- Keeps models **alive across long sessions** via persistent worker isolates
- Enforces **compute budget contracts** (p95 latency, battery, thermal, memory)
- **Auto-calibrates** to each device's actual performance via adaptive profiles
- Provides **structured output and function calling** for agent-style apps
- Enables **on-device RAG** with embeddings, vector search, and retrieval-augmented generation
- Detects **model uncertainty** via confidence scoring and signals cloud handoff
- Is **private by default** (no network calls during inference)

---

## Installation

```yaml
dependencies:
  edge_veda: ^2.1.0
```

---

## Text Generation

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

## Multi-Turn Conversation

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

// Start fresh (model stays loaded)
session.reset();
```

## Function Calling

```dart
final tools = [
  ToolDefinition(
    name: 'get_weather',
    description: 'Get current weather for a city',
    parameters: {
      'type': 'object',
      'properties': {
        'city': {'type': 'string', 'description': 'City name'},
      },
      'required': ['city'],
    },
  ),
];

// Model selects and invokes tools, multi-round chains
final response = await session.sendWithTools(
  'What\'s the weather in Tokyo?',
  tools: tools,
  toolHandler: (call) async {
    // Execute the tool and return result
    return ToolResult.success(call.id, {'temp': '22°C', 'condition': 'Sunny'});
  },
);
```

## Structured JSON Output

```dart
// Grammar-constrained generation ensures valid JSON
final result = await session.sendStructured(
  'Extract the person\'s name and age from: "John is 30 years old"',
  schema: {
    'type': 'object',
    'properties': {
      'name': {'type': 'string'},
      'age': {'type': 'integer'},
    },
    'required': ['name', 'age'],
  },
);
// result is guaranteed-valid JSON matching the schema
```

## Speech-to-Text (Whisper)

```dart
final whisperWorker = WhisperWorker();
await whisperWorker.spawn();
await whisperWorker.initWhisper(
  modelPath: whisperModelPath,
  numThreads: 4,
);

// Streaming transcription from microphone
final whisperSession = WhisperSession(worker: whisperWorker);
whisperSession.transcriptionStream.listen((segments) {
  for (final segment in segments) {
    print(segment.text);
  }
});

// Feed audio chunks (16kHz mono Float32)
whisperSession.addAudioChunk(audioData);

await whisperWorker.dispose();
```

## Continuous Vision Inference

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

await visionWorker.dispose();
```

## Text Embeddings

```dart
// Generate embeddings with any GGUF embedding model
final result = await edgeVeda.embed('The quick brown fox');
print('Dimensions: ${result.dimensions}');
print('Vector: ${result.embedding.take(5)}...');
```

## Confidence Scoring & Cloud Handoff

```dart
// Enable confidence tracking — zero overhead when disabled
final response = await edgeVeda.generate(
  'Explain quantum computing',
  options: GenerateOptions(confidenceThreshold: 0.3),
);

print('Confidence: ${response.avgConfidence}');

if (response.needsCloudHandoff) {
  // Model is uncertain — route to cloud API
  print('Low confidence, falling back to cloud');
}
```

## On-Device RAG

```dart
// 1. Build a knowledge base
final index = VectorIndex(dimensions: 768);
final docs = ['Flutter is a UI framework', 'Dart is a language', ...];

for (final doc in docs) {
  final emb = await edgeVeda.embed(doc);
  index.add(doc, emb.embedding, metadata: {'source': 'docs'});
}

// Save index to disk
await index.save(indexPath);

// 2. Query with RAG pipeline
final rag = RagPipeline(
  edgeVeda: edgeVeda,
  index: index,
  config: RagConfig(topK: 3, minScore: 0.5),
);

final answer = await rag.query('What is Flutter?');
print(answer.text);  // Answer grounded in your documents
```

## Compute Budget Contracts

Declare runtime guarantees. The Scheduler enforces them.

```dart
final scheduler = Scheduler(telemetry: TelemetryService());

// Auto-calibrates to this device's actual performance
scheduler.setBudget(EdgeVedaBudget.adaptive(BudgetProfile.balanced));
scheduler.registerWorkload(WorkloadId.vision, priority: WorkloadPriority.high);
scheduler.start();

// React to violations
scheduler.onBudgetViolation.listen((v) {
  print('${v.constraint}: ${v.currentValue} > ${v.budgetValue}');
});

// After warm-up (~40s), inspect measured baseline
final baseline = scheduler.measuredBaseline;
final resolved = scheduler.resolvedBudget;
```

| Profile | p95 Multiplier | Battery | Thermal | Use Case |
|---------|---------------|---------|---------|----------|
| Conservative | 2.0x | 0.6x (strict) | Floor 1 | Background workloads |
| Balanced | 1.5x | 1.0x (match) | Floor 2 | Default for most apps |
| Performance | 1.1x | 1.5x (generous) | Allow 3 | Latency-sensitive apps |

---

## Architecture

```
Flutter App (Dart)
    |
    +-- ChatSession ---------- Chat templates, context summarization, tool calling
    |
    +-- EdgeVeda ------------- generate(), generateStream(), embed()
    |
    +-- StreamingWorker ------ Persistent isolate, keeps text model loaded
    +-- VisionWorker --------- Persistent isolate, keeps VLM loaded (~600MB)
    +-- WhisperWorker -------- Persistent isolate, keeps Whisper model loaded
    |
    +-- RagPipeline ---------- embed → search → inject context → generate
    +-- VectorIndex ---------- Pure Dart HNSW vector search (local_hnsw)
    |
    +-- Scheduler ------------ Central budget enforcer, priority-based degradation
    +-- EdgeVedaBudget ------- Declarative constraints (p95, battery, thermal, memory)
    +-- RuntimePolicy -------- Thermal/battery/memory QoS with hysteresis
    +-- TelemetryService ----- iOS thermal, battery, memory polling
    +-- FrameQueue ----------- Drop-newest backpressure for camera frames
    +-- PerfTrace ------------ JSONL flight recorder for offline analysis
    |
    +-- FFI Bindings --------- 43 C functions via DynamicLibrary.process()
         |
    XCFramework (libedge_veda_full.a, ~8MB)
    +-- engine.cpp ----------- Text inference + embeddings + confidence (wraps llama.cpp)
    +-- vision_engine.cpp ---- Vision inference (wraps libmtmd)
    +-- whisper_engine.cpp --- Speech-to-text (wraps whisper.cpp)
    +-- memory_guard.cpp ----- Cross-platform RSS monitoring, pressure callbacks
    +-- llama.cpp b7952 ------ Metal GPU, ARM NEON, GGUF models (unmodified)
    +-- whisper.cpp v1.8.3 --- Shared ggml with llama.cpp (unmodified)
```

**Key design constraint:** Dart FFI is synchronous — calling native code directly would freeze the UI. All inference runs in background isolates. Native pointers never cross isolate boundaries. The `StreamingWorker`, `VisionWorker`, and `WhisperWorker` maintain persistent contexts so models load once and stay in memory across the entire session.

---

## Runtime Supervision

Edge-Veda continuously monitors device thermal state, available memory, and battery level, then dynamically adjusts quality of service:

| QoS Level | FPS | Resolution | Tokens | Trigger |
|-----------|-----|------------|--------|---------|
| Full | 2 | 640px | 100 | No pressure |
| Reduced | 1 | 480px | 75 | Thermal warning, battery <15%, memory <200MB |
| Minimal | 1 | 320px | 50 | Thermal serious, battery <5%, memory <100MB |
| Paused | 0 | -- | 0 | Thermal critical, memory <50MB |

Escalation is immediate. Restoration requires cooldown (60s per level) to prevent oscillation.

---

## Smart Model Advisor

Device-aware model recommendations with 4D scoring:

```dart
final device = await DeviceProfile.detect();
final recommendations = ModelAdvisor.recommend(device, UseCase.chat);

for (final rec in recommendations) {
  print('${rec.model.name}: ${rec.score}/100 (${rec.fit})');
  // Llama 3.2 1B: 82/100 (comfortable)
  // Qwen3 0.6B: 78/100 (comfortable)
  // Phi 3.5 Mini: 45/100 (tight)
}

// Quick fit check before download
if (ModelAdvisor.canRun(model, device)) {
  final config = rec.optimalConfig; // Pre-tuned EdgeVedaConfig
}
```

- **DeviceProfile** detects iPhone model, RAM, chip, tier (low/medium/high/ultra)
- **MemoryEstimator** predicts total memory per model+context with calibrated formulas
- **ModelAdvisor** scores 0–100 across fit, quality, speed, and context dimensions
- Each recommendation includes optimal `EdgeVedaConfig` for the model+device pair

---

## Performance

All numbers measured on a physical iPhone (A16 Bionic, 6 GB RAM, iOS 26.2.1) with Metal GPU. Release mode, LTO enabled. See [BENCHMARKS.md](https://github.com/ramanujammv1988/edge-veda/blob/main/BENCHMARKS.md) for full details.

### Text Generation

| Metric | Value |
|--------|-------|
| Throughput | 42–43 tok/s |
| TTFT | <500 ms |
| Steady-state memory | 400–550 MB |
| Multi-turn stability | No degradation over 10+ turns |

### RAG (Retrieval-Augmented Generation)

| Metric | Value |
|--------|-------|
| Generation speed | 42–43 tok/s |
| Vector search | <1 ms |
| End-to-end retrieval | 305–865 ms |

### Vision (Soak Test)

| Metric | Value |
|--------|-------|
| Sustained runtime | 12.6 minutes |
| Frames processed | 254 |
| p50 / p95 / p99 latency | 1,412 / 2,283 / 2,597 ms |
| Crashes / model reloads | 0 / 0 |

### Speech-to-Text

| Metric | Value |
|--------|-------|
| Transcription latency (p50) | ~670 ms per 3s chunk |
| Model size | 77 MB (whisper-tiny.en) |
| Streaming | Real-time segments |

### Memory Optimization

| Metric | Before | After |
|--------|--------|-------|
| KV cache | ~64 MB (F16) | ~32 MB (Q8_0) |
| Steady-state memory | ~1,200 MB peak | 400–550 MB |

---

## Supported Models

Pre-configured in `ModelRegistry` with download URLs and SHA-256 checksums:

| Model | Size | Template | Capabilities | Best For |
|-------|------|----------|-------------|----------|
| Llama 3.2 1B Instruct | 668 MB | `llama3Instruct` | chat, reasoning | General chat (default) |
| Phi 3.5 Mini Instruct | 2.3 GB | `chatML` | chat, reasoning | Quality reasoning |
| Gemma 2 2B Instruct | 1.6 GB | `generic` | chat | Balanced quality/speed |
| TinyLlama 1.1B Chat | 669 MB | `generic` | chat | Speed-first, low memory |
| Qwen3 0.6B | 397 MB | `qwen3` | chat, tool-calling | Function calling, tools |
| SmolVLM2 500M | 607 MB | — | vision | Camera/image analysis |
| Whisper Tiny | 77 MB | — | stt | Fast transcription |
| Whisper Base | 148 MB | — | stt | Quality transcription |
| MiniLM L6 v2 | 46 MB | — | embedding | RAG, similarity search |

### Template Selection

Using the wrong `ChatTemplateFormat` produces garbage output. Match the model to its template:

```dart
// Llama 3.x models
final session = ChatSession(edgeVeda: ev, templateFormat: ChatTemplateFormat.llama3Instruct);

// Qwen3 with tool calling
final session = ChatSession(edgeVeda: ev, templateFormat: ChatTemplateFormat.qwen3);

// Phi 3.5 models
final session = ChatSession(edgeVeda: ev, templateFormat: ChatTemplateFormat.chatML);

// Gemma, TinyLlama, or unknown models
final session = ChatSession(edgeVeda: ev, templateFormat: ChatTemplateFormat.generic);
```

Any GGUF model compatible with llama.cpp or whisper.cpp can be loaded by file path.

---

## Platform Status

| Platform | GPU | Status |
|----------|-----|--------|
| iOS (device) | Metal | Fully validated on-device |
| iOS (simulator) | CPU | Working (Metal stubs) |
| Android | CPU | Scaffolded, validation pending |

---

## Documentation

- [Full README and source](https://github.com/ramanujammv1988/edge-veda)
- [API Reference](https://pub.dev/documentation/edge_veda/latest/)
- [Example App](https://github.com/ramanujammv1988/edge-veda/tree/main/flutter/example)

---

## License

[Apache 2.0](https://github.com/ramanujammv1988/edge-veda/blob/main/LICENSE)

Built on [llama.cpp](https://github.com/ggml-org/llama.cpp) and [whisper.cpp](https://github.com/ggml-org/whisper.cpp) by Georgi Gerganov and contributors.
