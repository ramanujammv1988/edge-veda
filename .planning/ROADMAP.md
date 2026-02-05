# Roadmap: Edge Veda SDK

## Overview

Build a Flutter SDK enabling on-device LLM inference on iOS and Android devices. v1.0 delivered iOS with Metal GPU acceleration, Flutter FFI bindings, and pub.dev publication. v1.1 extends to Android with Vulkan GPU support and adds streaming token-by-token responses on both platforms. Each phase delivers a verifiable capability that unblocks the next.

## Milestones

- **v1.0 (Complete):** iOS SDK with Metal GPU, published to pub.dev
- **v1.1 (Active):** Android support with Vulkan, streaming responses

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

### v1.0 Phases (Complete)

- [x] **Phase 1: C++ Core + llama.cpp Integration** - Native engine builds with Metal support
- [x] **Phase 2: Flutter FFI + Model Management** - Dart bindings and model download working
- [x] **Phase 3: Demo App + Polish** - Example app demonstrates text generation
- [x] **Phase 4: Release** - Published to pub.dev with documentation

### v1.1 Phases (Active)

- [ ] **Phase 5: Android CPU Build** - Android NDK builds and loads native library with CPU inference
- [ ] **Phase 6: Streaming C++ + Dart Integration** - Token-by-token streaming works on iOS with long-lived isolate
- [ ] **Phase 7: Android Vulkan + Demo Update** - Vulkan GPU enabled, streaming on both platforms, demo updated

## Phase Details

### Phase 1: C++ Core + llama.cpp Integration (Complete)
**Goal**: Native C++ engine performs on-device inference with Metal GPU acceleration

**Depends on**: Nothing (first phase)

**Requirements**: R1.1, R1.2, R1.3, R1.4, R1.5, R3.1, R3.2, R4.3, R5.1, R5.2, R5.3

**Success Criteria** (what must be TRUE):
  1. llama.cpp submodule added at pinned commit and builds for iOS
  2. XCFramework builds for device and simulator with Metal enabled
  3. C++ API (ev_init, ev_generate, ev_free) loads GGUF model and generates coherent text
  4. Binary size stays under 15MB (measured with `size` command)
  5. Performance achieves >10 tok/sec on iPhone 12 with Metal backend

**Key Risks**:
- **Pitfall 1 (Critical)**: iOS memory kills app without warning - Implement memory guard proactively at 1.2GB limit
- **Pitfall 2 (Critical)**: Metal not enabled in build - Verify LLAMA_METAL ON and LLAMA_METAL_EMBED_LIBRARY ON in CMake
- **Pitfall 7 (Moderate)**: Binary size explosion - Disable desktop SIMD (AVX/AVX2), enable LTO, strip symbols

**Plans:** 4/4 complete

### Phase 2: Flutter FFI + Model Management (Complete)
**Goal**: Flutter developers can initialize SDK and download models with progress tracking

**Depends on**: Phase 1

**Requirements**: R2.1, R2.2, R2.3, R2.4, R3.3, R4.1, R4.2, R4.4

**Success Criteria** (what must be TRUE):
  1. FFI bindings match edge_veda.h API signatures (verified by compilation)
  2. Model downloads from URL with 0-100% progress callbacks
  3. Downloaded models cache locally and skip re-download on second init
  4. SHA256 checksum mismatch throws ModelValidationException
  5. All inference calls run in background isolate (UI never blocks)
  6. Memory stats API allows Flutter to monitor and respond to memory pressure

**Key Risks**:
- **Pitfall 3 (Critical)**: FFI blocks UI thread - Use Isolate.run() for all inference calls from start
- **Pitfall 4 (Critical)**: Model file path sandbox violations - Use applicationSupportDirectory, exclude from backup
- **Pitfall 6 (Critical)**: FFI memory leaks - Establish RAII wrapper pattern, clear ownership rules
- **Pitfall 12 (Moderate)**: Incorrect download progress - Use chunked download with explicit progress calculation

