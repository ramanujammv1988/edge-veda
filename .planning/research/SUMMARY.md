# Research Summary: Edge Veda v1.1 Android + Streaming

**Project:** Edge Veda SDK - Flutter On-Device LLM Inference
**Domain:** Mobile Native LLM Inference with Android NDK, Vulkan GPU, and Streaming Responses
**Researched:** 2026-02-04
**Confidence:** HIGH

## Executive Summary

v1.1 extends Edge Veda from iOS-only to cross-platform by adding Android support with Vulkan GPU acceleration and implementing token-by-token streaming responses. This milestone addresses two critical user expectations: platform parity (Android represents 70%+ mobile market share) and real-time streaming (users trained by ChatGPT expect tokens to appear immediately).

The recommended approach builds Android support with **CPU-first strategy** - get a stable CPU-only build working before enabling Vulkan, which has known reliability issues on mobile GPUs (Adreno crashes, Mali slowness). For streaming, the current `Isolate.run()` pattern must be refactored to a **long-lived worker isolate** using SendPort/ReceivePort communication - this is the most significant architectural change. The C++ streaming API already exists but is unimplemented; bridging it to Dart requires `NativeCallable.listener` for thread-safe callbacks.

Key risks include Android's Low Memory Killer (LMK) behaving differently than iOS jetsam (requires conservative 800MB limit vs iOS 1.2GB), Vulkan driver inconsistencies across GPU vendors, and threading complexity with FFI callbacks from native inference threads. Mitigation strategies: implement runtime GPU fallback, start with NDK r27c + llama.cpp b4658 (known working combination), and use token batching to prevent callback deadlocks.

## Key Findings

### Recommended Stack

Edge Veda v1.1 builds on the existing v1.0 iOS stack (llama.cpp b4658, Metal GPU, Flutter FFI) by adding Android-specific components. The critical constraint is NDK r27c LTS - newer versions (r28+) enable 16KB page alignment by default which breaks compatibility with older devices. Vulkan is officially supported but unreliable in practice.

**Core technologies:**
- **Android NDK r27c LTS** - Stable NDK with Vulkan 1.3 headers bundled; r28+ causes breaking 16KB page issues
- **Vulkan 1.1+ with CPU fallback** - GPU acceleration on Android, but default to CPU runtime due to driver issues (Adreno crashes, Mali slowness)
- **NativeCallable.listener (Dart 3.1+)** - Thread-safe FFI callbacks for streaming tokens from native inference thread
- **Long-lived worker isolate** - Persistent SendPort/ReceivePort pattern replaces v1.0's one-shot Isolate.run()
- **llama.cpp b4658 (pinned)** - Existing version works; newer commits have Android-specific regressions

**Android-specific additions:**
- CMake flags: `GGML_VULKAN=ON`, `VK_USE_PLATFORM_ANDROID_KHR=ON`, `ANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON`
- Disable incompatible features: `GGML_OPENMP=OFF`, `GGML_LLAMAFILE=OFF`
- Build for `arm64-v8a` only in v1.1 (90%+ device coverage, avoids binary bloat)

**Streaming-specific additions:**
- C++ streaming state machine: `ev_stream_impl` manages token-by-token generation
- Dart SDK constraint bump: `>=3.1.0` for `NativeCallable.listener`
- Cancellation mechanism: Atomic flag checked in generation loop (callbacks cannot return values)

### Expected Features

v1.1 delivers Android platform parity and streaming capabilities on both iOS and Android. Streaming is table stakes - users see ChatGPT/Claude emit tokens in real-time and expect the same from any LLM interface.

**Must have (table stakes):**
- **Token-by-token streaming** - Core streaming UX baseline; users expect real-time text appearance
- **Cancel generation mid-stream** - "Stop generating" button is mandatory UX pattern
- **Android Vulkan GPU support** - Essential for acceptable performance (with CPU fallback)
- **API 24+ compatibility** - Android 7.0+ covers ~95% of active devices
- **Memory pressure handling on Android** - Respond to `onTrimMemory()` callbacks to avoid LMK kills
- **Cross-platform API parity** - Same Dart API surface on both iOS and Android

**Should have (differentiators):**
- **Generation metrics at stream end** - Return full `GenerateResponse` with tok/sec, token counts after streaming completes
- **Token count in stream** - Emit running count during generation for quota tracking
- **Mid-range device support** - Galaxy A54/Pixel 6a (6GB RAM) must work, not just flagships
- **Dynamic GPU layer offloading** - Adjust layers based on available memory at runtime

