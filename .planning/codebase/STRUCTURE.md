# Directory Structure

## Root Layout

```
edge/
├── core/                    # C++ inference engine
├── flutter/                 # Flutter/Dart SDK
├── swift/                   # Swift Package (iOS/macOS)
├── kotlin/                  # Kotlin SDK (Android)
├── react-native/            # React Native module
├── web/                     # Web/WASM SDK
├── scripts/                 # Build and utility scripts
├── .claude/                 # Claude Code configuration
├── .github/                 # GitHub Actions workflows
├── Makefile                 # Cross-platform build orchestration
├── README.md                # Project documentation
└── prd.txt                  # Product requirements
```

## Core C++ (`core/`)

```
core/
├── CMakeLists.txt           # Main CMake configuration
├── include/
│   └── edge_veda.h          # Public C API header
├── src/
│   ├── engine.cpp           # Inference engine implementation
│   └── memory_guard.cpp     # Memory management
├── cmake/
│   ├── ios.toolchain.cmake  # iOS cross-compilation
│   └── android.toolchain.cmake  # Android cross-compilation
└── third_party/             # External dependencies (llama.cpp)
```

## Flutter SDK (`flutter/`)

```
flutter/
├── pubspec.yaml             # Package definition
├── lib/
│   ├── edge_veda.dart       # Public API exports
│   └── src/
│       ├── edge_veda_impl.dart  # Main implementation
│       ├── model_manager.dart   # Model loading/caching
│       ├── types.dart           # Type definitions
│       └── ffi/
│           └── bindings.dart    # FFI bindings
├── ios/
│   └── edge_veda.podspec    # CocoaPods spec
└── android/
    └── build.gradle         # Android plugin build
```

## Swift SDK (`swift/`)

```
swift/
├── Package.swift            # SPM package definition
├── Sources/
│   ├── CEdgeVeda/           # C library target
│   │   └── include/
│   │       └── edge_veda.h  # Header copy for SPM
│   └── EdgeVeda/
│       ├── EdgeVeda.swift   # Main SDK class
│       ├── Config.swift     # Configuration types
│       ├── Types.swift      # Type definitions
│       └── Internal/
│           └── FFIBridge.swift  # C interop bridge
└── Tests/
    └── EdgeVedaTests/
        └── EdgeVedaTests.swift  # Unit tests
```

## Kotlin SDK (`kotlin/`)

```
kotlin/
├── build.gradle.kts         # Gradle build configuration
├── src/
│   └── main/
│       ├── AndroidManifest.xml
│       ├── kotlin/com/edgeveda/sdk/
│       │   ├── EdgeVeda.kt      # Main SDK class
│       │   ├── Config.kt        # Configuration types
│       │   ├── Types.kt         # Type definitions
│       │   └── internal/
│       │       └── NativeBridge.kt  # JNI bridge
│       └── cpp/
│           ├── CMakeLists.txt   # Native build config
│           └── edge_veda_jni.cpp  # JNI implementation
```

## React Native (`react-native/`)

```
react-native/
├── package.json             # NPM package definition
├── tsconfig.json            # TypeScript config
├── src/
│   ├── index.tsx            # Public exports
│   ├── EdgeVeda.ts          # Main SDK class
│   ├── NativeEdgeVeda.ts    # TurboModule spec
│   └── types.ts             # Type definitions
├── ios/
│   ├── EdgeVeda.mm          # Objective-C++ bridge
│   └── EdgeVeda.swift       # Swift implementation
├── android/
│   ├── build.gradle
│   └── src/main/java/com/edgeveda/
│       ├── EdgeVedaModule.kt    # Native module
│       └── EdgeVedaPackage.kt   # Package registration
└── edge-veda.podspec        # CocoaPods spec
```

## Web SDK (`web/`)

```
web/
├── package.json             # NPM package definition
├── tsconfig.json            # TypeScript config
├── rollup.config.js         # Bundle configuration
└── src/
    ├── index.ts             # Main SDK class + exports
    ├── types.ts             # Type definitions
    ├── worker.ts            # Web Worker for inference
    ├── wasm-loader.ts       # WASM initialization
    └── model-cache.ts       # IndexedDB model caching
```

## Key Files by Purpose

### Configuration
| File | Purpose |
|------|---------|
| `core/CMakeLists.txt` | C++ build, backend selection |
| `Makefile` | Cross-platform build targets |
| `flutter/pubspec.yaml` | Flutter dependencies |
| `kotlin/build.gradle.kts` | Android build, NDK config |
| `swift/Package.swift` | SPM targets and dependencies |
| `web/rollup.config.js` | Web bundle settings |

### Public API
| File | Purpose |
|------|---------|
| `core/include/edge_veda.h` | C API (all platforms use this) |
| `flutter/lib/edge_veda.dart` | Flutter public exports |
| `swift/Sources/EdgeVeda/EdgeVeda.swift` | Swift public API |
| `kotlin/src/.../EdgeVeda.kt` | Kotlin public API |
| `react-native/src/index.tsx` | RN public exports |
| `web/src/index.ts` | Web public API |

### Native Bridges
| File | Purpose |
|------|---------|
| `flutter/lib/src/ffi/bindings.dart` | Dart FFI |
| `swift/Sources/EdgeVeda/Internal/FFIBridge.swift` | Swift-C bridge |
| `kotlin/src/main/cpp/edge_veda_jni.cpp` | Kotlin JNI |
| `react-native/ios/EdgeVeda.mm` | RN iOS bridge |
| `react-native/android/.../EdgeVedaModule.kt` | RN Android bridge |

## Naming Conventions

### Files
- C++: `snake_case.cpp`, `snake_case.h`
- TypeScript: `kebab-case.ts`
- Dart: `snake_case.dart`
- Swift: `PascalCase.swift`
- Kotlin: `PascalCase.kt`

### Directories
- All lowercase with hyphens: `react-native/`, `model-cache.ts`
- Exception: Platform conventions (e.g., `Sources/` for Swift)

### Classes/Types
- PascalCase across all languages: `EdgeVeda`, `EdgeVedaConfig`
- C structs: `ev_config`, `ev_context` (lowercase prefix)
- Error enums: `EdgeVedaError`, `ev_error_t`

## Adding New Code

### New Platform Feature
1. Add to C API: `core/include/edge_veda.h`
2. Implement in engine: `core/src/engine.cpp`
3. Update each SDK's bridge layer
4. Add platform-specific public API

### New Platform SDK
1. Create directory at root: `new-platform/`
2. Add build target to `Makefile`
3. Implement bridge to `edge_veda.h`
4. Mirror existing SDK patterns

### New Backend (e.g., CUDA)
1. Add `core/src/backend_cuda.cpp`
2. Update `core/CMakeLists.txt` with option
3. Add detection to `ev_detect_backend()`