**Plans:** 4/4 complete

### Phase 3: Demo App + Polish (Complete)
**Goal**: Example Flutter app demonstrates working text generation with proper lifecycle handling

**Depends on**: Phase 2

**Requirements**: None (demo integration, not new requirements)

**Success Criteria** (what must be TRUE):
  1. Example app in flutter/example/ runs: user types prompt, sees generated response
  2. App handles backgrounding gracefully (cancels generation, saves state)
  3. Memory stays under 1.2GB during sustained usage (10+ consecutive generations)
  4. Performance benchmarks logged: tok/sec, TTFT, memory usage on real iPhone 12
  5. README.md includes setup instructions, usage examples, and performance expectations

**Key Risks**:
- **Pitfall 5 (Critical)**: App Store rejects background execution - Cancel generation on pause, document foreground-only
- **Pitfall 11 (Moderate)**: Flutter hot reload breaks FFI state - Implement dispose() that calls ev_free()
- **Pitfall 14 (Minor)**: Simulator performance misleads - Benchmark on real device (iPhone 12)

**Plans:** 4/4 complete

### Phase 4: Release (Complete)
**Goal**: SDK published to pub.dev with complete documentation and CI/CD

**Depends on**: Phase 3

**Requirements**: None (packaging and distribution, not functional requirements)

**Success Criteria** (what must be TRUE):
  1. Package published to pub.dev with version 1.0.0
  2. pub.dev page shows usage example and API documentation
  3. CI/CD pipeline builds XCFramework and runs tests on every commit
  4. Developer can `flutter pub add edge_veda` and follow README to working inference in <30 minutes

**Key Risks**:
- Low risk phase - primary failure mode is incomplete documentation

**Plans:** 3/3 complete

---

### Phase 5: Android CPU Build
**Goal**: Android NDK builds native library and existing generate() API works on Android with CPU backend

**Depends on**: Phase 4 (v1.0 complete)

**Requirements**: R7.1, R7.3, R7.4, R7.5, R7.6

**Success Criteria** (what must be TRUE):
  1. User can run flutter example app on Android device and see model download progress
  2. User can type prompt on Android and receive generated response (CPU backend)
  3. App survives Android Low Memory Killer on 4GB device after 10 consecutive generations
  4. Model caches in Android app-appropriate directory and skips re-download on restart
  5. App recovers gracefully after process kill - model reloads on next launch

**Key Risks**:
- **P1 (Critical)**: Android LMK differs from iOS jetsam - Start with 800MB limit, test on 4GB devices
- **P2 (Critical)**: llama.cpp version compatibility - Keep pinned to b4658, build with GGML_OPENMP=OFF
- **P4 (Critical)**: Native library loading fails - Build arm64-v8a only, verify .so in APK
- **P7 (Moderate)**: NDK version mismatch - Pin NDK r27c explicitly in build.gradle
- **P9 (Moderate)**: mmap memory accounting differs - Consider --no-mmap or pre-touch pages

**Research flag**: Standard patterns - skip phase research

**Plans:** 3 plans

Plans:
- [ ] 05-01-PLAN.md - NDK build configuration (CMakeLists.txt, build.gradle, plugin)
- [ ] 05-02-PLAN.md - Android memory handling (onTrimMemory, caching, 800MB limit)
- [ ] 05-03-PLAN.md - Integration verification (build APK, test on device)

### Phase 6: Streaming C++ + Dart Integration
**Goal**: Users see tokens appear one-by-one as they are generated, with ability to cancel mid-stream

**Depends on**: Phase 4 (can parallelize with Phase 5)

**Requirements**: R6.1, R6.2, R6.3, R6.4, R8.3

