# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.4.0] - 2026-02-22

### Changed
- **Dynamic XCFramework:** Switched from static library with manual linker flags to dynamic framework via `vendored_frameworks`. Eliminates `use_modular_headers!` Podfile requirement, 88-line exported_symbol whitelist, and Xcode 26 debug stub workaround.
- **FFI loading:** Changed from `DynamicLibrary.process()` (static linking) to `DynamicLibrary.open('EdgeVedaCore.framework/EdgeVedaCore')` (dynamic framework)
- **ffi constraint:** Widened from `>=2.0.0 <2.1.0` to `^2.0.0` (objective_c simulator crash was caused by static linking approach, no longer applicable)

### Removed
- `use_modular_headers!` Podfile requirement (dynamic framework works with both `use_frameworks!` and `use_modular_headers!`)
- 88-line `-Wl,-exported_symbol` whitelist from podspec
- `-force_load` static library linker flags from podspec
- Xcode 26 debug blank executor `_main` / `___debug_main_executable_dylib_entry_point` workaround

## [2.1.0] - 2026-02-15

### Added
- **Smart Model Advisor:** Device-aware model recommendations with 4D scoring (fit, quality, speed, context)
- **DeviceProfile:** Detects iPhone model, RAM, chip, tier via sysctl FFI (27-entry device DB)
- **MemoryEstimator:** Calibrated bytes-per-parameter formulas (Q4_K_M=0.58, Q8_0=1.05) with KV cache + overhead
- **ModelAdvisor.recommend():** Ranked model list with per-model optimal EdgeVedaConfig
- **ModelAdvisor.canRun():** Quick fit check before download
- **Storage availability check:** getFreeDiskSpace() via MethodChannel
- **Qwen3 0.6B** added to ModelRegistry (tool-calling capable, Q4_K_M, 397 MB)
- **All MiniLM L6 v2** added to ModelRegistry (embedding model, F16, 46 MB)
- **RAG demo** in Chat tab — paperclip attach, chunk, embed, streaming RAG answers
- **Phone Detective Mode** — tool calling showcase scanning photo/calendar metadata with noir LLM narration

### Changed
- KV cache quantization: Q8_0 by default (halves KV cache from ~64MB to ~32MB)
- Flash attention AUTO enabled by default (Metal enables automatically)
- getMemoryStats() routed through existing StreamingWorker (eliminates ~600MB memory spike)
- Tool calling demo loads Qwen3-0.6B (not Llama 3.2) for correct model/template match

### Fixed
- Batched prompt evaluation: chunk tokens in n_batch-sized batches (fixes assertion on 3rd+ multi-turn message)
- Streaming persistence: assistant message saved after stream completes naturally (fixes break-on-cancel losing messages)
- GBNF grammar-constrained generation for detective narration JSON

## [1.1.1] - 2026-02-09

### Fixed
- License corrected to Apache 2.0 (was incorrectly MIT in pub.dev package)
- README rewritten with accurate capabilities and real soak test metrics
- CHANGELOG cleaned up to reflect only shipped features

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
- Published to pub.dev (150/160 pana score)
