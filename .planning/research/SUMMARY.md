# Research Summary: Edge Veda Flutter iOS SDK

**Domain:** On-device LLM inference for Flutter iOS
**Researched:** 2026-02-04

## Key Stack Recommendations

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Inference Engine | llama.cpp (pinned commit) | Industry standard, excellent Metal support |
| Model Format | GGUF (v3) | Native llama.cpp format, quantization support |
| GPU Backend | Metal | Required for >15 tok/sec on iOS |
| FFI | dart:ffi (manual bindings) | Control over async patterns |
| Async Pattern | Isolate.run() | Prevent UI blocking during inference |
| Model Storage | applicationSupportDirectory | iOS sandbox-safe, excludes from iCloud |

## Table Stakes (v1 Must-Have)

1. **Core Inference**
   - Load GGUF model from path
   - `generate(prompt)` returns text
   - System prompt support
   - Temperature/top-p/top-k sampling

2. **Model Management**
   - Download model from URL with progress
   - Local caching
   - Checksum verification (SHA256)

3. **Resource Management**
   - Memory usage tracking
   - Proper dispose/cleanup
   - Memory pressure handling

4. **Error Handling**
   - Typed exception hierarchy
   - Clear error messages

## Critical Architecture Decisions

1. **Threading:** Background isolate for all inference calls (never block main)
2. **Memory Budget:** Hard limit 1.2GB, warning at 900MB (4GB device safe)
3. **Context Window:** 2048 tokens default (memory-safe on all devices)
4. **llama.cpp Integration:** Git submodule, pinned to specific commit
5. **Binary Distribution:** XCFramework via CocoaPods

## Top Pitfalls to Avoid

| # | Pitfall | Prevention | Phase |
|---|---------|------------|-------|
| 1 | iOS memory kills app (jetsam) | Memory guard at 1.2GB, use mmap | 1 |
| 2 | Metal not enabled in build | Set LLAMA_METAL ON, LLAMA_METAL_EMBED_LIBRARY ON | 1 |
| 3 | FFI blocks UI thread | Always use Isolate.run() for inference | 2 |
| 4 | Wrong model storage path | Use applicationSupportDirectory, exclude from backup | 2 |
| 5 | Binary size explosion | Disable desktop SIMD (AVX/AVX2), strip symbols, LTO | 1 |
| 6 | FFI memory leaks | RAII wrappers, clear ownership rules, always free | 2 |
| 7 | App Store rejects background exec | Cancel on pause, save state, foreground-only | 3 |

## Recommended Phase Order

```
Phase 1: C++ Core + llama.cpp Integration
├── Add llama.cpp as git submodule (pin commit)
├── Configure CMake for iOS Metal build
├── Implement ev_init(), ev_generate(), ev_free()
├── Build XCFramework (device + simulator)
└── Validate binary size <15MB

Phase 2: Flutter FFI + Model Management
├── Complete FFI bindings matching edge_veda.h
├── Implement Isolate-based async wrapper
├── Model download with progress + checksum
├── Memory pressure integration
└── Basic error handling

Phase 3: Demo App + Polish
├── Example Flutter app (text in → text out)
├── Memory guard integration testing
├── Lifecycle handling (pause/resume)
├── Performance benchmarks on real devices
└── README documentation

Phase 4: Release
├── pub.dev publication
├── Final documentation
├── CI/CD setup
└── App Store submission prep
```

## Open Questions (Verify Before Implementation)

1. Current llama.cpp stable release tag (training data may be stale)
2. Exact CMake flags for llama.cpp Metal on iOS in 2025
3. Flutter 3.19+ isolate FFI patterns
4. Xcode 16+ toolchain compatibility

## Files Created

- `.planning/research/STACK.md` — Technology recommendations
- `.planning/research/FEATURES.md` — Feature landscape and prioritization
- `.planning/research/ARCHITECTURE.md` — Component boundaries and data flow
- `.planning/research/PITFALLS.md` — 17 pitfalls with prevention strategies

---
*Research synthesis complete. Ready for requirements definition.*
