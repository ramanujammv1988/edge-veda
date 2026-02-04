# External Integrations

## APIs & External Services

**No third-party API integrations detected.**

This is an offline-first, on-device inference SDK. All inference runs locally without network calls.

## Data Storage

### Web Platform
- **IndexedDB** - Model caching in browser
  - Location: `web/src/model-cache.ts`
  - Functions: `getCachedModel()`, `listCachedModels()`, `deleteCachedModel()`, `clearCache()`
  - Cache name: configurable via `EdgeVedaConfig.cacheName` (default: `edgeveda-models`)

### Mobile Platforms
- **Local Filesystem** - Device-local model storage
  - Flutter: `path_provider` for platform-specific paths
  - iOS/Android: App sandbox directories
  - Models stored in GGUF format

### Model Downloads
- **HTTP Fetch API** (Web) - Standard fetch for model downloads
- **http package** (Flutter) - Model download support
- No CDN or cloud storage configured

## Authentication & Identity

**Not applicable** - Offline-first, on-device inference requires no authentication.

## Hardware Interfaces

### GPU Acceleration
| Platform | Interface | Status |
|----------|-----------|--------|
| iOS/macOS | Metal Framework | Configured in CMake |
| Android | Vulkan SDK | Configured in CMake |
| Web | WebGPU API | Detection in `wasm-loader.ts` |
| All | CPU Fallback | Always available |

### Native Bridges
| SDK | Bridge Type | Location |
|-----|-------------|----------|
| Flutter | FFI (dart:ffi) | `flutter/lib/src/ffi/bindings.dart` |
| Swift | C Interop | `swift/Sources/CEdgeVeda/` |
| Kotlin | JNI | `kotlin/src/main/cpp/edge_veda_jni.cpp` |
| React Native | TurboModules/JSI | `react-native/src/NativeEdgeVeda.ts` |
| Web | WASM + Workers | `web/src/worker.ts` |

## Monitoring & Observability

### Logging
- Console-based logging across all platforms
- No external error tracking service configured
- Verbose mode toggle via `ev_set_verbose()`

### Memory Monitoring
- Built-in memory stats: `ev_get_memory_usage()`
- Memory pressure callbacks: `ev_set_memory_pressure_callback()`
- Auto-unload on memory pressure (configurable)

## CI/CD

### GitHub Actions
- Location: `.github/workflows/ci.yml`
- Platform: GitHub-hosted runners

### Makefile Targets
```make
ci-build-all    # Build macOS, iOS, Android
ci-test-all     # Run all platform tests
```

## Core Engine Integrations

### llama.cpp (LLM Inference)
- Integration: CMake submodule at `core/third_party/llama.cpp`
- Status: **Not yet added** (TODO in CMakeLists.txt)
- Configuration: Metal/Vulkan backends passthrough

### whisper.cpp (STT)
- Status: **Planned** (not integrated)

### Kokoro-82M (TTS)
- Status: **Planned** (not integrated)

## Platform SDKs Required

### iOS/macOS
- Metal.framework
- Foundation.framework
- CoreFoundation.framework

### Android
- Vulkan SDK (via NDK)
- Android logging (`liblog`)
- AndroidX Core KTX

### Web
- WebGPU API (browser support required)
- Web Workers API
- IndexedDB API

## Network Requirements

| Use Case | Network | Notes |
|----------|---------|-------|
| Inference | None | Fully offline |
| Model Download | Optional | One-time download, then cached |
| SDK Usage | None | No telemetry or callbacks |
