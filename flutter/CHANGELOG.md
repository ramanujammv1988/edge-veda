# Changelog

All notable changes to the Edge Veda Flutter SDK will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.1] - 2026-02-12

### Fixed
- README updated with complete v1.3.0 feature documentation (STT, function calling, embeddings, RAG, confidence scoring)
- Supported Models table now includes Whisper and embedding models

## [1.3.0] - 2026-02-12

### Added
- **Whisper STT:** On-device speech-to-text via whisper.cpp with streaming transcription API
- **WhisperWorker:** Persistent isolate for speech recognition (model loads once)
- **WhisperSession:** High-level streaming API with 3-second chunk processing at 16kHz
- **iOS Audio Capture:** AVAudioEngine + AVAudioConverter for native 48kHz to 16kHz mono conversion
- **Structured Output:** Grammar-constrained generation via GBNF sampler for valid JSON output
- **Function Calling:** `sendWithTools()` for multi-round tool chains with `ToolDefinition`, `ToolCall`, `ToolResult`
- **Tool Registry:** Register tools with JSON schema validation, model selects and invokes relevant tools
- **Embeddings API:** `embed()` returns L2-normalized float vectors via `ev_embed()` C API — works with any GGUF embedding model
- **Confidence Scoring:** Per-token confidence (0.0-1.0) from softmax entropy of logits, zero overhead when disabled
- **Cloud Handoff:** `needsCloudHandoff` flag when average confidence drops below `confidenceThreshold`
- **VectorIndex:** Pure Dart HNSW vector search (via local_hnsw) with cosine similarity and JSON persistence
- **RagPipeline:** End-to-end retrieval-augmented generation — embed query, search index, inject context, generate
- **STT Demo Screen:** Live microphone transcription with pulsing recording indicator
- **Chat Tools Demo:** Toggle function calling (get_time, calculate) in chat screen

### Changed
- XCFramework rebuilt with whisper, grammar, embedding, and confidence symbols
- Podspec symbol whitelist expanded for all new `ev_*` functions
- `EvGenerationParams` struct layout fixed (grammar_str/grammar_root fields added)
- `TokenChunk` and `GenerateResponse` now include confidence fields
- Chat templates extended with Qwen3/Hermes-style tool message support
- Android builds use 16KB page alignment for Android 15+ compliance

## [1.2.0] - 2026-02-09

### Added
- **Compute Budget Contracts:** Declare p95 latency, battery drain, thermal level, and memory ceiling constraints via `EdgeVedaBudget`
- **Adaptive Budget Profiles:** `BudgetProfile.conservative` / `.balanced` / `.performance` auto-calibrate to measured device performance after warm-up
- **MeasuredBaseline:** Inspect actual device metrics (p95, drain rate, thermal, RSS) via `Scheduler.measuredBaseline`
- **Central Scheduler:** Arbitrates concurrent workloads (vision + text) with priority-based degradation every 2 seconds
- **Budget Violation Events:** `Scheduler.onBudgetViolation` stream with constraint details, mitigation status, and `observeOnly` classification
- **Two-Phase Resolution:** Latency constraints resolve at ~40s, battery constraints resolve when drain data arrives (~2min)
- **Experiment Tracking:** `analyze_trace.py` supports 6 testable hypotheses with versioned experiment runs
- **Trace Export:** Share JSONL trace files from soak test via native iOS share sheet
- **Adaptive Budget UI:** Soak test screen shows measured baseline, resolved budget, and resolution status live

### Changed
- Soak test uses `EdgeVedaBudget.adaptive(BudgetProfile.balanced)` instead of hardcoded values
- `RuntimePolicy` is now display-only; `Scheduler` is sole authority for inference gating
- PerfTrace captures `scheduler_decision`, `budget_check`, `budget_violation`, and `budget_resolved` entries

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
