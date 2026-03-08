# Inference Layer Concerns

**Analysis Date:** 2026-03-08

---

## 1. Android Inference Performance

### 1A. CPU-Only Path (All Workloads)

**Issue:** Android builds are CPU-only. Vulkan GPU acceleration is explicitly disabled and deferred to "Phase 7."

- Files: `core/CMakeLists.txt` (line 108: `set(GGML_VULKAN OFF CACHE BOOL "" FORCE)`)
- Impact: All four workloads (LLM, STT, Vision, Image Gen) run on CPU NEON only, causing:
  - LLM: ~0.05-0.1 tok/s on SD845 (vs 10+ tok/s on iOS Metal)
  - Vision: 60+ second latency per frame
  - STT: Whisper timeout failures on minimum/low-tier devices
  - Image Gen: Likely 10-30 minutes per image (512x512, 4 steps) -- untested on Android
- Current mitigation: Adaptive thread count capped at `min(cores/2, 4)` to prevent thermal throttle (`flutter/example/lib/soak_test_service.dart` line 780-786)
- Fix approach: Enable Vulkan backend (Phase 7). Requires `GGML_VULKAN ON`, Vulkan 1.2+ device detection, and fallback to CPU on unsupported devices.

### 1B. Threading Configuration

**Issue:** Default thread count is hardcoded to 4 across all engines when `num_threads=0` (auto-detect).

- Files:
  - `core/src/engine.cpp` line 370: `ctx_params.n_threads = config->num_threads > 0 ? static_cast<uint32_t>(config->num_threads) : 4;`
  - `core/src/vision_engine.cpp` line 185-186: same pattern
  - `core/src/whisper_engine.cpp` line 102: `ctx->default_threads = config->num_threads > 0 ? config->num_threads : 4;`
  - `core/src/image_engine.cpp` line 163: `ctx->default_threads = config->num_threads > 0 ? config->num_threads : 4;`
- Impact: On 8-core Android SoCs (big.LITTLE), 4 threads is reasonable but not adaptive. On 4-core devices, 4 threads saturates all cores and causes thermal throttle. On desktop (10+ cores), 4 threads underutilizes hardware.
- Fix approach: The Dart layer (`soak_test_service.dart` line 780-786) implements platform-aware thread selection. The C layer should mirror this: `min(sysconf(_SC_NPROCESSORS_ONLN) / 2, 4)` on Android, `min(cores, 6)` on macOS.

### 1C. Timeout Strategy

**Issue:** Platform-aware timeouts exist in Dart but are crude approximations.

- Files:
  - `flutter/lib/src/isolate/vision_worker.dart` line 180: `Platform.isAndroid ? 600 : 120` seconds for describe
  - `flutter/lib/src/isolate/worker_isolate.dart` line 208: `Platform.isAndroid ? 300 : 60` seconds for next token
  - `flutter/lib/src/whisper_session.dart` lines 86-103: Device-tier aware timeouts (2s chunks/90s timeout for minimum tier)
- Impact: Timeouts are static and device-tier-aware only for Whisper (via `AdaptiveSttService`). LLM and Vision use flat platform checks (Android vs not-Android) rather than actual device capability detection. A Pixel 9 Pro and a 2018 budget phone get the same 600s timeout.
- Fix approach: Use `DeviceProfile.detect().tier` (already exists for STT) to set timeouts for LLM and Vision workers too. The `DeviceTier` enum and `DeviceProfile` class exist in the codebase.

---

## 2. Memory Management

### 2A. Memory Guard: Auto-Cleanup Not Implemented

**Issue:** The auto-cleanup mechanism in `memory_guard.cpp` is a TODO stub.

- Files: `core/src/memory_guard.cpp` lines 253-257
  ```cpp
  if (g_memory_guard.auto_cleanup && usage_ratio >= 0.95f) {
      // TODO: Trigger cleanup in main library
      // This would need to be coordinated with engine.cpp
  }
  ```
