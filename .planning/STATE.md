# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-04)

**Core value:** Developers can add on-device LLM inference to their Flutter apps with a simple API - text in, text out, on both iOS and Android.
**Current focus:** v1.1 Android + Streaming

## Current Position

Phase: 5 - Android CPU Build (and 6 can parallelize)
Plan: Not started
Status: Roadmap complete, awaiting phase planning
Last activity: 2026-02-05 - v1.1 roadmap created

Progress: [░░░░░░░░░░] 0% (0/14 v1.1 requirements)

## Milestone Summary

**v1.0: iOS SDK (Complete)**
- Published to pub.dev v1.0.0
- 150/160 pana score
- iOS Metal GPU working

**v1.1: Android + Streaming (Active)**
- Phase 5: Android CPU Build (5 requirements)
- Phase 6: Streaming C++ + Dart (5 requirements) - can parallelize with Phase 5
- Phase 7: Android Vulkan + Demo (4 requirements) - depends on 5 and 6

Total: 14 requirements across 3 phases

## Phase Dependencies

```
Phase 5 (Android CPU) ----+
                          +--> Phase 7 (Vulkan + Demo)
Phase 6 (Streaming)  ----+
```

Phases 5 and 6 are independent and can run in parallel.
Phase 7 depends on both 5 and 6 completing.

## Research Flags

| Phase | Research Needed | Reason |
|-------|-----------------|--------|
| Phase 5 | No | Standard NDK patterns, well-documented |
| Phase 6 | YES | Complex isolate threading, FFI callbacks, sparse examples |
| Phase 7 | YES | Vulkan device compatibility unclear, GPU fallback strategies |

## Accumulated Context

### Decisions

Decisions carried from v1.0:
- Flutter-first approach validated (Good)
- iOS before Android validated (Good)
- Download on first use validated (Good)
- Text in/out before streaming validated (Good)
- Llama 3.2 1B model validated (Good)

v1.1 decisions (from research):
- CPU-first Android strategy (Vulkan unreliable, validate foundation first)
- Long-lived worker isolate for streaming (replaces Isolate.run())
- NativeCallable.listener for thread-safe callbacks (Dart 3.1+)
- Android memory limit 800MB (more conservative than iOS 1.2GB)
- NDK r27c LTS pinned (r28+ has 16KB page issues)

### Pending Todos

Carried from v1.0:
- Configure PUB_TOKEN secret in GitHub for automated publishing (optional)
- Create GitHub Release with XCFramework when ready (improves user setup)

v1.1:
- Verify Android NDK r27c installed in dev environment
- Test Vulkan capability on target devices (Pixel 6a, Galaxy A54)

### Blockers/Concerns

None currently.

**Environment Notes:**
- CMake installed (4.2.3 via Homebrew)
- Flutter SDK available
- Xcode Command Line Tools only (users build XCFramework locally)
- Android NDK not yet verified in dev environment

## Key Pitfalls by Phase

**Phase 5 (Android CPU):**
- P1: Android LMK differs from iOS - use 800MB limit
- P2: llama.cpp version - keep b4658, GGML_OPENMP=OFF
- P4: dlopen fails - build arm64-v8a, verify in APK

**Phase 6 (Streaming):**
- P5: Wrong callback API crashes - use NativeCallable.listener
- P6: Isolate.run() insufficient - refactor to Isolate.spawn()
- P8: High-volume callbacks deadlock - batch tokens

**Phase 7 (Vulkan + Demo):**
- P3: Vulkan incomplete - CPU fallback, device allowlist
- P10: Platform parity - automated cross-platform tests

## Session Continuity

Last session: 2026-02-05
Stopped at: v1.1 roadmap creation complete
Resume with: `/gsd:plan-phase 5` or `/gsd:plan-phase 6` (can parallelize)

---
*v1.1 roadmap created. Next: Plan Phase 5 or 6 (parallelizable).*
