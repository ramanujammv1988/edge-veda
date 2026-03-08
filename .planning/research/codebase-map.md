# Edge Veda Codebase Map: Inference Architecture & Performance

**Analysis Date:** 2026-03-08
**Focus:** Vision pipeline, soak test infrastructure, native inference layer, Android CPU-only bottlenecks

---

## 1. Vision Pipeline: End-to-End Architecture

### Overview

The vision pipeline follows a **persistent worker isolate** pattern. A VisionWorker isolate loads the VLM model + mmproj ONCE, then processes frames sequentially via message-passing. The native context pointer NEVER crosses the isolate boundary.

### Data Flow

```
Camera/Screen → RGB conversion (Dart) → FrameQueue → VisionWorker isolate
    → FFI: ev_vision_describe() → mtmd_tokenize + mtmd_helper_eval_chunks
    → llama token generation loop → output string → Dart response
```

### Key Files

| File | Purpose |
|------|---------|
| `flutter/lib/src/isolate/vision_worker.dart` | Worker isolate manager (spawn, init, describeFrame, dispose) |
| `flutter/lib/src/isolate/vision_worker_messages.dart` | Typed sealed classes for isolate communication |
| `flutter/lib/src/frame_queue.dart` | Bounded queue (capacity=1) with drop-newest backpressure |
| `flutter/lib/src/camera_utils.dart` | BGRA→RGB (iOS), YUV420→RGB (Android), resize |
| `flutter/example/lib/vision_screen.dart` | UI: camera stream + file picker + description overlay |
| `core/src/vision_engine.cpp` | Native C implementation of ev_vision_* API |
| `core/include/edge_veda.h` | Public C API header (ev_vision_config, ev_vision_describe, ev_timings_data) |

### Vision Pipeline Initialization

```dart
// flutter/example/lib/vision_screen.dart, line 132-141
await _visionWorker.spawn();
await _visionWorker.initVision(
  modelPath: _modelPath!,
  mmprojPath: _mmprojPath!,
  numThreads: 4,
  contextSize: 4096,
  // Android build is CPU-only (Vulkan disabled); GPU only on iOS (Metal).
  useGpu: Platform.isIOS,
);
```

### Timeout/Fallback Analysis (KEY QUESTION)

**Does the vision pipeline have the same timeout/fallback issues as STT on low-end Android?**

**YES, but partially mitigated.** Here is the exact timeout logic:

```dart
// flutter/lib/src/isolate/vision_worker.dart, line 178-181
// describeFrame() timeout:
final timeout = Duration(seconds: Platform.isAndroid ? 600 : 120);
return await completer.future.timeout(timeout);
```

The vision pipeline uses a **platform-aware timeout**: 600 seconds (10 minutes) on Android vs 120 seconds on iOS/macOS. This is extremely generous -- contrast with WhisperSession's configurable timeout (30-90 seconds).

**Critical differences from STT fallback system:**

1. **No automatic fallback mechanism.** The STT pipeline has `AdaptiveSttService` (`flutter/example/lib/adaptive_stt_service.dart`) that switches to Android's SpeechRecognizer after 2 consecutive Whisper failures. Vision has NO equivalent -- if CPU-only inference is too slow, the frame just eventually returns or times out.

2. **No consecutive failure tracking.** WhisperSession tracks `onFallbackNeeded(consecutiveFailures)`. VisionWorker has no failure counter or degradation path.

3. **Soak test mitigations exist but are aggressive.** The soak test service (`flutter/example/lib/soak_test_service.dart`) works around slow Android inference with:
   - **Grab-and-stop camera pattern** (line 576-623): Captures ONE frame, stops camera stream, runs inference, then restarts camera. This eliminates GC pressure from unused YUV allocations.
   - **128px downscale** (line 605-619): Downscales to 128px longest side for CPU-only devices. Comment explains: "CLIP patch count scales quadratically (720x480 → ~1734 patches; 128x85 → ~54 patches → ~1000x faster attention on CPU)."
   - **Adaptive thread count** (line 779-786): Caps at half-cores (max 4) on Android to prevent thermal throttle on big.LITTLE SoCs.