- Impact: When memory usage hits 95% of limit, the memory guard fires the pressure callback but never actually unloads anything. The callback notifies Dart-side code, but there is no coordinated "evict least-recently-used model" logic. On Android with 800MB limit (`memory_guard.cpp` line 514), this means the app gets OOM-killed by LMK rather than gracefully unloading.
- Fix approach: Implement a `memory_guard_trigger_cleanup()` that calls a registered function pointer from `engine.cpp`. This function should clear KV caches first (cheapest), then unload embed_ctx (if present), then signal Dart to unload less-critical models.

### 2B. Memory Guard Is Global Singleton

**Issue:** `memory_guard.cpp` uses a single global `MemoryGuardState` shared across ALL context types.

- Files: `core/src/memory_guard.cpp` line 71: `MemoryGuardState g_memory_guard;`
- Impact: If an LLM context sets a 1.2GB limit and a Vision context sets a 800MB limit, the last `memory_guard_set_limit()` call wins. The memory guard cannot track per-context memory budgets. With 4 independent context types (LLM, Vision, Whisper, Image), this is a real collision risk.
- Fix approach: Either make memory guard per-context (pass context pointer), or change the limit to be a process-wide budget that all contexts share (which is the current intent, but not documented/enforced).

### 2C. No Cross-Engine Memory Coordination

**Issue:** Each engine type (LLM, Vision, Whisper, Image Gen) loads its model independently with no awareness of what other engines have loaded.

- Files:
  - `core/src/engine.cpp` line 357: `llama_model_load_from_file()` -- LLM
  - `core/src/vision_engine.cpp` line 160: `llama_model_load_from_file()` -- Vision
  - `core/src/whisper_engine.cpp` line 116: `whisper_init_from_file_with_params()` -- Whisper
  - `core/src/image_engine.cpp` line 198: `new_sd_ctx()` -- Image Gen
- Impact: Loading a 7B VLM (4GB) + a 1B LLM (700MB) + Whisper base (140MB) + SD Turbo (2GB) simultaneously would require ~7GB, far exceeding any mobile device's budget. There is no logic to check total loaded model memory before loading a new model.
- Fix approach: The Dart layer (`EdgeVeda` class in `edge_veda_impl.dart`) should track total loaded model memory and refuse to load a new model if it would exceed the memory guard limit. Alternatively, implement an LRU eviction policy that auto-disposes the least-recently-used model when a new load would exceed budget.

### 2D. Vision Context Lacks Memory Guard Integration

**Issue:** Vision, Whisper, and Image contexts do not call `memory_guard_set_limit()` or participate in memory pressure callbacks.

- Files:
  - `core/src/engine.cpp` lines 399-401: LLM sets memory limit via `memory_guard_set_limit()`
  - `core/src/vision_engine.cpp`: No memory guard calls anywhere
  - `core/src/whisper_engine.cpp`: No memory guard calls anywhere
  - `core/src/image_engine.cpp`: No memory guard calls anywhere
- Impact: Only the LLM engine participates in memory monitoring. Vision, Whisper, and Image Gen models are invisible to the memory guard, meaning their memory usage is untracked and they will never trigger pressure callbacks.
- Fix approach: Each engine's init function should call `memory_guard_set_limit()` (or accumulate into the global limit). Each engine's free function should update the guard.

---

## 3. Soak Test Gaps

### 3A. Soak Test Covers Only Vision

**Issue:** The soak test (`SoakTestService`) only exercises the vision pipeline. LLM, STT, and Image Gen are not soak-tested.

- Files: `flutter/example/lib/soak_test_service.dart`
  - Line 46: `final VisionWorker _visionWorker = VisionWorker();` -- only vision worker
  - Lines 154-177: Workload selection is `vision` (camera/screen) or `text` (manual only)
  - The `text` path (line 176) only monitors user activity -- it does not auto-generate LLM requests
