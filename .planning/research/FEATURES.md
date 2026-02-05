# Feature Landscape: v1.1 Android + Streaming

**Project:** Edge Veda SDK - Flutter On-Device LLM Inference
**Milestone:** v1.1 (Android + Streaming)
**Researched:** 2026-02-04
**Confidence:** HIGH (verified via official docs and multiple sources)

---

## Executive Summary

v1.1 adds two major capabilities to Edge Veda: Android platform support with Vulkan GPU acceleration and streaming token-by-token responses. These features are now table stakes - users trained by ChatGPT/Claude expect real-time streaming, and Android represents the largest mobile platform.

**Key insight:** Streaming is no longer optional - "users see tokens appear in real-time, creating the illusion of instant response even when generation takes just as long" (industry consensus). The perceived latency drops from seconds to milliseconds.

---

## Streaming Features

### Table Stakes

Features users expect from any LLM streaming implementation. Missing = product feels broken.

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|--------------|------------|--------------|-------|
| **Token-by-token emission** | ChatGPT/Claude trained users to expect real-time text appearance | Medium | Long-lived isolate | Core streaming UX baseline |
| **Cancel/abort generation** | Users must be able to stop generation mid-stream | Medium | CancelToken integration | "Stop generating" is mandatory |
| **Consistent token cadence** | Bursty token delivery feels janky; steady flow expected | Low | Native callback timing | Avoid dumping multiple tokens at once |
| **TTFT < 500ms** | Time-to-first-token under 500ms feels responsive | High | GPU acceleration | PRD target: <500ms TTFT |
| **Stream completion signal** | Clear indication when generation is done | Low | isFinal flag in TokenChunk | Existing TokenChunk.isFinal supports this |
| **Error propagation in stream** | Errors during generation must surface to UI | Medium | Stream error handling | StreamController.addError() pattern |
| **Pause/resume subscription** | Dart Stream contract requires pause behavior | Medium | Stream backpressure | async* generator auto-pauses at yield |

### Differentiators

Features that set the SDK apart. Not strictly required, but add significant value.

| Feature | Value Proposition | Complexity | Dependencies | Notes |
|---------|-------------------|------------|--------------|-------|
| **Token count in stream** | Emit running token count during generation | Low | Native token counter | Useful for quota/limit tracking |
| **Generation metrics at completion** | Return full GenerateResponse at stream end | Medium | Wrap stream with completion | tok/sec, prompt tokens, completion tokens |
| **Coalesced token batching** | Batch 2-3 tokens per UI update for performance | Low | Configurable buffer | Prevents render-every-token overhead |
| **Memory pressure events during stream** | Emit warnings if approaching limits | High | Long-lived isolate memory monitoring | Proactive user notification |
| **Intertoken latency reporting** | Report ITL for performance debugging | Low | Timestamp each token | Developer-facing metric |

### Anti-Features

Features to deliberately NOT build. Common mistakes in streaming implementations.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Render every single token** | Causes UI jank, excessive rebuilds | Coalesce into small batches (2-3 tokens) |
| **WebSocket-style bidirectional streaming** | Unnecessary complexity for on-device inference | Simple async* generator is sufficient |
| **Automatic retry on error** | Users expect control over when to retry | Expose error, let caller decide retry |
| **Progress percentage** | Streaming length is unpredictable; percentage is misleading | Show token count instead |
| **Background streaming service** | Adds Android Foreground Service complexity, battery drain | Keep inference foreground-only |
| **Custom binary framing** | Over-engineering; native callbacks are direct | Use native callback directly via FFI |

---

## Android Features

### Table Stakes

Features users expect on Android. Missing = platform feels incomplete.

| Feature | Why Expected | Complexity | Dependencies | Notes |
|---------|--------------|------------|--------------|-------|
| **GPU acceleration via Vulkan** | Essential for acceptable performance on Android | High | llama.cpp Vulkan backend | Vulkan officially supported on Android, unlike OpenCL |
| **API 24+ support** | Android 7.0+ covers ~95% of devices | Medium | NDK toolchain config | PROJECT.md constraint |
| **Model caching in app directory** | Parity with iOS implementation | Low | Platform-appropriate path | Use getExternalFilesDir or equivalent |
| **Background kill recovery** | Android LMK will kill memory-heavy apps | Medium | State restoration | Reload model gracefully after kill |
| **Memory pressure response** | onTrimMemory() callback compliance | Medium | Platform channel | Reduce memory or unload model proactively |
| **Mid-range device support** | Galaxy A54/Pixel 6a must work, not just flagships | High | Memory optimization | Test on 6GB RAM devices, not just 12GB |
| **ARM64 (arm64-v8a) target** | Primary Android architecture | Low | CMake config | x86_64 for emulator nice-to-have |

### Differentiators

Features that give Android implementation competitive advantage.

