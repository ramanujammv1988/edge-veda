# Feature Landscape: On-Device LLM Inference SDK

**Domain:** Flutter SDK for on-device LLM inference (iOS first)
**Researched:** 2026-02-04
**Confidence:** MEDIUM (based on training data + existing codebase analysis; WebSearch unavailable for verification)

## Executive Summary

On-device LLM inference SDKs exist in a nascent space. The major players (llama.cpp, MediaPipe LLM Inference, MLC-LLM) establish baseline expectations but Flutter-specific solutions are rare. Edge Veda's existing API design already covers most table stakes features. The key insight: **simplicity IS the differentiator** in this space - most existing solutions require complex setup.

---

## Table Stakes

Features users absolutely expect. Missing any of these = SDK is not production-ready.

### 1. Basic Text Generation

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **`generate(prompt) -> text`** | Core value proposition | Medium | Already designed in EdgeVeda API |
| **System prompt support** | Required for persona/behavior control | Low | Standard LLM feature |
| **Max tokens limit** | Prevent runaway generation | Low | Already in GenerateOptions |
| **Model loading** | Must load GGUF models | High | llama.cpp integration |

**v1 MVP:** All of these are non-negotiable.

### 2. Configuration

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Thread count control** | Performance tuning for device | Low | Already in EdgeVedaConfig |
| **Context length setting** | Memory/quality tradeoff | Low | Already designed (default 2048) |
| **GPU toggle** | Enable/disable Metal acceleration | Low | Already designed (useGpu flag) |
| **Memory limit** | Prevent OOM crashes | Medium | Critical for mobile - already designed |

**v1 MVP:** All present in current design.

### 3. Sampling Parameters

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Temperature** | Control randomness | Low | Already in GenerateOptions |
| **Top-p (nucleus)** | Standard sampling control | Low | Already designed |
| **Top-k** | Standard sampling control | Low | Already designed |
| **Repeat penalty** | Prevent loops | Low | Already designed |

**v1 MVP:** All present. These are standard llama.cpp parameters.

### 4. Model Management

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Download from URL** | Models are large (500MB-2GB) | Medium | Already in ModelManager |
| **Download progress** | UX requirement for large files | Low | Already designed |
| **Local caching** | Don't re-download | Low | Already designed |
| **Checksum verification** | Security/integrity | Medium | Already designed |

**v1 MVP:** All present in ModelManager design.

### 5. Resource Management

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Memory usage tracking** | Debug/monitoring | Low | getMemoryUsage() designed |
| **Proper cleanup (dispose)** | Prevent memory leaks | Medium | dispose() designed |
| **One instance per session** | Resource constraint | Low | Documented best practice |

**v1 MVP:** All present.

### 6. Error Handling

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **Typed exceptions** | Dart idioms | Low | Full hierarchy designed |
| **Initialization errors** | Know when setup fails | Low | InitializationException |
| **Generation errors** | Know when inference fails | Low | GenerationException |
| **Model load errors** | Know when model is bad | Low | ModelLoadException |

**v1 MVP:** All present in types.dart.

---

## Differentiators

Features that could set Edge Veda apart. Not expected, but valued if present.

### Tier 1: High Value, Achievable

| Feature | Value Proposition | Complexity | Recommendation |
|---------|-------------------|------------|----------------|
| **Zero-config default model** | "npm install and run" experience | Low | v1 stretch: Auto-download Llama 3.2 1B if no path specified |
| **JSON mode** | Structured output for apps | Medium | Already designed - implement in v1 if time allows |
| **Model registry** | Curated list of tested models | Low | Already designed in ModelRegistry |
| **Performance metrics** | tokens/sec in response | Low | Already designed in GenerateResponse |

### Tier 2: High Value, Defer to v2

| Feature | Value Proposition | Complexity | Recommendation |
|---------|-------------------|------------|----------------|
| **Streaming responses** | Real-time UX | High | Defer to v2 - prove basic works first |
| **Stop stream mid-generation** | User control | Medium | Comes with streaming |
| **Multi-turn chat history** | Conversational context | Medium | Defer - requires context management |
| **Conversation memory** | Automatic context window | High | Defer - complex KV cache management |

### Tier 3: Nice to Have, Future

| Feature | Value Proposition | Complexity | Recommendation |
|---------|-------------------|------------|----------------|
| **Stop sequences** | Fine-grained control | Low | Already designed but low priority |
| **Token counting API** | Dev tools | Low | Already designed |
| **Model info API** | Dev tools | Low | Already designed |
| **Benchmarking mode** | Performance validation | Medium | Future |
| **Headless/CI mode** | Automated testing | Medium | Future |

---

## Anti-Features

Features to deliberately NOT build in v1. Common mistakes in this domain.

### 1. Premature Abstraction

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Universal model format support** | GGUF is sufficient; ONNX/TFLite add complexity | Support GGUF only (llama.cpp native format) |
| **Backend abstraction layer** | Different backends have different APIs | Start with Metal-only, add abstraction when needed |
| **Plugin architecture** | Over-engineering for v1 | Monolithic is fine until proven otherwise |

### 2. Premature Optimization

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Speculative decoding** | Complex, marginal gains | Focus on basic inference first |
| **KV cache persistence** | Complex state management | Accept cold start cost initially |
| **Model sharding** | 1B models fit in memory | Not needed for target model size |
| **Batched inference** | Mobile is single-user | One request at a time is fine |

