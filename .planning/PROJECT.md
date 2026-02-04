# Edge Veda SDK

## What This Is

A Flutter SDK for on-device LLM inference, starting with iOS. Developers can run Llama 3.2 1B locally on user devices with sub-200ms latency and zero server costs. The model downloads on first use and caches locally.

## Core Value

**Developers can add on-device LLM inference to their Flutter iOS apps with a simple API — text in, text out.**

If everything else fails, this must work: load a model, send a prompt, get a response. On device. No network required after model download.

## Requirements

### Validated

Existing scaffolding in place:

- ✓ C++ core API defined (`core/include/edge_veda.h`) — existing
- ✓ Flutter plugin structure with FFI bindings (`flutter/lib/src/ffi/`) — existing
- ✓ CMake build system with iOS toolchain — existing
- ✓ Makefile orchestration for cross-platform builds — existing

### Active

v1 deliverables (Flutter iOS):

- [ ] llama.cpp integrated as C++ submodule
- [ ] C++ engine implements actual inference (not stubs)
- [ ] Metal GPU acceleration enabled for iOS
- [ ] Flutter FFI bindings complete and working
- [ ] Model manager downloads Llama 3.2 1B on first use
- [ ] Model caching with checksum validation
- [ ] Simple API: `EdgeVeda.generate(prompt)` returns response
- [ ] Demo Flutter app showing text in → text out
- [ ] README with setup and usage instructions
- [ ] Published to pub.dev

### Out of Scope

- Android support — v2 (after iOS validated)
- Streaming responses — v2 (prove basic works first)
- Other platforms (Swift, Kotlin, React Native, Web) — future milestones
- STT (whisper.cpp) — future milestone
- TTS (Kokoro) — future milestone
- Multi-turn chat with history — v2
- Control plane / OTA updates — future milestone

## Context

**Existing codebase state:**
- Architecture: Single C++ core + multi-platform bindings pattern
- All platform SDKs are scaffolded but contain stub implementations
- llama.cpp is referenced in CMakeLists.txt but not added as submodule
- No actual inference code exists — engine.cpp has placeholders
- Zero test coverage across all platforms

**PRD reference:**
- 12-week roadmap exists in `prd.txt`
- Performance targets: >15 tok/sec on mid-range mobile, <500ms TTFT on iPhone 13+
- Memory safety: Watchdog to prevent OS kill when RAM >1.5GB on 4GB devices
- Binary size target: <25MB base SDK (excluding models)

**Model:**
- Llama 3.2 1B in GGUF format (quantized)
- Downloaded from CDN on first use
- Cached in app's documents directory
- ~500MB-1GB depending on quantization

## Constraints

- **Platform:** iOS 15.0+ (Metal framework required)
- **Flutter:** 3.16.0+ with Dart 3.0+
- **Model format:** GGUF only (llama.cpp native format)
- **Build tools:** CMake 3.15+, Xcode 15+, Ninja
- **Memory:** Must not crash on 4GB devices with 1B model

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Flutter-first | PRD priority + widest reach with one codebase | — Pending |
| iOS before Android | Metal path simpler, validate approach first | — Pending |
| Download on first use | Keeps app size small, only needs network once | — Pending |
| Text in/out before streaming | Prove core works before adding complexity | — Pending |
| Llama 3.2 1B | PRD primary model, good quality/size tradeoff | — Pending |

---
*Last updated: 2026-02-04 after initialization*
