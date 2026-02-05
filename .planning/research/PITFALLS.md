# Pitfalls Research: v1.1 Android + Streaming

**Project:** Edge Veda SDK
**Milestone:** v1.1 Android Support + Streaming Responses
**Researched:** 2026-02-04
**Confidence:** HIGH (verified against official docs, GitHub issues, and existing codebase)

This document catalogs common mistakes when adding Android NDK support and streaming responses to an existing Flutter iOS LLM SDK. Each pitfall includes warning signs for early detection and actionable prevention strategies.

---

## Critical Pitfalls (Must Address)

These pitfalls cause crashes, rewrites, or major architectural issues if not addressed.

### P1: Android Memory Killer (LMK) Behavior Differs from iOS Jetsam

**Risk:** Android's Low Memory Killer Daemon (LMKD) uses different heuristics than iOS jetsam. Your 1.2GB iOS memory limit may be inappropriate for Android, causing either unnecessary throttling (too conservative) or OOM kills (too aggressive).

**Why It Happens:**
- iOS jetsam kills based on memory footprint with clear thresholds
- Android LMK uses PSI (Pressure Stall Information) on Android 10+ and oom_adj_score
- Android has no direct API for detecting native memory pressure events
- mmap behavior differs: Android may not count mmap'd memory the same way iOS does

**Warning Signs:**
- App killed silently on Android with no crash report
- `ApplicationExitInfo` shows `REASON_LOW_MEMORY`
- Works fine on high-end devices, crashes on 4GB devices
- Memory stats show low usage but app still gets killed

**Prevention:**
1. Use `ApplicationExitInfo` API to monitor LMK kills in testing
2. Start with 800MB limit on Android (more conservative than iOS 1.2GB)
3. Test on 4GB RAM devices as baseline (API 24 devices often have 2-4GB)
4. Use `context-size` of 2048-4096 initially (not 8192) to reduce memory spikes
5. Monitor PSS (Proportional Set Size) not just raw allocation

**Phase:** Phase 1 (Android NDK build) - Must determine memory limits before integration testing