- Impact: The soak test validates:
  - Vision inference stability over 35 minutes
  - Memory leak detection (RSS tracking)
  - Thermal behavior under sustained vision load
  - Battery drain under vision load

  The soak test does NOT validate:
  - LLM streaming under sustained load (multi-turn conversations)
  - Whisper STT under sustained audio input
  - Image generation under repeated prompts
  - Concurrent workloads (Vision + LLM + STT simultaneously)
  - Model switching/reloading under memory pressure
- Fix approach: Add workload modes to `SoakTestService`:
  1. `WorkloadId.text` -- Auto-generate LLM prompts in a loop
  2. `WorkloadId.stt` -- Feed synthetic or recorded audio in a loop
  3. `WorkloadId.imageGen` -- Generate images in a loop
  4. `WorkloadId.mixed` -- Rotate between all workloads

### 3B. Soak Test Does Not Validate OOM Recovery

**Issue:** The soak test monitors RSS but never tests what happens when memory approaches the limit.

- Files: `flutter/example/lib/soak_test_service.dart` line 743: `_trace?.record(stage: 'rss_bytes', value: snap.memoryRssBytes.toDouble());` -- records but doesn't assert
- Impact: There is no test that:
  1. Loads a large model (near memory limit)
  2. Runs inference until memory climbs
  3. Verifies the app either gracefully unloads or recovers (vs crash/OOM kill)
- Fix approach: Add a "memory stress" soak mode that intentionally loads multiple models and monitors for graceful degradation vs crash.

### 3C. Soak Test Android GPU Field Missing

**Issue:** The soak test sets `useGpu: Platform.isIOS` (line 166), meaning Android always runs CPU-only in soak tests even when Vulkan is eventually enabled.

- Files: `flutter/example/lib/soak_test_service.dart` line 166: `useGpu: Platform.isIOS,`
- Impact: When Vulkan support is added (Phase 7), the soak test will not exercise the GPU path on Android.
- Fix approach: Change to `useGpu: Platform.isIOS || (Platform.isAndroid && gpuAvailable)` where `gpuAvailable` checks `getGpuBackend() != "CPU"`.

---

## 4. Adaptive Behavior Gaps

### 4A. STT Has Adaptive Pipeline; LLM/Vision Do Not

**Issue:** The STT pipeline has a sophisticated adaptive system (`AdaptiveSttService`, device-tier detection, automatic fallback to system STT). LLM and Vision have no equivalent.

- Files:
  - `flutter/example/lib/adaptive_stt_service.dart`: Full adaptive system with:
    - Device tier detection (`DeviceTier.minimum`, `low`, `medium`)
    - Chunk size adaptation (2000ms for slow, 3000ms for fast)
    - Timeout adaptation (30s to 90s based on tier)
    - Automatic fallback to Android SpeechRecognizer after 2 consecutive failures
  - `flutter/lib/src/isolate/worker_isolate.dart`: LLM has flat platform timeout only
  - `flutter/lib/src/isolate/vision_worker.dart`: Vision has flat platform timeout only
- Impact: On minimum-tier Android devices:
  - STT gracefully degrades to system STT -- user still gets transcription
  - LLM has no fallback -- user waits 5 minutes per response or gets a timeout error
  - Vision has no fallback -- user waits 10 minutes per frame or gets a timeout error
- Fix approach for LLM:
  1. Detect device tier at init time
  2. On minimum/low tier: reduce `max_tokens` default, reduce `context_size`, use smaller model recommendation
  3. On timeout: offer cloud fallback option (confidence handoff mechanism already exists in `ev_stream_get_token_info`)
- Fix approach for Vision:
  1. Detect device tier at init time
  2. On minimum/low tier: reduce image resolution more aggressively (already partially done: 128px cap in soak test)
  3. On timeout: return partial description or error with specific guidance

### 4B. No Adaptive Thread Count at C Layer

**Issue:** The C layer always defaults to 4 threads regardless of device capability. All adaptation happens in Dart.

