# Inference Layer Research Summary

**Project:** Edge Veda -- Flutter plugin with on-device AI inference (LLM, Vision, STT, Image Gen)
**Domain:** On-device ML inference optimization (Android CPU-only resilience, soak test coverage, memory safety)
**Researched:** 2026-03-08
**Confidence:** HIGH

## Executive Summary

Edge Veda's inference layer has a significant asymmetry: the iOS/macOS path is well-optimized (Metal GPU, mature soak testing, adaptive STT), while the Android path is crippled by CPU-only execution with no adaptive behavior for LLM or Vision workloads. The vision pipeline on CPU-only Android takes 60+ seconds per frame at 128px resolution and potentially minutes at the default 768px -- with no fallback, no streaming, and no device-tier adaptation. STT solved this problem with `AdaptiveSttService` and system SpeechRecognizer fallback; LLM and Vision have no equivalent. This is the single most impactful gap in the inference layer.

The memory management layer has a structural problem: only the LLM engine participates in `memory_guard`. Vision, Whisper, and Image Gen contexts load models without any memory tracking, coordination, or pressure response. The auto-cleanup mechanism is a TODO stub. On Android devices with 4-6GB RAM and an 800MB recommended limit, loading multiple models concurrently will trigger OOM kills with no graceful degradation. Cross-engine memory coordination must be implemented before Android can be considered production-ready.

