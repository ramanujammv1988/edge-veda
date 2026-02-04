# Roadmap: Edge Veda Flutter iOS SDK v1.0

## Overview

Build a Flutter SDK enabling on-device LLM inference on iOS devices. Start with C++ core integrating llama.cpp with Metal GPU acceleration, wrap with Flutter FFI bindings and model management, deliver a working demo app, then publish to pub.dev. Each phase delivers a verifiable capability that unblocks the next.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: C++ Core + llama.cpp Integration** - Native engine builds with Metal support
- [ ] **Phase 2: Flutter FFI + Model Management** - Dart bindings and model download working
- [ ] **Phase 3: Demo App + Polish** - Example app demonstrates text generation
- [ ] **Phase 4: Release** - Published to pub.dev with documentation

## Phase Details

### Phase 1: C++ Core + llama.cpp Integration
**Goal**: Native C++ engine performs on-device inference with Metal GPU acceleration

**Depends on**: Nothing (first phase)

**Requirements**: R1.1, R1.2, R1.3, R1.4, R1.5, R3.1, R3.2, R4.3, R5.1, R5.2, R5.3

**Success Criteria** (what must be TRUE):
  1. llama.cpp submodule added at pinned commit and builds for iOS
  2. XCFramework builds for device and simulator with Metal enabled
  3. C++ API (ev_init, ev_generate, ev_free) loads GGUF model and generates coherent text
  4. Binary size stays under 15MB (measured with `size` command)
  5. Performance achieves >10 tok/sec on iPhone 12 with Metal backend

**Key Risks**:
- **Pitfall 1 (Critical)**: iOS memory kills app without warning - Implement memory guard proactively at 1.2GB limit
- **Pitfall 2 (Critical)**: Metal not enabled in build - Verify LLAMA_METAL ON and LLAMA_METAL_EMBED_LIBRARY ON in CMake
- **Pitfall 7 (Moderate)**: Binary size explosion - Disable desktop SIMD (AVX/AVX2), enable LTO, strip symbols

**Plans:** 4 plans

Plans:
- [x] 01-01-PLAN.md - Add llama.cpp submodule and configure CMake for iOS Metal builds
- [x] 01-02-PLAN.md - Implement C++ inference engine with llama.cpp API calls
- [x] 01-03-PLAN.md - Build iOS static libraries and create XCFramework
- [x] 01-04-PLAN.md - Verify inference with smoke test and performance measurement

### Phase 2: Flutter FFI + Model Management
**Goal**: Flutter developers can initialize SDK and download models with progress tracking

**Depends on**: Phase 1

**Requirements**: R2.1, R2.2, R2.3, R2.4, R3.3, R4.1, R4.2, R4.4

**Success Criteria** (what must be TRUE):
  1. FFI bindings match edge_veda.h API signatures (verified by compilation)
  2. Model downloads from URL with 0-100% progress callbacks
  3. Downloaded models cache locally and skip re-download on second init
  4. SHA256 checksum mismatch throws ModelValidationException
  5. All inference calls run in background isolate (UI never blocks)
  6. Memory stats API allows Flutter to monitor and respond to memory pressure

**Key Risks**:
- **Pitfall 3 (Critical)**: FFI blocks UI thread - Use Isolate.run() for all inference calls from start
- **Pitfall 4 (Critical)**: Model file path sandbox violations - Use applicationSupportDirectory, exclude from backup
- **Pitfall 6 (Critical)**: FFI memory leaks - Establish RAII wrapper pattern, clear ownership rules
- **Pitfall 12 (Moderate)**: Incorrect download progress - Use chunked download with explicit progress calculation

**Plans:** 4 plans in 3 waves

Plans:
- [x] 02-01-PLAN.md - Align FFI bindings to edge_veda.h and create RAII memory helpers (Wave 1)
- [x] 02-02-PLAN.md - Harden model download with caching, atomic temp file, typed exceptions (Wave 1)
- [ ] 02-03-PLAN.md - Rewrite SDK implementation with Isolate.run() for non-blocking FFI (Wave 2)
- [ ] 02-04-PLAN.md - Add memory stats polling and finalize public API exports (Wave 3)

### Phase 3: Demo App + Polish
**Goal**: Example Flutter app demonstrates working text generation with proper lifecycle handling

**Depends on**: Phase 2

**Requirements**: None (demo integration, not new requirements)

**Success Criteria** (what must be TRUE):
  1. Example app in flutter/example/ runs: user types prompt, sees generated response
  2. App handles backgrounding gracefully (cancels generation, saves state)
  3. Memory stays under 1.2GB during sustained usage (10+ consecutive generations)
  4. Performance benchmarks logged: tok/sec, TTFT, memory usage on real iPhone 12
  5. README.md includes setup instructions, usage examples, and performance expectations

**Key Risks**:
- **Pitfall 5 (Critical)**: App Store rejects background execution - Cancel generation on pause, document foreground-only
- **Pitfall 11 (Moderate)**: Flutter hot reload breaks FFI state - Implement dispose() that calls ev_free()
- **Pitfall 14 (Minor)**: Simulator performance misleads - Benchmark on real device (iPhone 12)

**Plans**: TBD

Plans:
- [ ] Plan details to be defined during phase planning

### Phase 4: Release
**Goal**: SDK published to pub.dev with complete documentation and CI/CD

**Depends on**: Phase 3

**Requirements**: None (packaging and distribution, not functional requirements)

**Success Criteria** (what must be TRUE):
  1. Package published to pub.dev with version 1.0.0
  2. pub.dev page shows usage example and API documentation
  3. CI/CD pipeline builds XCFramework and runs tests on every commit
  4. Developer can `flutter pub add edge_veda` and follow README to working inference in <30 minutes

**Key Risks**:
- Low risk phase - primary failure mode is incomplete documentation

**Plans**: TBD

Plans:
- [ ] Plan details to be defined during phase planning

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. C++ Core + llama.cpp Integration | 4/4 | **Complete** | 2026-02-04 |
| 2. Flutter FFI + Model Management | 2/4 | In progress | - |
| 3. Demo App + Polish | 0/? | Not started | - |
| 4. Release | 0/? | Not started | - |

---
*Roadmap created: 2026-02-04*
*Phase 1 planned: 2026-02-04*
*Phase 2 planned: 2026-02-04*
*Depth: comprehensive (from config.json)*
*Coverage: 19/19 v1 requirements mapped*