- Files: See section 1B above
- Impact: Direct C API consumers (Swift, Kotlin apps using the SDK directly) get no adaptive behavior. The 4-thread default is a compromise that's suboptimal for both low-end (too many threads) and high-end (too few threads) devices.
- Fix approach: When `num_threads=0` (auto-detect), the C layer should use:
  ```cpp
  #if defined(__ANDROID__)
      int cores = sysconf(_SC_NPROCESSORS_ONLN);
      int threads = std::min(std::max(cores / 2, 1), 4);
  #elif defined(__APPLE__)
      int cores = sysconf(_SC_NPROCESSORS_ONLN);
      int threads = std::min(cores, 6);
  #else
      int threads = std::min(sysconf(_SC_NPROCESSORS_ONLN), 8);
  #endif
  ```

### 4C. Vision Has No Frame Resolution Adaptation

**Issue:** The vision C API (`ev_vision_describe`) accepts whatever resolution is passed in. All resolution management is in Dart.

- Files:
  - `core/src/vision_engine.cpp` line 283-296: Accepts raw bytes with width/height, no validation of reasonable limits
  - `flutter/example/lib/soak_test_service.dart` lines 606-619: Dart-side 128px cap for mobile, 320px for macOS
- Impact: If a developer passes a 4K image (3840x2160) to `ev_vision_describe`, the CLIP encoder will attempt to process it, consuming enormous memory and taking potentially hours on CPU. No warning, no automatic downscaling.
- Fix approach: Add resolution clamping in `ev_vision_describe()` itself (e.g., max 640px longest edge), or at minimum document the expected resolution range in `edge_veda.h`.

---

## 5. Test Coverage Blind Spots

### 5A. No Dart-Side Inference Tests

**Issue:** All Dart tests are unit tests for pure-logic modules. None test actual inference.

- Files in `flutter/test/`:
  - `budget_test.dart` -- Budget/scheduler logic (pure Dart)
  - `json_recovery_test.dart` -- JSON recovery (pure Dart)
  - `latency_tracker_test.dart` -- Latency math (pure Dart)
  - `runtime_policy_test.dart` -- QoS policy (pure Dart)
  - `schema_validator_test.dart` -- Schema validation (pure Dart)
  - `text_cleaner_test.dart` -- Text cleaning (pure Dart)
  - `memory_estimator_test.dart` -- Memory estimation (pure Dart)
  - `model_manager_test.dart` -- Model manager (pure Dart)
  - `android_plugin_test.dart` -- Android plugin registration (mock)
  - `android_build_script_test.dart` -- Build script validation
  - `macos_plugin_test.dart` -- macOS plugin registration (mock)
  - `edge_veda_test.dart` -- Basic SDK setup (mock)
- Impact: Zero Dart integration tests verify that `EdgeVeda.generate()`, `EdgeVeda.generateStream()`, `WhisperSession`, `VisionWorker`, or `ImageWorker` actually work end-to-end. All tests mock the FFI layer. A regression in FFI bindings, isolate communication, or native/Dart marshalling would be invisible to CI.
- Fix approach: Add at minimum one integration test per workload type that loads a tiny model (e.g., TinyLlama 1.1B Q4) and verifies output. Mark these as slow tests that run on device only (not in CI without a device).

### 5B. C++ Tests Cover LLM Only

**Issue:** The C++ test suite (`core/tests/`) tests LLM generation and embeddings but nothing else.

- Files:
  - `core/tests/test_api_guards.cpp` -- NULL-path guards for LLM API only. No guards tested for `ev_vision_*`, `ev_whisper_*`, or `ev_image_*`.
  - `core/tests/test_inference.cpp` -- Model load + text generation smoke test
  - `core/tests/test_model_backed.cpp` -- Stream lifecycle, single-stream enforcement, embeddings