| Feature | Value Proposition | Complexity | Dependencies | Notes |
|---------|-------------------|------------|--------------|-------|
| **Thermal throttling awareness** | Reduce inference speed before device overheats | High | Platform APIs | Battery/thermal monitoring |
| **NPU fallback exploration** | Qualcomm Hexagon NPU offers 10x GPU speedup | Very High | LiteRT/MediaPipe | Future consideration, not v1.1 |
| **Dynamic layer offloading** | Adjust GPU layers based on available memory | Medium | Runtime memory checks | Start conservative, increase if headroom |
| **Download resume on network change** | Resume model download after connectivity restored | Medium | HTTP range requests | Existing download progress infrastructure |
| **ProGuard/R8 compatibility** | Minification must not break FFI | Low | Keep rules | Test release builds |

### Anti-Features

Features to deliberately NOT build for Android.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **OpenCL GPU backend** | OpenCL banned on Android 7.0+; not future-proof | Use Vulkan exclusively |
| **Foreground Service for inference** | Battery drain complaints; complexity | Keep inference activity-bound |
| **Background model downloads** | WorkManager complexity, battery impact | Foreground download with progress UI |
| **Multi-GPU support** | Android devices have single GPU | Single GPU path only |
| **x86 (32-bit) support** | Negligible device share, maintenance burden | arm64-v8a only (x86_64 for emulator) |
| **Persistent in-memory model** | Will get killed by LMK anyway | Accept reload cost; optimize reload time |
| **Custom Vulkan shaders** | llama.cpp handles this; maintenance nightmare | Use llama.cpp Vulkan backend as-is |

---

## Cross-Platform Considerations

Features that affect both iOS and Android implementations.

### API Parity Requirements

| Capability | iOS v1.0 Status | Android v1.1 Requirement | Notes |
|------------|-----------------|--------------------------|-------|
| `generate(prompt)` | Implemented | Must match | Text-in/text-out core |
| `generateStream(prompt)` | Not implemented | New for both | v1.1 feature |
| `init(config)` | Implemented | Must match | Same config structure |
| `dispose()` | Implemented | Must match | Cleanup pattern |
| `getMemoryStats()` | Implemented | Must match | Memory monitoring |
| `isMemoryPressure()` | Implemented | Must match | Quick pressure check |
| Model download | Implemented | Must match | Same ModelManager |
| CancelToken | Defined, unused | Must work for streaming | Cancel generation |

### Streaming API Design

Based on Dart Stream best practices and existing SDK patterns:

```dart
// Table stakes API shape
Stream<TokenChunk> generateStream(
  String prompt, {
  GenerateOptions? options,
  CancelToken? cancelToken,
});

// TokenChunk already defined in types.dart:
// - token: String (the text content)
// - index: int (position in sequence)
// - isFinal: bool (completion signal)
```

**Key implementation decisions:**

| Decision | Rationale | Source |
|----------|-----------|--------|
| Use `async*` generator | Single-subscription by default, auto-pause at yield | Dart official docs |
| Long-lived worker isolate | Required for persistent native context + streaming callbacks | Current iOS impl notes |
| SendPort/ReceivePort | Bidirectional communication with worker isolate | Dart isolate pattern |
| CancelToken checks at yield | Clean cancellation without orphaned resources | Existing CancelToken type |

### Memory Management Differences

| Aspect | iOS | Android | Implication |
|--------|-----|---------|-------------|
| Kill mechanism | Jetsam (memory pressure levels) | LMK (oom_adj_score) | Different thresholds |
| Memory budget | 1.2GB per PRD | 1.2GB per PRD | Same target |
| Pressure callback | iOS memory warnings | onTrimMemory() | Platform-specific handling |
| Typical device RAM | 6-8GB (iPhone 15) | 6-12GB (varies widely) | Android needs more caution |
| Background behavior | Suspended, then killed | Killed more aggressively | Android needs faster recovery |

### Shared Infrastructure

Components that work for both platforms:

| Component | Reusability | Notes |
|-----------|-------------|-------|
| ModelManager | 100% shared | Download, cache, checksum |
| Types/exceptions | 100% shared | All in types.dart |
| EdgeVedaConfig | 100% shared | Platform-agnostic config |
| GenerateOptions | 100% shared | Sampling parameters |
| TokenChunk | 100% shared | Streaming response type |
| CancelToken | 100% shared | Cancellation mechanism |
| FFI bindings | Partial | Same C API, different build artifacts |

---

## Feature Dependencies

```
Android Support
    |
    +-- NDK Build Infrastructure
    |       |
    |       +-- Vulkan backend enabled
    |       +-- ARM64 target
    |
    +-- Platform-specific memory handling
    |       |
    |       +-- onTrimMemory() integration
    |       +-- LMK-aware thresholds
    |
    +-- Model caching path
            |
            +-- Platform channel for directory

Streaming Support
    |
    +-- Long-lived Worker Isolate
    |       |
    |       +-- SendPort/ReceivePort setup
    |       +-- Persistent native context
    |
    +-- Token callback from native
    |       |
    |       +-- C callback function
    |       +-- FFI callback registration
    |
    +-- CancelToken integration
    |       |
    |       +-- Check at each token
    |       +-- Clean resource teardown
    |
    +-- Stream API surface
            |
            +-- async* generator
            +-- Error propagation
```