4. **VisionScreen (non-soak) uses 768px max** (`_maxInferenceDimension = 768`, line 22), which is much larger than soak's 128px. This means regular vision usage on low-end Android is MUCH slower than soak test vision.

**Risk assessment:** On CPU-only Android (e.g., Snapdragon 845), regular vision screen inference at 768px will take **minutes per frame** with no fallback. The soak test's 128px makes it barely viable (~60s/frame per the documented SD845 evidence). There is no "system vision" fallback equivalent to system STT.

### Native Vision Engine Internals

The C++ vision engine (`core/src/vision_engine.cpp`) uses llama.cpp's **libmtmd** (multimodal) library:

```
ev_vision_describe():
  1. mtmd_bitmap_init(width, height, rgb_bytes)     ← Create bitmap from RGB888
  2. mtmd_tokenize(mtmd_ctx, chunks, text, bitmaps)  ← Tokenize prompt + image
  3. mtmd_helper_eval_chunks(...)                     ← Evaluate (image encode + prompt eval)
  4. Token generation loop (llama_sampler_sample → llama_decode, repeated)
  5. Free chunks immediately after eval (P2 memory explosion fix)
```

**Timing instrumentation:** `ev_vision_get_last_timings()` returns:
- `model_load_ms` (from llama_perf_context)
- `image_encode_ms` (measured around mtmd_helper_eval_chunks via clock_gettime)
- `prompt_eval_ms` (from llama_perf_context)
- `decode_ms` (from llama_perf_context)
- `prompt_tokens` and `generated_tokens` counts

**Thread safety:** Vision context has its own mutex, independent from text context. Blocking call -- only one inference at a time per vision context.

### FrameQueue Backpressure

```dart
// flutter/lib/src/frame_queue.dart
// Drop-newest policy: new frames REPLACE pending slot (not queue up)
// Only 1 pending slot: at most 1 frame waits while inference runs
// NOT thread-safe -- runs on main Dart isolate (single-threaded event loop)
```

The FrameQueue prevents unbounded frame accumulation during slow inference. On slow devices, most camera frames are dropped. The `droppedFrames` counter is tracked by the soak test for trace analysis.

---

## 2. Soak Test Infrastructure

### Architecture

```
SoakTestService (singleton, ChangeNotifier)
    ├── VisionWorker (persistent isolate)
    ├── FrameQueue (drop-newest backpressure)
    ├── TelemetryService (thermal, battery, memory polling)
    ├── RuntimePolicy (QoS level evaluation)
    ├── Scheduler (budget enforcement, optional)
    ├── PerfTrace (JSONL trace file)
    └── Camera/ScreenCapture (frame source)
```

**File:** `flutter/example/lib/soak_test_service.dart`

### What it measures

The soak test records the following metrics every frame and every 2 seconds:

**Per-frame (via PerfTrace):**
- `image_encode` -- ms for CLIP image encoding
- `prompt_eval` -- ms for prompt evaluation
- `decode` -- ms for token generation
- `total_inference` -- wall-clock ms for full describeFrame()
- `prompt_tokens` and `generated_tokens` counts

**Every 2 seconds (telemetry polling):**
- `rss_bytes` -- process RSS memory
- `thermal_state` -- 0-3 thermal level
- `battery_level` -- 0.0-1.0
- `available_memory` -- bytes available

**Aggregated in-memory:**
- Frame count, total tokens, avg/last latency, dropped frames
- Budget violations (actionable vs observe-only)
- Measured baseline (p95 latency, battery drain rate)

### Does soak test cover vision?

**YES -- it is primarily a vision soak test.** On camera-supported platforms (iOS, Android, macOS), the soak test runs continuous vision inference.

```dart
// flutter/example/lib/soak_test_service.dart, line 154
_workloadId = cameraSupported ? WorkloadId.vision : WorkloadId.text;
```

- **iOS/Android:** Camera → VisionWorker (grab-and-stop pattern, 128px downscale)
- **macOS:** Screen capture at ~0.7 FPS → VisionWorker (320px downscale)
- **Non-camera platforms:** Falls back to monitoring user-driven inference events

