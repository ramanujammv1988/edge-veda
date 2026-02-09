# Changelog

All notable changes to the Edge Veda Flutter SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-02-08

### Added
- **Vision (VLM):** SmolVLM2-500M support for real-time camera-to-text inference
- **Chat Session API:** Multi-turn conversation management with context overflow summarization
- **Chat Templates:** Llama 3 Instruct, ChatML, and generic template formats
- **System Prompt Presets:** Built-in assistant, coder, and creative personas
- **VisionWorker:** Persistent isolate for vision inference (model loads once, reused across frames)
- **FrameQueue:** Drop-newest backpressure for camera frame processing
- **RuntimePolicy:** Adaptive QoS with thermal/battery/memory-aware hysteresis
- **TelemetryService:** iOS thermal state, battery level, memory polling via MethodChannel
- **PerfTrace:** JSONL performance trace logger for soak test analysis
- **Soak Test Screen:** 15-minute automated vision benchmark in demo app
- `initVision()` and `describeImage()` APIs
- `CameraUtils` for BGRA/YUV420 to RGB conversion
- Context indicator (turn count + usage bar) in demo Chat tab
- New Chat button and persona picker in demo app

### Changed
- Upgraded llama.cpp from b4658 to b7952
- XCFramework rebuilt with all symbols including `ev_vision_get_last_timings`
- Demo app redesigned with dark theme, 3-tab navigation (Chat, Vision, Settings)
- Chat tab rewritten to use ChatSession API (no direct generate() calls)
- All FFI bindings now eager (removed lazy workaround for missing symbols)
- Constrained ffi to <2.1.0 (avoids objective_c simulator crash)

### Fixed
- Xcode 26 debug blank executor: export `_main` in podspec symbol whitelist
- RuntimePolicy evaluate() de-escalation when pressure improves but persists

## [1.0.0] - 2026-02-04

### Added
- **Core SDK:** On-device LLM inference via llama.cpp with Metal GPU on iOS
- **Dart FFI:** 37 native function bindings via `DynamicLibrary.process()`
- **Streaming:** Token-by-token generation with `CancelToken` cancellation
- **Model Management:** Download, cache, SHA-256 verify, delete
- **Memory Monitoring:** RSS tracking, pressure callbacks, configurable limits
- **Isolate Safety:** All FFI calls in `Isolate.run()`, persistent `StreamingWorker`
- **XCFramework:** Device arm64 + simulator arm64 static library packaging
- **Demo App:** Chat screen with streaming, model selection, benchmark mode
- **Exception Hierarchy:** 10 typed exceptions mapped from native error codes
