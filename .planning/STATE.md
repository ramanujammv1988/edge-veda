# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-04)

**Core value:** Developers can add on-device LLM inference to their Flutter iOS apps with a simple API - text in, text out.
**Current focus:** Phase 1 - C++ Core + llama.cpp Integration

## Current Position

Phase: 1 of 4 (C++ Core + llama.cpp Integration)
Plan: 3 of 4 complete
Status: In progress
Last activity: 2026-02-04 - Completed 01-03-PLAN.md (iOS Build Script)

Progress: [####......] 30%

## Performance Metrics

**Velocity:**
- Total plans completed: 3
- Average duration: 5.7 min
- Total execution time: 0.28 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 3/4 | 17min | 5.7min |

**Recent Trend:**
- Last 5 plans: 01-01 (5min), 01-02 (4min), 01-03 (8min)
- Trend: Stable

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Flutter-first approach with iOS before Android (validate on Metal path first)
- Download on first use keeps app size small
- Text in/out before streaming (prove core works before adding complexity)
- Llama 3.2 1B model (good quality/size tradeoff per PRD)
- (01-01) Pinned llama.cpp to b4658 tag (855cd0734) for API stability
- (01-01) Use GGML_METAL not deprecated LLAMA_METAL
- (01-01) Disabled all desktop SIMD (AVX/AVX2/FMA/F16C) to prevent binary bloat
- (01-01) Enabled GGML_METAL_EMBED_LIBRARY for iOS shader embedding
- (01-02) Use llama_batch_get_one for simple batching (single-shot, not streaming)
- (01-02) Clear KV cache before each generation for stateless API design
- (01-02) Sampler chain order: penalties -> top_k -> top_p -> temp -> dist
- (01-03) Build device with Metal ON, simulator with Metal OFF (limited simulator Metal support)
- (01-03) Merge llama.cpp/ggml libraries into single static archive for simpler linking
- (01-03) XCFramework is build artifact (gitignored), not committed to repo

### Pending Todos

- Install Xcode to enable actual iOS build execution (required for Phase 2)

### Blockers/Concerns

**Phase 1 Risks:**
- ~~iOS memory management (jetsam) requires proactive monitoring - memory_guard.cpp exists but needs integration~~ RESOLVED in 01-02
- ~~Metal backend configuration is error-prone - must verify build flags before first compile~~ RESOLVED in 01-01
- ~~Binary size can explode with desktop SIMD - disable non-ARM optimizations in CMake~~ RESOLVED in 01-01

**Phase 2 Risks:**
- FFI threading violations will block UI - must use background isolate from start
- File path sandbox violations on iOS - must use correct path_provider API

**Environment Notes:**
- ~~CMake not installed in dev environment~~ RESOLVED: Installed via Homebrew (4.2.3)
- Xcode not installed (only Command Line Tools) - required for actual iOS build
- Build script verified structurally; actual compilation deferred until Xcode available

## Session Continuity

Last session: 2026-02-04
Stopped at: Completed 01-03-PLAN.md (iOS Build Script)
Resume file: None

---
*Next step: Execute 01-04-PLAN.md (Integration Testing) or install Xcode for actual build*
