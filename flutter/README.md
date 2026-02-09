# Edge-Veda

**A managed on-device AI runtime for Flutter that keeps text and vision models running sustainably on real phones under real constraints — private by default.**

`~15,900 LOC | 31 C API functions | 21 Dart SDK files | 0 cloud dependencies`

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

- Runs **text and vision models fully on device**
- Keeps models **alive across long sessions**
- Enforces **compute budget contracts** (p95 latency, battery, thermal, memory)
- **Auto-calibrates** to each device's actual performance via adaptive profiles
- Adapts automatically to **thermal, memory, and battery pressure**
- Applies **runtime policies** instead of crashing
- Provides **structured observability** for debugging and analysis
- Is **private by default** (no network calls during inference)

---

## Installation

```yaml
dependencies:
  edge_veda: ^1.2.0
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

// Clean up when done
await visionWorker.dispose();
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
    +-- ChatSession ---------- Chat templates, context summarization, system presets
    |
    +-- EdgeVeda ------------- generate(), generateStream(), describeImage()
    |
    +-- StreamingWorker ------ Persistent isolate, keeps text model loaded
    +-- VisionWorker --------- Persistent isolate, keeps VLM loaded (~600MB)
    |
    +-- Scheduler ------------ Central budget enforcer, priority-based degradation
    +-- EdgeVedaBudget ------- Declarative constraints (p95, battery, thermal, memory)
    +-- RuntimePolicy -------- Thermal/battery/memory QoS with hysteresis
    +-- TelemetryService ----- iOS thermal, battery, memory polling
    +-- FrameQueue ----------- Drop-newest backpressure for camera frames
    +-- PerfTrace ------------ JSONL flight recorder for offline analysis
    |
    +-- FFI Bindings --------- 31 C functions via DynamicLibrary.process()
         |
    XCFramework (libedge_veda_full.a, ~15MB)
    +-- engine.cpp ----------- Text inference (wraps llama.cpp)
    +-- vision_engine.cpp ---- Vision inference (wraps libmtmd)
    +-- memory_guard.cpp ----- Cross-platform RSS monitoring, pressure callbacks
    +-- llama.cpp b7952 ------ Metal GPU, ARM NEON, GGUF models (unmodified)
```

**Key design constraint:** Dart FFI is synchronous — calling llama.cpp directly would freeze the UI. All inference runs in background isolates. Native pointers never cross isolate boundaries. The `StreamingWorker` and `VisionWorker` maintain persistent contexts so models load once and stay in memory across the entire session.

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

## Performance (Vision Soak Test)

Validated on physical iPhone, continuous vision inference:

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
| Thermal handling | Graceful pause and resume |

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

Built on [llama.cpp](https://github.com/ggml-org/llama.cpp) by Georgi Gerganov and contributors.
