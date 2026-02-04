# EdgeVeda Swift SDK - Project Structure

## Directory Tree

```
swift/
├── Package.swift                          # Swift Package Manager manifest
├── README.md                              # Main documentation
├── API.md                                 # API reference documentation
├── INTEGRATION.md                         # Integration guide
├── STRUCTURE.md                           # This file
├── .gitignore                             # Git ignore rules
│
├── Sources/
│   ├── EdgeVeda/                          # Main Swift library
│   │   ├── EdgeVeda.swift                 # Public API - Main actor
│   │   ├── Config.swift                   # Configuration types
│   │   ├── Types.swift                    # Error types and data structures
│   │   └── Internal/
│   │       └── FFIBridge.swift            # C FFI bridge layer
│   │
│   └── CEdgeVeda/                         # C library wrapper
│       └── include/
│           └── edge_veda.h                # C header file
│
├── Tests/
│   └── EdgeVedaTests/
│       └── EdgeVedaTests.swift            # Unit and integration tests
│
└── Examples/
    ├── SimpleExample.swift                # Basic usage example
    ├── StreamingExample.swift             # Streaming generation example
    └── ConfigExample.swift                # Configuration examples
```

## File Descriptions

### Root Level

#### `Package.swift`
Swift Package Manager manifest defining:
- Package name: EdgeVeda
- Platforms: iOS 15+, macOS 12+
- Products: EdgeVeda library
- Targets: EdgeVeda (Swift), CEdgeVeda (C wrapper), EdgeVedaTests
- Dependencies and build settings

#### `README.md`
Main documentation covering:
- Features and capabilities
- Installation instructions
- Quick start guide
- Configuration options
- Usage examples
- Requirements and building

#### `API.md`
Complete API reference documentation:
- EdgeVeda actor methods
- Configuration structures
- Generation options
- Error types
- All public types and enums

#### `INTEGRATION.md`
Integration guide for developers:
- iOS/macOS integration steps
- Xcode setup
- Bundle management
- SwiftUI/UIKit examples
- Troubleshooting

### Sources/EdgeVeda/

#### `EdgeVeda.swift`
Main public API implemented as an actor:
- **Class**: `EdgeVeda` (actor)
- **Key Methods**:
  - `init(modelPath:config:)` - Initialize with model
  - `generate(_:)` - Synchronous generation
  - `generateStream(_:)` - Streaming generation
  - `unloadModel()` - Cleanup
  - `resetContext()` - Reset conversation
- **Properties**:
  - `memoryUsage` - Current memory usage
- **Features**:
  - Async/await API
  - Actor isolation for thread safety
  - Automatic cleanup on deinit

#### `Config.swift`
Configuration and generation options:
- **`Backend` enum**: CPU, Metal, Auto
- **`EdgeVedaConfig` struct**: Model loading configuration
  - Preset configs: default, cpu, metal, lowMemory, highPerformance
- **`GenerateOptions` struct**: Text generation parameters
  - Preset options: default, creative, precise, greedy
- All types conform to `Sendable` for concurrency safety

#### `Types.swift`
Error types and data structures:
- **`EdgeVedaError` enum**: Comprehensive error handling
  - modelNotFound, loadFailed, generationFailed, etc.
  - Localized error descriptions
  - Recovery suggestions
- **`StreamToken` struct**: Individual streaming tokens
- **`ModelInfo` struct**: Model metadata
- **`PerformanceMetrics` struct**: Performance data
- **`GenerationResult` struct**: Complete generation result
- **`StopReason` enum**: Generation stop reasons
- **`DeviceInfo` struct**: Device capabilities

### Sources/EdgeVeda/Internal/

#### `FFIBridge.swift`
C Foreign Function Interface bridge:
- **FFI Functions**:
  - `loadModel()` - Load GGUF model via C
  - `unloadModel()` - Free model resources
  - `generate()` - Synchronous generation
  - `generateStream()` - Streaming with callbacks
  - `getMemoryUsage()` - Query memory
  - `getModelMetadata()` - Retrieve metadata
  - `resetContext()` - Clear KV cache
- **Safety**:
  - Unsafe pointer management
  - Memory cleanup
  - Error handling
  - C string conversions
- **Structs**:
  - `edge_veda_config` - C config struct
  - `edge_veda_generate_params` - C params struct
- **Note**: Contains C function stubs replaced by actual library at link time

### Sources/CEdgeVeda/include/

#### `edge_veda.h`
C header file defining FFI interface:
- **Types**:
  - `edge_veda_model_t` - Opaque model handle
  - `edge_veda_config` - Model configuration
  - `edge_veda_generate_params` - Generation parameters
  - `edge_veda_stream_callback` - Streaming callback
