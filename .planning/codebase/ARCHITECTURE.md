# Architecture

## Pattern

**Single Core + Multi-Platform Bindings**

```
                    ┌─────────────────────────────────────┐
                    │           Platform SDKs             │
                    ├────────┬────────┬────────┬──────────┤
                    │ Flutter│ Swift  │ Kotlin │ React    │
                    │  FFI   │ Interop│  JNI   │ Native   │
                    └────┬───┴────┬───┴────┬───┴────┬─────┘
                         │        │        │        │
                    ┌────▼────────▼────────▼────────▼─────┐
                    │       C++ Core (edge_veda.h)        │
                    │    Unified API • Memory Guard       │
                    ├─────────────────────────────────────┤
                    │    llama.cpp / whisper.cpp / TTS    │
                    ├────────┬────────┬────────┬──────────┤
                    │ Metal  │ Vulkan │ WebGPU │   CPU    │
                    └────────┴────────┴────────┴──────────┘
                              Hardware Backends

                    ┌─────────────────────────────────────┐
                    │           Web SDK (WASM)            │
                    │    TypeScript + Web Workers         │
                    │    Compiled from C++ via Emscripten │
                    └─────────────────────────────────────┘
```

## Layers

### 1. Public SDK Layer
Each platform has a consistent high-level API:

| Platform | Entry Point | Pattern |
|----------|-------------|---------|
| Flutter | `EdgeVeda` class in `flutter/lib/edge_veda.dart` | Async/Stream |
| Swift | `EdgeVeda` actor in `swift/Sources/EdgeVeda/EdgeVeda.swift` | Swift Concurrency |
| Kotlin | `EdgeVeda` class in `kotlin/src/.../EdgeVeda.kt` | Coroutines/Flow |
| React Native | `EdgeVeda` class in `react-native/src/EdgeVeda.ts` | Promises/Events |
| Web | `EdgeVeda` class in `web/src/index.ts` | Promises/AsyncGenerator |

### 2. Native Bridge Layer
Platform-specific FFI/interop:

| Platform | Bridge | Location |
|----------|--------|----------|
| Flutter | dart:ffi | `flutter/lib/src/ffi/bindings.dart` |
| Swift | C Interop | `swift/Sources/EdgeVeda/Internal/FFIBridge.swift` |
| Kotlin | JNI | `kotlin/src/main/cpp/edge_veda_jni.cpp` |
| React Native | TurboModules | `react-native/ios/EdgeVeda.mm`, `react-native/android/.../EdgeVedaModule.kt` |
| Web | WASM Workers | `web/src/worker.ts`, `web/src/wasm-loader.ts` |

### 3. C++ Core Layer
- Location: `core/src/`, `core/include/`
- Public API: `core/include/edge_veda.h`
- Engine: `core/src/engine.cpp`
- Memory: `core/src/memory_guard.cpp`

### 4. Backend Layer
Hardware-specific acceleration:
- Metal: `core/src/backend_metal.cpp` (iOS/macOS)
- Vulkan: `core/src/backend_vulkan.cpp` (Android)
- CPU: Always available fallback

## Data Flow

### Initialization
```
App → SDK.init(config)
        → Bridge → ev_init(config)
                     → Backend detection
                     → Model loading
                     → Memory allocation
        ← ev_context handle
    ← Ready state
```

### Text Generation (Streaming)
```
App → SDK.generateStream(prompt)
        → Bridge → ev_generate_stream(ctx, prompt, params)
                     → Tokenization
                     → Inference loop
                     → Token sampling
        ← ev_stream handle

    → while SDK.hasNext()
        → Bridge → ev_stream_next(stream)
                     → Generate next token
        ← token string
        → yield to app

    → SDK.streamFree()
        → Bridge → ev_stream_free(stream)
```

## Entry Points

### C++ Core
- `ev_init()` - Create inference context
- `ev_generate()` - Single-shot generation
- `ev_generate_stream()` - Start streaming generation
- `ev_free()` - Release context

### Platform SDKs
| Platform | Init | Generate | Stream |
|----------|------|----------|--------|
| Flutter | `EdgeVeda.init()` | `generate()` | `generateStream()` |
| Swift | `EdgeVeda.initialize()` | `generate()` | `generateStream()` |
| Kotlin | `EdgeVeda.init()` | `generate()` | `generateStream()` |
| React Native | `EdgeVeda.initialize()` | `generate()` | Event-based |
| Web | `new EdgeVeda().init()` | `generate()` | `generateStream()` |

## Key Abstractions

### Configuration (`ev_config`)
Unified across all platforms:
- `model_path` - GGUF model file
- `backend` - Metal/Vulkan/CPU/Auto
- `context_size` - Token context window
- `memory_limit_bytes` - Memory cap
- `gpu_layers` - GPU offload control

### Generation Parameters (`ev_generation_params`)
Standard LLM sampling:
- `max_tokens`, `temperature`, `top_p`, `top_k`
- `repeat_penalty`, `frequency_penalty`, `presence_penalty`
- `stop_sequences`

### Memory Stats (`ev_memory_stats`)
- `current_bytes`, `peak_bytes`, `limit_bytes`
- `model_bytes`, `context_bytes`

## Error Handling

### C++ Layer
- Error codes: `ev_error_t` enum
- Error messages: `ev_error_string()`, `ev_get_last_error()`

### SDK Layer
Each platform wraps errors idiomatically:
- Flutter/Dart: Exceptions
- Swift: `EdgeVedaError` enum with associated values
- Kotlin: `EdgeVedaException` with code
- React Native: Event-based errors + Promise rejection
- Web: `Error` class with error codes
