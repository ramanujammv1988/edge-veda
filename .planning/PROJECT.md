# Edge Veda SDK

## What This Is

A Flutter SDK for on-device LLM inference on iOS and Android. Developers can run Llama 3.2 1B locally on user devices with GPU acceleration (Metal on iOS, Vulkan on Android), sub-200ms latency, and zero server costs. The model downloads on first use and caches locally.

## Core Value

**Developers can add on-device LLM inference to their Flutter apps with a simple API — text in, text out, on both iOS and Android.**

If everything else fails, this must work: load a model, send a prompt, get a response. On device. No network required after model download.

## Current Milestone: v1.1 Android + Streaming

**Goal:** Expand Edge Veda to Android with Vulkan GPU acceleration and add streaming responses for better chat UX on both platforms.

**Target features:**
- Android support with Vulkan GPU backend (API 24+)
- Streaming token-by-token responses
- Feature parity with iOS v1.0

## Requirements

### Validated

v1.0 shipped capabilities (iOS):

- ✓ C++ core with llama.cpp integration (pinned to b4658)
- ✓ Metal GPU acceleration for iOS
- ✓ Flutter FFI bindings with Isolate-based async
- ✓ Model download with progress and SHA256 verification
- ✓ Model caching in applicationSupportDirectory
- ✓ Simple API: `EdgeVeda.generate(prompt)` returns response
- ✓ Memory pressure handling with 1.2GB limit
- ✓ Demo Flutter app with metrics display
- ✓ Published to pub.dev (v1.0.0, 150/160 pana score)

### Active

v1.1 deliverables (Android + Streaming):

- [ ] Android NDK build with Vulkan GPU backend
- [ ] Android-specific memory management (different from iOS jetsam)
- [ ] Streaming API: `EdgeVeda.generateStream(prompt)` yields tokens
- [ ] Streaming works on both iOS and Android
- [ ] Long-lived worker isolate for streaming (replaces per-call Isolate.run)
- [ ] Cancel token for aborting streaming generation
- [ ] Demo app updated with streaming UI and Android support
- [ ] README updated with Android setup instructions

### Out of Scope

- Other platforms (Swift, Kotlin, React Native, Web) — future milestones
- STT (whisper.cpp) — future milestone
- TTS (Kokoro) — future milestone
- Multi-turn chat with history — v1.2 (after streaming validated)
- Control plane / OTA updates — future milestone
- OpenCL GPU backend — Vulkan sufficient for API 24+

## Context

**v1.0 codebase state:**
- Architecture: Single C++ core + Flutter FFI bindings
- llama.cpp integrated as submodule (pinned to b4658 tag)
- iOS build working with Metal GPU acceleration
- XCFramework builds via build-ios.sh script
- Isolate.run() pattern for non-blocking inference
- Published to pub.dev with 150/160 pana score

**PRD reference:**
- Performance targets: >15 tok/sec on mid-range mobile, <500ms TTFT
- Memory safety: Watchdog at 1.2GB limit
- Binary size target: <25MB base SDK (excluding models)

**Model:**
- Llama 3.2 1B in GGUF format (Q4_K_M quantization)
- Downloaded from CDN on first use
- Cached in platform-appropriate directory
- ~700MB file size

## Constraints

- **iOS:** iOS 15.0+ (Metal framework required)
- **Android:** API 24+ (Android 7.0+, Vulkan required)
- **Flutter:** 3.16.0+ with Dart 3.0+
- **Model format:** GGUF only (llama.cpp native format)
- **Build tools:** CMake 3.15+, Xcode 15+, Android NDK r25+
- **Memory:** Must not crash on 4GB devices with 1B model

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Flutter-first | PRD priority + widest reach with one codebase | ✓ Good |
| iOS before Android | Metal path simpler, validate approach first | ✓ Good |
| Download on first use | Keeps app size small, only needs network once | ✓ Good |
| Text in/out before streaming | Prove core works before adding complexity | ✓ Good |
| Llama 3.2 1B | PRD primary model, good quality/size tradeoff | ✓ Good |
| Vulkan for Android | Best performance on API 24+, llama.cpp native support | — Pending |
| Long-lived isolate for streaming | Enables persistent callback for token streaming | — Pending |

---
*Last updated: 2026-02-04 after v1.1 milestone start*