---

## MVP Recommendation for v1.1

### Must Have (Table Stakes)

For v1.1 to feel complete:

1. **Android Vulkan inference** - Core platform support
2. **generateStream(prompt)** - Streaming API on both platforms
3. **Cancel generation** - CancelToken for abort
4. **Memory pressure handling** - Platform-appropriate responses
5. **API parity** - Same Dart API surface on both platforms

### Should Have (Differentiators)

For v1.1 to feel polished:

1. **Generation metrics at stream end** - Full response stats
2. **Token count in stream** - Running count
3. **Mid-range device testing** - Galaxy A54, Pixel 6a validation

### Defer to Post-v1.1

1. **Thermal throttling awareness** - Complex, device-specific
2. **NPU exploration** - Requires different framework (LiteRT)
3. **Memory pressure events during stream** - Nice-to-have optimization

---

## Performance Benchmarks

### Key Metrics to Track

| Metric | Target | Why It Matters |
|--------|--------|----------------|
| **TTFT (Time to First Token)** | <500ms | User perceives response as immediate |
| **ITL (Inter-Token Latency)** | <100ms | Smooth streaming experience |
| **TPS (Tokens Per Second)** | >15 tok/s | PRD requirement |
| **Memory Peak** | <1.2GB | Device stability |

### Device Tier Testing Matrix

| Tier | Example Devices | RAM | Expected Performance |
|------|-----------------|-----|---------------------|
| **Flagship** | Pixel 8 Pro, S24 Ultra | 12GB | Full speed, all layers on GPU |
| **Mid-range** | Pixel 6a, Galaxy A54 | 6GB | Reduced layers, acceptable speed |
| **Budget** | Older 4GB devices | 4GB | May need CPU-only fallback |

---

## Historical Context (v1.0 Features)

These features are already implemented for iOS and need Android parity:

### Already Shipped (iOS v1.0)

- Load GGUF model from path
- `generate(prompt)` returns complete text
- System prompt support
- Temperature/top-p/top-k sampling
- Model download with progress
- Model caching with checksum
- Memory pressure handling (1.2GB limit)
- Typed exception hierarchy
- Metal GPU acceleration

### Not Yet Implemented (v1.1 Scope)

- `generateStream(prompt)` yields tokens
- Android Vulkan GPU backend
- Android-specific memory management
- Cancel token for aborting generation
- Long-lived worker isolate pattern

---

## Sources

### Streaming UX and Patterns
- [Dart Stream API Documentation](https://api.flutter.dev/flutter/dart-async/Stream-class.html) - Stream semantics and contracts
- [Creating Streams in Dart](https://dart.dev/libraries/async/creating-streams) - async* generator patterns
- [Streaming LLM Responses Guide](https://dataa.dev/2025/02/18/streaming-llm-responses-building-real-time-ai-applications/) - UX patterns and benchmarks
- [SSE for LLM Streaming 2025](https://procedure.tech/blogs/the-streaming-backbone-of-llms-why-server-sent-events-(sse)-still-wins-in-2025) - Protocol comparison
- [Chrome AI Streaming Docs](https://developer.chrome.com/docs/ai/streaming) - How LLMs stream responses

### Android LLM Inference
- [llama.cpp Android Documentation](https://github.com/ggml-org/llama.cpp/blob/master/docs/android.md) - Official NDK build guide
- [Building AI Mobile Apps 2025](https://medium.com/@stepan_plotytsia/building-ai-powered-mobile-apps-running-on-device-llms-in-android-and-flutter-2025-guide-0b440c0ae08b) - Flutter/Android LLM guide
- [GPT4All Vulkan Support](https://www.nomic.ai/blog/posts/gpt4all-gpu-inference-with-vulkan) - Vulkan for cross-platform GPU
- [Android LMK Documentation](https://developer.android.com/topic/performance/vitals/lmk) - Memory killer behavior
- [MediaPipe LLM Inference](https://ai.google.dev/edge/mediapipe/solutions/genai/llm_inference/android) - Google's on-device approach

### Vulkan vs OpenCL
- [GPGPU and Vulkan Compute Analysis](https://www.lei.chat/posts/gpgpu-ml-inference-and-vulkan-compute/) - Why Vulkan for ML inference
- [VComputeBench Research](https://d-nb.info/1192370589/34) - Vulkan 1.59x speedup over OpenCL on mobile

### Performance Metrics
- [TTFT Explained](https://www.emergentmind.com/topics/time-to-first-token-ttft) - Time to first token importance
- [LLM Inference Metrics](https://bentoml.com/llm/inference-optimization/llm-inference-metrics) - Key benchmarking metrics
