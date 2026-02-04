# Domain Pitfalls: Flutter + llama.cpp + iOS

**Domain:** On-device LLM inference SDK for Flutter iOS
**Researched:** 2026-02-04
**Confidence:** MEDIUM (based on project analysis + domain expertise; WebSearch unavailable)

---

## Critical Pitfalls

Mistakes that cause rewrites, App Store rejection, or crashes in production.

---

### Pitfall 1: iOS Memory Pressure Kills App Without Warning

**What goes wrong:** iOS aggressively terminates apps that exceed memory limits. Unlike desktop, there is no swap file. On a 4GB iPhone, system reserves ~2GB, leaving ~2GB for foreground apps. A 1B parameter GGUF model at Q4 quantization uses ~500MB-1GB just for weights, plus ~500MB-1GB for KV cache during inference. Total can easily exceed 1.5GB, triggering jetsam (iOS memory watchdog).

**Why it happens:**
- Developers test on high-end devices (iPhone 15 Pro with 8GB RAM) but users have iPhone 11/12 with 4GB
- llama.cpp allocates memory upfront during model load, not incrementally
- KV cache grows with context length (2048 tokens = ~500MB for 1B model)
- iOS does not send memory warnings to FFI/C++ code - only to Swift/ObjC

**Consequences:**
- App is killed instantly (SIGKILL) - no chance to save state
- User loses conversation context
- Repeated kills lead to poor App Store reviews
- Apple may reject app during review if it crashes on test devices

**Prevention:**
1. **Implement proactive memory monitoring** (already scaffolded in `memory_guard.cpp`)
   - Monitor via `mach_task_basic_info` (resident_size)
   - Set hard limit at 1.2GB, warning at 900MB
   - Register for `didReceiveMemoryWarning` in Flutter's iOS runner
2. **Use llama.cpp's mmap mode** (`use_mmap: true`)
   - Memory-mapped files don't count against app's memory footprint as heavily
   - OS can evict pages under pressure
3. **Limit context window** to 2048 tokens on 4GB devices, detect device RAM at init
4. **Implement graceful degradation**
   - If approaching limit: stop generation, return partial result
   - Expose `ev_memory_pressure_callback` to Flutter layer

**Detection (warning signs):**
- Test on iPhone 11 (4GB RAM) - if it crashes during long generation, you have this problem
- Memory usage exceeds 1.2GB during inference (check Xcode Instruments)
- Random SIGKILL with exit code 137 in Xcode

**Phase to address:** Phase 1 (Core Setup) - Before llama.cpp integration, validate memory guard works

---

### Pitfall 2: llama.cpp Metal Backend Build Configuration

**What goes wrong:** llama.cpp Metal support requires specific CMake flags and Xcode configuration. Missing flags result in CPU-only inference (10x slower) or build failures on iOS.

**Why it happens:**
- llama.cpp's CMake is designed for desktop first
- iOS cross-compilation requires toolchain file + specific flags
- Metal shaders must be compiled with correct SDK
- bitcode is deprecated but old llama.cpp versions may require it off
- arm64 simulators (Apple Silicon Macs) need different settings than arm64 devices

**Consequences:**
- Performance target of >15 tok/sec impossible without Metal
- Build fails with cryptic Metal compiler errors
- App runs on simulator but crashes on device (or vice versa)
- Binary bloat from unused CPU-specific SIMD code

**Prevention:**
1. **Set correct CMake flags for iOS:**
   ```cmake
   set(LLAMA_METAL ON)
   set(LLAMA_METAL_EMBED_LIBRARY ON)  # Embed shaders in binary
   set(LLAMA_ACCELERATE ON)           # Apple Accelerate framework
   set(LLAMA_BUILD_TESTS OFF)
   set(LLAMA_BUILD_EXAMPLES OFF)
   set(CMAKE_OSX_DEPLOYMENT_TARGET "15.0")  # Match project target
   ```
2. **Use iOS toolchain file** (already exists at `core/cmake/ios.toolchain.cmake`)
   - Set `CMAKE_SYSTEM_NAME iOS`
   - Set `CMAKE_OSX_ARCHITECTURES "arm64"` for device
   - Separate build for simulator: `CMAKE_OSX_ARCHITECTURES "arm64"` with `CMAKE_OSX_SYSROOT iphonesimulator`
