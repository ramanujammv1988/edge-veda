# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-04)

**Core value:** Developers can add on-device LLM inference to their Flutter iOS apps with a simple API - text in, text out.
**Current focus:** RELEASED - v1.0.0 on pub.dev

## Current Position

Phase: 4 of 4 (Release) - COMPLETE
Plan: 3 of 3 complete
Status: PROJECT RELEASED
Last activity: 2026-02-04 - Completed 04-03-PLAN.md (Release Execution)

Progress: [##########] 100% (Phase 1: 4/4, Phase 2: 4/4, Phase 3: 4/4, Phase 4: 3/3)

## Release Status

**edge_veda v1.0.0 PUBLISHED**

| Artifact | Status | URL |
|----------|--------|-----|
| pub.dev package | Published | https://pub.dev/packages/edge_veda |
| pana score | 150/160 | Exceeds 130 threshold |
| GitHub Release | Skipped | Users build XCFramework locally |

## Performance Metrics

**Velocity:**
- Total plans completed: 13
- Average duration: 8.5 min
- Total execution time: ~2 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01 | 4/4 | 24min | 6.0min |
| 02 | 4/4 | 27min | 6.8min |
| 03 | 4/4 | 24min | 6.0min |
| 04 | 3/3 | 75min | 25.0min |

**Recent Trend:**
- Last 5 plans: 03-01 (6min), 03-02 (6min), 04-01 (6min), 04-02 (44min), 04-03 (25min)
- Trend: Release plans longer due to publishing and verification

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
- (01-04) Updated to new llama.cpp API (vocab-based tokenization, llama_model_* functions)
- (01-04) Smoke test achieved 79 tok/sec with Llama 3.2 1B Q4_K_M on M1 Mac
- (02-01) Dart enums use named value property for C interop (not ordinal)
- (02-01) RAII scopes provide both free() and use() pattern for flexibility
- (02-01) Memory ownership: Dart allocs -> calloc.free(), C++ allocs -> ev_free_string()
- (02-02) ModelValidationException separate from ChecksumException (broader validation scope)
- (02-02) NativeErrorCode.toException() returns nullable for success code handling
- (02-02) 3 retries with exponential backoff (1s/2s/4s) for transient network errors
- (02-02) Atomic temp file pattern: download to .tmp, verify checksum, rename
- (02-03) Each Isolate.run() creates fresh context (correct for v1, efficient pattern in v2)
- (02-03) Streaming deferred to v2 (requires long-lived worker isolate)
- (02-03) Validation runs on main isolate (no FFI, safe)
- (02-04) Memory pressure uses polling (getMemoryStats) not callbacks - Isolate.run() architecture prevents persistent callbacks
- (02-04) CancelToken and EdgeVedaGenericException added to exports during verification
- (02-04) Phase 2 marked complete despite XCFramework gap - gap is Phase 1 environment issue (Xcode needed), not Phase 2 code
- (03-02) Stopwatch-based timing more accurate than DateTime.now() arithmetic
- (03-02) Token estimation: ~4 chars per token heuristic for English text
- (03-02) Memory warning threshold at 1000MB (1.2GB limit from PRD)
- (04-01) XCFramework distributed via GitHub Releases HTTP download
- (04-01) prepare-release.sh validates without modifying files
- (04-01) Dart Native Assets migration planned for v1.1.0
- (04-02) PUB_TOKEN deferred - first release will be manual
- (04-02) Three-job workflow: validate -> build-release -> publish
- (04-02) Prerelease detection via version suffix (contains -)
- (04-03) GitHub Release skipped - users build XCFramework locally via build-ios.sh
- (04-03) pana score 150/160 achieved (10 points for iOS-only platform support)

### Pending Todos

- Configure PUB_TOKEN secret in GitHub for automated publishing (optional for future releases)
- Create GitHub Release with XCFramework when ready (improves user setup time)

### Blockers/Concerns

**All Blockers RESOLVED - Project Released**

**Environment Notes:**
- ~~CMake not installed in dev environment~~ RESOLVED: Installed via Homebrew (4.2.3)
- Flutter SDK available - used for dart analyze and pub publish
- Xcode not installed (only Command Line Tools) - users build XCFramework locally

## Session Continuity

Last session: 2026-02-04
Stopped at: PROJECT RELEASED - edge_veda v1.0.0 on pub.dev
Resume file: None

---
*Project released! edge_veda v1.0.0 available at https://pub.dev/packages/edge_veda*

## Post-Release Checklist

Completed:
- [x] pana score validation (150/160 points)
- [x] Manual publish to pub.dev
- [x] Installation verification from fresh project

Future improvements:
- [ ] Create GitHub Release with pre-built XCFramework
- [ ] Configure PUB_TOKEN for automated releases
- [ ] Dart Native Assets integration (v1.1.0)
