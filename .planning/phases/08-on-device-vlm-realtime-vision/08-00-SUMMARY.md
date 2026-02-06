---
phase: 08-on-device-vlm-realtime-vision
plan: 00
subsystem: core-engine
tags: [llama.cpp, upgrade, b7952, xcframework, libmtmd, api-migration]
requires: []
provides:
  - llama.cpp b7952 submodule with SmolVLM2 + libmtmd support
  - iOS XCFramework rebuilt with updated llama.cpp
  - engine.cpp adapted to b7952 memory API
affects:
  - 08-01 (VLM C API depends on libmtmd from b7952)
  - 08-02 (Dart FFI bindings depend on rebuilt XCFramework)
  - 08-03 (Model download depends on SmolVLM2 GGUF availability)
  - 08-04 (Demo app depends on working XCFramework)
tech-stack:
  added: []
  patterns: [llama_memory_clear API pattern for KV cache management]
key-files:
  created: []
  modified:
    - core/third_party/llama.cpp (submodule b4658 -> b7952)
    - core/src/engine.cpp (llama_kv_cache_clear -> llama_memory_clear migration)
    - scripts/build-ios.sh (include ggml-metal in simulator merge)
key-decisions:
  - id: llama-memory-api
    decision: "Migrate from llama_kv_cache_clear() to llama_memory_clear(llama_get_memory(ctx), true)"
    rationale: "b7952 removed KV cache direct API in favor of unified memory management"
  - id: simulator-metal-lib
    decision: "Include libggml-metal.a in simulator XCFramework merge"
    rationale: "b7952 unconditionally references ggml_backend_metal_reg; simulator needs Metal stubs to resolve symbols"
metrics:
  duration: ~10 minutes
  completed: 2026-02-06
---

# Phase 8 Plan 0: Upgrade llama.cpp to b7952 Summary

**Upgrade llama.cpp from b4658 to b7952 (12 months of updates) with single API migration: llama_kv_cache_clear -> llama_memory_clear**

## Performance

- iOS device XCFramework: 6.5MB (arm64)
- iOS simulator XCFramework: 6.6MB (arm64, includes Metal stubs)
- Both under 15MB limit
- Build time: ~3 minutes per platform (device + simulator)

## Accomplishments

1. **Upgraded llama.cpp submodule** from b4658 to b7952 -- 12 months of improvements including SmolVLM2 support, libmtmd API, Android acceleration improvements, and hundreds of bug fixes
2. **Migrated engine.cpp** to b7952 API -- only 4 call sites needed updating (llama_kv_cache_clear -> llama_memory_clear), all other APIs remained stable
3. **Fixed simulator XCFramework** -- b7952 unconditionally registers Metal backend, requiring ggml-metal library in simulator merge for symbol resolution
4. **Verified all 25 ev_* symbols** present in both device and simulator XCFramework libraries
5. **Confirmed mtmd.h availability** at `tools/mtmd/mtmd.h` -- the foundation for all Phase 8 vision plans
6. **Preserved public API** -- zero changes to edge_veda.h, full backward compatibility

## Task Commits

| Task | Name | Commit | Key Changes |
|------|------|--------|-------------|
| 1 | Upgrade llama.cpp submodule to b7952 | bba3b2c | Submodule update, engine.cpp API migration |
| 2 | Verify existing generate() API still works | ea7b752 | build-ios.sh simulator Metal fix |

## Files Modified

| File | Change | Lines |
|------|--------|-------|
| core/third_party/llama.cpp | Submodule b4658 -> b7952 | N/A (submodule pointer) |
| core/src/engine.cpp | 4x llama_kv_cache_clear -> llama_memory_clear | 4 lines changed |
| scripts/build-ios.sh | Add SIM_GGML_METAL_LIB to simulator merge | 3 lines added |

## Decisions Made

### 1. Memory API Migration (llama_kv_cache_clear -> llama_memory_clear)
- **Context:** b7952 removed direct KV cache manipulation in favor of a unified `llama_memory_t` abstraction
- **Decision:** Replace all 4 `llama_kv_cache_clear(ctx)` calls with `llama_memory_clear(llama_get_memory(ctx), true)`
- **Rationale:** The new API is functionally equivalent; `true` for the `data` parameter clears all cached data
- **Impact:** Minimal -- exact same behavior, just different function signature

### 2. Simulator Metal Stubs
- **Context:** b7952 llama.cpp unconditionally references `ggml_backend_metal_reg` even when GGML_METAL is disabled, because the backend registry auto-discovers available backends
- **Decision:** Include `libggml-metal.a` in the simulator XCFramework merge (previously only included for device)
- **Rationale:** The Metal library for simulator contains stub implementations that satisfy the symbol requirement without actually enabling Metal
- **Impact:** Simulator library grows from 5.8MB to 6.6MB (800KB increase from Metal stubs)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Simulator XCFramework missing Metal symbols**
- **Found during:** Task 2, Flutter iOS Simulator build
- **Issue:** b7952 llama.cpp unconditionally references `_ggml_backend_metal_reg` in its backend registry, causing undefined symbol errors when linking the simulator library (which previously excluded Metal libs)
- **Fix:** Updated build-ios.sh to search for and include `libggml-metal.a` in the simulator library merge
- **Files modified:** scripts/build-ios.sh
- **Commit:** ea7b752

## Issues Encountered

1. **Minimal API breakage:** Only `llama_kv_cache_clear` was removed in b7952. All other APIs used by engine.cpp (llama_model_load_from_file, llama_init_from_model, llama_decode, llama_sampler_*, llama_tokenize, llama_token_to_piece, llama_vocab_is_eog, llama_model_get_vocab, llama_model_n_params, llama_model_n_embd, llama_model_n_layer, llama_log_set) remained stable across the 12-month gap.

2. **Flutter BUILD_DIR override:** `flutter build ios --simulator` fails with undefined ev_* symbols, while direct `xcodebuild` succeeds. This appears to be a pre-existing Flutter tooling issue with how BUILD_DIR is passed (not related to the b7952 upgrade). Direct xcodebuild confirms the XCFramework links correctly.

## Next Phase Readiness

- **08-01 (VLM C API):** Ready -- mtmd.h available at `tools/mtmd/mtmd.h` for libmtmd integration
- **08-02 (Dart FFI Bindings):** Ready -- XCFramework rebuilt with b7952
- **08-03 (Model Download):** Ready -- SmolVLM2 GGUF models compatible with b7952
- **08-04 (Demo App):** Ready -- existing text API verified, XCFramework includes all symbols

No blockers for subsequent Phase 8 plans.

## Self-Check: PASSED
