# Roadmap: Edge Veda SDK

## Overview

Build a Flutter SDK enabling on-device LLM inference on iOS and Android devices. v1.0 delivered iOS with Metal GPU acceleration, Flutter FFI bindings, and pub.dev publication. v1.1 extends to Android with Vulkan GPU support and adds streaming token-by-token responses on both platforms. Each phase delivers a verifiable capability that unblocks the next.

## Milestones

- **v1.0 (Complete):** iOS SDK with Metal GPU, published to pub.dev
- **v1.1 (Active):** Android support with Vulkan, streaming responses
- **v2.0 (Planned):** Competitive features — STT, structured output, function calling, embeddings, RAG

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
- [ ] **Phase 8: On-Device VLM** - Real-time vision/camera object description, zero latency, fully offline
- [ ] **Phase 9: v1.1.0 Release + App Redesign** - Dark minimal demo app, version bump, publish to GitHub + pub.dev
- [ ] **Phase 10: Premium App Redesign** - Full UI overhaul with "Veda" branding, Netflix-style red V icon, teal/cyan accent, welcome flow, Settings tab, model selection, premium navigation
- [ ] **Phase 11: Production Runtime** - Persistent vision worker, sustained-session benchmarks, runtime policy layer (memory/thermal/battery adaptation)
- [ ] **Phase 12: Chat Session API** - Multi-turn conversation management with context overflow summarization
- [ ] **Phase 13: Compute Budget Contracts** - Declarative runtime guarantees (latency, battery, thermal, memory) enforced by central scheduler across concurrent workloads
- [x] **Phase 22: On-Device Intent Engine Demo** - Virtual smart home app with LLM function calling, animated device dashboard, natural language home control, HA connector

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

### Phase 8: On-Device VLM (Vision Language Model) - URGENT COMPETITIVE RESPONSE
**Goal**: Users can point phone camera at objects and get real-time descriptions with zero latency, fully offline

**Depends on**: Phase 4 (iOS-first; Android support after Phase 5)

**Requirements**: VLM model integration, camera frame processing, vision API

**Success Criteria** (what must be TRUE):
  1. User points camera at object, sees description within 2-5 seconds (realistic mobile latency)
  2. Works 100% offline - no WiFi/cellular required after model download
  3. Demo app shows real-time object description as camera moves
  4. SmolVLM-500M model supported (437MB Q8_0, fits memory constraints)
  5. Memory stays under device limits (1.2GB iOS, 800MB Android) during vision inference
  6. Works on iPhone 12+ and modern Android devices with acceptable performance

**Key Risks** (from 08-RESEARCH.md):
- **P1 (Critical)**: Image encoding dominates latency - Use smaller models (SmolVLM), consider GPU acceleration
- **P2 (Critical)**: Memory explosion with image tensors - Add 200-300MB headroom, free embeddings immediately
- **P3 (Moderate)**: Camera frame format mismatch - Convert YUV420/BGRA to RGB before inference
- **P4 (Moderate)**: Context size insufficient - Configure context = image_tokens + prompt + output
- **P5 (Critical)**: Blocking UI thread - Run ALL vision ops in background isolate

**Research flag**: Research complete (08-RESEARCH.md)

**Plans:** 5 plans

Plans:
- [x] 08-00-PLAN.md - llama.cpp upgrade b4658 to b7952 (pre-step for libmtmd/SmolVLM2 support)
- [x] 08-01-PLAN.md - C++ Vision API (ev_vision_* header and vision_engine.cpp using libmtmd)
- [x] 08-02-PLAN.md - Build system + VLM model support (CMakeLists, podspec, model_manager)
- [x] 08-03-PLAN.md - Dart FFI + VisionSession (bindings, camera_utils, initVision/describeImage)
- [x] 08-04-PLAN.md - Demo app + verification (vision tab, camera integration, human verification)

**Urgency:** Competitive response - direct competitor launched similar feature

### Phase 9: v1.1.0 Release + App Redesign
**Goal**: Demo app redesigned with dark minimal aesthetic (Claude-inspired), SDK published as v1.1.0 to GitHub Releases and pub.dev

**Depends on**: Phase 8 (vision features to include in release)

**Requirements**: None (release packaging + demo polish, not new SDK requirements)

**Success Criteria** (what must be TRUE):
  1. Demo app uses dark theme with minimal Claude-inspired aesthetic on both Chat and Vision tabs
  2. App looks social-media-ready in screenshots (no debug UI, polished transitions)
  3. Version 1.1.0 consistent across pubspec.yaml, podspec, and CHANGELOG.md
  4. `./scripts/prepare-release.sh 1.1.0` passes all checks
  5. `flutter analyze` passes with no errors on example app
  6. CHANGELOG.md documents all v1.1.0 features (vision, streaming, VLM)

