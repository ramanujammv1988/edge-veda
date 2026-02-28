---
phase: 02-native-android-layer
plan: 01
subsystem: native-bridge
tags: [jni, whisper, stt, android]
dependency_graph:
  requires: [phase-01-jni-foundation]
  provides: [whisper-jni-api]
  affects: [kotlin-native-interface]
tech_stack:
  added: []
  patterns: [jni-lifecycle-management, float-array-transfer]
key_files:
  created: []
  modified:
    - core/src/bridge_jni.cpp
    - flutter/android/src/main/kotlin/com/edgeveda/edge_veda/NativeEdgeVeda.kt
decisions:
  - "Force CPU-only backend for Android whisper (config.use_gpu = false) to match Phase 1 LLM pattern"
  - "Concatenate all whisper result segments into single string for JNI return"
  - "Use JNI_ABORT flag when releasing float array (read-only operation)"
metrics:
  duration_seconds: 78
  tasks_completed: 2
  files_modified: 2
  commits: 2
  completed_date: "2026-02-28"
---

# Phase 02 Plan 01: Whisper JNI Bridge Integration Summary

**One-liner:** Added 5 JNI functions for whisper speech-to-text (init, transcribe, free, version, isValid) with CPU-only backend and proper float array lifecycle management.

## Overview

This plan extended the Android JNI bridge from 4 to 9 total functions by adding whisper speech-to-text capabilities. The implementation follows the established Phase 1 pattern: CPU-only backend, LOGI/LOGE logging, zero/null return on failure, and reinterpret_cast for context handles.

## Tasks Completed

### Task 1: Add 5 whisper JNI functions to bridge_jni.cpp
**Status:** ✓ Complete
**Commit:** 51ca729

Added the following JNI functions inside the existing `extern "C"` block:

1. **whisperVersionNative** - Returns SDK version string via `ev_version()`
2. **whisperInitNative** - Initializes whisper context with CPU-only backend (forced `config.use_gpu = false`)
3. **whisperTranscribeNative** - Transcribes float32 PCM audio to text with proper JNI float array lifecycle (GetFloatArrayElements/ReleaseFloatArrayElements with JNI_ABORT)
4. **whisperFreeNative** - Frees whisper context and logs cleanup
5. **whisperIsValidNative** - Checks if context is valid via `ev_whisper_is_valid()`

All functions follow established error handling: return 0/empty string/JNI_FALSE on failure, log errors with LOGE, log success with LOGI.

**Files modified:** core/src/bridge_jni.cpp

### Task 2: Add whisper external fun declarations to NativeEdgeVeda.kt
**Status:** ✓ Complete
**Commit:** 4dbebc6

Added 5 `external fun` declarations to NativeEdgeVeda.kt with matching signatures:

```kotlin
external fun whisperVersionNative(): String
external fun whisperInitNative(modelPath: String, numThreads: Int, useGpu: Boolean): Long
external fun whisperTranscribeNative(contextHandle: Long, audioData: FloatArray, numSamples: Int, language: String): String
external fun whisperFreeNative(contextHandle: Long)
external fun whisperIsValidNative(contextHandle: Long): Boolean
```

Each declaration includes KDoc comments documenting parameters, return values, and behavior.

**Files modified:** flutter/android/src/main/kotlin/com/edgeveda/edge_veda/NativeEdgeVeda.kt

## Verification Results

All verification steps passed:

1. ✓ `grep -c "JNICALL" core/src/bridge_jni.cpp` returns 9 (4 LLM + 5 whisper)
2. ✓ `grep -c "external fun" NativeEdgeVeda.kt` returns 9 (4 LLM + 5 whisper)
3. ✓ All 5 whisper function names match between JNI (Java_com_edgeveda_edge_1veda_NativeEdgeVeda_whisper*) and Kotlin
4. ✓ JNI float array lifecycle properly managed (Get/Release with JNI_ABORT for read-only operation)

## Implementation Highlights

### CPU-Only Backend Enforcement
```cpp
// Phase 2 Android: CPU-only backend (matching existing LLM pattern)
config.use_gpu = false;
```

Matches the existing LLM pattern from Phase 1. GPU/Vulkan support will be added in future phases.

### Float Array Lifecycle Management
```cpp
jfloat *samples = env->GetFloatArrayElements(audioData, NULL);
// ... use samples ...
env->ReleaseFloatArrayElements(audioData, samples, JNI_ABORT);
```

Uses JNI_ABORT flag since the native code only reads the array (transcription is read-only on input audio).

### Segment Concatenation
```cpp
std::string fullText;
for (int i = 0; i < result.n_segments; i++) {
  if (result.segments[i].text != nullptr) {
    fullText += result.segments[i].text;
  }
}
```

All whisper result segments are concatenated into a single string for simpler JNI return. Timing information is discarded at the JNI boundary (Kotlin layer receives only the full transcribed text).

## Deviations from Plan

None - plan executed exactly as written.

## Key Decisions

1. **CPU-only backend:** Forced `config.use_gpu = false` to match Phase 1 LLM pattern. GPU support deferred to future phases.

2. **Segment concatenation:** Concatenate all `result.segments[i].text` into single string at JNI boundary. This simplifies the Kotlin API by avoiding complex segment array marshaling. Timing information is lost but not needed for basic STT use case.

3. **JNI_ABORT flag:** Use JNI_ABORT when releasing float array since transcription is read-only on audio data.

## Integration Points

**Provides:**
- `whisper-jni-api`: 5 whisper JNI entry points callable from Kotlin

**Requires:**
- `phase-01-jni-foundation`: Existing JNI infrastructure (System.loadLibrary, LOGI/LOGE macros, jstring2string helper)

**Affects:**
- `kotlin-native-interface`: Kotlin layer now has 9 total external fun declarations (ready for high-level wrapper in next plan)

## Next Steps

Plan 02-02 will add Kotlin wrapper classes (EdgeVedaWhisper) and ViewModel integration to expose whisper STT to Flutter Dart layer via method channels.

## Self-Check

**Status:** PASSED

Verified all created/modified files exist:
- ✓ core/src/bridge_jni.cpp (modified)
- ✓ flutter/android/src/main/kotlin/com/edgeveda/edge_veda/NativeEdgeVeda.kt (modified)

Verified all commits exist:
- ✓ 51ca729 (Task 1: whisper JNI bridge functions)
- ✓ 4dbebc6 (Task 2: whisper Kotlin external declarations)