3. **Build universal XCFramework** combining device and simulator slices
4. **Verify Metal shader compilation** - look for `.metallib` in build output

**Detection:**
- Run `ev_detect_backend()` returns `EV_BACKEND_CPU` instead of `EV_BACKEND_METAL`
- Inference speed <5 tok/sec on iPhone 13+
- Build log shows "Metal not available" warnings

**Phase to address:** Phase 1 (C++ Core build) - Get llama.cpp compiling with Metal first

---

### Pitfall 3: Flutter FFI Threading Violations

**What goes wrong:** Dart FFI calls block the Dart isolate. Long-running C++ inference blocks Flutter's UI thread, causing ANR (Application Not Responding) or iOS watchdog termination.

**Why it happens:**
- Dart FFI is synchronous by design
- llama.cpp `ev_generate()` can take 5-30 seconds for long responses
- iOS kills apps that block main thread for >10 seconds
- Flutter's UI updates freeze during blocking FFI calls

**Consequences:**
- UI freezes during inference
- iOS shows "app not responding" dialog
- Watchdog kills app after ~10 seconds of main thread block
- Poor UX - users think app crashed

**Prevention:**
1. **Never call inference from main isolate** - use `compute()` or spawn dedicated isolate
   ```dart
   // BAD - blocks UI
   final result = await _bindings.edgeVedaGenerate(ctx, prompt);

   // GOOD - runs in background isolate
   final result = await Isolate.run(() {
     return _bindings.edgeVedaGenerate(ctx, prompt);
   });
   ```
2. **Use streaming generation** (`ev_generate_stream`) with polling
   - Call `ev_stream_next()` in short bursts
   - Yield to event loop between tokens
3. **Set timeouts on FFI calls** - if C++ hangs, detect and recover
4. **Show loading UI** immediately before FFI call returns

**Detection:**
- UI freezes when tapping "Generate"
- Xcode shows purple "main thread blocked" warning
- `flutter run --verbose` shows long gaps in event processing

**Phase to address:** Phase 2 (Flutter FFI bindings) - Design async wrapper from start

---

### Pitfall 4: Model File Path Sandbox Violations

**What goes wrong:** iOS apps are sandboxed. Models downloaded to wrong directory are inaccessible, or paths hardcoded for one device fail on another.

**Why it happens:**
- iOS sandbox paths change between app installs
- Developers hardcode paths during testing
- Documents directory on iOS is different from Android
- iCloud backup may try to backup large model files (uses quota, slow)

**Consequences:**
- Model load fails with "file not found"
- Works on simulator, fails on device
- App rejected for backing up large files to iCloud

**Prevention:**
1. **Use `path_provider` correctly:**
   ```dart
   // For model files (large, no backup needed)
   final dir = await getApplicationSupportDirectory();  // Not Documents!
   final modelPath = '${dir.path}/models/llama-3.2-1b.gguf';
   ```
2. **Exclude models from iCloud backup:**
   ```dart
   final file = File(modelPath);
   await file.setAttributes({FileAttribute.excludeFromBackup: true});
   ```
3. **Pass absolute paths to C++** - never relative paths
4. **Validate path exists in Dart** before calling `ev_init()`

**Detection:**
- `EV_ERROR_MODEL_LOAD_FAILED` after app reinstall
- Works on first install, fails after update
- iCloud backup complains about large files

**Phase to address:** Phase 2 (Model Manager) - Design download + storage correctly

---

### Pitfall 5: App Store Review Rejection for Background Execution

**What goes wrong:** Apple rejects apps that run CPU-intensive tasks in background. If user switches apps during generation, iOS suspends the process. Developers try to use background modes incorrectly.

**Why it happens:**
- Background Audio/Location modes don't apply to LLM inference
- `beginBackgroundTask` only gives 30 seconds
- Developers try to cheat with silent audio playing
- Apple specifically tests for this during review

**Consequences:**
- App Store rejection (Guideline 2.5.4 - Background execution)
- Generation stops mid-response when user switches apps
- Users lose partial results

**Prevention:**
1. **Do not request background execution** - it won't be approved
2. **Save state before backgrounding:**
   ```dart
   WidgetsBindingObserver {
     void didChangeAppLifecycleState(state) {
       if (state == AppLifecycleState.paused) {
         // Cancel current generation, save partial result
         _edgeVeda.cancelGeneration();
       }
     }
   }
   ```