**Defer to v2+:**
- **Thermal throttling awareness** - Complex, device-specific; reduce speed before overheating
- **NPU exploration** - Qualcomm Hexagon NPU requires different framework (LiteRT/MediaPipe)
- **Coalesced token batching** - Batch 2-3 tokens per UI update to prevent render jank (performance optimization)
- **OpenCL backend for Adreno** - Alternative to Vulkan with better Qualcomm support but limits device coverage

### Architecture Approach

The v1.1 architecture extends the existing iOS pattern (Flutter -> FFI -> C++ -> llama.cpp -> Metal) by adding Android build path and refactoring the Dart side for streaming. The key insight: threading model is the critical path - Dart's `Isolate.run()` cannot maintain long-lived native context required for streaming.

**Major architectural changes:**

1. **Long-lived worker isolate (replaces Isolate.run)**
   - Main isolate spawns persistent worker isolate at `init()`
   - Worker maintains native `ev_context` pointer across multiple requests
   - SendPort/ReceivePort bidirectional communication (commands down, tokens up)
   - Worker loads `DynamicLibrary` once, reuses across streams

2. **C++ streaming state machine**
   - `ev_generate_stream()` - Tokenizes prompt, evaluates batch, creates sampler
   - `ev_stream_next()` - Generates one token, advances decode state, returns token text
   - `ev_stream_has_next()` - Checks if generation complete (EOS reached)
   - Stream cancellation via atomic flag (callbacks cannot return values)

3. **Android build infrastructure**
   - Gradle CMake integration already scaffolded in `flutter/android/build.gradle`
   - New script: `scripts/build-android.sh` mirrors `build-ios.sh` structure
   - Outputs: `libedge_veda.so` in `jniLibs/arm64-v8a/`
   - Vulkan shaders cross-compiled for Android target

**Data flow: Streaming generation**
```
[Main Isolate] --(SendPort: StreamMessage)--> [Worker Isolate]
                                                    |
                                                    v
                                            ev_generate_stream()
                                                    |
                                                    v
                                            while(has_next):
                                              ev_stream_next()
                                                    |
[Main Isolate] <--(SendPort: TokenChunk)-------    |
[Main Isolate] <--(SendPort: TokenChunk)-------    |
[Main Isolate] <--(SendPort: StreamDone)-------    v
```

### Critical Pitfalls

The research identified 15 pitfalls across build system, memory management, threading, and streaming domains. The top 5 most impactful:

1. **Android LMK differs from iOS jetsam** - Android's Low Memory Killer uses different heuristics (PSI + oom_adj_score vs iOS memory footprint). Your 1.2GB iOS limit may cause OOM kills on Android. **Prevention:** Start with 800MB limit, test on 4GB devices, monitor PSS not just raw allocation.

2. **Vulkan support incomplete on Android** - Unlike Metal (universal on iOS), Vulkan varies dramatically by GPU vendor. Adreno GPUs often slower than CPU, Mali drivers buggy on older devices. **Prevention:** Default to CPU backend, implement runtime capability detection, maintain device allowlist for Vulkan.

3. **Long-lived worker isolate required** - Current `Isolate.run()` pattern cannot support streaming (context dies when function returns). **Prevention:** Refactor to `Isolate.spawn()` with persistent worker, use SendPort for communication, plan adequate time for architectural change.

4. **Streaming callbacks crash with wrong API** - `Pointer.fromFunction` only works on main isolate mutator thread; crashes when called from native inference thread. **Prevention:** Use `NativeCallable.listener` exclusively for streaming callbacks, always call `callback.close()` to prevent isolate leak.

5. **Native library loading fails (dlopen)** - Common when `.so` missing or built for wrong architecture. **Prevention:** Build for `arm64-v8a`, verify library in APK (`unzip -l app.apk | grep libedge_veda`), test on physical arm64 device.

**Additional critical risks:**
- llama.cpp version compatibility - b4658 works; newer versions have Android regressions
- High-volume callbacks cause deadlocks - batch tokens every 16ms (~60fps) to prevent event loop overload
- Memory accounting differences - mmap pages loaded on-demand; pre-touch model pages or use `--no-mmap`

## Implications for Roadmap

v1.1 should be structured around two parallel but independent workstreams: **Android platform support** and **Streaming API**. Android is self-contained (build system only), while streaming touches both C++ and Dart layers. Building Android first validates the cross-compilation toolchain without adding streaming complexity.

### Suggested Phase Structure

```
Phase 1: Android CPU Build
    |
    +-- Validates NDK toolchain, library loading
    |
    v
Phase 2: Streaming C++ Implementation  <-- Can parallelize with Phase 1
    |
    +-- Implements ev_stream_* in engine.cpp
    |
    v
Phase 3: Dart Streaming Integration
    |
    +-- Refactor to long-lived worker isolate
    +-- Bridge C++ streaming to Dart Stream<String>
    |
    v
Phase 4: Android Vulkan + Demo Update
    |
    +-- GPU acceleration with runtime fallback
    +-- Update example app with streaming UI
```