### Soak test modes

1. **Managed mode** (`_isManaged = true`): Uses Scheduler with adaptive budget (BudgetProfile.balanced). Scheduler polls telemetry, degrades QoS on thermal/battery pressure, emits budget violations.

2. **Raw mode** (`_isManaged = false`): Fixed knobs (fps=2, res=640, tok=100), no QoS adaptation. Device may thermally throttle.

### Duration and known limitations

```dart
static const _testDuration = Duration(minutes: 35);
```

**35 minutes** (increased from 30). Comment explains: "SD845 testing showed thermal ramp-up can take 25+ minutes before reaching steady state."

**Known CPU-only Android limitation (documented in class comment):**
> On devices without Vulkan GPU support (e.g. Snapdragon 845), soak tests run CPU-only with very low throughput (~0.05 tok/s, 60+ second latency per frame). SD845 evidence shows 2/6 criteria PASS (no crash, no memory leak) while thermal monitoring and battery drain assertions fail due to sustained CPU load.

### Vision model selection in soak test

```dart
// flutter/example/lib/soak_test_service.dart, line 341-349
final candidates = Platform.isMacOS
    ? [ModelRegistry.qwen2vl_7b, ModelRegistry.llava16_mistral_7b, ModelRegistry.smolvlm2_500m]
    : [ModelRegistry.smolvlm2_500m];
```

- **macOS:** Prefers Qwen2-VL 7B > LLaVA 1.6 7B > SmolVLM2 500M
- **Mobile:** Always SmolVLM2 500M (smallest, ~620MB model + ~110MB mmproj)

### External inference recording

The soak test can also track non-soak vision inferences (e.g., VisionScreen):

```dart
// flutter/example/lib/soak_test_service.dart, line 639-668
void recordExternalInference({source, latencyMs, generatedTokens, workloadId})
```

VisionScreen calls this after each `describeFrame()` to feed latency data into the soak scheduler.

---

## 3. Native Inference Layer

### Architecture

```
Flutter (Dart) ──FFI──> edge_veda.h C API ──> engine.cpp (text), vision_engine.cpp, whisper_engine.cpp, image_engine.cpp
                                                    │              │                  │                    │
                                                    └──> llama.cpp └──> llama.cpp     └──> whisper.cpp    └──> stable-diffusion.cpp
                                                                       + libmtmd
                                                                                    ↑ All share ggml backend
```

### Core C++ Source Files

| File | Lines | Purpose |
|------|-------|---------|
| `core/src/engine.cpp` | ~1334 | Text LLM: ev_init, ev_generate, ev_generate_stream, ev_embed |
| `core/src/vision_engine.cpp` | ~486 | Vision: ev_vision_init, ev_vision_describe, ev_vision_get_last_timings |
| `core/src/whisper_engine.cpp` | ~200+ | STT: ev_whisper_init, ev_whisper_transcribe |
| `core/src/image_engine.cpp` | ~200+ | Image gen: ev_image_init, ev_image_generate |
| `core/src/memory_guard.cpp` | ~653 | Platform-specific RSS monitoring, pressure callbacks |
| `core/src/backend_lifecycle.cpp` | ~49 | Reference-counted llama_backend_init/free |
| `core/include/edge_veda.h` | ~1072 | Public C API header |

### FFI Binding Layer

**File:** `flutter/lib/src/ffi/bindings.dart` (~1358 lines)

Library loading per platform:
```dart
if (Platform.isAndroid) DynamicLibrary.open('libedge_veda.so');
if (Platform.isIOS) DynamicLibrary.open('EdgeVedaCore.framework/EdgeVedaCore');
if (Platform.isMacOS) DynamicLibrary.process(); // statically linked
```

Singleton pattern: `EdgeVedaNativeBindings.instance` lazily initializes and caches all lookups.

### Third-Party Dependencies (all compiled from source)

