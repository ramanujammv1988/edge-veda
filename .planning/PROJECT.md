# Edge Veda: Multi-Platform On-Device AI

## What This Is

Edge Veda is a Flutter plugin providing zero-cloud, on-device AI inference (LLM, STT, image generation) across iOS, macOS, and Android platforms via a unified C++ core with platform-native bridges.

## Core Value

Zero-cloud, on-device AI for Flutter applications natively utilizing hardware accelerators.

## Current Milestone: v1.1 CI/CD + Quality

**Goal:** Establish CI/CD pipeline, test suite, and release infrastructure to ensure quality gates before further feature expansion.

**Target features:**
- CI/CD pipeline with multi-platform build verification (#21)
- Unit and integration test suite (#22)
- CI green-by-default with deterministic vs device-only lane separation (#49)
- Release artifact contract fix for XCFramework (#46)

## Constraints & Boundaries
- **Must not break existing code:** iOS/macOS Metal logic remains intact. Android extensions are additive.
- **Target Architecture:** arm64-v8a only for Android (no 32-bit).

## Requirements

### Validated
- ✓ [Core LLM inference] — existing (llama.cpp)
- ✓ [STT/TTS capabilities] — existing
- ✓ [iOS / macOS Flutter Plugin framework] — existing
- ✓ [Issue #12: Flutter Android support via pub.dev] — v1.0

### Active
- [ ] CI/CD pipeline for multi-platform builds and testing (#21)
- [ ] Unit and integration test suite (#22)
- [ ] CI green-by-default: deterministic vs device-only lanes (#49)
- [ ] Release artifact contract alignment (#46)

### Out of Scope
- Android GPU (Vulkan/OpenCL) support — deferred to v1.2+
- Battery level and free disk space telemetry — stubs returning -1
- Developer experience improvements (tiered exports, metrics, canRun guard) — v1.2
- Native SDKs (Swift SPM, Kotlin Maven) — v2.0+

## Context

Shipped v1.0 with 1,136 lines added across 10 files on `feat/12-flutter-android` branch.
Tech stack: C++ core (llama.cpp, whisper.cpp, stable-diffusion.cpp), Kotlin JNI bridge, Dart FFI, Flutter plugin.
Platform support: iOS (Obj-C, Metal), macOS (Swift, Metal), Android (Kotlin, CPU-only).
No CI/CD pipeline currently — builds and tests are manual.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| CPU-only execution | Broadest Android compatibility, lower crash risk | ✓ Good — enforced at JNI, CMake, and Gradle layers |
| JNI C++ Bridge in core/src/ | Single source of truth, compiled via CMakeLists.txt | ✓ Good — eliminated divergent copy |
| 16KB page alignment | Android 15+ / Google Play requirement | ✓ Good — verified via readelf |
| Thermal returns -1 on Android | No direct API equivalent to iOS NSProcessInfo.ThermalState | ✓ Good — graceful degradation |
| ActivityManager.MemoryInfo.availMem | Android equivalent of iOS os_proc_available_memory | ✓ Good — consistent with iOS pattern |
| Whisper segments concatenated | Simpler JNI return, timing info not needed for basic STT | ✓ Good — avoids complex array marshaling |
| v1.1 = CI/CD before features | Quality gates before expanding feature surface | — Pending |

---
*Last updated: 2026-02-28 after v1.1 milestone start*