### Phase 1: Android CPU Build
**Rationale:** Get stable Android foundation before GPU complexity. Validates build system, library loading, memory limits.

**Delivers:**
- `libedge_veda.so` building and loading on Android
- Existing `generate()` API works on Android (CPU backend)
- Memory pressure handling adapted for Android LMK

**Addresses:**
- Android platform support (table stakes)
- API 24+ compatibility
- Memory pressure handling on Android

**Avoids:**
- P1: Android LMK differences (determine memory limits early)
- P2: llama.cpp version compatibility (validate b4658 on Android)
- P4: Native library loading failures (verify dlopen before feature work)
- P7: NDK version mismatch (pin NDK r27c explicitly)

**Research flag:** Standard Android NDK build - well-documented patterns, skip phase research.

### Phase 2: Streaming C++ Implementation
**Rationale:** Implement streaming in C++ layer first (single-threaded, testable without Dart complexity). Can parallelize with Phase 1.

**Delivers:**
- `ev_generate_stream()`, `ev_stream_next()`, `ev_stream_cancel()` implemented
- Streaming works in C++ (can test with simple C++ harness)
- Token-by-token generation loop with sampler chain

**Uses:**
- llama.cpp streaming pattern (already exists in `examples/simple/simple.cpp`)
- Existing `ev_stream_impl` structure from `edge_veda.h`

**Implements:**
- C++ streaming state machine component
- Atomic cancellation flag pattern

**Avoids:**
- P12: Cancel token complexity (atomic flag prevents race conditions)

**Research flag:** Standard llama.cpp patterns - examples exist in codebase, skip phase research.

### Phase 3: Dart Streaming Integration
**Rationale:** Bridge C++ streaming to Dart. Requires architectural change to long-lived worker isolate. Most complex phase due to threading model shift.

**Delivers:**
- `Stream<TokenChunk> generateStream(prompt)` API
- Long-lived worker isolate pattern operational
- Cross-platform streaming (works on both iOS and Android)
- Cancel token integration

**Uses:**
- `NativeCallable.listener` for thread-safe callbacks
- SendPort/ReceivePort for worker communication
- Dart SDK >=3.1.0

**Implements:**
- Long-lived worker isolate architecture component
- FFI callback bridge from native to Dart

**Avoids:**
- P6: Long-lived worker isolate required (fundamental architecture)
- P5: Streaming callbacks crash (NativeCallable.listener prevents thread issues)
- P8: High-volume callbacks deadlock (token batching prevents event loop overload)
- P11: GC freezes with isolates (minimize Dart heap data in worker)

**Research flag:** NEEDS RESEARCH - Complex isolate patterns, FFI threading, cancellation coordination. Run `/gsd:research-phase` before planning.

### Phase 4: Android Vulkan + Demo Update
**Rationale:** Add GPU acceleration after stable CPU baseline. Update demo app to showcase streaming.

**Delivers:**
- Vulkan backend enabled with CPU fallback
- Runtime GPU capability detection
- Example app updated with streaming UI
- Cross-platform feature parity demonstrated

**Uses:**
- GGML_VULKAN=ON build flags
- Runtime backend selection logic

**Addresses:**
- Android Vulkan GPU support (table stakes)
- Mid-range device testing (6GB RAM devices)

**Avoids:**
- P3: Vulkan support incomplete (CPU fallback strategy prevents poor UX)
- P10: Feature parity testing (automated CI on both platforms)

**Research flag:** NEEDS RESEARCH - Vulkan device compatibility matrix, GPU fallback strategies. Run `/gsd:research-phase` before planning.

### Phase Ordering Rationale

- **Android CPU first** - Establishes cross-platform foundation without GPU complexity; validates memory limits and build system independently
- **C++ streaming next** - Single-threaded implementation is easier to test and debug; can be validated without Dart layer
- **Dart integration third** - Depends on working C++ streaming; isolate refactor is architectural risk that benefits from stable native layer
- **Vulkan + demo last** - GPU optimization and polishing after core functionality proven; demo update depends on both Android and streaming working

**Dependency chain:**
```
Phase 1 (Android CPU) --> Phase 4 (Vulkan)
Phase 2 (C++ streaming) --> Phase 3 (Dart streaming) --> Phase 4 (Demo)
```

Phases 1 and 2 can proceed in parallel.

### Research Flags

**Phases needing deeper research:**
- **Phase 3 (Dart Streaming)** - Complex isolate threading, FFI callback patterns, cancellation coordination not fully documented; sparse examples
- **Phase 4 (Vulkan)** - Device compatibility matrix unclear, GPU fallback strategies vary by vendor; needs empirical testing