3. **Implement generation resume** - store prompt + partial output, continue when foregrounded
4. **Show user warning** if they try to leave during generation
5. **Keep responses short** - if user needs 60+ seconds, generation is too long

**Detection:**
- App review feedback mentions "background execution"
- Generation stops when phone locked
- Battery drain complaints from users

**Phase to address:** Phase 3 (Flutter SDK) - Handle lifecycle from start

---

### Pitfall 6: FFI Memory Leaks from Pointer Mismanagement

**What goes wrong:** Dart FFI requires manual memory management for C strings. Forgetting to free pointers leaks memory. On mobile, even small leaks compound over sessions.

**Why it happens:**
- Dart has GC, C++ does not - mental model mismatch
- `toNativeUtf8()` allocates, but where is `free()`?
- Error paths skip cleanup
- Streaming generation creates many small string allocations

**Consequences:**
- Memory grows over multiple generations
- Eventually triggers memory pressure / jetsam
- Hard to debug - no crash, just gradual degradation

**Prevention:**
1. **Establish clear ownership rules:**
   - Dart allocates -> Dart frees (via `malloc.free()`)
   - C++ allocates (ev_generate output) -> C++ frees (`ev_free_string()`)
2. **Use RAII wrapper in Dart:**
   ```dart
   extension NativeStringScope on String {
     R useNative<R>(R Function(Pointer<Utf8>) fn) {
       final ptr = toNativeUtf8();
       try {
         return fn(ptr);
       } finally {
         malloc.free(ptr);
       }
     }
   }
   ```
3. **Always free in finally blocks** - error paths must clean up
4. **Test with leak detection:**
   - Xcode Instruments > Leaks
   - `flutter run --profile` with DevTools memory view

**Detection:**
- Memory grows linearly with number of generations
- Leaks instrument shows growing C heap
- App slows down after ~20-30 generations

**Phase to address:** Phase 2 (FFI Bindings) - Build correct patterns before replication

---

### Pitfall 7: Binary Size Explosion from llama.cpp

**What goes wrong:** llama.cpp compiled with all backends and SIMD variants can add 50MB+ to app size. PRD requires <25MB SDK footprint.

**Why it happens:**
- Default llama.cpp build includes AVX, AVX2, AVX512 (desktop SIMD)
- Multiple backend support (Metal + CPU + Vulkan)
- Debug symbols not stripped
- Unused code not eliminated

**Consequences:**
- App Store size limit concerns (200MB OTA limit)
- Slow downloads over cellular
- PRD target missed

**Prevention:**
1. **Build iOS-only configuration:**
   ```cmake
   set(LLAMA_NATIVE OFF)      # No auto-detect (it's for desktop)
   set(LLAMA_AVX OFF)
   set(LLAMA_AVX2 OFF)
   set(LLAMA_FMA OFF)
   set(LLAMA_F16C OFF)
   # Keep only ARM NEON (automatic on iOS)
   set(LLAMA_METAL ON)
   ```
2. **Strip symbols in release:**
   ```cmake
   set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -s")
   set(CMAKE_CXX_FLAGS_RELEASE "${CMAKE_CXX_FLAGS_RELEASE} -s")
   ```
3. **Enable LTO (Link Time Optimization):**
   ```cmake
   set(CMAKE_INTERPROCEDURAL_OPTIMIZATION ON)
   ```
4. **Measure with `size` command** - track binary size per commit

**Detection:**
- `libedge_veda.a` or `.framework` > 15MB
- App Store submission shows large download size
- `nm -S libedge_veda.a | sort -k2 -n` shows large unused symbols

**Phase to address:** Phase 1 (C++ Core build) - Set flags before first build

---

## Moderate Pitfalls

Mistakes that cause delays, technical debt, or user friction.

---

### Pitfall 8: llama.cpp API Version Mismatch

**What goes wrong:** llama.cpp evolves rapidly. Code written for one commit breaks on newer versions. API changes every few weeks.

**Prevention:**
1. **Pin llama.cpp to specific commit** - not a branch
   ```bash
   git submodule add https://github.com/ggerganov/llama.cpp third_party/llama.cpp
   cd third_party/llama.cpp
   git checkout b3879  # Specific commit hash
   ```
2. **Document the pinned version** and what API it provides
3. **Create abstraction layer** in `engine.cpp` - don't expose llama.cpp types in public API
4. **Schedule quarterly llama.cpp updates** - batched migration

