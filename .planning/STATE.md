# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-04)

**Core value:** Developers can add on-device LLM inference to their Flutter apps with a simple API - text in, text out, on both iOS and Android.
**Current focus:** v1.1 Android + Streaming / Phase 8 VLM

## Current Position

Phase: 8 - On-Device VLM (Vision Language Model)
Plan: 08-01 complete (VLM C API)
Status: In progress
Last activity: 2026-02-06 - Completed 08-01-PLAN.md (VLM C API)

Progress: [########..] 80% (8/10 plans complete across active phases)

## Milestone Summary

**v1.0: iOS SDK (Complete)**
- Published to pub.dev v1.0.0
- 150/160 pana score
- iOS Metal GPU working

**v1.1: Android + Streaming (Active)**
- Phase 5: Android CPU Build (3 plans) - 05-01, 05-02 complete
- Phase 6: Streaming C++ + Dart (5 plans) - 06-01, 06-02, 06-03, 06-04 complete
- Phase 7: Android Vulkan + Demo (4 requirements) - depends on 5 and 6

Total: 8 plans across 2 parallel phases, then Phase 7

**Phase 8: On-Device VLM (Started)**
- 08-00: llama.cpp b7952 Upgrade - **Complete**
- 08-01: VLM C API - **Complete**
- 08-02 through 08-04: Vision integration - Pending

## Phase Dependencies

```
Phase 5 (Android CPU) ----+
                          +--> Phase 7 (Vulkan + Demo)
Phase 6 (Streaming)  ----+

Phase 8 (VLM) - Independent, urgent competitive response
  08-00 (llama.cpp upgrade) --> 08-01 --> 08-02 --> 08-03 --> 08-04
```

Phases 5 and 6 are independent and can run in parallel.
Phase 7 depends on both 5 and 6 completing.
Phase 8 is independent of 5/6/7.

## Phase 5 Progress

| Plan | Name | Status |
|------|------|--------|
| 05-01 | Android CMake Build | **Complete** |
| 05-02 | Memory Pressure Handling | **Complete** |
| 05-03 | APK Build & Verification | Pending |

## Phase 6 Progress

| Plan | Name | Status |
|------|------|--------|
| 06-01 | C++ Streaming API | **Complete** |
| 06-02 | Dart FFI Bindings | **Complete** |
| 06-03 | Worker Isolate | **Complete** (via 06-04 blocking fix) |
| 06-04 | Public Streaming API | **Complete** |
| 06-05 | Integration Tests | Pending |

## Phase 8 Progress

| Plan | Name | Status |
|------|------|--------|
| 08-00 | llama.cpp b7952 Upgrade | **Complete** |
| 08-01 | VLM C API | **Complete** |
| 08-02 | Dart FFI Vision Bindings | Pending |
| 08-03 | Model Download | Pending |
| 08-04 | Demo App | Pending |

## Research Flags

| Phase | Research Needed | Status |
|-------|-----------------|--------|
| Phase 5 | No | Skipped (standard NDK patterns) |
| Phase 6 | Yes | **Complete** (06-RESEARCH.md) |
| Phase 7 | Yes | Pending (Vulkan compatibility) |
| Phase 8 | Yes | **Complete** (08-RESEARCH.md) |

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

Phase 5 Plan 2 decisions:
- 800MB default for 4-6GB Android devices, 1GB for 8GB, 1.2GB for 12GB+
- iOS keeps 1.2GB (jetsam more predictable than LMK)
- EventChannel for platform-to-Dart memory pressure events

Phase 6 Plan 1 decisions:
- Pull-based streaming design (Dart calls ev_stream_next in loop) avoids callback threading issues
- Stream does NOT own context - context is shared, stream only owns sampler
- Atomic cancellation uses std::atomic<bool> with release/acquire memory ordering
- Natural end returns nullptr + EV_SUCCESS, cancellation returns nullptr + EV_ERROR_STREAM_ENDED

Phase 6 Plan 2 decisions:
- EvStreamImpl as opaque type matching C++ ev_stream_impl*
- Pointer<Int32> for error codes matching ev_error_t*

Phase 6 Plan 4 decisions:
- CancelToken uses listener pattern for cancellation propagation to worker
- Final TokenChunk has empty token with isFinal=true to signal stream end
- Single streaming session at a time (throws if generateStream called during active stream)
- Worker isolate reused across streaming sessions for efficiency

Phase 8 Plan 0 decisions:
- llama_kv_cache_clear() migrated to llama_memory_clear(llama_get_memory(ctx), true) for b7952
- Simulator XCFramework includes Metal stubs (b7952 unconditionally references ggml_backend_metal_reg)
- llama.cpp upgrade path: b4658 -> b7952 (12 months, only 1 API breaking change)

Phase 8 Plan 1 decisions:
- Vision context (ev_vision_context) fully separate from text context (ev_context)
- Used mtmd_helper_eval_chunks for combined encode+decode (recommended by mtmd-cli.cpp)
- Image marker prepended to prompt (mtmd_default_marker + newline + user prompt)
- Bitmap freed after tokenize, chunks freed after eval (P2 memory mitigation)
- 4096 default context size for VLM (accommodates image tokens + prompt + output)
- llama_batch_get_one used for generation loop (core API, not common library)

### Pending Todos

Carried from v1.0:
- Configure PUB_TOKEN secret in GitHub for automated publishing (optional)
- Create GitHub Release with XCFramework when ready (improves user setup)

v1.1:
- Verify Android NDK r27c installed in dev environment
- Test Vulkan capability on target devices (Pixel 6a, Galaxy A54)

### Roadmap Evolution

- Phase 8 added: On-Device VLM (Vision Language Model) - URGENT competitive response
  - Real-time camera object description/detection
  - Zero latency, fully offline
  - Marked urgent due to competitor launch
  - 08-00 upgrade complete, libmtmd now available

### Blockers/Concerns

None currently.

**Environment Notes:**
- CMake installed (4.2.3 via Homebrew)
- Flutter SDK available
- Xcode Command Line Tools only (users build XCFramework locally)
- Android NDK not yet verified in dev environment
- llama.cpp now at b7952 (upgraded from b4658)

## Key Pitfalls by Phase

**Phase 5 (Android CPU):**
- P1: Android LMK differs from iOS - use 800MB limit [IMPLEMENTED 05-02]
- P2: llama.cpp version - now at b7952 (upgraded for Phase 8) [UPDATED 08-00]
- P4: dlopen fails - build arm64-v8a, verify in APK [CONFIGURED 05-01]

**Phase 6 (Streaming):**
- P5: Wrong callback API crashes - use NativeCallable.listener [AVOIDED via pull-based design]
- P6: Isolate.run() insufficient - refactor to Isolate.spawn() [IMPLEMENTED 06-03/06-04]
- P8: High-volume callbacks deadlock - batch tokens [AVOIDED via pull-based design]
- Pull-based streaming implemented in C++ (06-01) - avoids callback issues

**Phase 7 (Vulkan + Demo):**
- P3: Vulkan incomplete - CPU fallback, device allowlist
- P10: Platform parity - automated cross-platform tests

**Phase 8 (VLM):**
- llama.cpp b7952 upgrade complete [08-00]
- libmtmd available at tools/mtmd/mtmd.h
- SmolVLM2-500M-Video-Instruct target model
- P2: Memory explosion from image embeddings - MITIGATED [08-01] (immediate free after eval)

## Session Continuity

Last session: 2026-02-06
Stopped at: Completed 08-01-PLAN.md (VLM C API)
Resume with: `/gsd:execute-phase 8` for 08-02 (CMake + Build Integration)

---
*Phase 8 in progress. 08-00 and 08-01 complete. Next: 08-02 CMake + Build Integration.*
