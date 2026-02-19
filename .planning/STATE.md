# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-04)

**Core value:** Developers can add on-device LLM inference to their Flutter apps with a simple API - text in, text out, on both iOS and Android.
**Current focus:** Phase 23 Add Image Generation Capabilities. Plan 23-02 complete (XCFramework + FFI bindings).

## Current Position

Phase: 23 (Add Image Generation Capabilities)
Plan: 23-02 complete (2/4 plans done)
Status: **In Progress**
Last activity: 2026-02-19 - Completed 23-02: XCFramework rebuild + podspec + Dart FFI bindings

Progress: [###################_] ~96% (Phase 16: 6/6, Phase 17: 3/3, Phase 18: 2/3, Phase 19: 3/3, Phase 20: 2/2, Phase 21: 3/4, Phase 22: 3/3, Phase 23: 2/4 complete)

## Milestone Summary

**v1.0: iOS SDK (Complete)**
- Published to pub.dev v1.0.0
- 150/160 pana score
- iOS Metal GPU working

**v1.1: Android + Streaming (Active)**
- Phase 5: Android CPU Build (3 plans) - 05-01, 05-02 complete
- Phase 6: Streaming C++ + Dart (5 plans) - 06-01, 06-02, 06-03, 06-04 complete
- Phase 7: Android Vulkan + Demo (4 requirements) - depends on 5 and 6

**Phase 8: On-Device VLM (Complete)**
- All 5 plans done, human-verified

**Phase 9: v1.1.0 Release + App Redesign (Complete)**
- 09-01: Dark Theme Redesign - **Complete**
- 09-02: Version Bump + CHANGELOG - **Complete**
- 09-03: Automated Validation + Human Verification - **Complete**

**Phase 10: Premium App Redesign (Complete)**
- All 4 plans done, human-verified

**Phase 11: Production Runtime (Complete)**
- All 5 plans done, soak test verified on device

**Phase 12: Chat Session API (Complete)**
- 12-01: Chat Session SDK Layer - **Complete**
- 12-02: XCFramework Rebuild - **Complete** (GitHub Release skipped per user request)
- 12-03: Demo App Chat Rewrite - **Complete**
- 12-04: Validation + Human Verification - **Complete**

**Phase 13: Compute Budget Contracts (Complete)**
- 13-01: Core Budget Types and Scheduler - **Complete**
- 13-02: SDK Exports and Soak Test Integration - **Complete**
- 13-03: Experiment Tracking - **Complete**
- 13-04: DX Gap Closure - **Complete**
- 13-05: Adaptive Budget Resolution - **Complete**

**v2.0: Competitive Features (Active)**
- Phase 14: Whisper STT (Speech-to-Text) - **Complete**
  - 14-01: Whisper.cpp Submodule + CMake Integration - **Complete**
  - 14-02: C API Wrapper - **Complete**
  - 14-03: FFI Bindings + XCFramework - **Complete**
  - 14-04: WhisperWorker Isolate + WhisperSession - **Complete**
  - 14-05: Audio Capture + Model Registry + SDK Exports - **Complete**
  - 14-06: Human Verification - **Complete**
- Phase 15: Structured Output & Function Calling - **Complete**
  - 15-01: Tool Type Definitions + Schema Validation - **Complete**
  - 15-02: ChatTemplate Tool Message Support - **Complete**
  - 15-03: C API Grammar Support - **Complete**
  - 15-04: FFI Bindings + XCFramework - **Complete**
  - 15-05: Dart StructuredOutput API - **Complete**
  - 15-06: SDK Exports + Chat Demo + Human Verification - **Complete**
  - 15-07: Tool Calling Gap Closure (Qwen3 Model Switch) - **Complete**
- Phase 16: Embeddings, Confidence & RAG - **Complete**
  - 16-01: Build Hardening + Type Declarations - **Complete**
  - 16-02: Embeddings C API - **Complete**
  - 16-03: Confidence Scoring - **Complete**
  - 16-04: VectorIndex (HNSW) - **Complete**
  - 16-05: RAG Pipeline - **Complete**
  - 16-06: Final Validation + Human Verification - **Complete**
- Phase 17: RAG Demo Apps - **Complete**
  - 17-01: Embedding Model + Two-Model RAG Pipeline - **Complete**
  - 17-02: RAG Demo Screen - **Complete**
  - 17-03: Human Verification - **Complete** (UAT 3/3 passed)
- Phase 18: Tool Calling iOS Demo - **Complete**
  - 18-01: Native Data Providers + Qwen3 Model - **Complete**
  - 18-02: Dart Insight Engine + Detective Screen - **Complete**
  - 18-03: Human Verification + Hardening - **Complete** (LLM self-checks, GBNF grammar, verified on device)
- Phase 19: Memory Optimization - **Complete**
  - 19-01: Route getMemoryStats Through StreamingWorker - **Complete**
  - 19-02: KV Cache Quantization + Flash Attention - **Complete**
  - 19-03: Validation + Bug Fixes - **Complete** (batched prompt eval + streaming persistence fix)
- Phase 20: Smart Model Advisor - **Complete**
  - 20-01: ModelAdvisor Core SDK - **Complete**
  - 20-02: Settings Screen Integration + Human Verification - **Complete**

## Phase Dependencies

```
Phase 5 (Android CPU) ----+
                          +--> Phase 7 (Vulkan + Demo)
Phase 6 (Streaming)  ----+

Phase 8 (VLM) - COMPLETE
Phase 9 (Release) - COMPLETE
Phase 10 (Premium Redesign) - COMPLETE
Phase 11 (Production Runtime) - COMPLETE
Phase 12 (Chat Session API) - COMPLETE
Phase 13 (Compute Budget Contracts) - COMPLETE
  13-01 (Budget Types + Scheduler) DONE
  13-02 (SDK Exports + Soak Test Integration) DONE
  13-03 (Experiment Tracking) DONE
  13-04 (DX Gap Closure) DONE
  13-05 (Adaptive Budget Resolution) DONE
  Depends on: Phase 11 (RuntimePolicy, TelemetryService, PerfTrace)

Phase 14 (Whisper STT) - IN PROGRESS
  14-01 (Submodule + CMake Integration) DONE
  14-02 (C API Wrapper) DONE
  14-03 (FFI Bindings + XCFramework) DONE
  14-04 (WhisperWorker Isolate + WhisperSession) DONE
  14-05 (Audio Capture + Model Registry + SDK Exports) DONE
  Depends on: Phase 13

Phase 15 (Structured Output & Function Calling) - COMPLETE
  15-01 (Tool Type Definitions + Schema Validation) DONE
  15-02 (ChatTemplate Tool Message Support) DONE
  15-03 (C API Grammar Support) DONE
  15-04 (FFI Bindings + GenerateOptions Grammar) DONE
  15-05 (Dart StructuredOutput API) DONE
  15-06 (SDK Exports + Chat Demo) DONE
  15-07 (Tool Calling Gap Closure) DONE
  Depends on: Phase 12 (ChatSession), Phase 13 (Scheduler)

Phase 16 (Embeddings, Confidence & RAG) - COMPLETE
  16-01 (Build Hardening + Type Declarations) DONE
  16-02 (Embeddings C API) DONE
  16-03 (Confidence Scoring) DONE
  16-04 (VectorIndex HNSW) DONE
  16-05 (RAG Pipeline) DONE
  16-06 (Final Validation) DONE
  Depends on: Phase 13 (Scheduler)

Phase 17 (RAG Demo Apps) - COMPLETE
  17-01 (Embedding Model + Two-Model RAG Pipeline) DONE
  17-02 (RAG Demo Screen) DONE
  17-03 (Human Verification) DONE
  Depends on: Phase 16 (RagPipeline, VectorIndex, embed())

Phase 18 (Tool Calling iOS Demo) - IN PROGRESS
  18-01 (Native Data Providers + Qwen3 Model) DONE
  18-02 (Dart Insight Engine + Detective Screen) DONE
  18-03 (Human Verification) PENDING
  Depends on: Phase 15 (ToolDefinition, ToolRegistry, sendWithTools)

Phase 19 (Memory Optimization) - COMPLETE
  19-01 (Route getMemoryStats Through StreamingWorker) DONE
  19-02 (KV Cache Quantization + Flash Attention) DONE
  19-03 (Validation + Bug Fixes) DONE
  Depends on: Phase 6 (StreamingWorker)

Phase 20 (Smart Model Advisor) - COMPLETE
  20-01 (ModelAdvisor Core SDK) DONE
  20-02 (Settings Screen Integration) DONE
  Depends on: Phase 19 (calibrated memory data)

Phase 21 (Standalone Sample Apps) - IN PROGRESS
  21-01 (Document Q&A) DONE
  21-02 (Health Advisor) DONE
  21-03 (Voice Journal) DONE
  Depends on: Phase 16 (RagPipeline, VectorIndex, embed(), ConfidenceInfo)

Phase 22 (Intent Engine Demo) - COMPLETE
  22-01 (Service Layer: Models, Intent Service, HA Connector) DONE
  22-02 (Dashboard UI) DONE
  22-03 (Validation + Human Verification) DONE
  Depends on: Phase 15 (ToolDefinition, ToolRegistry, sendWithTools, ChatTemplateFormat.qwen3)

Phase 23 (Add Image Generation Capabilities) - IN PROGRESS
  23-01 (Submodule + C API) DONE
  23-02 (FFI Bindings + XCFramework) DONE
  23-03 (ImageWorker Isolate + Dart API) PENDING
  23-04 (Demo Screen + Human Verification) PENDING
  Depends on: Phase 14 (submodule integration pattern)
```

## Remaining Work

| Phase | Plan | Name | Status |
|-------|------|------|--------|
| 5 | 05-03 | APK Build & Verification | Pending (no Android device) |
| 6 | 06-05 | Integration Tests | Pending (no Android device) |
| 7 | -- | Android Vulkan + Demo | Not yet planned |

## Accumulated Context

### Decisions

Phase 23 Plan 2 decisions:
- XCFramework grows from ~8MB to ~31MB per slice with sd.cpp (binary size limit raised to 40MB)
- All 8 ev_image_* FFI bindings are eager (XCFramework rebuilt with verified symbols)
- Progress callback uses NativeFunction pointer type for NativeCallable in ImageWorker isolate
- EvImageGenParams struct maps C enums (sampler, schedule) as Int32 fields

Phase 23 Plan 1 decisions:
- sd.cpp CMake target is 'stable-diffusion' (not 'sd'), linked with target_link_libraries PRIVATE
- Shared ggml via if(NOT TARGET ggml) check in sd.cpp CMakeLists (no SD_USE_SYSTEM_GGML needed)
- Thread-local g_active_image_ctx for progress callback bridge (sd_set_progress_callback is global, not per-context)
- vae_decode_only=true + free_params_immediately=true for text-to-image only (saves memory)
- Pixel data copied from sd.cpp into malloc'd buffer (clean ownership -- caller frees via ev_image_free_result)
- SD_METAL=ON on Apple platforms; flash_attn + diffusion_flash_attn enabled when GPU active
- iOS simulator forces CPU-only via #if TARGET_OS_SIMULATOR guard (same as whisper_engine.cpp)

Phase 22 Plan 3 decisions:
- README follows established sample app pattern (SDK Features, Quick Start, Architecture table, Adapting for Your App)
- Human verification approved: all 9 phase success criteria confirmed on real iPhone device

Phase 22 Plan 2 decisions:
- Command interface pattern (single assistant response area, not full chat history) -- home control, not chat app
- Suggestion chips hide after first command to maximize dashboard space
- New Conversation resets chat context but preserves device states
- Action log in collapsible panel (max 200px) between dashboard and chat
- Hide Flutter LockState via import directive to resolve naming collision with device model

Phase 22 Plan 1 decisions:
- ChatSession recreated after each intent to refresh system prompt with updated home status
- Device IDs listed explicitly in system prompt for 0.6B model (small models cannot infer IDs)
- 6 tools (5 device control + 1 status query) with maxTools=6 in ToolRegistry
- HomeAssistantConnector logs curl commands but makes no HTTP calls (pure stub)
- LocalActionRouter applies actions directly to HomeState (default backend)
- IntentService wraps all SDK interaction -- app never imports edge_veda directly

Phase 21 Plan 1 decisions:
- RagService wraps all SDK interaction -- app never imports edge_veda directly
- Dual-model approach: MiniLM L6 v2 (384-dim embeddings) + Llama 3.2 1B (generation)
- Chunk-by-chunk embedding loop (not embedBatch) for progress callback support
- Messages stored as simple List<Map<String, String>> with role/content keys
- Typing indicator uses dart:math sin() for smooth pulsing animation

Phase 21 Plan 3 decisions:
- whisper-base-en model (148MB, better accuracy) chosen over whisper-tiny-en for journal quality
- WhisperSession.stop() not called after stopRecording -- keeps model loaded for reuse across entries
- ChatSession.reset() called after each summarization to prevent context accumulation across entries
- VectorIndex removeEntry is a no-op (no public delete API); stale entries filtered by valid DB IDs at query time
- Root .gitignore models/ pattern catches lib/models/ -- used git add -f for journal_entry.dart

Phase 21 Plan 2 decisions:
- ConfidenceResult is a separate data class in the sample app (not part of SDK) to keep it self-contained
- Three-phase UI state machine: setup (model download) -> ready (document picker) -> chat (Q&A with confidence)
- Green accent uses Colors.green.shade400 (non-const) with shade700 for user bubbles
- HandoffBanner is dismissible with local state (not persisted across sessions)
- ChatMsg data class in message_bubble.dart carries confidence metadata per message

Phase 20 Plan 2 decisions:
- Use-case chips limited to 5 (Chat, Reasoning, Vision, Speech, Fast) -- toolCalling and embedding excluded from Settings UI
- Existing _DeviceInfo class preserved for Device Status rows; tier badge uses SDK DeviceProfile.detect()
- All models shown in recommendations including non-fitting (grayed out with "Too Large" badge rather than hidden)

Phase 20 Plan 1 decisions:
- ModelInfo 4 new fields are all optional/nullable (backward compatible with existing code)
- Device DB is inline const Map with 27 iPhone entries (iPhone 12 through iPhone 17 series, no external dependency)
- Simulator fallback uses hw.memsize RAM-based tier detection (hw.machine returns Mac model on simulator)
- Non-LLM models (whisper, minilm) use simpler formula: fileSize + 100MB overhead
- Safety multiplier 1.3x on calibrated formula produces ~460MB for Llama 1B (middle of 400-550MB observed range)
- All models returned in recommendations including fits:false (UI decides rendering)

Phase 19 Plan 2 decisions:
- C-side defaults F16 (kv_cache_type_k=1, kv_cache_type_v=1), Dart-side overrides to Q8_0 (8) for mobile memory optimization
- Flash attention defaults to AUTO (-1) on both C and Dart sides (Metal enables automatically)
- Three new int fields placed between seed and reserved in ev_config for struct compatibility
- XCFramework binary is gitignored -- rebuilt locally with new struct layout

Phase 19 Plan 1 decisions:
- Route getMemoryStats() through existing StreamingWorker instead of loading a second model via Isolate.run()
- Return zero-valued MemoryStats when no worker is active (no crash, no model load)
- 5-second timeout on getMemoryStats() worker response (same Completer+subscription pattern)
- Removed unused MemoryException import from edge_veda_impl.dart after Isolate.run code removed

Phase 18 Plan 2 decisions:
- LLM is stylist/narrator only -- InsightEngine computes all deductions deterministically in pure Dart
- Two-phase LLM: Phase 1 sendWithTools for data gathering, Phase 2 plain send for noir narration
- Tool calling fallback: if sendWithTools fails (ToolCallParseException), direct MethodChannel fetch
- Narration JSON fallback: if LLM JSON parse fails, construct DetectiveReport from raw InsightCandidates
- Demo Mode synthetic data designed to trigger multiple insight rules (weekend clustering, peak hours, midnight Friday photos)
- Separate EdgeVeda instance with contextLength 4096 for tool prompts + narration
- 5-minute TTL cache on photo/calendar data to avoid redundant MethodChannel calls
- main.dart import not needed (settings_screen.dart handles detective_screen.dart navigation directly)

Phase 18 Plan 1 decisions:
- Photos and EventKit frameworks added to podspec (not just imported in .m)
- Sequential permission requests (photos then calendar) using dispatch_semaphore to avoid overwhelming user
- Location grid cells rounded to 2 decimal places (~1km resolution) for privacy-preserving clustering
- Event titles truncated to 50 chars for privacy
- iOS 17+ requestFullAccessToEventsWithCompletion with fallback to requestAccessToEntityType for older iOS
- iOS 14+ PHAccessLevelReadWrite with fallback to requestAuthorization for older iOS
- Qwen3-0.6B Q4_K_M from Mungert HuggingFace (~524 MB), added to getAllModels()
- Photo/calendar data returned as lightly processed summaries (histograms, grid cells, samples) not raw rows

Phase 17 Plan 2 decisions:
- RAG messages stored in separate _ragMessages list (not ChatSession) since RAG bypasses session turn tracking
- Embedder kept alive after indexing for query-time embedding (must match indexing model dimensions)
- Text chunking at ~500 chars with 50-char overlap, paragraph/sentence boundary detection
- Indexing overlay uses Stack + Container with semi-transparent black background
- Document cleanup inlined in _resetChat (no snackbar) vs _removeDocument (with snackbar)

Phase 17 Plan 1 decisions:
- file_picker constrained to ^7.0.2 (not ^8.0.0) due to ffi <2.1.0 project constraint (win32 transitive dep)
- RagPipeline backward-compatible: original constructor sets both _embedder and _generator to same instance
- Embedding model all-MiniLM-L6-v2 at 46MB F16, 384 dimensions from Mungert/all-MiniLM-L6-v2-GGUF

Phase 15 Plan 7 decisions:
- Dispose and reinit EdgeVeda on model switch (only one model at a time to avoid ~1GB+ memory overhead)
- get_time tool changed from timezone enum to free-form location parameter (Qwen3-0.6B always picked UTC from enum)
- Init always uses Llama 3.2 with llama3Instruct template; tools toggle handles Qwen3 switch independently
- _changePreset() respects _toolsEnabled to maintain correct template/tools after persona change

Phase 15 Plan 6 decisions:
- Tool exports added to barrel file after budget section (ToolDefinition, ToolCall, ToolResult, ToolPriority, ToolCallParseException, ToolRegistry, ToolTemplate, SchemaValidator, SchemaValidationResult, GbnfBuilder)
- Parallel agent (14-05) committed tool exports alongside whisper exports -- no conflict, both coexist
- Tools toggle creates new ChatSession with ChatTemplateFormat.qwen3 (supports Hermes-style tool calls)
- Tool calling uses sendWithTools (non-streaming) while normal chat uses sendStream (streaming)
- Demo tools: get_time (returns UTC ISO8601 timestamp) and calculate (stub -- demo only)
- Tool messages rendered with monospace JSON, distinct icons/colors (wrench for calls, checkmark for results)

Phase 15 Plan 5 decisions:
- Single tool call per round in sendWithTools (first parsed call processed, loop for multi-round chains)
- maxToolRounds=3 default to prevent infinite tool call chains
- sendStructured reuses send() with grammar options (no separate inference path)
- Tool call/result messages stored as JSON-encoded content in ChatMessage for template-agnostic storage
- Error rollback only removes user message; toolCall/toolResult messages remain for debugging
- Local variable pattern for null promotion of ToolRegistry? field (Dart field promotion not available)

Phase 14 Plan 5 decisions:
- WorkloadId.stt already present from 14-04 -- no changes needed to budget.dart
- Whisper model extension determined by modelId prefix (startsWith whisper-) rather than format field for backward compat
- 300ms buffer size (4800 samples at 16kHz) for AVAudioEngine tap balances latency vs UI jank
- Microphone permission uses existing telemetry MethodChannel (no new channel needed)
- Float32List via FlutterStandardTypedData.typedDataWithFloat32 for zero-copy PCM delivery
- EVAudioCaptureHandler follows EVThermalStreamHandler pattern exactly

Phase 14 Plan 4 decisions:
- WorkloadId.stt added to budget.dart enum (needed for WhisperSession compilation, was planned for 14-05)
- STT workload registered with WorkloadPriority.low (vision/text more important than background transcription)
- 3-second audio chunks (48000 samples at 16kHz) for balanced latency/quality
- QoS gating checks maxFps == 0 for paused state (same pattern as VisionWorker)
- Audio buffer uses List<double> for accumulation, converts to Float32List for FFI call

Phase 16 Plan 1 decisions:
- confidence_threshold is float (not double) to match C struct alignment and minimize padding
- Lazy FFI binding pattern used for ev_embed, ev_free_embeddings, ev_stream_get_token_info (XCFramework not rebuilt until 16-03)
- ev_stream_token_info.confidence defaults to -1.0 when not computed (sentinel value distinct from valid 0.0-1.0 range)
- 16KB page alignment uses both max-page-size and common-page-size linker flags for Android 15+

Phase 16 Plan 3 decisions:
- XCFramework binary size unchanged at 8.1MB (embedding/confidence code is minimal addition)
- Swift package header not overwritten (legacy API, different from ev_* naming convention)
- Single commit for both tasks since Task 1 produced no git-tracked files (XCFramework is gitignored)

Phase 16 Plan 2 decisions:
- Separate embedding context per ev_embed() call for thread safety and correct pooling mode
- MEAN pooling type with non-causal attention for bidirectional encoding
- Confidence computed from Shannon entropy of softmax distribution, normalized and inverted
- Handoff threshold requires >= 3 tokens before triggering to avoid false positives
- Both tasks in single commit since all changes in engine.cpp with shared cmath dependency

Phase 16 Plan 5 decisions:
- confidenceThreshold wired through all 5 EvGenerationParams population sites for consistency (default 0.0 = disabled)
- embed() follows Isolate.run() + per-request context pattern (same as generate()) for thread safety
- RagPipeline uses string-keyed metadata with 'text' field for document retrieval
- queryStream() uses async* with yield* delegation to generateStream for zero-copy streaming

Phase 16 Plan 4 decisions:
- Used local_hnsw ^1.0.0 (pure Dart HNSW) over flat brute-force index for O(log n) search
- Cosine metric (LocalHnswMetric.cosine) as default for L2-normalized embeddings
- Adapted plan API to actual local_hnsw interface: dim param, LocalHnswItem, encodeItem/decodeItem callbacks
- Duplicate ID handling: delete-then-re-add to prevent ghost entries in HNSW graph

Phase 14 Plan 3 + Phase 15 Plan 4 decisions:
- Eager binding for whisper FFI functions (XCFramework confirmed to contain all symbols)
- Grammar fields use calloc nullptr default at all inline population sites
- NativeParamsScope owns grammar string lifetime (alloc in constructor, free in free())
- AVFoundation framework added to podspec for whisper audio processing pipeline

Phase 14 Plan 2 decisions:
- Greedy sampling strategy (WHISPER_SAMPLING_GREEDY) for whisper_full -- simplest and fastest for real-time STT
- Segment text owned by context vectors (segment_texts owns strings, segments holds pointers) -- avoids heap allocation per segment
- ev_whisper_free_result zeros result struct only (segments owned by context, not result)
- suppress_blank and suppress_nst enabled for cleaner output
- Default language "en" when NULL

Phase 14 Plan 1 decisions:
- whisper.cpp v1.8.3 chosen as submodule (latest stable, WHISPER_USE_SYSTEM_GGML support)
- Target detection (`if (NOT TARGET ggml)`) is primary ggml sharing mechanism, not find_package
- CoreML disabled (WHISPER_COREML=OFF) to avoid .mlmodelc size overhead; Metal GPU via ggml sufficient
- BUILD_SHARED_LIBS=OFF for static library XCFramework integration
- whisper.cpp v1.8.3 ggml API fully compatible with llama.cpp b7952 ggml 0.9.5
- XCFramework binary size increased ~500KB (7.6MB to 8.1MB) with whisper.cpp (shared ggml, not duplicated)

Phase 15 Plan 3 decisions:
- Grammar sampler placed before dist sampler in chain (constrains valid tokens, then dist selects from constrained set)
- Null-check + empty-string check on grammar_str guards against both NULL and empty string inputs
- Default grammar_root to "root" when NULL or empty (standard GBNF convention)
- Vocab nullptr guard in create_sampler for defensive robustness
- Borrowed pointer pattern for grammar_str/grammar_root in ev_stream_impl (no copy, caller owns lifetime)

Phase 15 Plan 1 decisions:
- ToolDefinition validates in constructor (fail-fast) rather than lazy validation
- ToolCall ID uses DateTime.microsecondsSinceEpoch.toRadixString(36) for compact unique IDs without UUID dependency
- ToolResult uses private constructor with success/failure factories for type safety
- ToolCallParseException extends EdgeVedaException (consistent exception hierarchy)
- SchemaValidator uses static methods (no state, utility class pattern)
- ToolRegistry stores List.unmodifiable for immutable tool collections

Phase 13 Plan 5 decisions:
- Non-redirecting factory for EdgeVedaBudget.adaptive() (redirecting would expose _AdaptiveBudget across library boundaries)
- Public adaptiveProfile getter for cross-library type introspection instead of is-check on private type
- Two resolution flags (_latencyResolved, _batteryResolved) to enable battery constraint addition after initial latency-only resolution
- Memory ceiling always null in adaptive resolution (observe-only, QoS knobs cannot reduce model footprint)
- Telemetry polling moved before resolved budget null check in _enforce() to accumulate battery samples during warm-up

Phase 13 Plan 4 decisions:
- observeOnly defaults to false in BudgetViolation constructor for backward compatibility
- Only actionable violations update the "Last Violation" detail text (observe-only counted silently)
- Observe-only counter rendered in textTertiary color to visually de-emphasize non-actionable violations
- Export Trace button only enabled when test is stopped (avoids sharing partial trace files)
- validate() threshold raised from 400MB to 2000MB to reflect real VLM memory requirements

Phase 13 Plan 2 decisions:
- Scheduler is sole authority for inference gating; RuntimePolicy camera pause/resume removed from _pollTelemetry (display only)
- Camera stream stays always-on; paused workload skips inference via maxFps==0 check
- Budget defaults for soak test: p95=3s, battery=5%/10min, thermal=2, memory=2.5GB

Phase 13 Plan 1 decisions:
- Scheduler manages per-workload QoSLevel independently, uses RuntimePolicy.knobsForLevel() for mapping only
- Single degradation per enforcement cycle (2s) to avoid over-correcting
- Restoration prioritizes highest-priority workloads first (reverse of degradation)
- BudgetViolation events only emitted when mitigation fails (all workloads already at max degradation)

Phase 12 Plan 4 decisions:
- No code changes needed -- all 10 automated checks passed on first run
- Human verification confirmed all features working on simulator

Phase 12 Plan 3 decisions:
- Persona picker shown only on fresh sessions (0 messages) to avoid mid-conversation persona changes
- Streaming text displayed as local _streamingText buffer appended to session messages
- Benchmark kept using direct _edgeVeda.generate() (raw inference, not conversation)
- Summary messages rendered with [Context summary] prefix in MessageBubble

Phase 12 Plan 2 decisions:
- GitHub Release upload skipped per user request (can be done later)
- All FFI bindings now eager in _initBindings() (no more lazy workarounds)
- VisionWorker null-check for timings binding removed (symbol guaranteed in XCFramework)

Phase 12 Plan 1 decisions:
- System prompt is immutable after ChatSession creation (set via constructor or preset)
- Llama 3 Instruct is default chat template format (primary model)
- Context overflow triggers summarization at 70% of available tokens
- Summary messages use dedicated ChatRole.summary, rendered as system messages with context prefix
- Summarization fallback: truncate oldest messages if model summarization fails
- Token estimation: ~4 chars/token heuristic (exact tokenization deferred)

Phase 9 Plan 3 decisions:
- ffi constrained to >=2.0.0 <2.1.0 to avoid objective_c simulator crash
- ev_vision_get_last_timings now exported in podspec and eagerly bound (supersedes lazy workaround from 09-03)

(Prior decisions preserved in phase SUMMARY.md files)

### Pending Todos

Carried from v1.0:
- Configure PUB_TOKEN secret in GitHub for automated publishing (optional)
- Create GitHub Release with XCFramework when ready (improves user setup)

v1.1:
- Verify Android NDK r27c installed in dev environment
- Test Vulkan capability on target devices (Pixel 6a, Galaxy A54)

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 1 | Fix balanced BudgetProfile thermal target from 2 (Serious) to 1 (Fair) | 2026-02-09 | 0faf4db | [1-fix-balanced-budgetprofile-thermal-targe](./quick/1-fix-balanced-budgetprofile-thermal-targe/) |
| 2 | Phase 18 Tool Calling iOS Demo hardening (Task 1: LLM self-checks) | 2026-02-13 | 5494ec4 | [2-human-verification-for-phase-18-tool-cal](./quick/2-human-verification-for-phase-18-tool-cal/) |
| 3 | Phone Detective noir fallback + GBNF grammar-constrained narration | 2026-02-15 | ce3c482, c276deb | [3-make-phone-detective-demo-more-exciting-](./quick/3-make-phone-detective-demo-more-exciting-/) |
| 4 | ModelAdvisor: canRun, checkStorageAvailability, validateMemoryAfterLoad | 2026-02-15 | e9f3e0c, 12cf91e | [4-modeladvisor-storage-check-real-time-mem](./quick/4-modeladvisor-storage-check-real-time-mem/) |
| 5 | DX quick wins: real READMEs, ffi comments, magic number docs, download UX | 2026-02-15 | d12d61e, d3b9984, dc50d4c | [5-fix-dx-quick-wins-readmes-ffi-comments-m](./quick/5-fix-dx-quick-wins-readmes-ffi-comments-m/) |

### Blockers/Concerns

- **Phase 5 (05-03), Phase 6 (06-05), Phase 7:** Blocked -- no Android SDK/NDK installed, no Android device available. Deferred until hardware available.

**Environment Notes:**
- CMake installed (4.2.3 via Homebrew)
- Flutter SDK available
- Xcode Command Line Tools only (users build XCFramework locally)
- Android NDK not yet verified in dev environment
- llama.cpp now at b7952 (upgraded from b4658)
- ffi constrained to <2.1.0 (objective_c native assets crash on simulator)

## Session Continuity

Last session: 2026-02-19
Stopped at: Completed 23-02-PLAN.md (XCFramework rebuild + FFI bindings + podspec)
Resume file: .planning/phases/23-add-image-generation-capabilities/23-03-PLAN.md

---
### Roadmap Evolution
- Phase 13 added: Compute Budget Contracts -- declarative runtime guarantees enforced by central scheduler across concurrent workloads
- Phase 14 added: Whisper STT (Speech-to-Text) -- whisper.cpp integration, streaming transcription, WhisperWorker, battery-aware STT
- Phase 15 added: Structured Output & Function Calling -- tool/function calling for Qwen3/Gemma3, JSON schema validation, budget-aware tool degradation
- Phase 17 added: RAG Demo Apps -- example apps showcasing on-device document Q&A and knowledge base search
- Phase 18 added: Tool Calling iOS Demo -- demo app showcasing function/tool calling capabilities on iOS
- Phase 19 added: Memory Optimization -- fix getMemoryStats() to query existing StreamingWorker (eliminates ~600MB spike), enable KV cache Q8_0 quantization with flash attention (halves KV cache from ~64MB to ~32MB)
- Phase 20 added: Smart Model Advisor -- device-aware model recommendations with 4D scoring (fit, quality, speed, context), MemoryEstimator with calibrated bytes-per-parameter formulas, ModelAdvisor with use-case weighted scoring, optimal EdgeVedaConfig generation. Inspired by llm-checker.
- Phase 21 added: Standalone Sample Apps -- 3 clone-and-run Flutter apps (Document Q&A, Health Advisor + RAG, Voice Journal with STT) for developer adoption
- Phase 22 added: On-Device Intent Engine Demo -- Virtual smart home app with LLM function calling, animated device dashboard, natural language home control, Home Assistant connector architecture
- Phase 23 added: Add image generation capabilities

*Phase 20 (Smart Model Advisor) COMPLETE: DeviceProfile with 27-entry iPhone DB, MemoryEstimator calibrated to real-world 400-550MB data, ModelAdvisor 4D scoring (fit/quality/speed/context) with use-case weighted recommendations. Settings screen shows tier badge + Recommended Models section with use-case selector chips and scored model cards. Human verified on real iPhone. Android work (Phases 5, 6, 7) deferred.*