**Detection:**
- Build breaks after `git submodule update`
- Functions have different signatures in llama.h

**Phase to address:** Phase 1 (submodule setup)

---

### Pitfall 9: GGUF Model Format Incompatibility

**What goes wrong:** GGUF format evolves. Models quantized with newer llama.cpp may not load in older versions.

**Prevention:**
1. **Document supported GGUF version** (currently v3)
2. **Validate GGUF magic/version** before loading
3. **Provide canonical download URLs** for tested models
4. **Error message must include** model version vs SDK version

**Detection:**
- Model loads on developer machine, fails in production
- `EV_ERROR_MODEL_LOAD_FAILED` with cryptic llama.cpp error

**Phase to address:** Phase 2 (Model Manager)

---

### Pitfall 10: Tokenizer Mismatch

**What goes wrong:** Different Llama models use different tokenizers. Using wrong tokenizer produces garbage output.

**Prevention:**
1. **Llama 3.2 uses tiktoken-based tokenizer** - llama.cpp handles this internally
2. **Never expose token IDs to Dart layer** - only strings
3. **Test with known prompt/response pairs**
4. **Include model metadata check** - verify tokenizer type in GGUF

**Detection:**
- Output is garbage or repeating patterns
- System prompt ignored or mangled

**Phase to address:** Phase 2 (Inference integration)

---

### Pitfall 11: Flutter Hot Reload Breaks FFI State

**What goes wrong:** Flutter hot reload reinitializes Dart but not C++. Native context becomes invalid, causing crashes.

**Prevention:**
1. **Implement `dispose()` in Flutter SDK** that calls `ev_free()`
2. **Track initialization state** in Dart - check before FFI calls
3. **Handle hot restart gracefully:**
   ```dart
   class EdgeVeda {
     static ev_context? _ctx;

     Future<void> init() async {
       if (_ctx != null) {
         // Already initialized, reinitialize clean
         ev_free(_ctx!);
         _ctx = null;
       }
       _ctx = ev_init(...);
     }
   }
   ```
4. **Document that hot reload resets model** in development

**Detection:**
- Crash after pressing 'R' in Flutter debug
- `EV_ERROR_CONTEXT_INVALID` after code change

**Phase to address:** Phase 2 (Flutter SDK)

---

### Pitfall 12: Incorrect Model Download Progress

**What goes wrong:** `http` package progress callbacks are unreliable for large files. Progress jumps or stalls, users think download failed.

**Prevention:**
1. **Use chunked download with explicit progress:**
   ```dart
   final response = await client.send(request);
   final contentLength = response.contentLength ?? 0;
   var downloaded = 0;

   await for (final chunk in response.stream) {
     downloaded += chunk.length;
     _progressController.add(downloaded / contentLength);
     file.writeAsBytesSync(chunk, mode: FileMode.append);
   }
   ```
2. **Support resume** - check existing file size, use Range header
3. **Validate checksum after download** - SHA256 of complete file
4. **Show bytes downloaded** not just percentage

**Detection:**
- Progress bar stuck at 0% or 99%
- Download takes much longer than expected

**Phase to address:** Phase 2 (Model Manager)

---

### Pitfall 13: Concurrent Inference Attempts

**What goes wrong:** User taps "Generate" twice quickly. Two simultaneous inference calls corrupt llama.cpp internal state.

**Prevention:**
1. **llama.cpp is not thread-safe** for single context - document this
2. **Mutex in C++ layer** (already present in `engine.cpp`)
3. **Queue in Dart layer** - second request waits for first
4. **Disable UI button** during generation
5. **Consider cancellation** - second tap cancels first, starts new

**Detection:**
- Garbage output or crash on double-tap
- Mutex deadlock (app hangs)

**Phase to address:** Phase 2 (Flutter SDK)

---

## Minor Pitfalls

Annoyances that are fixable but wasteful if encountered.

---

### Pitfall 14: Simulator Performance Misleads

**What goes wrong:** Metal on iOS Simulator runs on Mac GPU - performance looks great. Real device with mobile GPU is 2-3x slower.

**Prevention:**
1. **Always benchmark on real device**
2. **Document expected tok/sec per device class**
3. **CI tests should include device farm** (BrowserStack, Firebase Test Lab)

**Phase to address:** Phase 3 (Testing)