| Library | Path | Purpose | Backend |
|---------|------|---------|---------|
| llama.cpp | `core/third_party/llama.cpp/` | Text LLM + ggml compute | Metal (Apple), CPU (Android) |
| libmtmd | `core/third_party/llama.cpp/tools/mtmd/` | Multimodal vision (CLIP, image encoding) | Via ggml |
| whisper.cpp | `core/third_party/whisper.cpp/` | Speech-to-text | Shares ggml from llama.cpp |
| stable-diffusion.cpp | `core/third_party/stable-diffusion.cpp/` | Text-to-image | Shares ggml from llama.cpp |

**All three share the same ggml backend** -- compiled once from llama.cpp, reused by whisper.cpp and stable-diffusion.cpp.

### Build Configuration (CMake)

**File:** `core/CMakeLists.txt`

**Android-specific critical settings:**
```cmake
# CRITICAL: CPU-only build for Phase 5 (Vulkan deferred to Phase 7)
set(GGML_VULKAN OFF CACHE BOOL "" FORCE)

# CRITICAL: Disable OpenMP - causes dlopen failures on many Android devices
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)

# ARM targets: enable NEON (SIMD), disable LLAMAFILE (x86-only)
set(GGML_NEON ON CACHE BOOL "" FORCE)
set(GGML_LLAMAFILE OFF CACHE BOOL "" FORCE)
```

**Apple-specific:**
```cmake
set(GGML_METAL ON CACHE BOOL "" FORCE)
set(GGML_METAL_EMBED_LIBRARY ON CACHE BOOL "" FORCE)
set(GGML_ACCELERATE ON CACHE BOOL "" FORCE)
```

### Thread Safety Model

From `core/include/edge_veda.h` (lines 171-190):
```
Lock ordering (always acquire in this order to prevent deadlock):
  1. ev_stream::mutex   (stream-level, acquired first)
  2. ev_context::mutex  (context-level, acquired second)
```

Each engine type (text, vision, whisper, image) has its own independent context with its own mutex. The Dart SDK serializes all commands through isolate SendPort/ReceivePort, so lock ordering is not observable from Dart.

### Memory Management

**memory_guard.cpp** provides platform-specific RSS monitoring:
- **Apple:** `mach_task_basic_info` (resident_size)
- **Android/Linux:** `/proc/self/statm` (RSS in pages)
- **Windows:** `GetProcessMemoryInfo` (WorkingSetSize)

Background monitoring thread polls every 1 second when a memory limit is set. Triggers callback at 90% threshold.

**Recommended limits (from memory_guard.cpp line 503-535):**
- Android 4-6GB devices: 800MB
- Android 8GB devices: 1GB
- Android 12GB+ devices: 1.2GB
- iOS: 1.2GB (jetsam is more predictable)
- Desktop: 60% of total RAM

**Backend lifecycle** (`core/src/backend_lifecycle.cpp`): Reference-counted `llama_backend_init`/`llama_backend_free`. Multiple contexts can coexist. Backend freed only when last context is released.

---

## 4. Android CPU-Only Bottleneck Analysis

### Current State

Android builds are **CPU-only** with NEON SIMD. Vulkan GPU acceleration is explicitly disabled:
```cmake
# core/CMakeLists.txt line 108
set(GGML_VULKAN OFF CACHE BOOL "" FORCE)  # Phase 5: CPU-only, Vulkan deferred to Phase 7
```

### Where Time is Spent (Vision Pipeline)

Based on the timing instrumentation in `core/src/vision_engine.cpp` and soak test observations:

1. **Image encoding (CLIP)** -- `mtmd_helper_eval_chunks()` -- This is the **dominant bottleneck** on CPU-only Android. CLIP processes image patches through transformer attention. Patch count scales **quadratically** with resolution:
   - 720x480 → ~1734 patches → extremely slow on CPU
   - 128x85 → ~54 patches → ~1000x fewer attention operations
   - The soak test mitigates by downscaling to 128px (line 611 of soak_test_service.dart)

2. **Token generation (decode)** -- Sequential `llama_decode()` calls, one token at a time. Each call involves a full forward pass through the model. SmolVLM2 500M is already very small; throughput ~0.05 tok/s on SD845.

3. **Prompt evaluation** -- One-time cost per frame for the text prompt tokens. Relatively fast for short prompts.

