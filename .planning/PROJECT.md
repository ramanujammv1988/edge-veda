# Edge Veda: Multi-Platform On-Device AI

## What This Is

Edge Veda is a Flutter plugin providing zero-cloud, on-device AI inference (LLM, STT, image generation) across iOS, macOS, and Android platforms via a unified C++ core with platform-native bridges.

## Core Value

Zero-cloud, on-device AI for Flutter applications natively utilizing hardware accelerators.

## Constraints & Boundaries
- **Must not break existing code:** iOS/macOS Metal logic remains intact. Android extensions are additive.
- **Vulkan Deferred:** Android runs CPU-only execution (Vulkan deferred to v1.1 to reduce device fragmentation risk).
- **Target Architecture:** arm64-v8a only for Android initial release (no 32-bit).

## Requirements

### Validated
- ✓ [Core LLM inference] — existing (llama.cpp)
- ✓ [STT/TTS capabilities] — existing
- ✓ [iOS / macOS Flutter Plugin framework] — existing
- ✓ [Issue #12: Flutter Android support via pub.dev] — v1.0
  - Android NDK CMake cross-compilation
  - 9-function JNI bridge (4 LLM + 5 whisper STT)
  - Telemetry MethodChannel with 7 Android API implementations
  - 48/48 ev_* FFI bindings with DynamicLibrary.open
  - Verified integration chain (C++ → JNI → Kotlin → Dart)

### Active

(No active requirements — define via `/gsd:new-milestone`)

### Out of Scope
- Android GPU (Vulkan/OpenCL) support — deferred to v1.1
- Battery level and free disk space telemetry — stubs returning -1
- On-device runtime testing — verified statically, needs device validation

## Context

Shipped v1.0 with 1,136 lines added across 10 files on `feat/12-flutter-android` branch.
Tech stack: C++ core (llama.cpp, whisper.cpp, stable-diffusion.cpp), Kotlin JNI bridge, Dart FFI, Flutter plugin.
Platform support: iOS (Obj-C, Metal), macOS (Swift, Metal), Android (Kotlin, CPU-only).

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| CPU-only execution | Broadest Android compatibility, lower crash risk | ✓ Good — enforced at JNI, CMake, and Gradle layers |
| JNI C++ Bridge in core/src/ | Single source of truth, compiled via CMakeLists.txt | ✓ Good — eliminated divergent copy |
| 16KB page alignment | Android 15+ / Google Play requirement | ✓ Good — verified via readelf |
| Thermal returns -1 on Android | No direct API equivalent to iOS NSProcessInfo.ThermalState | ✓ Good — graceful degradation |
| ActivityManager.MemoryInfo.availMem | Android equivalent of iOS os_proc_available_memory | ✓ Good — consistent with iOS pattern |
| Whisper segments concatenated | Simpler JNI return, timing info not needed for basic STT | ✓ Good — avoids complex array marshaling |

---
*Last updated: 2026-02-28 after v1.0 milestone*