---

### Pitfall 15: Forgetting to Handle Stop Sequences

**What goes wrong:** Model generates past desired endpoint. "What is 2+2?" produces "2+2 = 4. Now let me explain calculus..."

**Prevention:**
1. **Implement stop sequences in C++ layer** - `ev_generation_params.stop_sequences`
2. **Default stop sequences** for chat: `["</s>", "<|eot_id|>", "<|end|>"]`
3. **Trim trailing whitespace** from output

**Phase to address:** Phase 2 (Inference)

---

### Pitfall 16: Temperature=0 Still Has Randomness

**What goes wrong:** Developer expects deterministic output at temp=0. llama.cpp may still sample randomly due to float precision.

**Prevention:**
1. **Set seed explicitly** for reproducible tests
2. **Document that temp=0 means "greedy" not "deterministic across runs"**
3. **For true determinism**: temp=0 + seed=12345 + top_k=1

**Phase to address:** Phase 2 (API documentation)

---

### Pitfall 17: Missing System Prompt Format

**What goes wrong:** Raw prompt sent to model without chat template. Output is inconsistent or model doesn't follow instructions.

**Prevention:**
1. **Llama 3.2 requires specific template:**
   ```
   <|begin_of_text|><|start_header_id|>system<|end_header_id|>

   {system_prompt}<|eot_id|><|start_header_id|>user<|end_header_id|>

   {user_prompt}<|eot_id|><|start_header_id|>assistant<|end_header_id|>
   ```
2. **Apply template in C++ layer** before tokenization
3. **Expose `useRawPrompt` option** for power users

**Phase to address:** Phase 2 (Inference)

---

## Phase-Specific Warnings

| Phase | Topic | Likely Pitfall | Mitigation |
|-------|-------|----------------|------------|
| Phase 1 | llama.cpp submodule | API version drift | Pin to specific commit |
| Phase 1 | CMake iOS build | Metal not enabled | Verify build flags |
| Phase 1 | Binary size | Desktop SIMD included | Disable non-ARM optimizations |
| Phase 2 | FFI bindings | Memory leaks | RAII wrappers, ownership rules |
| Phase 2 | Threading | UI blocking | Background isolate for inference |
| Phase 2 | Model storage | Sandbox violations | Use applicationSupportDirectory |
| Phase 2 | Download | Progress stalls | Chunked download with validation |
| Phase 3 | Memory | Jetsam kills app | Monitor at 900MB, limit at 1.2GB |
| Phase 3 | Lifecycle | Background termination | Cancel on pause, save state |
| Phase 3 | Testing | Simulator misleads | Real device benchmarks required |
| Phase 4 | App Review | Background execution | Don't request, handle gracefully |

---

## Confidence Assessment

| Pitfall Category | Confidence | Basis |
|------------------|------------|-------|
| iOS Memory (Jetsam) | HIGH | Well-documented iOS behavior, visible in project constraints |
| llama.cpp Build | MEDIUM | Based on llama.cpp repo patterns, not verified 2025+ |
| Flutter FFI Threading | HIGH | Documented dart:ffi limitation |
| File Path Sandbox | HIGH | Standard iOS behavior |
| App Store Review | HIGH | Published Apple guidelines |
| FFI Memory Management | HIGH | Documented dart:ffi requirement |
| Binary Size | MEDIUM | Based on typical llama.cpp builds |
| API Version Issues | MEDIUM | llama.cpp known for rapid changes |

---

## Sources

- Project files analyzed: `prd.txt`, `core/CMakeLists.txt`, `core/src/engine.cpp`, `core/src/memory_guard.cpp`, `flutter/lib/src/ffi/bindings.dart`, `.planning/codebase/CONCERNS.md`
- iOS memory management: Apple Developer Documentation (training data)
- llama.cpp build patterns: Repository analysis (training data, may be stale)
- Flutter FFI: dart:ffi package documentation
- Note: WebSearch and WebFetch unavailable - some findings based on training data may be outdated

---

## Gaps Requiring Phase-Specific Research

1. **Current llama.cpp iOS Metal API** - verify exact CMake flags for 2025+ versions
2. **Xcode 16+ compatibility** - may have new iOS toolchain requirements
3. **Flutter 3.19+ FFI changes** - verify isolate spawn patterns still valid
4. **GGUF v4 format** - if released, may affect model loading