- **Functions**:
  - Model management (load, free)
  - Text generation (sync, stream)
  - Model information (memory, metadata)
  - Context management
- **Memory Management**: String allocation/deallocation
- **Platform**: C89 compatible, C++ extern "C" support

### Tests/EdgeVedaTests/

#### `EdgeVedaTests.swift`
Comprehensive test suite:
- **Configuration Tests**: All preset and custom configs
- **Generation Options Tests**: All preset options
- **Backend Tests**: Enum values and conversions
- **Error Tests**: All error types and messages
- **Type Tests**: StreamToken, ModelInfo, etc.
- **Integration Tests**: EdgeVeda initialization
- **Concurrency Tests**: Actor isolation
- **Performance Tests**: Configuration/option creation
- **Total Tests**: 30+ test cases

### Examples/

#### `SimpleExample.swift`
Basic usage demonstration:
- Model loading
- Simple generation
- Custom options
- Streaming
- Error handling
- Memory monitoring

#### `StreamingExample.swift`
Advanced streaming example:
- High-performance configuration
- Device information
- Multiple prompts
- Performance metrics
- Token-by-token streaming
- Context reset

#### `ConfigExample.swift`
Configuration comparison:
- Test all preset configs
- Custom configuration
- Load time measurement
- Memory usage comparison
- Inference benchmarking
- Backend compatibility

## Architecture Overview

### Layers

```
┌─────────────────────────────────────────┐
│         Swift Application               │
│  (iOS/macOS App, SwiftUI, UIKit)       │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│         EdgeVeda Actor                  │
│  Public API (EdgeVeda.swift)           │
│  - async/await                          │
│  - Actor isolation                      │
│  - Thread-safe                          │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│         Configuration Layer             │
│  Config.swift, Types.swift             │
│  - Type-safe configs                    │
│  - Error handling                       │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│         FFI Bridge                      │
│  FFIBridge.swift                       │
│  - Unsafe pointer handling              │
│  - C interop                            │
│  - Memory management                    │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│         C Library (edge_veda.h)        │
│  - GGUF loading                         │
│  - llama.cpp backend                    │
│  - Metal/CPU inference                  │
└─────────────────────────────────────────┘
```

### Concurrency Model

- **EdgeVeda**: Actor (ensures serial access)
- **Config/Types**: Sendable structs (safe to pass across actors)
- **FFI Bridge**: Internal, called only from EdgeVeda actor
- **Streaming**: AsyncThrowingStream for async iteration

### Memory Management

1. **Model Loading**: Memory-mapped or loaded into RAM
2. **Context**: KV cache stored in model handle
3. **Strings**: C strings allocated/freed via FFI
4. **Cleanup**: Automatic via actor deinit + manual unloadModel()

## Build Process

### Swift Package Manager

```bash
swift build                 # Build debug
swift build -c release      # Build release
swift test                  # Run tests
swift package clean         # Clean build
```

### Xcode

```bash
# Generate Xcode project
swift package generate-xcodeproj

# Or open directly in Xcode
open Package.swift
```

### Integration

```swift
// In Package.swift dependencies
.package(url: "https://github.com/user/edge-veda-swift", from: "1.0.0")
```

## Dependencies

### Runtime Dependencies
- **EdgeVeda C library**: Core inference engine
- **libc++**: C++ standard library (for llama.cpp)

### Platform Dependencies
- **iOS 15+**: Foundation, Metal (optional)
- **macOS 12+**: Foundation, Metal (optional)
- **Swift 5.9+**: Async/await, actors, Sendable

### Development Dependencies
- **XCTest**: Testing framework (built-in)

## Size Estimates

- **Swift Source**: ~15 KB (compressed)
- **C Header**: ~3 KB
- **Compiled Library**: ~50-100 KB (without C library)
- **C Library**: ~5-50 MB (depending on quantization)
- **Model Files**: 100 MB - 10+ GB (separate)

## Future Additions

Planned additions to structure:

```
Sources/EdgeVeda/
  ├── Vision/                # Vision model support
  ├── Adapters/              # LoRA adapters
  └── Quantization/          # Runtime quantization

Examples/
  ├── ChatApp/               # Complete chat app
  ├── VisionExample/         # Image understanding
  └── BenchmarkSuite/        # Performance benchmarks

Docs/
  ├── Tutorials/             # Step-by-step guides
  └── Architecture/          # Architecture docs
```

## Contributing

When adding files:
1. Place Swift code in `Sources/EdgeVeda/`
2. Internal code in `Sources/EdgeVeda/Internal/`
3. C headers in `Sources/CEdgeVeda/include/`
4. Tests in `Tests/EdgeVedaTests/`
5. Examples in `Examples/`
6. Documentation in root (*.md)

## License

All files in this project are under MIT License unless otherwise specified.