### Performance Numbers (from documented SD845 evidence)

- **Throughput:** ~0.05 tok/s on Snapdragon 845 (CPU-only)
- **Latency per frame:** 60+ seconds at 128px resolution
- **Soak result:** 2/6 criteria PASS (no crash, no memory leak), thermal/battery fail

### Specific Bottlenecks and Opportunities

**1. No GPU acceleration (Vulkan deferred to Phase 7)**

The single biggest opportunity. Vulkan would offload matrix multiplications to the GPU, potentially 10-50x speedup for image encoding. The CMakeLists.txt already has the infrastructure:
```cmake
option(EDGE_VEDA_ENABLE_VULKAN "Enable Vulkan backend for Android" OFF)
```

**2. Image encoding is not optimized for mobile resolution**

VisionScreen uses `_maxInferenceDimension = 768` (line 22 of vision_screen.dart). The soak test uses 128px. There is no adaptive resolution based on device tier -- it is either 768 (normal usage) or 128 (soak test). A DeviceTier-aware resolution selector would help:
- Minimum tier: 128px (current soak behavior)
- Low tier: 256px
- Medium tier: 384px
- High tier: 768px

**3. No vision model tier selection on Android**

The soak test always uses SmolVLM2 500M on mobile. But VisionScreen uses `ModelSelector.bestVision()` which may try larger models. There is no enforcement that CPU-only devices use the smallest model.

**4. Camera frame conversion is pure Dart**

`CameraUtils.convertYuv420ToRgb()` and `resizeRgb()` (in `flutter/lib/src/camera_utils.dart`) are **pure Dart pixel loops**. On Android, camera frames are YUV420 which requires per-pixel color space conversion. This could be done natively (via a JNI/FFI helper) for significant speedup, especially at higher resolutions.

**5. OpenMP is disabled on Android**

```cmake
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
```

Comment: "causes dlopen failures on many Android devices that don't ship libgomp." This means ggml's CPU parallelism relies on `std::thread` instead of OpenMP, which may be less efficient for parallel matrix operations. Investigating static linking of OpenMP or using pthreads-based parallelism could help.

**6. No batch processing of vision frames**

Each frame is processed completely independently -- the KV cache is cleared between frames (`llama_memory_clear` at vision_engine.cpp line 315). For continuous camera scanning, the prompt text is identical each time, so prompt evaluation could potentially be cached across frames (only re-encoding the new image).

**7. No quantized CLIP/vision encoder**

The mmproj for SmolVLM2 is F16. A quantized mmproj (Q4 or Q8) would reduce both memory and compute for image encoding, though quality may degrade.

---

## 5. Comparison: Vision vs STT Resilience on Low-End Android

| Aspect | STT (Whisper) | Vision |
|--------|---------------|--------|
| **Fallback mechanism** | AdaptiveSttService auto-switches to Android SpeechRecognizer | **None** -- no system vision fallback |
| **Timeout** | Configurable (30-90s based on DeviceTier) | Fixed: 600s on Android, 120s on iOS |
| **Consecutive failure tracking** | Yes, via onFallbackNeeded callback | **No** |
| **Adaptive config** | chunkSizeMs and timeout based on DeviceTier | Resolution only adapted in soak test (128px), not in VisionScreen |
| **GC pressure mitigation** | N/A (audio is small) | Grab-and-stop camera pattern (soak only) |
| **Model tier selection** | Single model (whisper-tiny.en) | SmolVLM2 500M on mobile, larger on macOS |
| **Device tier awareness** | Yes, via DeviceProfile.detect() | **Minimal** -- only soak test adapts resolution |

### Recommended improvements for vision resilience

1. **Add DeviceTier-aware resolution selection in VisionScreen** (not just soak test)
2. **Add a vision timeout that is based on DeviceTier** instead of platform-only
3. **Add consecutive failure tracking with user-facing degradation** (reduce resolution, reduce maxTokens, show "low-end device" warning)
4. **Port the grab-and-stop camera pattern from soak test to VisionScreen** for CPU-only devices
5. **Vulkan GPU acceleration** (Phase 7) -- the single most impactful change