**Key Risks**:
- **P1 (Low)**: Theme changes break existing functionality — keep all business logic intact, only modify UI layer
- **P2 (Low)**: pub.dev publish fails — dry-run first, existing CI/CD handles the flow

**Research flag**: Skip research — UI redesign + release packaging are standard patterns

**Plans:** 3 plans

Plans:
- [x] 09-01-PLAN.md — Dark theme redesign (Chat + Vision screens, remove debug UI)
- [x] 09-02-PLAN.md — Version bump to 1.1.0 + CHANGELOG entry
- [x] 09-03-PLAN.md — Automated validation + human visual verification

### Phase 10: Premium App Redesign
**Goal**: Full UI overhaul of demo app with production-grade design quality — "Veda" branding with Netflix-style bold red V app icon, teal/cyan accent on true black, welcome/onboarding flow, model selection modal, Settings tab, premium bottom navigation with pill indicators, radial glow effects, card-based surfaces, and polished typography hierarchy

**Depends on**: Phase 9

**Requirements**: None (demo app UX overhaul, not new SDK requirements)

**Success Criteria** (what must be TRUE):
  1. Demo app uses true black (#000000) background with teal/cyan accent color system
  2. App name is "Veda" everywhere (not "Edge Veda") — welcome screen, app bar, settings
  3. App launcher icon is black background with bold red "V" (Netflix-style)
  4. Welcome/onboarding screen with radial red glow, bold red "V" logo, "Get Started" button, and "100% Private" tagline
  5. Chat screen redesigned with premium card-based message bubbles, polished input area, refined metrics display
  6. Vision screen polished with consistent teal accent, premium overlays
  7. Settings tab added with generation settings (temperature slider, max tokens), storage overview, model management, and about section
  8. Model selection modal with device status info and downloadable model list
  9. Bottom navigation uses pill-shaped active indicator with 3 tabs (Chat, Vision, Settings)
  10. All screens match reference-quality design finesse — no debug UI, production-ready screenshots

**Key Risks**:
- **P1 (Low)**: Large UI refactor may break existing business logic — keep all SDK interaction code intact, only modify UI layer
- **P2 (Low)**: New Settings screen adds complexity — keep it read-only display + simple controls, no new SDK features

**Research flag**: Skip research — UI redesign with known Flutter patterns

**Plans:** 4 plans

Plans:
- [x] 10-01-PLAN.md -- Theme foundation + app shell + welcome screen + red V icon + 3-tab navigation
- [x] 10-02-PLAN.md -- Chat screen premium redesign + model selection modal
- [x] 10-03-PLAN.md -- Settings tab + Vision screen teal polish
- [x] 10-04-PLAN.md -- Automated validation + human visual verification

### Phase 11: Production Runtime
**Goal**: Deliver a production-feeling mobile multimodal runtime with persistent vision inference (no per-frame model reload), sustained-session benchmark harness (10-20 min) with graphs, and runtime policy layer adapting to memory/thermal/battery constraints

**Depends on**: Phase 10 (demo app redesign complete), Phase 8 (vision API)

**Non-goals**: No custom kernels, no model conversion toolchain, no NPU integration, no Vulkan backend in this iteration

**Success Criteria** (what must be TRUE):
  1. Vision loop runs continuously for 15 minutes without per-frame model reload
  2. PerfTrace produces JSONL files with frame_id, ts_ms, stage, value for every inference
  3. ev_get_last_timings() returns model_load_ms, image_encode_ms, prompt_eval_ms, decode_ms
  4. VisionWorker isolate loads model once on init, subsequent frames skip model load
  5. Frame queue with backpressure drops frames under load instead of growing latency
  6. Soak test mode runs 15-min vision loop recording throughput, latency, RSS, thermal, battery
  7. iOS thermal + battery telemetry feeds into trace via MethodChannel
  8. RuntimePolicy adjusts QoS knobs (fps, resolution, maxTokens) in response to memory/thermal/battery pressure
  9. Memory pressure triggers graceful degradation (reduce resolution -> reduce tokens -> pause vision)
  10. Thermal adaptation with hysteresis: throttle on heat, restore slowly on cool
  11. tools/analyze_trace.py produces p50/p95/p99 latency, throughput time series, thermal overlay
  12. README includes measured sustained-session benchmark numbers (not aspirational claims)

**Key Risks**:
- **P1 (Critical)**: Persistent vision context memory — keeping ~600MB model resident requires careful memory budget
- **P2 (Critical)**: Frame queue stalls — backpressure policy must not starve the inference loop
- **P3 (Moderate)**: Thermal throttling detection latency — iOS thermalState polling interval vs actual thermal events
- **P4 (Moderate)**: Battery estimation accuracy — 2-minute rolling average may lag real drain rate
- **P5 (Low)**: Android thermal API availability — graceful fallback to "unsupported" on older devices

**Research flag**: Research complete (11-RESEARCH.md)

**Plans:** 5 plans in 3 waves

Plans:
- [x] 11-00-PLAN.md — Native timing hooks (ev_timings_data + ev_vision_get_last_timings) + PerfTrace JSONL logger
- [x] 11-01-PLAN.md — Persistent VisionWorker isolate + FrameQueue with drop-newest backpressure
- [x] 11-02-PLAN.md — iOS telemetry MethodChannel (thermal/battery/memory) + RuntimePolicy with hysteresis
- [x] 11-03-PLAN.md — VisionScreen rewiring + SoakTestScreen (15-min benchmark harness)
- [x] 11-04-PLAN.md — analyze_trace.py (stats + charts) + human verification on device

### Phase 12: Chat Session API
**Goal**: Expose a ChatSession class with automatic multi-turn history management, system prompt support (with presets), and context-overflow summarization. Rebuild XCFramework with all symbols. Rewrite demo Chat tab to use ChatSession.

**Depends on**: Phase 8 (vision API for XCFramework), Phase 11 (timing symbols for XCFramework)

**Requirements**: Multi-turn conversation, system prompt, XCFramework completeness

**Success Criteria** (what must be TRUE):
  1. Developer creates ChatSession and calls send()/sendStream() — SDK manages history automatically
  2. System prompt supported (optional, with built-in presets: assistant, coder, creative)
  3. When context window fills, older messages are summarized (not truncated) before making room
  4. session.messages provides read-only access to conversation history
  5. Demo Chat tab uses ChatSession with visible context indicator (turn count or usage bar)
  6. "New Chat" button resets session; auto-reset on context overflow with visual indication
  7. XCFramework rebuilt from b7952 with ALL C API symbols (text + vision + timings)
  8. XCFramework published to GitHub Releases for easy download
  9. ChatSession is pure Dart — no new C API symbols needed

**Key Risks**:
- **P1 (Moderate)**: Context summarization quality — small models may produce poor summaries
- **P2 (Low)**: Chat template handling — different models use different templates
- **P3 (Low)**: XCFramework size growth — adding all symbols may increase binary size

**Research flag**: Research complete (12-RESEARCH.md)

**Plans:** 4/4 complete

Plans:
- [x] 12-01-PLAN.md — ChatSession SDK class + chat types + chat templates (pure Dart)
- [x] 12-02-PLAN.md — XCFramework rebuild + podspec update + eager bindings
- [x] 12-03-PLAN.md — Demo Chat tab rewrite using ChatSession
- [x] 12-04-PLAN.md — Automated validation + human visual verification

### Phase 13: Compute Budget Contracts
**Goal**: Implement a Compute Budget Contract feature that lets developers declare runtime guarantees (p95 latency, battery drain per 10 minutes, max thermal level, and memory ceiling) and have the runtime enforce those guarantees across concurrent workloads (VisionWorker + StreamingWorker) via a central scheduler

**Depends on**: Phase 11 (RuntimePolicy, TelemetryService), Phase 12 (ChatSession)

**Requirements**: Budget declaration API, central scheduler, budget violation events

**Success Criteria** (what must be TRUE):
  1. Developer creates EdgeVedaBudget with declarative constraints (p95 latency, battery drain/10min, max thermal level, memory ceiling)
  2. Central runtime Scheduler arbitrates vision + text execution using existing telemetry + RuntimePolicy knobs (resolution, fps, max tokens, pause/resume)
  3. Higher-priority workloads maintained while lower-priority ones are degraded to stay within budgets
  4. onBudgetViolation callback/event fires when runtime cannot satisfy declared budget, including which constraint was violated and what mitigation was attempted
  5. On real iPhone soak run with both text + vision active, system stays within declared budgets by degrading/pacing/pause-resume
  6. When budgets cannot be satisfied, clear budget-violation events are emitted with traces showing scheduler decisions
  7. PerfTrace captures scheduler decisions (priority changes, budget checks, degradation actions) in JSONL

**Key Risks**:
- **P1 (Critical)**: Concurrent VisionWorker + StreamingWorker resource contention — scheduler must arbitrate without starving either
- **P2 (Critical)**: p95 latency enforcement requires sufficient historical samples — cold-start period before enforcement kicks in
- **P3 (Moderate)**: Battery drain estimation accuracy — rolling average may lag actual drain rate
- **P4 (Moderate)**: Scheduler overhead — budget checking must not add measurable latency to inference path
- **P5 (Low)**: Budget parameter tuning — unrealistic budgets should be rejected or warned at declaration time

**Research flag**: Research complete (13-RESEARCH.md)

**Plans:** 5 plans in 5 waves

Plans:
- [x] 13-01-PLAN.md — Budget types + LatencyTracker + BatteryDrainTracker + Scheduler (core SDK classes)
- [x] 13-02-PLAN.md — SDK exports + SoakTestScreen integration (demo with budget enforcement)
- [x] 13-03-PLAN.md — Experiment tracking with hypotheses and versioned runs
- [x] 13-04-PLAN.md — Gap closure: observeOnly violations, improved validate(), trace export (DX fixes from device testing)
- [x] 13-05-PLAN.md — Gap closure: adaptive budget profiles (conservative/balanced/performance) with device-calibrated resolution

## Progress

**Execution Order:**
- v1.0: 1 -> 2 -> 3 -> 4 (complete)
- v1.1: 5 and 6 can parallelize, then 7, then 8

```
Phase 5 (Android CPU) ----+
                          +--> Phase 7 (Vulkan + Demo) --> Phase 8 (VLM)
Phase 6 (Streaming)  ----+
```

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. C++ Core + llama.cpp Integration | 4/4 | **Complete** | 2026-02-04 |
| 2. Flutter FFI + Model Management | 4/4 | **Complete** | 2026-02-04 |
| 3. Demo App + Polish | 4/4 | **Complete** | 2026-02-04 |
| 4. Release | 3/3 | **Complete** | 2026-02-04 |
| 5. Android CPU Build | 0/3 | **Planned** | -- |
| 6. Streaming C++ + Dart Integration | 0/5 | **Planned** | -- |
| 7. Android Vulkan + Demo Update | 0/? | Pending | -- |
| 8. On-Device VLM | 5/5 | **Complete** | 2026-02-06 |
| 9. v1.1.0 Release + App Redesign | 3/3 | **Complete** | 2026-02-08 |
| 10. Premium App Redesign | 4/4 | **Complete** | 2026-02-06 |
| 11. Production Runtime | 5/5 | **Complete** | 2026-02-07 |
| 12. Chat Session API | 4/4 | **Complete** | 2026-02-08 |
| 13. Compute Budget Contracts | 5/5 | **Complete** | 2026-02-09 |
| 14. Whisper STT (Speech-to-Text) | 6/6 | **Complete** | 2026-02-14 |
| 15. Structured Output & Function Calling | 7/7 | **Complete** | 2026-02-15 |
| 16. Embeddings, Confidence & RAG | 6/6 | **Complete** | 2026-02-12 |
| 17. RAG Demo Apps | 3/3 | **Complete** | 2026-02-15 |
| 18. Phone Detective Mode | 3/3 | **Complete** | 2026-02-15 |
| 20. Smart Model Advisor | 2/2 | **Complete** | 2026-02-14 |
| 21. Standalone Sample Apps | 0/? | Planned | -- |
| 22. On-Device Intent Engine Demo | 2/3 | Complete    | 2026-02-19 |

### v2.0 Phases (Planned)

### Phase 14: Whisper STT (Speech-to-Text)
**Goal**: Integrate whisper.cpp for on-device speech recognition with streaming transcription API, battery-aware runtime management, and Flutter SDK support via persistent WhisperWorker isolate

**Depends on**: Phase 13 (Scheduler for battery-aware inference management)

**Requirements**: Whisper model integration, streaming transcription API, WhisperWorker isolate

**Success Criteria** (what must be TRUE):
  1. Developer can transcribe audio to text fully on-device using whisper-tiny or whisper-base models
  2. Streaming transcription API delivers partial results as audio is processed (not batch-only)
  3. WhisperWorker runs as persistent isolate (like VisionWorker) with model loaded once
  4. RuntimePolicy manages STT inference — thermal/battery constraints prevent drain spirals
  5. Scheduler gates STT workload alongside vision/text without starving any workload
  6. ModelRegistry supports whisper-tiny (~75MB) and whisper-base (~142MB) model variants
  7. Works offline after model download, no cloud fallback

**Key Risks**:
- **P1 (Critical)**: GGML symbol conflict between whisper.cpp and llama.cpp — must use WHISPER_USE_SYSTEM_GGML=ON
- **P2 (Critical)**: Memory pressure with concurrent STT + VLM — need careful budget with 3 models loaded
- **P3 (Moderate)**: Streaming latency vs accuracy tradeoff — chunk size affects both
- **P4 (Low)**: whisper.cpp version compatibility with our llama.cpp pin

**Research flag**: Research complete (14-RESEARCH.md)

**Plans:** 6 plans in 6 waves

Plans:
- [x] 14-01-PLAN.md — whisper.cpp submodule + CMake shared ggml integration + XCFramework build validation
- [x] 14-02-PLAN.md — C API (ev_whisper_* declarations in edge_veda.h + whisper_engine.cpp implementation)
- [x] 14-03-PLAN.md — XCFramework rebuild + podspec symbol exports + Dart FFI bindings
- [x] 14-04-PLAN.md — WhisperWorker persistent isolate + messages + WhisperSession high-level API
- [x] 14-05-PLAN.md — iOS audio capture (AVAudioEngine) + Scheduler WorkloadId.stt + ModelRegistry + SDK exports
- [x] 14-06-PLAN.md — Demo STT tab with live microphone transcription + human verification on device

### Phase 15: Structured Output & Function Calling
**Goal**: Add tool/function calling support for compatible models (Qwen3, Gemma3) with structured JSON output, schema validation, and budget-aware execution integrated into ChatSession

**Depends on**: Phase 12 (ChatSession), Phase 13 (Scheduler for budget-aware function calling)

**Requirements**: Function calling protocol, JSON schema validation, ChatSession tool message types

**Success Criteria** (what must be TRUE):
  1. Developer registers tools with name, description, and JSON schema — model selects and invokes relevant tools
  2. Structured JSON output validated against developer-provided schema before delivery
  3. Tool calls are first-class ChatMessage types (role: toolCall, toolResult) in ChatSession
  4. Tool filtering auto-selects relevant tools from registered set based on conversation context
  5. Scheduler can degrade tool complexity under thermal pressure (fewer tools, simpler schemas)
  6. Works with Qwen3 and Gemma3 function-calling formats (model-specific template handling)
  7. Developer can inspect tool call chain in session.messages for debugging

**Key Risks**:
- **P1 (Critical)**: Model-specific function calling formats — each model family uses different tool call syntax
- **P2 (Critical)**: JSON schema validation overhead — must not add measurable latency to inference path
- **P3 (Moderate)**: Tool selection accuracy with small models — 500M-3B models may struggle with complex tool sets
- **P4 (Low)**: Budget-aware tool degradation UX — developer needs clear signal when tools are reduced

**Research flag**: Research complete (15-RESEARCH.md)

**Plans:** 7 plans in 5 waves

Plans:
- [x] 15-01-PLAN.md — Tool types + registry + schema validator (pure Dart foundation)
- [x] 15-02-PLAN.md — Chat template extensions (qwen3/gemma3) + tool template + GBNF builder
- [x] 15-03-PLAN.md — C API grammar extension (ev_generation_params + grammar sampler)
- [x] 15-04-PLAN.md — XCFramework rebuild + FFI bindings + GenerateOptions grammar support
- [x] 15-05-PLAN.md — ChatSession tool integration (sendWithTools/sendStructured) + Scheduler tool degradation
- [x] 15-06-PLAN.md — SDK exports + demo app + human verification
- [x] 15-07-PLAN.md — Gap closure: load Qwen3-0.6B model when tools toggle is ON (fixes model/template mismatch)

### Phase 16: Embeddings, Confidence & RAG
**Goal**: Add text embeddings API, entropy-based confidence scoring with cloud handoff signal, pure-Dart vector index for on-device RAG, and build system hardening (visibility, LTO, 16KB pages) — closing competitive gaps identified in Cactus analysis

**Depends on**: Phase 12 (ChatSession for cloud handoff integration), Phase 13 (Scheduler for embedding workload)

**Requirements**: Embeddings C API, confidence metric in generation response, vector index, build hardening

**Success Criteria** (what must be TRUE):
  1. Developer calls `ev_embed()` with text and gets back float array of embeddings — works with any GGUF embedding model (nomic-embed, bge, etc.)
  2. Dart `embed()` runs in `Isolate.run()` and returns `List<double>` with configurable normalization
  3. Every generated token includes a confidence score (0.0-1.0) derived from softmax entropy of logits
  4. Streaming `TokenChunk` and one-shot `GenerateResponse` both expose `confidence` field
  5. When average confidence drops below `confidenceThreshold`, generation stops and `needsCloudHandoff: true` is set
  6. `VectorIndex.create()` / `.add()` / `.query()` / `.delete()` works as pure Dart with persistent storage
  7. End-to-end RAG pipeline works: embed query → search index → inject context → generate response
  8. Android builds use `-Wl,-z,max-page-size=16384` for 16KB page alignment
  9. C API uses `__attribute__((visibility("default")))` with `-fvisibility=hidden` to minimize export table
  10. Android Release builds use `-flto=thin` for binary size reduction

**Key Risks**:
- **P1 (Moderate)**: Embedding model memory — separate context needed, can't share with text model
- **P2 (Moderate)**: Confidence calibration — entropy-based scoring may not correlate well with actual quality for all model sizes
- **P3 (Low)**: Vector index performance at scale — flat index fine for <10K docs, may need HNSW for larger
- **P4 (Low)**: LTO build time increase — thin LTO mitigates but still adds ~30% to Android build

**Research flag**: Research complete (16-RESEARCH.md)

**Plans:** 6 plans in 5 waves

Plans:
- [x] 16-01-PLAN.md — Fix EvGenerationParams struct layout + confidence_threshold field + 16KB page alignment + C API type declarations
- [x] 16-02-PLAN.md — Embeddings C API (ev_embed, ev_free_embeddings) + confidence scoring in ev_stream_next
- [x] 16-03-PLAN.md — XCFramework rebuild + podspec symbol exports + eager Dart FFI bindings
- [x] 16-04-PLAN.md — VectorIndex (pure Dart HNSW or flat fallback) with persistent storage
- [x] 16-05-PLAN.md — Dart types (EmbeddingResult, ConfidenceInfo) + embed() method + RagPipeline + SDK exports
- [x] 16-06-PLAN.md — Automated validation + human verification

### Phase 17: RAG Demo Apps
**Goal**: Integrate RAG directly into the Chat tab — user attaches a document via paperclip icon, it gets chunked and embedded on-device, then chat becomes context-aware with RAG-powered streaming answers. Like ChatGPT with file uploads, but 100% on-device.

**Depends on**: Phase 16 (Embeddings, Confidence & RAG)

**Plans:** 3 plans in 3 waves

Plans:
- [x] 17-01-PLAN.md — Embedding model registry + RagPipeline two-model architecture + file_picker dependency
- [x] 17-02-PLAN.md — Chat tab RAG integration (paperclip attach, chunking, progress UI, document chip, RAG-powered streaming)
- [x] 17-03-PLAN.md — Automated validation + human verification on device

### Phase 18: Phone Detective Mode
**Goal**: Build "Phone Detective Mode" -- a demo screen that scans real photo metadata and calendar events from the user's phone, computes behavioral insights deterministically in Dart, then has an on-device Qwen3-0.6B LLM narrate the findings in noir detective style. Showcases the SDK's tool calling capability with real personal data, entirely offline. Accessible from Settings > Developer section.

**Depends on**: Phase 15 (Structured Output & Function Calling SDK)

**Plans:** 3 plans in 3 waves

Plans:
- [x] 18-01-PLAN.md — Native photo/calendar data providers (Objective-C in EdgeVedaPlugin.m) + permissions + Qwen3-0.6B model registry
- [x] 18-02-PLAN.md — DetectiveScreen with InsightEngine (deterministic Dart analysis), tool calling, noir LLM narration, animated scan steps, results card, Demo Mode, Settings entry
- [x] 18-03-PLAN.md — Evidence anchoring, LLM self-checks, determinism hardening + human verification on device

### Phase 19: Memory Optimization (getMemoryStats + KV Cache Quantization)

**Goal:** Fix getMemoryStats() to query existing StreamingWorker (eliminates ~600MB spike) and enable KV cache Q8_0 quantization with flash attention (halves KV cache from ~64MB to ~32MB)
**Depends on:** Phase 18
**Plans:** 3 plans in 3 waves

Plans:
- [ ] 19-01-PLAN.md -- Worker-routed getMemoryStats (Dart-only, eliminates double-load memory spike)
- [ ] 19-02-PLAN.md -- KV cache Q8_0 + flash attention (C struct + Dart FFI + all config sites + XCFramework rebuild)
- [ ] 19-03-PLAN.md -- Automated validation + human verification on device

### Phase 20: Smart Model Advisor

**Goal:** Device-aware model recommendations with 4D scoring (fit, quality, speed, context). Extends ModelInfo with inference metadata (parametersB, maxContextLength, capabilities, family). DeviceProfile detects iPhone model/RAM/chip via existing sysctl FFI. MemoryEstimator uses calibrated bytes-per-parameter formulas (Q4_K_M=0.58, Q8_0=1.05, etc.) plus KV cache and runtime overhead. ModelAdvisor scores models 0-100 with use-case weighted scoring (chat, reasoning, toolCalling, vision, stt, embedding, fast) and outputs ranked recommendations + optimal EdgeVedaConfig per model+device pair. Example app Settings gets device-aware recommendations UI. Inspired by github.com/Pavelevich/llm-checker. iOS only for now, pure Dart scoring, ~300 lines core logic.

**Depends on:** Phase 19

**Requirements:** ModelInfo inference metadata, device profiling, memory estimation, 4D scoring, recommended config generation

**Success Criteria** (what must be TRUE):
  1. ModelInfo extended with parametersB, maxContextLength, capabilities, family — populated for all 10 registry models
  2. DeviceProfile.detect() returns device model, total RAM, available RAM, chip name, tier (low/medium/high/ultra)
  3. MemoryEstimator.estimate(model, contextLength) returns model/KV-cache/overhead/total bytes with ModelFit enum
  4. ModelAdvisor.score(model, device, useCase) returns 0-100 composite score with per-dimension breakdown
  5. ModelAdvisor.recommend(device, useCase) returns ranked list excluding models that won't fit
  6. Each recommendation includes an optimal EdgeVedaConfig (contextLength, numThreads, maxMemoryMb tuned to device)
  7. Settings screen shows device info card and use-case-grouped model recommendations with scores
  8. Works on real iPhone — recommendations match expected behavior (e.g., Phi 3.5 Mini marked as "tight" on 6GB device)

**Key Risks:**
- **P1 (Low)**: Memory estimation accuracy — bytes-per-parameter calibrated from llm-checker but mobile overhead may differ
- **P2 (Low)**: Speed estimation without benchmarks — using theoretical Metal coefficients, not measured tok/s
- **P3 (Low)**: Small model catalog — scoring engine is overkill for 5 text models, but designed to scale

**Research flag**: Research complete (llm-checker analysis + existing SDK audit)

**Plans:** 2 plans in 2 waves

Plans:
- [x] 20-01-PLAN.md — SDK core: ModelInfo extension + DeviceProfile + MemoryEstimator + ModelAdvisor + types + barrel exports
- [x] 20-02-PLAN.md — Settings screen recommendations UI + human verification on device

### Phase 21: Standalone Sample Apps
**Goal**: Ship 3 clone-and-run Flutter sample apps that showcase Edge Veda SDK capabilities end-to-end. Each app should work on a real iPhone within 15 minutes of cloning (model download + build). Target: developer adoption through "I can see myself building this."

**Sample App 1: Document Q&A** — Camera/file → chunk → embed → RAG-powered Q&A. "ChatGPT for your paperwork, but offline."
- Uses: RAG pipeline, embeddings, chat, file picker
- Target: professionals dealing with contracts, manuals, receipts

**Sample App 2: Health Advisor + RAG** — Load medical PDFs/notes → private on-device health Q&A with confidence scoring + cloud handoff signal.
- Uses: RAG pipeline, confidence scoring, chat
- Target: privacy-conscious users, HIPAA-friendly angle

**Sample App 3: Voice Journal** — Tap to record → live STT transcription → LLM summarizes/tags → searchable journal entries.
- Uses: Whisper STT, chat (summarization), embeddings (search past entries)
- Target: universal note-taking. Best demo for video — interactive in real-time.

**Depends on:** Phase 20, Phase 14 (STT), Phase 16 (RAG/Embeddings)

**Plans:** 4 plans in 2 waves

Plans:
- [ ] 21-01-PLAN.md -- Document Q&A sample app (RAG pipeline, file picker, PDF extraction)
- [ ] 21-02-PLAN.md -- Health Advisor sample app (RAG + confidence scoring + cloud handoff)
- [ ] 21-03-PLAN.md -- Voice Journal sample app (STT + summarization + semantic search + SQLite)
- [ ] 21-04-PLAN.md -- Automated validation + human verification on device

### Phase 22: On-Device Intent Engine Demo App
**Goal**: Build a standalone Flutter demo app showcasing on-device LLM as a natural language intent engine for smart home control. Virtual home simulation with animated device state dashboard (lights, thermostat, locks, TV, fan), LLM function calling maps ambiguous phrases ("I'm heading to bed", "it's cold in here") to structured ToolCall actions, real-time UI state updates. Pluggable backend architecture with Home Assistant REST API connector. Privacy-first, offline, no cloud. The "brain with hands" demo.

**Depends on**: Phase 15 (Structured Output & Function Calling), Phase 21 (sample app patterns)

**Requirements**: Virtual device state engine, animated home dashboard UI, tool definitions for home devices, LLM intent parsing via sendWithTools, pluggable action router, Home Assistant connector stub

**Success Criteria** (what must be TRUE):
  1. User types natural language ("I'm heading to bed") and sees multiple device state changes animate in real-time
  2. Virtual home dashboard shows rooms with device cards (lights with brightness, thermostat with temp, locks, TV, fan)
  3. LLM produces structured ToolCall objects via sendWithTools() — not regex or keyword matching
  4. Ambiguous phrases work ("too bright", "movie time", "I'm leaving") without pre-programming each scenario
  5. Conversational context maintained across turns ("dim the lights... more... perfect")
  6. Action log shows exactly what the LLM decided and which tools it called (transparent reasoning)
  7. Works fully offline after model download — no cloud dependency
  8. Home Assistant REST API connector stub included (wirable to real HA instance)
  9. App is clone-and-run: works on real iPhone within 15 min of cloning

**Key Risks**:
- **P1 (Moderate)**: Small model tool call accuracy — Qwen3-0.6B may struggle with complex multi-device scenarios
- **P2 (Low)**: UI animation complexity — many simultaneous state changes need smooth transitions
- **P3 (Low)**: Home Assistant API integration — REST API is simple but auth token setup adds friction

**Research flag**: Skip research — uses existing SDK function calling + standard Flutter UI patterns

**Plans:** 3/3 plans complete

Plans:
- [x] 22-01-PLAN.md — Project scaffold, device models, LLM intent service, HA connector
- [x] 22-02-PLAN.md — Animated home dashboard UI, chat interface, action log
- [x] 22-03-PLAN.md — README + human verification on device

### Phase 23: Add Image Generation Capabilities

**Goal:** Add on-device text-to-image generation to the Edge Veda Flutter SDK using stable-diffusion.cpp and GGUF-quantized Stable Diffusion models. Developer calls `generateImage(prompt)` on EdgeVeda class, receives PNG bytes with progress streaming. Dedicated ImageWorker isolate manages persistent sd_ctx. Demo app gets new Image tab with prompt input, gallery, and advanced parameter controls.

**Depends on:** Phase 22

**Requirements:** Image generation C API, ImageWorker isolate, generateImage on EdgeVeda, SD model registry, demo Image tab

**Success Criteria** (what must be TRUE):
  1. stable-diffusion.cpp integrated as third engine submodule with shared ggml (no duplicate symbols)
  2. ev_image_* C API wraps sd.cpp (init, generate, free, progress callback)
  3. XCFramework rebuilt with all ev_image_* symbols, podspec exports them
  4. ImageWorker persistent isolate manages sd_ctx (model loaded once, reused)
  5. Developer calls `generateImage(prompt)` on EdgeVeda, receives PNG Uint8List
  6. Progress callback fires for each denoising step (step N of M)
  7. Full parameter control: prompt, negative prompt, seed, steps, guidance scale, dimensions, sampler, schedule
  8. SD v2.1 Turbo Q8_0 (~2.3GB) model in ModelRegistry with HuggingFace download URL
  9. Demo Image tab with prompt input, image display, gallery history, advanced settings panel
  10. Works on real iPhone within 15-60 seconds generation time

**Key Risks**:
- **P1 (Critical)**: ggml version mismatch between sd.cpp and llama.cpp -- must share ggml successfully
- **P2 (Critical)**: ~2.3GB model + app memory exceeds iPhone 6GB budget -- recommend unloading LLM first
- **P3 (Moderate)**: Generation time may exceed 60s on older devices -- turbo model (4 steps) mitigates
- **P4 (Low)**: Metal simulator crash -- use TARGET_OS_SIMULATOR guard (proven pattern)

**Research flag**: Research complete (23-RESEARCH.md)

**Plans:** 2/4 plans executed

Plans:
- [ ] 23-01-PLAN.md -- stable-diffusion.cpp submodule + CMake integration + ev_image_* C API + image_engine.cpp
- [ ] 23-02-PLAN.md -- XCFramework rebuild + podspec symbol exports + Dart FFI bindings
- [ ] 23-03-PLAN.md -- ImageWorker isolate + Dart types + generateImage() on EdgeVeda + model registry + SDK exports
- [ ] 23-04-PLAN.md -- Demo Image tab (prompt, gallery, advanced settings) + human verification on device

---
*Roadmap created: 2026-02-04*
*v1.1 phases added: 2026-02-05*
*Phase 5 planned: 2026-02-05*
*Phase 6 planned: 2026-02-05*
*Phase 8 planned: 2026-02-06*
*Phase 9 added: 2026-02-06*
*Phase 11 added: 2026-02-07*
*Phase 11 planned: 2026-02-07*
*Depth: comprehensive (from config.json)*
*Phase 13 added: 2026-02-09*
*Phase 13 planned: 2026-02-09*
*Phase 13 gap closure: 2026-02-09*
*Phase 14 added: 2026-02-09*
*Phase 14 planned: 2026-02-11*
*Phase 15 added: 2026-02-09*
*Phase 15 planned: 2026-02-11*
*Phase 15 gap closure: 2026-02-14 (model/template mismatch fix)*
*Phase 16 planned: 2026-02-12*
*Phase 18 planned: 2026-02-12*
*Phase 18 re-planned: 2026-02-12 (Phone Detective Mode)*
*Phase 20 added: 2026-02-14 (Smart Model Advisor)*
*Phase 20 planned: 2026-02-14 (2 plans in 2 waves)*
*Phase 22 added: 2026-02-18 (On-Device Intent Engine Demo)*
*Phase 23 planned: 2026-02-19 (4 plans in 4 waves)*
*v1.0 Coverage: 19/19 requirements mapped*
*v1.1 Coverage: 14/14 requirements mapped*
