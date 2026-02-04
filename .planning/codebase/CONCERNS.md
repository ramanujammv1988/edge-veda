# Technical Concerns

## Tech Debt

### Critical - Blocking Inference

| Issue | Location | Impact |
|-------|----------|--------|
| llama.cpp not integrated | `core/CMakeLists.txt:88-110` | No LLM inference works |
| TODO: Add llama.cpp as submodule | `core/third_party/llama.cpp` missing | SDK is non-functional |
| Backend sources missing | `backend_metal.cpp`, `backend_vulkan.cpp` | GPU acceleration unavailable |

### High - Architecture Issues

| Issue | Location | Impact |
|-------|----------|--------|
| Zero test coverage | All platforms | No regression protection |
| Stub implementations | Engine functions return placeholders | Need full implementation |
| WASM init incomplete | `web/src/wasm-loader.ts` | Web platform broken |
| Worker code placeholder | `web/src/index.ts:313-321` | Web inference non-functional |

### Medium - Implementation Gaps

| Issue | Location | Impact |
|-------|----------|--------|
| Model manager stub | `flutter/lib/src/model_manager.dart` | No model downloading |
| FFI bindings incomplete | `flutter/lib/src/ffi/bindings.dart` | Flutter SDK broken |
| JNI bridge stub | `kotlin/src/main/cpp/edge_veda_jni.cpp` | Kotlin SDK broken |
| Swift FFI bridge stub | `swift/Sources/.../FFIBridge.swift` | Swift SDK broken |

## Known Bugs

### Race Conditions (Potential)
| Issue | Location | Mitigation |
|-------|----------|------------|
| Concurrent generate calls | All SDKs | No mutex/lock protection in stubs |
| Worker message handling | `web/src/index.ts:248-297` | Map lookup may race |
| Stream state | Streaming generators | No cancellation token propagation |

### Configuration Issues
| Issue | Location | Impact |
|-------|----------|--------|
| Invalid config not validated | C++ `ev_init()` | Crashes on bad input |
| Memory limit = 0 means unlimited | Documentation unclear | Unexpected behavior |

## Security Concerns

### Input Validation
| Risk | Location | Severity |
|------|----------|----------|
| Prompt injection | All generate functions | Medium - LLM behavior |
| Path traversal | Model path loading | High - file system access |
| Buffer overflow | C++ string handling | High - memory corruption |

### Data Handling
| Risk | Location | Severity |
|------|----------|----------|
| Model cache unencrypted | IndexedDB (Web), filesystem (mobile) | Low - local only |
| No credential handling | N/A - offline SDK | None |

### Memory Safety
| Risk | Location | Severity |
|------|----------|----------|
| Use-after-free | `ev_stream_*` functions | High - crashes |
| Memory leaks | `ev_free_string()` not called | Medium - resource exhaustion |
| Double-free | Stream cleanup | High - crashes |

## Performance Bottlenecks

### Memory
| Issue | Impact | Mitigation |
|-------|--------|------------|
| No streaming tokenization | Full prompt in memory | Chunk processing needed |
| Model kept in memory | 1-7GB per model | Auto-unload implemented but untested |
| Context accumulation | Memory grows with conversation | `ev_reset()` available |

### Inference Speed
| Issue | Impact | Mitigation |
|-------|--------|------------|
| GPU offload incomplete | CPU-only speed | Backend implementation needed |
| No batch processing | Single request at a time | Future optimization |
| No KV cache persistence | Repeated prompt processing | Could add session resume |

### Platform-Specific
| Platform | Issue | Impact |
|----------|-------|--------|
| Web | Main thread blocking | Worker isolation helps |
| iOS | Background execution limits | May terminate mid-inference |
| Android | Thermal throttling | Performance degrades over time |

## Fragile Areas

### High Risk Code
| Area | Location | Why Fragile |
|------|----------|-------------|
| FFI boundary | All bridges | Type mismatches crash |
| Memory guard | `core/src/memory_guard.cpp` | Complex state machine |
| Stream state machine | Streaming generators | Many edge cases |

### Integration Points
| Integration | Risk | Notes |
|-------------|------|-------|
| llama.cpp updates | High | API may change |
| Platform SDK updates | Medium | Deprecation possible |
| Hardware APIs | Medium | Metal/Vulkan version requirements |

## Scaling Limits

| Limit | Value | Impact |
|-------|-------|--------|
| Model size | Device RAM | Larger models won't load |
| Context window | 2048-8192 typical | Long conversations truncated |
| Concurrent sessions | 1 per SDK instance | No parallelism |

## Dependencies at Risk

| Dependency | Risk | Notes |
|------------|------|-------|
| llama.cpp | Active development | API stability varies |
| react-native-builder-bob | Build tool | Must track RN versions |
| Emscripten | WASM compilation | Complex setup |

## Missing Features

### Documented but Not Implemented
| Feature | Location | Status |
|---------|----------|--------|
| whisper.cpp (STT) | Mentioned in docs | Not started |
| TTS (Kokoro-82M) | Mentioned in docs | Not started |
| Model quantization | PRD mentions | Not implemented |

### Expected but Missing
| Feature | Impact |
|---------|--------|
| Model download progress | UX during initial load |
| Inference cancellation | User can't abort |
| Session persistence | Lost on app restart |

## Test Coverage Gaps

| Area | Coverage | Risk |
|------|----------|------|
| C++ core | 0% | Critical |
| FFI bridges | 0% | Critical |
| Platform SDKs | 0% | High |
| Error paths | 0% | High |
| Edge cases | 0% | Medium |

## Build/Deployment Concerns

| Issue | Impact |
|-------|--------|
| No published packages | Can't install from npm/pub/SPM |
| No binary distribution | Must build from source |
| Large binary size | llama.cpp adds significant weight |
| Cross-compile complexity | Requires multiple toolchains |

## Immediate Action Items

1. **Add llama.cpp submodule** - Required for any inference
2. **Implement C++ engine functions** - Currently stubs
3. **Add basic tests** - At minimum, initialization tests
4. **Complete one platform bridge** - Prove architecture works
5. **Document build requirements** - Help contributors