### 3. Scope Creep

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Built-in chat UI** | SDK should be headless | Provide examples, not components |
| **Cloud fallback** | Violates "on-device" promise | Fail clearly if device can't run model |
| **Analytics/telemetry** | Privacy concerns, scope creep | Let apps implement their own |
| **OTA model updates** | Control plane scope | Defer to dedicated milestone |
| **Multi-model routing** | Over-engineering | One model at a time |

### 4. Platform Overreach

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| **Android in v1** | Validate iOS first | Explicit v2 milestone |
| **Web/WASM in v1** | Different architecture entirely | Separate milestone |
| **Desktop in v1** | Mobile-first validation | Future milestone |

---

## Feature Dependencies

```
Model Loading (REQUIRED FIRST)
    |
    v
Basic Generate (text in -> text out)
    |
    +---> GPU Acceleration (Metal)
    |         |
    |         v
    |     Performance Optimization
    |
    +---> JSON Mode (structured output)
    |
    +---> [v2] Streaming
              |
              v
          Stop Stream
              |
              v
          Multi-turn Chat
              |
              v
          Conversation Memory
```

**Critical path for v1:** Model Loading -> Basic Generate -> GPU Acceleration

---

## Comparison to Existing Solutions

### llama.cpp (C++ library)

| Aspect | llama.cpp | Edge Veda Target |
|--------|-----------|------------------|
| **Language** | C/C++ | Dart (Flutter) |
| **Setup complexity** | High (build from source) | Low (pub.dev package) |
| **Mobile support** | Manual FFI work | Built-in |
| **Streaming** | Yes | v2 |
| **Model format** | GGUF | GGUF (via llama.cpp) |

**Edge Veda advantage:** Developer experience. llama.cpp is powerful but requires C++ expertise.

### MediaPipe LLM Inference (Google)

| Aspect | MediaPipe | Edge Veda Target |
|--------|-----------|------------------|
| **Platforms** | iOS, Android, Web | iOS (v1), Android (v2) |
| **Flutter support** | Limited/indirect | Native |
| **Model format** | TFLite, custom | GGUF |
| **Models** | Gemma, Phi, Falcon | Any GGUF (Llama, etc.) |
| **API style** | Callback-heavy | Async/await native |

**Edge Veda advantage:** Flutter-native API, broader model support via GGUF.

### MLC-LLM

| Aspect | MLC-LLM | Edge Veda Target |
|--------|---------|------------------|
| **Compilation** | Requires model compilation | Pre-quantized GGUF |
| **Setup** | Complex toolchain | Simple pub.dev |
| **Performance** | Highly optimized | Good (llama.cpp) |
| **Model flexibility** | Any model (with work) | Any GGUF model |

**Edge Veda advantage:** No compilation step. Download and run.

---

## MVP Feature Checklist for v1

### Must Have (blocking release)

- [ ] Load GGUF model from path
- [ ] `generate(prompt)` returns text
- [ ] System prompt support
- [ ] Max tokens limit
- [ ] Temperature/top-p/top-k sampling
- [ ] Metal GPU acceleration (iOS)
- [ ] Memory usage tracking
- [ ] Proper dispose/cleanup
- [ ] Download model from URL
- [ ] Download progress reporting
- [ ] Checksum verification
- [ ] Typed exception hierarchy

### Should Have (include if time)

- [ ] JSON mode for structured output
- [ ] Model registry with pre-configured models
- [ ] Performance metrics (tokens/sec) in response
- [ ] Verbose logging mode

### Could Have (stretch goals)

- [ ] Zero-config with default model auto-download
- [ ] Token counting API

### Won't Have (explicit v2+)

- [ ] Streaming responses
- [ ] Multi-turn chat
- [ ] Android support
- [ ] Stop sequences (low value)
- [ ] Any cloud features

---

## Implications for Roadmap

### Phase Structure Recommendation

1. **Core Inference** - Model loading + basic generate
   - Critical path, highest risk
   - llama.cpp integration is the key technical challenge

2. **GPU Acceleration** - Metal backend
   - Required for acceptable performance
   - Depends on core inference working

3. **Model Management** - Download, cache, verify
   - High polish area for DX
   - Can be done in parallel with GPU work

4. **Polish & Release** - Error handling, logging, docs
   - Already designed, just needs implementation validation
   - pub.dev publication

### Risk Areas Requiring Deeper Research

| Area | Risk | Mitigation |
|------|------|------------|
| llama.cpp FFI | Memory management across Dart/C++ boundary | Phase-specific research on Dart FFI patterns |
| Metal integration | llama.cpp Metal backend stability on iOS | Test early, have CPU fallback |
| Model download | Large file handling, resume support | Test on slow networks early |

---

## Sources

**HIGH confidence (codebase analysis):**
- `/Users/ram/Documents/explore/edge/flutter/doc/API.md` - Existing API design
- `/Users/ram/Documents/explore/edge/flutter/lib/src/types.dart` - Type definitions
- `/Users/ram/Documents/explore/edge/flutter/lib/src/edge_veda_impl.dart` - Implementation skeleton
- `/Users/ram/Documents/explore/edge/flutter/lib/src/model_manager.dart` - Model management
- `/Users/ram/Documents/explore/edge/prd.txt` - Product requirements

**MEDIUM confidence (training data, unverified):**
- llama.cpp feature set and API patterns
- MediaPipe LLM Inference capabilities
- MLC-LLM architecture approach
- General on-device ML SDK patterns

**Note:** WebSearch was unavailable during this research. Competitor analysis based on training data (cutoff: January 2025). Verify current state of competitors before finalizing decisions.