---

## 6. Model Registry: Vision Models

| Model | ID | Size | Platform | Notes |
|-------|----|------|----------|-------|
| SmolVLM2 500M Q8 | `smolvlm2-500m-video-instruct-q8` | ~620MB | Mobile (iOS/Android) | Smallest VLM, CPU-viable |
| SmolVLM2 mmproj F16 | `smolvlm2-500m-mmproj-f16` | ~110MB | Mobile | Required companion |
| LLaVA 1.6 Mistral 7B Q4 | `llava-1.6-mistral-7b-q4` | ~4.8GB | macOS | High-quality desktop VLM |
| Qwen2-VL 7B Q4 | `qwen2vl-7b-q4` | ~5GB | macOS | Best screen description quality |

**File:** `flutter/lib/src/model_manager.dart`, ModelRegistry class (line 746+)

---

## 7. Supporting Infrastructure

### RuntimePolicy (`flutter/lib/src/runtime_policy.dart`)

QoS levels with knob mappings:
- **full:** 2 FPS, 640px, 100 tokens
- **reduced:** 1 FPS, 480px, 75 tokens
- **minimal:** 1 FPS, 320px, 50 tokens
- **paused:** 0 FPS, 0px, 0 tokens

Uses TAPAS-inspired hysteresis: escalation (degradation) is immediate, restoration requires cooldown and happens one level at a time.

### Scheduler (`flutter/lib/src/scheduler.dart`)

Central budget enforcement coordinator. Polls TelemetryService every 2 seconds. When a constraint is violated, degrades the lowest-priority workload first. Supports:
- Adaptive budgets (BudgetProfile.balanced) with warm-up period
- Per-workload latency tracking via LatencyTracker
- Battery drain rate measurement
- Memory eviction callbacks

### TelemetryService (`flutter/lib/src/telemetry_service.dart`)

Cross-platform MethodChannel-based polling for:
- Thermal state (0-3)
- Battery level (0.0-1.0)
- Process RSS memory
- Available memory
- Disk space

---

## 8. Summary of Key Findings

### Does the vision pipeline have the same timeout/fallback issues as STT on low-end Android?

**Yes, and worse.** Vision has no automatic fallback mechanism (STT has AdaptiveSttService → system SpeechRecognizer). Vision timeout is a flat 600 seconds on Android with no device-tier adaptation. Regular VisionScreen uses 768px resolution which is catastrophically slow on CPU-only devices. Only the soak test mitigates with 128px downscale and grab-and-stop camera pattern.

### What does the soak test actually measure and does it cover vision?

The soak test is **primarily a vision inference soak test**. It measures per-frame timing breakdown (image encode, prompt eval, decode, total), thermal state, battery drain, memory RSS, QoS violations, and dropped frames. It supports managed mode (Scheduler with adaptive budget) vs raw mode (no protection). Duration is 35 minutes. On macOS it uses screen capture instead of camera.

### What are the current inference layer bottlenecks on Android (CPU-only)?

1. **No GPU acceleration** -- Vulkan disabled, deferred to Phase 7
2. **CLIP image encoding** -- quadratic in patch count, dominates latency
3. **Resolution not adapted to device capability** in VisionScreen (768px fixed)
4. **Pure Dart camera frame conversion** -- could be native
5. **OpenMP disabled** -- limits CPU parallelism
6. **No KV cache reuse** across frames for identical prompts

### Where are the opportunities for inference layer improvements?

1. **Vulkan GPU acceleration** (Phase 7) -- 10-50x potential speedup
2. **DeviceTier-aware resolution in VisionScreen** -- immediate, no native changes
3. **Port soak test mitigations to production** (grab-and-stop, adaptive resolution)
4. **Quantized mmproj** (Q8 or Q4) -- reduces image encoding compute
5. **Native YUV→RGB conversion** -- eliminates pure-Dart pixel loop overhead
6. **Prompt KV cache reuse** across frames with same text prompt
7. **Add vision fallback/degradation path** analogous to STT's AdaptiveSttService