**Sources:**
- [Android LMK Documentation](https://developer.android.com/topic/performance/vitals/lmk)
- [Understanding Low Memory Management in Android](https://www.droidcon.com/2025/01/14/understanding-low-memory-management-in-android-kswapd-lmk/)
- [llama.cpp Discussion #1876 - Understanding memory usage](https://github.com/ggml-org/llama.cpp/discussions/1876)

---

### P2: llama.cpp Version Compatibility - Segfaults After b5028

**Risk:** Building from recent llama.cpp versions can cause segmentation faults on Android. Your pinned version (b4658) should work, but upgrading or using wrong build flags will cause crashes.

**Why It Happens:**
- llama.cpp is under rapid development with breaking changes
- Some commits introduce Android-specific regressions
- Vulkan backend support is less mature than Metal
- OpenMP and llamafile features don't work on Android

**Warning Signs:**
- App crashes immediately on model load with SIGSEGV
- Works on iOS but crashes on Android
- Native crash logs show segfault in `libedge_veda.so`
- Different crash behavior between debug and release builds

**Prevention:**
1. Keep llama.cpp pinned to b4658 (known working version)
2. Build with explicit flags:
   ```cmake
   -DGGML_OPENMP=OFF
   -DGGML_LLAMAFILE=OFF
   ```
3. Test any version bump on Android FIRST (higher risk than iOS)
4. Use NDK r25+ (your constraint) but test specific NDK version
5. Verify architecture: `arm64-v8a` is primary target

**Phase:** Phase 1 (Android NDK build) - Must validate before any integration

**Sources:**
- [llama.cpp Android Documentation](https://github.com/ggml-org/llama.cpp/blob/master/docs/android.md)
- [llama.cpp Android Tutorial](https://github.com/JackZeng0208/llama.cpp-android-tutorial)
- [Building llama.cpp for Android Discussion](https://github.com/ggml-org/llama.cpp/discussions/4960)

---

### P3: Vulkan Support is Incomplete on Android - Use CPU Fallback Strategy

**Risk:** Vulkan GPU acceleration on Android is unreliable across devices. Unlike Metal (which works universally on iOS 15+), Vulkan support varies dramatically by device, driver version, and GPU vendor.

**Why It Happens:**
- Vulkan flash attention not supported (except on newest NVIDIA drivers with coopmat2)
- Adreno GPUs (Qualcomm) often slower with Vulkan than CPU
- Mali GPUs (Samsung, MediaTek) have buggy drivers on older devices
- Some devices report Vulkan support but produce wrong inference results

**Warning Signs:**
- Inference results differ between iOS and Android
- GPU inference slower than CPU on mid-range devices
- Crashes on specific device models with Vulkan enabled
- Works in emulator but fails on physical devices

**Prevention:**
1. Default to CPU backend on Android initially (safer baseline)
2. Implement runtime Vulkan capability detection:
   ```dart
   if (Platform.isAndroid) {
     config.backend = EvBackend.cpu; // Safe default
     // Enable Vulkan only on verified devices
   }
   ```
3. Test on Adreno (Snapdragon), Mali (Samsung/MediaTek), and PowerVR
4. Consider OpenCL backend for Adreno instead of Vulkan (better driver support)
5. Maintain device allowlist for Vulkan acceleration

**Phase:** Phase 1 (Android NDK build) - Architecture decision upfront

**Sources:**
- [Vulkan on Android - Google PDF](https://vulkan.org/user/pages/09.events/vulkanised-2025/T15-Ian-Elliott-Google-Vulkan-on-Android.pdf)
- [llama.cpp Issue #11695 - Vulkan Android compile bug](https://github.com/ggml-org/llama.cpp/issues/11695)
- [llama.cpp Issue #8705 - GPU acceleration on Android](https://github.com/ggml-org/llama.cpp/issues/8705)
- [ncnn Vulkan FAQ](https://github.com/Tencent/ncnn/wiki/FAQ-ncnn-vulkan)

---

### P4: Native Library Loading Fails with dlopen/UnsatisfiedLinkError

**Risk:** Flutter Android app crashes at startup with `dlopen failed: library "libedge_veda.so" not found`. This is common when native libraries are missing or built for wrong architecture.

**Why It Happens:**
- Library not bundled in correct ABI folder in APK
- 32-bit library on 64-bit device (architecture mismatch)
- NDK version mismatch between Flutter and native plugin
- CMake didn't copy .so to correct output location

**Warning Signs:**
- App crashes immediately on Android launch
- Error: `java.lang.UnsatisfiedLinkError: dlopen failed`
- Works on emulator (x86_64) but not on device (arm64-v8a)
- Works on some devices but not others

**Prevention:**
1. Build for `arm64-v8a` as primary ABI (Google Play requirement since 2021)
2. Verify library placement in APK:
   ```bash
   unzip -l app-release.apk | grep libedge_veda
   # Should show: lib/arm64-v8a/libedge_veda.so
   ```
3. Set explicit abiFilters in build.gradle:
   ```gradle
   ndk { abiFilters 'arm64-v8a' }
   ```
4. Match NDK version between Flutter and native build (use NDK 25 or 27)
5. Test on physical arm64 device, not just emulator

**Phase:** Phase 1 (Android NDK build) - Must pass before any functionality testing

**Sources:**
- [Flutter Issue #170797 - JNI Library Loading on 64-bit](https://github.com/flutter/flutter/issues/170797)
- [Flutter Issue #108079 - libflutter.so not found](https://github.com/flutter/flutter/issues/108079)
- [Android ABIs Documentation](https://developer.android.com/ndk/guides/abis)

---

### P5: Streaming Callbacks from Native Thread Crash with Wrong API

**Risk:** Using `Pointer.fromFunction` for streaming token callbacks will crash when called from C++ inference thread. Must use `NativeCallable.listener` for cross-thread callbacks.

**Why It Happens:**
- `Pointer.fromFunction` can only be invoked on the main Dart isolate's mutator thread
- llama.cpp inference runs on a background thread
- Calling from wrong thread causes immediate process abort
- Error is not caught - just crashes

**Warning Signs:**
- App crashes during streaming generation (not at start or end)
- Crash happens after first few tokens are generated
- Works with non-streaming `generate()` but crashes with `generateStream()`
- Native crash log shows abort in FFI callback

**Prevention:**
1. Use `NativeCallable.listener` for streaming callbacks:
   ```dart
   final callback = NativeCallable<TokenCallbackNative>.listener(
     (Pointer<Utf8> token) {
       sendPort.send(token.toDartString());
     },
   );
   ```
2. Never use `Pointer.fromFunction` for callbacks from native threads
3. Always close NativeCallable when done: `callback.close()`
4. Test streaming on both iOS and Android to verify thread safety

**Phase:** Phase 2 (Streaming API) - Critical for streaming implementation

**Sources:**
- [NativeCallable.listener Documentation](https://api.flutter.dev/flutter/dart-ffi/NativeCallable/NativeCallable.listener.html)
- [Dart SDK Issue #54276 - Invoke callback from native code](https://github.com/dart-lang/sdk/issues/54276)
- [Dart SDK Issue #61272 - High number of FFI callbacks deadlock](https://github.com/dart-lang/sdk/issues/61272)

---

### P6: Long-Lived Worker Isolate Pattern Required for Streaming

**Risk:** Current v1.0 `Isolate.run()` pattern cannot support streaming. Each `Isolate.run()` creates/destroys context, making token-by-token streaming impossible. Requires architectural change to long-lived worker isolate.

**Why It Happens:**
- `Isolate.run()` terminates isolate when function completes
- Pointers cannot transfer between isolates
- Native context must persist across multiple token emissions
- Current implementation (correctly) noted this in v1.0 code comments

**Warning Signs:**
- Attempting streaming with Isolate.run() returns only final result
- Memory leaks if trying to keep context alive incorrectly
- UI freezes if running inference on main isolate

**Prevention:**
1. Implement dedicated worker isolate with `Isolate.spawn()`:
   ```dart
   // Main isolate
   final receivePort = ReceivePort();
   await Isolate.spawn(workerEntryPoint, receivePort.sendPort);

   // Worker isolate
   void workerEntryPoint(SendPort mainSendPort) {
     final workerReceivePort = ReceivePort();
     mainSendPort.send(workerReceivePort.sendPort);
     // Keep native context alive here
   }
   ```
2. Use SendPort for commands (main -> worker) and responses (worker -> main)
3. Keep native context alive in worker isolate (not main isolate)
4. Stream tokens via SendPort as they're generated
5. Implement graceful shutdown to free native resources

**Phase:** Phase 2 (Streaming API) - Fundamental architecture for streaming

**Sources:**
- [Flutter Isolates Documentation](https://docs.flutter.dev/perf/isolates)
- [Dart Isolates Language Guide](https://dart.dev/language/isolates)
- [Mastering Isolates in Flutter & Dart](https://plugfox.dev/mastering-isolates/)

---

## Moderate Pitfalls (Should Address)

These pitfalls cause delays, technical debt, or degraded user experience.

### P7: NDK Version Mismatch Between Flutter and Native Plugin

**Risk:** Flutter plugin requires one NDK version, native build uses another. Causes build failures or runtime crashes.

**Why It Happens:**
- Flutter 3.29+ warns about NDK version mismatches
- Different packages may require different NDK versions
- Android Studio updates can change default NDK
- Manual NDK downloads vs Android Studio managed NDK

**Warning Signs:**
- Build warning: "plugin(s) depend on a different Android NDK version"
- Build fails with cryptic CMake errors
- Multiple NDK folders consuming disk space
- Works locally but fails in CI

**Prevention:**
1. Pin NDK version explicitly in `android/app/build.gradle`:
   ```gradle
   android {
       ndkVersion "25.2.9519653"  // Match your native build
   }
   ```
2. Use same NDK version for native build script and Flutter
3. Document required NDK version in README
4. Add CI check to verify NDK version

**Phase:** Phase 1 (Android NDK build)

**Sources:**
- [Flutter Issue #163945 - NDK version mismatch](https://github.com/flutter/flutter/issues/163945)
- [Flutter Android C Interop Documentation](https://docs.flutter.dev/platform-integration/android/c-interop)

---

### P8: High-Volume Streaming Callbacks Cause Deadlocks

**Risk:** When streaming generates tokens very fast (>100/sec on fast devices), the volume of FFI callbacks can cause VM deadlocks.

**Why It Happens:**
- NativeCallable.listener uses message passing to main isolate
- High callback frequency overwhelms the event loop
- VM mutex contention when many callbacks queue up
- Reported as deadlock but is actually backpressure issue

**Warning Signs:**
- App freezes during fast generation
- CPU spikes to 100% during streaming
- Works fine with slow models, hangs with fast models
- Deadlock appears random, not reproducible on slow devices

**Prevention:**
1. Implement token batching (send every N tokens or every M ms)
2. Use throttling in native callback:
   ```cpp
   static auto lastSend = std::chrono::steady_clock::now();
   auto now = std::chrono::steady_clock::now();
   if (now - lastSend > std::chrono::milliseconds(16)) {  // ~60 fps
       sendTokenBatch();
       lastSend = now;
   }
   ```
3. Consider accumulating tokens in native buffer
4. Test with artificially fast generation to stress-test

**Phase:** Phase 2 (Streaming API) - Performance optimization

**Sources:**
- [Dart SDK Issue #61272 - High number of FFI callbacks deadlock](https://github.com/dart-lang/sdk/issues/61272)

---

### P9: mmap vs malloc Memory Accounting Differences

**Risk:** llama.cpp uses mmap for model loading by default. Android may account mmap'd memory differently, causing confusion about actual memory usage and incorrect memory pressure decisions.

**Why It Happens:**
- mmap creates virtual address mappings without immediate RAM consumption
- Pages loaded on-demand as model weights are accessed
- PSS (Proportional Set Size) counts shared pages differently
- Memory stats may show low usage while system is actually under pressure

**Warning Signs:**
- `getMemoryStats()` shows low usage but app gets LMK killed
- Model appears to load instantly (too fast - pages not actually loaded)
- Performance degrades significantly after a few inferences (page faults)
- Memory usage jumps dramatically during first inference

**Prevention:**
1. Use `--no-mmap` flag if memory accounting needed
2. Pre-touch model pages after loading (force page faults early):
   ```cpp
   // After model load, touch all pages
   volatile char* p = model_data;
   for (size_t i = 0; i < model_size; i += 4096) {
       (void)*p;
       p += 4096;
   }
   ```
3. Account for both PSS and USS in memory monitoring
4. Test memory behavior with and without mmap on target devices

**Phase:** Phase 1 (Android NDK build) - Memory management strategy

**Sources:**
- [llama.cpp Discussion #1876 - Understanding memory usage](https://github.com/ggml-org/llama.cpp/discussions/1876)
- [Why MMAP in llama.cpp hides true memory usage](https://news.ycombinator.com/item?id=35426679)

---

### P10: Feature Parity Testing - Platform-Specific Behavior Differences

**Risk:** Same API produces different results on iOS vs Android. Users expect identical behavior but underlying implementations differ.

**Why It Happens:**
- Metal vs Vulkan/CPU produce slightly different floating point results
- Thread scheduling differs between platforms
- Memory pressure handling differs
- Random seed behavior may vary

**Warning Signs:**
- Identical prompts produce different outputs on iOS vs Android
- Performance metrics differ significantly
- Tests pass on iOS but fail on Android (or vice versa)
- User reports "Android version is broken"

**Prevention:**
1. Create platform-parity test suite with known prompts/outputs
2. Use deterministic settings for testing (temperature=0, seed=fixed)
3. Accept minor numerical differences in floating point
4. Document any intentional platform differences
5. Run CI tests on both iOS and Android devices

**Phase:** Phase 3 (Demo app update) - Integration testing

**Sources:**
- [Flutter Multi-Platform Documentation](https://flutter.dev/multi-platform)

---

### P11: Isolate Memory Management - GC Freezes with Multiple Isolates

**Risk:** Using multiple long-lived isolates (main + worker) causes longer garbage collection pauses. With large model data, GC can freeze UI for seconds.

**Why It Happens:**
- Dart GC must pause all isolates when collecting long-lived objects
- More isolates = longer GC coordination time
- Large model metadata in Dart heap compounds the issue
- Returning to foreground triggers full GC on all isolates

**Warning Signs:**
- UI freezes for several seconds when app returns from background
- Stuttering during streaming (GC pauses between tokens)
- Memory usage appears stable but app becomes unresponsive
- Freeze duration increases with more isolates

**Prevention:**
1. Minimize data stored in worker isolate's Dart heap
2. Keep model metadata in native memory, not Dart objects
3. Use TransferableTypedData for large binary transfers
4. Consider single worker isolate (not isolate pool)
5. Profile with `--observe` flag to identify GC pressure

**Phase:** Phase 2 (Streaming API) - Architecture decision

**Sources:**
- [Flutter Performance Degradation with Isolates](https://github.com/dart-lang/sdk/issues/47672)
- [Flutter Issue #166945 - Isolate performance regression](https://github.com/flutter/flutter/issues/166945)

---

### P12: Cancel Token Implementation Complexity

**Risk:** Implementing cancel token for streaming requires careful coordination between Dart, FFI, and native code. Incorrect implementation causes resource leaks or crashes.

**Why It Happens:**
- Native inference loop must check cancellation flag
- Worker isolate must handle cancel command mid-stream
- Native resources must be freed even if cancelled
- Race conditions between cancel and normal completion

**Warning Signs:**
- Cancel doesn't stop generation (keeps running in background)
- Memory leaks after cancellation
- Crash when cancelling during token callback
- Deadlock when cancel and completion race

**Prevention:**
1. Use atomic flag for cancellation check in native code:
   ```cpp
   std::atomic<bool> cancelled{false};
   // In generation loop:
   if (cancelled.load()) break;
   ```
2. Ensure native cleanup runs regardless of cancellation
3. Test cancel at various points: start, middle, near end
4. Use timeout as fallback if cancel doesn't respond

**Phase:** Phase 2 (Streaming API) - Cancel token implementation

---

## Minor Pitfalls (Nice to Address)

These cause annoyance but are fixable without major rework.

### P13: Android Studio CMake Integration is Unreliable

**Risk:** Android Studio's CMake/NDK integration has known issues. Relying on it for complex native builds leads to frustration.

**Why It Happens:**
- Android Studio cmake support described as "always been terrible"
- IDE caching causes stale build configurations
- Incremental builds may not pick up native changes
- Different behavior between IDE and command-line builds

**Warning Signs:**
- Native changes not reflected after rebuild in IDE
- Build succeeds in terminal but fails in Android Studio
- CMakeLists.txt errors that don't match actual content
- Different .so output between IDE and command line

**Prevention:**
1. Build native .so separately with script (like `build-android.sh`)
2. Use Android Studio only for Dart/Flutter code
3. Add `flutter clean` to debugging workflow
4. Verify builds work from command line before debugging IDE issues

**Phase:** Phase 1 (Android NDK build) - Build system setup

**Sources:**
- [llama.cpp Discussion #4960](https://github.com/ggml-org/llama.cpp/discussions/4960)

---

### P14: NDK Optimization Flags Can Cause Crashes

**Risk:** Aggressive optimization flags (`-Os`, `-O3` with certain options) can cause code generation bugs in specific NDK versions.

**Why It Happens:**
- NDK r25c known to produce invalid code with `-Os` for arm64-v8a
- Vectorization patches can cause crashes
- LTO can expose latent issues in llama.cpp code
- Debug vs Release builds may have different behavior

**Warning Signs:**
- Release build crashes but debug build works
- Crashes only on specific device architectures
- Intermittent crashes that seem random
- Crash in optimized math code paths

**Prevention:**
1. Start with `-O2` instead of `-Os` or `-O3`
2. Test release builds thoroughly (don't only test debug)
3. Document exact NDK version and flags that work
4. Consider disabling LTO initially for stability

**Phase:** Phase 1 (Android NDK build)

**Sources:**
- [Android NDK Issue #1862 - Invalid code with -Os](https://github.com/android/ndk/issues/1862)
- [Android NDK NEON Documentation](https://developer.android.com/ndk/guides/cpu-arm-neon)

---

### P15: Binary Size Bloat from Multi-ABI Build

**Risk:** Building for multiple ABIs (arm64-v8a + armeabi-v7a + x86_64) multiplies APK size. Native library already ~15MB means 45MB+ in APK.

**Why It Happens:**
- Each ABI requires separate compiled binary
- No way to share code between ABIs
- Google Play requirement for 64-bit drives arm64-v8a necessity
- Emulator testing may want x86_64

**Warning Signs:**
- APK size exceeds 100MB (raises user concern)
- Google Play AAB still larger than expected
- CI build times very long (building 3+ variants)
- Disk space issues in CI

**Prevention:**
1. Ship only `arm64-v8a` for v1.1 (covers 90%+ of active devices)
2. Use Android App Bundle (AAB) for Play Store (delivers only needed ABI)
3. Defer armeabi-v7a support unless required
4. Skip x86_64 in release builds (emulator-only)

**Phase:** Phase 1 (Android NDK build)

**Sources:**
- [Android Support 64-bit architectures](https://developer.android.com/games/optimize/64-bit)

---

## Pitfall Summary Table

| # | Pitfall | Severity | Phase | Category |
|---|---------|----------|-------|----------|
| P1 | Android LMK differs from iOS jetsam | Critical | Phase 1 | Memory |
| P2 | llama.cpp version compatibility | Critical | Phase 1 | Build |
| P3 | Vulkan support incomplete on Android | Critical | Phase 1 | GPU |
| P4 | Native library loading fails (dlopen) | Critical | Phase 1 | Build |
| P5 | Streaming callbacks crash with wrong API | Critical | Phase 2 | Streaming |
| P6 | Long-lived worker isolate required | Critical | Phase 2 | Architecture |
| P7 | NDK version mismatch | Moderate | Phase 1 | Build |
| P8 | High-volume callbacks cause deadlocks | Moderate | Phase 2 | Streaming |
| P9 | mmap vs malloc memory accounting | Moderate | Phase 1 | Memory |
| P10 | Feature parity testing across platforms | Moderate | Phase 3 | Testing |
| P11 | GC freezes with multiple isolates | Moderate | Phase 2 | Memory |
| P12 | Cancel token implementation complexity | Moderate | Phase 2 | Streaming |
| P13 | Android Studio CMake unreliable | Minor | Phase 1 | Build |
| P14 | NDK optimization flags cause crashes | Minor | Phase 1 | Build |
| P15 | Binary size bloat from multi-ABI | Minor | Phase 1 | Build |

---

## Phase-Specific Pitfall Summary

### Phase 1: Android NDK Build
Must address: P1, P2, P3, P4
Should address: P7, P9
Nice to address: P13, P14, P15

**Key insight:** Focus on getting a stable CPU-only build working first. Vulkan optimization is secondary to correctness.

### Phase 2: Streaming API
Must address: P5, P6
Should address: P8, P11, P12

**Key insight:** The architecture change from `Isolate.run()` to long-lived worker isolate is the biggest technical challenge. Plan adequate time.

### Phase 3: Demo App Update
Should address: P10

**Key insight:** Feature parity testing should be automated in CI to catch platform differences early.

---

## Integration Pitfalls with Existing iOS System

These pitfalls specifically address adding Android support to your existing iOS codebase:

### Existing Pattern: Per-Call Isolate.run()
Your current `edge_veda_impl.dart` uses `Isolate.run()` for each `generate()` call. This works for iOS non-streaming but **must be refactored** for streaming (P6). Plan to:
1. Keep existing `generate()` API working during transition
2. Add new `generateStream()` alongside, not replacing
3. Eventually migrate `generate()` to use long-lived worker internally

### Existing Pattern: Singleton Bindings
Your `EdgeVedaNativeBindings.instance` pattern works but needs Android library loading:
```dart
// Current: Works for iOS
if (Platform.isIOS) {
  return DynamicLibrary.process();
}
// Add: Android support
if (Platform.isAndroid) {
  return DynamicLibrary.open('libedge_veda.so');  // Must be in correct ABI folder
}
```

### Existing Pattern: Backend Detection
Your `EvBackend` enum already includes Vulkan. Ensure fallback:
```dart
// In config population
configPtr.ref.backend = useGpu
    ? (Platform.isAndroid ? EvBackend.cpu.value : EvBackend.auto_.value)  // Conservative Android default
    : EvBackend.cpu.value;
```

---

## Recommendations for Roadmap

Based on these pitfalls, the v1.1 roadmap should:

1. **Start with CPU-only Android** - Get Android working without GPU acceleration first (P3)
2. **Validate memory early** - Determine Android memory limits before extensive development (P1)
3. **Plan streaming architecture upfront** - The isolate pattern change affects all streaming work (P6)
4. **Build verification matrix** - Test on multiple device types: high-end, mid-range, 4GB devices
5. **Add platform parity CI** - Automated tests running on both iOS and Android

---

*Confidence: HIGH - Research verified against official documentation, GitHub issues, and analysis of existing v1.0 codebase patterns.*