- Impact: There are zero C-level tests for:
  - `ev_vision_init`, `ev_vision_describe`, `ev_vision_free` -- not even NULL guards
  - `ev_whisper_init`, `ev_whisper_transcribe`, `ev_whisper_free` -- not even NULL guards
  - `ev_image_init`, `ev_image_generate`, `ev_image_free` -- not even NULL guards
  - Memory guard functions (`memory_guard_*`) -- no unit tests at all
  - Backend lifecycle reference counting -- no test for acquire/release pairing
- Fix approach:
  1. Add NULL-guard tests for all Vision, Whisper, and Image APIs to `test_api_guards.cpp`
  2. Add model-backed tests for Vision (requires VLM + mmproj GGUF)
  3. Add model-backed tests for Whisper (requires whisper model GGUF)
  4. Add memory guard unit tests (can be CI-safe, no model needed)

### 5C. No Concurrency Tests

**Issue:** There are no tests for concurrent access patterns.

- Files: The entire test suite is single-threaded
- Impact: Known thread safety issues have been fixed (issue #25 active_stream_count, issue #26 model_desc race, issue #28 use-after-free, issue #29 single-stream enforcement, issue #33 grammar string ownership) but none of these fixes have regression tests that actually exercise concurrent access. The fixes were validated by code review, not by stress tests.
- Fix approach: Add a C++ test that:
  1. Calls `ev_generate_stream()` and `ev_embed()` from two threads simultaneously (should fail gracefully due to single-stream enforcement)
  2. Calls `ev_free()` while a stream is active (should trigger assert in debug, not crash in release)
  3. Calls `ev_stream_next()` from one thread while `ev_stream_cancel()` from another

### 5D. No Regression Test for memory_guard_get_recommended_limit()

**Issue:** The Android-specific tiered memory limits in `memory_guard_get_recommended_limit()` are untested.

- Files: `core/src/memory_guard.cpp` lines 503-535
  - 800MB for 4-6GB devices
  - 1000MB for 8GB devices
  - 1200MB for 12GB+ devices
  - 1200MB flat for iOS
  - 60% of total for desktop
- Impact: These limits are the foundation of OOM prevention on Android. A regression (e.g., returning 0, or returning the wrong tier) would cause either OOM kills or unnecessary model unloads. No test validates the tiering logic.
- Fix approach: Add a C++ unit test that mocks `get_total_physical_memory()` return values and verifies the recommended limits match the documented tiers.

### 5E. No Image Generation Tests Anywhere

**Issue:** Image generation (`ev_image_*` API) has zero tests at any level.

- Files:
  - `core/src/image_engine.cpp` -- 360 lines of code, 0 tests
  - `flutter/lib/src/isolate/image_worker.dart` -- 474 lines of code, 0 tests
  - `flutter/example/lib/image_screen.dart` -- UI only, no automated test
- Impact: The entire Stable Diffusion integration is tested exclusively by manual use. Regressions in model loading, progress callbacks, pixel data extraction, or memory management would go undetected.
- Fix approach: At minimum, add NULL-guard tests for `ev_image_init(NULL, ...)`, `ev_image_generate(NULL, ...)`, `ev_image_free(NULL)`, `ev_image_free_result(NULL)`.

---

## 6. Additional Concerns

### 6A. Vision Inference Is Blocking (No Streaming)

**Issue:** `ev_vision_describe` is a single blocking call with no streaming equivalent.

- Files: `core/src/vision_engine.cpp` line 283: `ev_error_t ev_vision_describe(...)` -- blocking call
- Impact: On CPU-only Android, this single call can block for 60+ seconds. There is no way for the Dart layer to:
  1. Show incremental progress (tokens as they generate)
  2. Cancel mid-generation
  3. Report partial results on timeout
- Current mitigation: The Dart `VisionWorker` runs in a separate isolate so the UI doesn't freeze, but the user still waits with no progress indicator during token generation (only image encoding progress is measurable).
- Fix approach: Add `ev_vision_describe_stream()` analogous to `ev_generate_stream()` that returns tokens incrementally. This would enable cancel support and partial results.

### 6B. Image Generation Has No Cancel Support

**Issue:** `ev_image_generate` is blocking with no cancellation mechanism.

- Files: `core/src/image_engine.cpp` line 298: `sd_image_t* images = generate_image(ctx->sd_ctx, &gen_params);` -- fully blocking
- Impact: If a user starts image generation (15-60 seconds on GPU, potentially 10+ minutes on CPU), there is no way to cancel it. The progress callback fires step updates, but there is no cancel path.
- Fix approach: stable-diffusion.cpp supports a cancel callback mechanism. Wire it through the `ev_image_context` to allow Dart-side cancellation.

### 6C. Backend Lifecycle Reference Counting Not Tested

**Issue:** `backend_lifecycle.cpp` uses a simple refcount for `llama_backend_init/free`, but edge cases are untested.

- Files: `core/src/backend_lifecycle.cpp` lines 27-47
- Impact: If `edge_veda_backend_release()` is called more than `acquire()` (bug in caller), the guard prevents negative refcount but the backend may be freed prematurely. If multiple threads call `acquire()` and `release()` simultaneously, the mutex protects the refcount, but `llama_backend_init()` itself may not be thread-safe.
- Fix approach: Add a test that:
  1. Calls acquire() N times, release() N times, verifies backend_free called exactly once
  2. Calls release() without acquire() -- should not crash

### 6D. ev_image_free Has Lock-Before-Delete Anti-Pattern

**Issue:** Both `ev_image_free` and `ev_whisper_free` lock a mutex on the object being deleted, then delete the object while the lock_guard is still in scope.

- Files:
  - `core/src/image_engine.cpp` lines 220-235:
    ```cpp
    void ev_image_free(ev_image_context ctx) {
        if (!ctx) return;
        std::lock_guard<std::mutex> lock(ctx->mutex);
        // ... free sd_ctx ...
        delete ctx;  // mutex destroyed while lock_guard holds it
    }
    ```
  - `core/src/whisper_engine.cpp` lines 138-156: Same pattern
- Impact: The code comments acknowledge this ("Note: unlock before delete... This is safe because we hold the only reference"). This is technically undefined behavior per the C++ standard -- destroying a mutex while it's locked. In practice it works on all major implementations, but sanitizers may flag it.
- Fix approach: Copy the pattern from `ev_free()` in `engine.cpp` which correctly scopes the lock:
  ```cpp
  {
      std::lock_guard<std::mutex> lock(ctx->mutex);
      // cleanup
  }
  delete ctx;
  ```

---

## Priority Summary

| Concern | Severity | Effort | Recommendation |
|---------|----------|--------|----------------|
| 2A. Memory guard auto-cleanup is TODO stub | **High** | Medium | Implement before shipping Android |
| 5B. No C++ tests for Vision/Whisper/Image APIs | **High** | Low | Add NULL-guard tests immediately |
| 3A. Soak test covers only Vision | **High** | Medium | Add LLM + STT soak modes |
| 2C. No cross-engine memory coordination | **High** | High | Implement LRU model eviction in Dart |
| 1A. Android CPU-only path | **High** | High | Phase 7 Vulkan (already planned) |
| 5A. No Dart integration tests | **Medium** | Medium | Add per-workload integration tests |
| 6A. Vision inference is blocking | **Medium** | Medium | Add streaming vision API |
| 4A. LLM/Vision lack adaptive behavior | **Medium** | Medium | Port device-tier logic from STT |
| 2D. Vision/Whisper/Image not in memory guard | **Medium** | Low | Add memory_guard calls to init/free |
| 6D. Lock-before-delete UB | **Low** | Low | Fix mutex scoping in 2 files |
| 5C. No concurrency tests | **Medium** | Medium | Add thread stress tests |
| 6B. Image gen has no cancel | **Low** | Low | Wire sd.cpp cancel callback |

---

*Inference layer concerns audit: 2026-03-08*
