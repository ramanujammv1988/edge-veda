# Requirements: Edge Veda SDK v1.1

**Milestone:** v1.1 - Android Support + Streaming Responses
**Target:** Developers can run Llama 3.2 1B on iOS and Android with streaming token output

---

## Success Criteria

1. **Cross-platform inference:** `generate(prompt)` works on both iOS and Android
2. **Streaming output:** `generateStream(prompt)` yields tokens in real-time
3. **Acceptable Android performance:** >10 tokens/sec on Pixel 6a with Vulkan
4. **Stable Android memory:** No LMK kills on 6GB devices
5. **Cancel support:** User can abort generation mid-stream

---

## v1.0 Requirements (Validated)

These requirements shipped in v1.0 and are now validated:

| ID | Requirement | Status |
|----|-------------|--------|
| R1.1 | Load GGUF model from file path | Complete |
| R1.2 | Generate text from prompt | Complete |
| R1.3 | System prompt support | Complete |
| R1.4 | Configurable max tokens | Complete |
| R1.5 | Sampling parameters (temp, top-p, top-k) | Complete |
| R2.1-R2.4 | Model download, progress, caching, checksum | Complete |
| R3.1-R3.3 | Memory tracking, cleanup, iOS pressure handling | Complete |
| R4.1-R4.4 | Typed exceptions, clear messages | Complete |
| R5.1-R5.3 | Metal GPU, performance, CPU fallback | Complete |

---

## v1.1 Functional Requirements

### R6: Streaming Inference (Must Have)

| ID | Requirement | Acceptance Criteria |
|----|-------------|---------------------|
| R6.1 | Token-by-token streaming | `generateStream(prompt)` yields tokens as generated |
| R6.2 | Stream completion signal | TokenChunk.isFinal is true on last token |
| R6.3 | Cancel generation mid-stream | CancelToken aborts generation, stream closes cleanly |
| R6.4 | Error propagation in stream | Errors during generation surface via stream error |
| R6.5 | Generation metrics at stream end | Final TokenChunk includes tok/sec, token counts |

### R7: Android Platform Support (Must Have)

| ID | Requirement | Acceptance Criteria |
|----|-------------|---------------------|
| R7.1 | Android API 24+ compatibility | SDK works on Android 7.0+ devices |
| R7.2 | Vulkan GPU acceleration | GPU layers used when Vulkan available |
| R7.3 | CPU fallback on Android | Works (slower) if Vulkan unavailable |
| R7.4 | Android memory pressure handling | SDK responds to onTrimMemory() callbacks |
| R7.5 | Android model caching | Models cached in app-appropriate directory |
| R7.6 | Background kill recovery | Model reloads gracefully after LMK kill |

### R8: Cross-Platform Parity (Must Have)

| ID | Requirement | Acceptance Criteria |
|----|-------------|---------------------|
| R8.1 | Same Dart API on both platforms | EdgeVeda API identical on iOS and Android |
| R8.2 | Streaming works on both platforms | generateStream() works on iOS and Android |
| R8.3 | Same exception types | All exceptions consistent across platforms |

---

## Non-Functional Requirements

### Performance

| Metric | iOS Target | Android Target | Measurement |
|--------|------------|----------------|-------------|
| Token generation | >10 tok/sec | >10 tok/sec | Llama 3.2 1B Q4_K_M |
| Time to first token | <500ms | <500ms | From generateStream() to first token |
| Model load time | <5 seconds | <5 seconds | From create() to ready state |
| Memory ceiling | <1.2 GB | <1.0 GB | Android more conservative |

### Compatibility

| Requirement | iOS | Android |
|-------------|-----|---------|
| OS version | 15.0+ | API 24+ (7.0+) |
| Flutter version | 3.16.0+ | 3.16.0+ |
| Dart version | 3.1.0+ | 3.1.0+ |
| Architectures | arm64 | arm64-v8a |

### Binary Size

| Component | iOS Target | Android Target |
|-----------|------------|----------------|
| Native library | <15 MB | <20 MB |
| Total plugin overhead | <20 MB | <25 MB |

---

## Out of Scope (v1.1)

These are explicitly NOT in v1.1:

- **Multi-turn chat history** - Deferred to v1.2
- **Stop sequences** - Low priority
- **Token counting API** - Nice to have
- **Multiple simultaneous models** - Not needed
- **Background inference** - Platform restrictions
- **x86/x86_64 Android** - arm64-v8a only for v1.1
- **OpenCL backend** - Vulkan + CPU sufficient
- **Thermal throttling awareness** - Complex, defer
- **NPU exploration** - Requires different framework

---

## Constraints

### Technical Constraints

1. **llama.cpp dependency:** Must use llama.cpp b4658 (pinned for stability)
2. **GGUF only:** Only GGUF model format supported
3. **Foreground only:** Inference runs in foreground on both platforms
4. **Single instance:** One EdgeVeda instance at a time per app
5. **NativeCallable.listener:** Required for streaming callbacks (Dart 3.1+)

### Resource Constraints

| Platform | Memory Budget | Warning Threshold |
|----------|---------------|-------------------|
| iOS | 1.2 GB | 900 MB |
| Android | 1.0 GB | 800 MB |

### Build Constraints

1. **Android NDK:** r27c LTS (avoid r28+ 16KB page issues)
2. **Vulkan:** 1.1+ with VK_USE_PLATFORM_ANDROID_KHR
3. **CMake flags:** GGML_VULKAN=ON, GGML_OPENMP=OFF, GGML_LLAMAFILE=OFF

---

## Dependencies

### New Dependencies for v1.1

| Dependency | Version | Purpose |
|------------|---------|---------|
| Android NDK | r27c | Native Android build |
| Vulkan SDK | 1.1+ | GPU acceleration |

### Existing Dependencies (from v1.0)

| Dependency | Version | Purpose |
|------------|---------|---------|
| llama.cpp | b4658 | Inference engine |
| Flutter ffi | ^2.1.0 | Native bindings |
| path_provider | ^2.1.0 | File system paths |
| http | ^1.2.0 | Model download |
| crypto | ^3.0.3 | SHA256 checksum |

---

## Validation Plan

### Unit Tests
- Streaming callback correctness
- Cancel token behavior
- Cross-platform FFI binding tests

### Integration Tests
- Full streaming pipeline (iOS + Android)
- Memory pressure response on both platforms
- Model caching on Android

### Device Tests (Manual)

**iOS:**
- iPhone 12 (4GB RAM) - Streaming performance baseline
- iPhone 13 Pro (6GB RAM) - Performance target

**Android:**
- Pixel 6a (6GB RAM) - Mid-range baseline
- Galaxy A54 (6GB RAM) - Samsung validation
- Pixel 8 Pro (12GB RAM) - Flagship performance

### Acceptance Tests
- Demo app: User types prompt -> sees tokens stream in real-time
- Cancel: User taps stop -> generation aborts cleanly
- Performance: >10 tok/sec on Pixel 6a logged in console
- Memory: No crashes after 10 consecutive streaming generations

---

## Traceability

### Requirement to Phase (Roadmap Mapping)

| Requirement | Phase | Status |
|-------------|-------|--------|
| R6.1 | Phase 6 | Pending |
| R6.2 | Phase 6 | Pending |
| R6.3 | Phase 6 | Pending |
| R6.4 | Phase 6 | Pending |
| R6.5 | Phase 7 | Pending |
| R7.1 | Phase 5 | Pending |
| R7.2 | Phase 7 | Pending |
| R7.3 | Phase 5 | Pending |
| R7.4 | Phase 5 | Pending |
| R7.5 | Phase 5 | Pending |
| R7.6 | Phase 5 | Pending |
| R8.1 | Phase 7 | Pending |
| R8.2 | Phase 7 | Pending |
| R8.3 | Phase 6 | Pending |

**Coverage:** 14/14 v1.1 requirements mapped (100%)

### Phase Summary

| Phase | Requirements | Count |
|-------|--------------|-------|
| Phase 5: Android CPU Build | R7.1, R7.3, R7.4, R7.5, R7.6 | 5 |
| Phase 6: Streaming C++ + Dart | R6.1, R6.2, R6.3, R6.4, R8.3 | 5 |
| Phase 7: Android Vulkan + Demo | R6.5, R7.2, R8.1, R8.2 | 4 |
| **Total** | | **14** |

---

*Requirements defined: 2026-02-04*
*Traceability updated: 2026-02-05*
*Based on research: STACK_v1.1.md, FEATURES.md, ARCHITECTURE.md, PITFALLS.md*