**Success Criteria** (what must be TRUE):
  1. User calls generateStream(prompt) and sees tokens appear progressively in UI (not all at once)
  2. User can tap "Stop" button and generation halts within 500ms, stream closes cleanly
  3. When generation completes naturally, final TokenChunk has isFinal=true
  4. If native error occurs during streaming, error surfaces via stream error (not silent failure)
  5. Same exception types thrown on iOS and Android for identical error conditions

**Key Risks**:
- **P5 (Critical)**: Streaming callbacks crash with wrong API - Use NativeCallable.listener exclusively
- **P6 (Critical)**: Long-lived worker isolate required - Refactor from Isolate.run() to Isolate.spawn()
- **P8 (Moderate)**: High-volume callbacks cause deadlocks - Batch tokens every 16ms
- **P11 (Moderate)**: GC freezes with isolates - Minimize Dart heap data in worker
- **P12 (Moderate)**: Cancel token complexity - Use atomic flag in native, test cancel at various points

**Research flag**: Research complete (06-RESEARCH.md)

**Plans:** 5 plans

Plans:
- [ ] 06-01-PLAN.md - C++ streaming implementation (ev_stream_impl, atomic cancellation)
- [ ] 06-02-PLAN.md - Dart FFI streaming bindings (EvStreamImpl, ev_stream_* functions)
- [ ] 06-03-PLAN.md - Worker isolate infrastructure (long-lived isolate, typed messages)
- [ ] 06-04-PLAN.md - Public streaming API (generateStream(), CancelToken enhancement)
- [ ] 06-05-PLAN.md - Integration verification (demo app streaming UI, human verification)

### Phase 7: Android Vulkan + Demo Update
**Goal**: Android achieves GPU-accelerated performance, demo app showcases streaming on both platforms

**Depends on**: Phase 5, Phase 6

**Requirements**: R6.5, R7.2, R8.1, R8.2

**Success Criteria** (what must be TRUE):
  1. User on Vulkan-capable Android device sees >10 tok/sec (GPU accelerated)
  2. User on non-Vulkan device still works (CPU fallback, slower but stable)
  3. Final TokenChunk includes generation metrics: tokens/sec, total tokens, elapsed time
  4. Demo app on Android shows streaming tokens appearing in real-time (same UX as iOS)
  5. Same EdgeVeda Dart API works identically on iOS and Android (no platform-specific code in user app)

**Key Risks**:
- **P3 (Critical)**: Vulkan support incomplete - Default to CPU, maintain device allowlist for Vulkan
- **P10 (Moderate)**: Feature parity differences - Create platform-parity test suite, use deterministic settings

**Research flag**: NEEDS RESEARCH - Vulkan device compatibility matrix, GPU fallback strategies

**Plans:** TBD

## Progress

**Execution Order:**
- v1.0: 1 -> 2 -> 3 -> 4 (complete)
- v1.1: 5 and 6 can parallelize, then 7

```
Phase 5 (Android CPU) ----+
                          +--> Phase 7 (Vulkan + Demo)
Phase 6 (Streaming)  ----+
```

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. C++ Core + llama.cpp Integration | 4/4 | **Complete** | 2026-02-04 |
| 2. Flutter FFI + Model Management | 4/4 | **Complete** | 2026-02-04 |
| 3. Demo App + Polish | 4/4 | **Complete** | 2026-02-04 |
| 4. Release | 3/3 | **Complete** | 2026-02-04 |
| 5. Android CPU Build | 0/3 | **Planned** | — |
| 6. Streaming C++ + Dart Integration | 0/5 | **Planned** | — |
| 7. Android Vulkan + Demo Update | 0/? | Pending | — |

---
*Roadmap created: 2026-02-04*
*v1.1 phases added: 2026-02-05*
*Phase 5 planned: 2026-02-05*
*Phase 6 planned: 2026-02-05*
*Depth: comprehensive (from config.json)*
*v1.0 Coverage: 19/19 requirements mapped*
*v1.1 Coverage: 14/14 requirements mapped*