**Phases with standard patterns (skip research-phase):**
- **Phase 1 (Android CPU)** - Well-documented NDK build process, official docs comprehensive
- **Phase 2 (C++ Streaming)** - llama.cpp examples exist in codebase, streaming pattern is standard

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | NDK r27c + llama.cpp b4658 verified working; Vulkan limitations well-documented; NativeCallable.listener official API |
| Features | HIGH | Streaming UX patterns verified via official Dart docs and ChatGPT comparison; Android requirements from PROJECT.md constraints |
| Architecture | HIGH | Existing codebase analyzed; long-lived isolate pattern standard in Flutter; llama.cpp streaming examples exist |
| Pitfalls | HIGH | 15 pitfalls verified against GitHub issues, official docs, and community reports; LMK behavior documented by Android team |

**Overall confidence:** HIGH

Research based on:
- Official documentation (Android NDK, Flutter FFI, Dart isolates, llama.cpp)
- GitHub issue analysis (llama.cpp Android build issues, Flutter FFI threading)
- Existing codebase inspection (`core/CMakeLists.txt`, `engine.cpp`, `edge_veda_impl.dart`)
- Community consensus (Vulkan mobile GPU issues confirmed across multiple sources)

### Gaps to Address

**Memory limit validation:**
- Research recommends 800MB for Android vs 1.2GB iOS, but optimal limit varies by device tier
- **Mitigation:** Benchmark on 4GB/6GB/12GB devices during Phase 1; adjust dynamically based on device detection

**Vulkan device compatibility:**
- Known issues with Adreno/Mali but specific device models uncatalogued
- **Mitigation:** Maintain runtime allowlist during Phase 4; collect telemetry from beta users

**Token batching frequency:**
- Research suggests 16ms batching (60fps) to prevent callback deadlocks but optimal value untested
- **Mitigation:** Profile on fast models during Phase 3; make batching interval configurable

**OpenCL alternative:**
- Qualcomm OpenCL backend offers better Adreno performance but limits device coverage to Snapdragon
- **Mitigation:** Defer to post-v1.1; consider separate Adreno-optimized build variant if Vulkan proves problematic

## Sources

### Primary (HIGH confidence)
- [Android NDK Revision History](https://developer.android.com/ndk/downloads/revision_history) - NDK r27c specifications
- [Android LMK Documentation](https://developer.android.com/topic/performance/vitals/lmk) - Memory killer behavior
- [Flutter Android C Interop](https://docs.flutter.dev/platform-integration/android/c-interop) - Native library integration
- [Dart NativeCallable.listener API](https://api.flutter.dev/flutter/dart-ffi/NativeCallable/NativeCallable.listener.html) - Thread-safe callbacks
- [Dart Isolates Language Guide](https://dart.dev/language/isolates) - Worker isolate patterns
- [llama.cpp Android Build Guide](https://github.com/ggml-org/llama.cpp/blob/master/docs/android.md) - Official build instructions
- Existing codebase: `core/CMakeLists.txt`, `core/src/engine.cpp`, `flutter/lib/src/edge_veda_impl.dart`

### Secondary (MEDIUM confidence)
- [llama.cpp Discussion #9464](https://github.com/ggml-org/llama.cpp/discussions/9464) - Vulkan Android performance issues
- [llama.cpp Issue #11695](https://github.com/ggml-org/llama.cpp/issues/11695) - Vulkan Android compile bugs
- [llama.cpp Discussion #1876](https://github.com/ggml-org/llama.cpp/discussions/1876) - Memory usage patterns
- [Qualcomm OpenCL Backend](https://www.qualcomm.com/developer/blog/2024/11/introducing-new-opn-cl-gpu-backend-llama-cpp-for-qualcomm-adreno-gpu) - Adreno optimization
- [Understanding Android LMK (Droidcon 2025)](https://www.droidcon.com/2025/01/14/understanding-low-memory-management-in-android-kswapd-lmk/) - Memory management deep dive
- [Dart SDK Issue #61272](https://github.com/dart-lang/sdk/issues/61272) - High-volume FFI callback deadlocks

### Tertiary (LOW confidence - needs validation)
- [Medium: Building AI Mobile Apps 2025](https://medium.com/@stepan_plotytsia/building-ai-powered-mobile-apps-running-on-device-llms-in-android-and-flutter-2025-guide-0b440c0ae08b) - Flutter/Android LLM patterns
- [ncnn Vulkan FAQ](https://github.com/Tencent/ncnn/wiki/FAQ-ncnn-vulkan) - Mobile Vulkan best practices
- Community reports on Vulkan device compatibility (anecdotal, not systematically verified)

---
*Research completed: 2026-02-04*
*Ready for roadmap: yes*