Test coverage is the third critical gap. The soak test exercises only the vision pipeline. There are zero C++ tests for Vision, Whisper, or Image Gen APIs -- not even NULL-guard tests. There are zero Dart integration tests that exercise actual inference. All concurrency fixes (issues #25, #26, #28, #29, #33) were validated by code review, not by regression tests. Two `*_free` functions have lock-before-delete undefined behavior. These gaps compound: without tests, the memory and adaptive behavior improvements suggested above are high-risk to implement.

## Key Findings

### Codebase Architecture (from codebase-map.md)

The native inference layer follows a clean architecture: Dart FFI calls into a C API (`edge_veda.h`, 48 `ev_*` symbols), which delegates to four independent engines -- each wrapping a third-party C++ library (llama.cpp, libmtmd, whisper.cpp, stable-diffusion.cpp). All share a single ggml backend with reference-counted lifecycle. Each engine has its own mutex; the Dart SDK serializes access through isolate SendPort/ReceivePort.

**Vision pipeline specifics:**
- Persistent worker isolate pattern: model loaded once, frames processed sequentially
- FrameQueue with capacity=1, drop-newest backpressure (prevents frame accumulation during slow inference)
- CLIP image encoding is the dominant bottleneck: patch count scales quadratically with resolution
- Soak test mitigates with 128px downscale + grab-and-stop camera pattern; VisionScreen does not
- 600-second timeout on Android (flat, no device-tier awareness)

**Soak test infrastructure:**
- Primarily a vision soak test (35 minutes, managed or raw mode)
- Records per-frame timing breakdown, thermal state, battery drain, RSS memory
- macOS uses screen capture at 320px; mobile uses camera at 128px
- Does NOT cover LLM, STT, or Image Gen workloads
- Does NOT test OOM recovery or multi-model memory pressure

### Inference Concerns (from inference-concerns.md)

16 specific concerns identified across 6 categories, with 5 rated High severity:

**High severity:**
1. Memory guard auto-cleanup is a TODO stub -- app gets OOM-killed instead of gracefully unloading
2. No C++ tests for Vision/Whisper/Image APIs -- zero coverage for 3 of 4 engines
3. Soak test covers only Vision -- LLM, STT, Image Gen untested under sustained load
4. No cross-engine memory coordination -- multiple model loads can exceed device budget silently
5. Android CPU-only path -- all workloads run on NEON only, Vulkan deferred to Phase 7

**Medium severity:**
6. No Dart integration tests for actual inference
7. Vision inference is blocking (no streaming, no cancel, no partial results)
8. LLM/Vision lack adaptive behavior (STT has it, others do not)
9. Vision/Whisper/Image contexts not registered with memory guard
10. No concurrency regression tests for fixed thread-safety issues

**Low severity:**
11. Lock-before-delete UB in `ev_image_free` and `ev_whisper_free`
12. Image generation has no cancel support

### Critical Pitfalls

1. **OOM on Android without graceful degradation** -- Memory guard auto-cleanup is unimplemented, and 3 of 4 engines do not participate in memory tracking at all. Fix: implement cleanup callback chain, register all engines with memory guard.
2. **Vision pipeline unusable on low-end Android** -- 768px default with no device-tier adaptation, no fallback, 600s flat timeout. Fix: port soak test mitigations (128px, grab-and-stop) to VisionScreen, add device-tier-aware resolution.
3. **No test safety net for inference changes** -- Zero C++ tests for Vision/Whisper/Image, zero Dart integration tests. Any refactoring of memory management or adaptive behavior could introduce regressions invisible to CI. Fix: add NULL-guard tests and at least one model-backed test per engine before making structural changes.
4. **Thread count hardcoded to 4 in C layer** -- Saturates all cores on 4-core devices (thermal throttle), underutilizes 10+ core desktops. The Dart layer works around this, but direct SDK consumers get no adaptation. Fix: platform-aware auto-detect in C layer.
5. **Vision has no streaming API** -- Single blocking call, no incremental tokens, no cancel, no partial results. On CPU-only Android this means 60+ seconds of user uncertainty. Fix: add `ev_vision_describe_stream()` analogous to `ev_generate_stream()`.

## Implications for Roadmap

Based on combined research, the work should be structured in dependency order: tests first (to catch regressions), then memory safety (foundation for everything else), then adaptive behavior (user-facing improvements), then performance (Vulkan, streaming).

### Phase 1: Test Foundation

**Rationale:** Every subsequent phase modifies core inference code. Without tests, regressions are invisible. This must come first.
**Delivers:** C++ NULL-guard tests for all 4 engine APIs, memory guard unit tests, backend lifecycle tests, concurrency regression tests, fix lock-before-delete UB in 2 files.
**Addresses:** Concerns 5B (no C++ tests for Vision/Whisper/Image), 5C (no concurrency tests), 5D (memory guard untested), 5E (no image gen tests), 6C (backend lifecycle untested), 6D (lock-before-delete UB).
**Avoids:** Shipping structural changes to memory management or adaptive behavior without a safety net.
**Effort:** Low-Medium. Most tests are small and do not require model files (NULL-guard, unit tests). Memory guard tests can mock system memory.

### Phase 2: Memory Safety

**Rationale:** Memory is the #1 production risk on Android. OOM kills destroy user trust. Must be solid before adding adaptive behavior (which loads/unloads models dynamically).
**Delivers:** Memory guard auto-cleanup implementation, all 4 engines registered with memory guard, cross-engine memory coordination in Dart (LRU eviction or load-time budget check), process-wide memory budget enforcement.
**Addresses:** Concerns 2A (auto-cleanup stub), 2B (global singleton collision), 2C (no cross-engine coordination), 2D (Vision/Whisper/Image not in memory guard).
**Avoids:** OOM kills on Android, silent memory budget overruns from concurrent model loads.
**Effort:** Medium-High. Requires coordinated changes across C++ memory_guard, all 4 engine init/free paths, and Dart-side EdgeVeda model management.

### Phase 3: Adaptive Behavior for LLM and Vision

**Rationale:** STT already has the adaptive pattern (`AdaptiveSttService`, device-tier detection, automatic fallback). LLM and Vision need the same treatment. This is the highest-impact user-facing change for low-end Android.
**Delivers:** Device-tier-aware timeouts for LLM and Vision workers, device-tier-aware resolution in VisionScreen (not just soak test), adaptive thread count in C layer, grab-and-stop camera pattern ported from soak test to VisionScreen for CPU-only devices, consecutive failure tracking for vision.
**Addresses:** Concerns 1B (threading), 1C (timeout strategy), 4A (LLM/Vision lack adaptive behavior), 4B (no adaptive thread count at C layer), 4C (no resolution adaptation in C layer).
**Avoids:** Users on low-end Android waiting minutes with no feedback or degradation path.
**Effort:** Medium. `DeviceProfile` and `DeviceTier` already exist. Main work is wiring them into VisionWorker and LLM worker, plus C-layer thread auto-detect.

### Phase 4: Soak Test Expansion

**Rationale:** With memory safety and adaptive behavior in place, soak testing should validate these new behaviors under sustained load across all workloads.
**Delivers:** LLM soak mode (auto-generated prompts), STT soak mode (synthetic/recorded audio), Image Gen soak mode (repeated generation), mixed-workload mode, OOM recovery stress test, Android GPU field for future Vulkan.
**Addresses:** Concerns 3A (soak covers only vision), 3B (no OOM recovery test), 3C (Android GPU field missing).
**Avoids:** Shipping adaptive behavior and memory management without sustained-load validation.
**Effort:** Medium. SoakTestService architecture already supports workload modes; main work is adding new WorkloadId variants and their execution loops.

### Phase 5: Vision Streaming and Cancel

**Rationale:** Depends on adaptive behavior (Phase 3) being in place so streaming respects device tier. Also benefits from expanded soak tests (Phase 4) for validation.
**Delivers:** `ev_vision_describe_stream()` C API with incremental token delivery, cancel support for vision inference, partial result handling on timeout, cancel support for image generation (wire stable-diffusion.cpp cancel callback).
**Addresses:** Concerns 6A (vision blocking), 6B (image gen no cancel).
**Avoids:** Users staring at blank screens for 60+ seconds with no progress indication.
**Effort:** Medium. The streaming pattern already exists in `ev_generate_stream()` and can be replicated for vision. Image gen cancel is low effort (callback already exists in stable-diffusion.cpp).

### Phase 6: Vulkan GPU Acceleration (Already Planned as Phase 7)

**Rationale:** The single highest-impact performance change (10-50x speedup potential), but requires all prior phases to be stable. Vulkan introduces a new failure mode (device compatibility), so adaptive behavior and memory management must already handle graceful degradation.
**Delivers:** Vulkan backend enabled for Android, device detection with CPU fallback, soak test GPU path validation.
**Addresses:** Concern 1A (Android CPU-only path).
**Avoids:** Shipping GPU acceleration without memory safety, adaptive fallback, or soak test coverage.
**Effort:** High. Requires Vulkan 1.2+ device detection, CMake integration, fallback logic, and extensive per-device testing.

### Phase 7: Dart Integration Tests

**Rationale:** Requires model files and on-device execution. Lower priority than C++ tests (Phase 1) because the FFI layer is thin and well-structured. Best done after all structural changes are complete.
**Delivers:** One integration test per workload (LLM, Vision, STT, Image Gen) that loads a tiny model and verifies end-to-end output. Marked as slow/device-only tests.
**Addresses:** Concern 5A (no Dart integration tests).
**Effort:** Medium. Requires CI infrastructure for on-device test execution or a "slow test" marker system.

### Phase Ordering Rationale

- **Tests before changes:** Phases 2-5 all modify core inference code. Phase 1 provides the safety net.
- **Memory before adaptive:** Adaptive behavior may trigger model loads/unloads. Memory coordination must be solid first.
- **Adaptive before soak:** Soak tests should validate the new adaptive behavior, not the old non-adaptive behavior.
- **Streaming after adaptive:** Streaming vision needs to respect device-tier settings from Phase 3.
- **Vulkan last:** Highest effort, highest reward, but requires stable foundations. Already planned as Phase 7 in the existing roadmap.
- **Dart integration tests last:** Structural changes in Phases 2-5 would invalidate integration tests written earlier. Write them after the dust settles.

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 2 (Memory Safety):** Cross-engine memory coordination design needs careful architecture. How does Dart-side LRU eviction interact with C-side memory guard callbacks? Need to validate that model unload from Dart safely reaches C `*_free` without race conditions.
- **Phase 5 (Vision Streaming):** The streaming pattern in `ev_generate_stream()` uses stream objects with token-by-token polling. Vision adds image encoding as a long blocking prefix before token generation starts. Research whether libmtmd supports incremental image encoding or if streaming can only begin after `mtmd_helper_eval_chunks` completes.
- **Phase 6 (Vulkan):** Vulkan device compatibility matrix across Android devices is poorly documented. Need device-specific testing plan. Research ggml Vulkan backend maturity and known device-specific issues.

Phases with standard patterns (skip deep research):
- **Phase 1 (Test Foundation):** Straightforward test writing. Patterns already exist in `core/tests/test_api_guards.cpp`.
- **Phase 3 (Adaptive Behavior):** Pattern already fully implemented in `AdaptiveSttService`. Replication to LLM/Vision is mechanical.
- **Phase 4 (Soak Test Expansion):** `SoakTestService` architecture already supports multiple workloads. Adding new modes is well-understood.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Codebase Architecture | HIGH | Direct source code analysis with file/line references. All claims verifiable. |
| Inference Concerns | HIGH | 16 concerns with specific file paths, line numbers, and code snippets. Severity rankings based on production impact analysis. |
| Android CPU Bottlenecks | HIGH | Documented SD845 evidence from soak test results. Performance numbers from actual device testing. |
| Memory Management Gaps | HIGH | Code analysis shows clear gaps (TODO stubs, missing memory_guard calls). Not speculative. |
| Vulkan Speedup Estimates | MEDIUM | 10-50x estimate is based on general GPU vs CPU benchmarks for transformer inference. Actual speedup will depend on device GPU, model size, and ggml Vulkan backend maturity. |
| Phase Effort Estimates | MEDIUM | Based on code complexity analysis but not validated against development velocity data. |

**Overall confidence:** HIGH

The research is based on direct source code analysis with specific file paths and line numbers. All 16 concerns are verifiable against the codebase. The main uncertainty is in effort estimates and Vulkan performance projections.

### Gaps to Address

- **Vulkan device compatibility:** No research into which Android devices support Vulkan 1.2+ and how ggml's Vulkan backend performs on them. Must be researched before Phase 6 planning.
- **Image generation on Android:** The codebase-map notes Image Gen is "untested on Android." Actual performance numbers and stability data are missing. Phase 4 soak testing should collect this data.
- **Quantized mmproj viability:** A quantized CLIP encoder (Q4/Q8) could significantly reduce vision encoding time on CPU, but quality impact is unknown. Needs empirical testing.
- **Cloud fallback architecture:** Concern 4A mentions a "cloud fallback option" for LLM on minimum-tier devices. The `ev_stream_get_token_info` confidence mechanism exists but no cloud integration is designed. This is a product decision, not a technical gap.
- **OpenMP static linking:** Concern 1A notes OpenMP is disabled on Android due to dlopen failures. Whether static linking of libgomp is viable (and what performance gain it provides over std::thread) is unresearched.

## Sources

### Primary (HIGH confidence)
- Direct source code analysis of `core/src/` (engine.cpp, vision_engine.cpp, whisper_engine.cpp, image_engine.cpp, memory_guard.cpp, backend_lifecycle.cpp)
- Direct source code analysis of `core/include/edge_veda.h` (public C API, 1072 lines)
- Direct source code analysis of `flutter/lib/src/` (FFI bindings, isolate workers, frame queue, scheduler, telemetry)
- Direct source code analysis of `flutter/example/lib/` (soak_test_service.dart, adaptive_stt_service.dart, vision_screen.dart)
- Direct source code analysis of `core/CMakeLists.txt` (build configuration, Vulkan/OpenMP/NEON flags)
- Direct source code analysis of `core/tests/` (existing test coverage)

### Secondary (MEDIUM confidence)
- SD845 soak test evidence (documented in code comments, not independently verified)
- Performance estimates (0.05 tok/s, 60s/frame) from documented device testing

### Tertiary (LOW confidence)
- Vulkan 10-50x speedup projection (general industry benchmarks, not Edge Veda specific)
- OpenMP performance impact estimate (theoretical, not measured)

---
*Research completed: 2026-03-08*
*Ready for roadmap: yes*
