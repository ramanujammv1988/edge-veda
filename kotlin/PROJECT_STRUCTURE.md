# EdgeVeda Kotlin SDK - Project Structure

## Directory Layout

```
kotlin/
├── build.gradle.kts                    # Gradle build configuration
├── proguard-rules.pro                  # ProGuard rules for SDK
├── consumer-rules.pro                  # ProGuard rules for consumers
├── .gitignore                          # Git ignore patterns
├── README.md                           # SDK documentation
│
├── src/
│   ├── main/
│   │   ├── AndroidManifest.xml         # Android manifest
│   │   │
│   │   ├── kotlin/com/edgeveda/sdk/
│   │   │   ├── EdgeVeda.kt            # Main SDK API class
│   │   │   ├── Config.kt              # Configuration classes
│   │   │   ├── Types.kt               # Type definitions & exceptions
│   │   │   │
│   │   │   └── internal/
│   │   │       └── NativeBridge.kt    # JNI bridge to native code
│   │   │
│   │   └── cpp/
│   │       ├── CMakeLists.txt         # CMake build configuration
│   │       └── edge_veda_jni.cpp      # JNI C++ implementation
│   │
│   └── test/
│       └── kotlin/com/edgeveda/sdk/
│           └── EdgeVedaTest.kt        # Unit tests
```

## File Descriptions

### Build Configuration

- **build.gradle.kts**: Gradle build script with Kotlin DSL
  - Android library plugin configuration
  - Kotlin 1.9.22 with coroutines support
  - NDK and CMake integration for native code
  - Maven publishing configuration
  - Dependencies: coroutines, AndroidX, testing libraries

- **proguard-rules.pro**: R8/ProGuard rules for SDK minification
  - Keeps public API classes
  - Preserves native methods
  - Protects data classes and enums

- **consumer-rules.pro**: ProGuard rules for apps using the SDK
  - Ensures SDK API remains accessible after app minification

### Android Configuration

- **AndroidManifest.xml**: Android manifest declaration
  - minSdk 26 (Android 8.0)
  - Vulkan feature declarations
  - Optional permissions

### Kotlin Source Files

#### Public API (`src/main/kotlin/com/edgeveda/sdk/`)

- **EdgeVeda.kt**: Main SDK interface
  - `EdgeVeda.create()`: Factory method
  - `suspend fun init()`: Model initialization
  - `suspend fun generate()`: Blocking text generation
  - `fun generateStream()`: Streaming generation with Flow
  - `val memoryUsage`: Memory usage property
  - `suspend fun unloadModel()`: Model unloading
  - `fun close()`: Resource cleanup (Closeable)

- **Config.kt**: Configuration classes
  - `enum class Backend`: Hardware backend options
    - CPU, VULKAN, NNAPI, AUTO
  - `data class EdgeVedaConfig`: Model configuration
    - Preset configs: mobile(), highQuality(), fast()
    - Builder methods: withBackend(), withMaxTokens(), etc.
    - Validation in init block

- **Types.kt**: Type definitions
  - `data class GenerateOptions`: Generation parameters
    - Presets: creative(), deterministic(), balanced()
  - `data class GenerationStats`: Generation metrics
  - `data class ModelInfo`: Model metadata
  - `data class DeviceInfo`: Device capabilities
  - `enum class FinishReason`: Generation stop reasons
  - `sealed class EdgeVedaException`: Exception hierarchy
    - ModelLoadError, GenerationError, InvalidConfiguration
    - NativeLibraryError, CancelledException, etc.
  - `fun interface StreamCallback`: Streaming callback

#### Internal Implementation (`src/main/kotlin/com/edgeveda/sdk/internal/`)

- **NativeBridge.kt**: JNI bridge to native code
  - External native function declarations
  - Native library loading (System.loadLibrary)
  - Handle management for native instances
  - Thread-safe operations
  - Error translation from native to Kotlin exceptions

### Native Code (`src/main/cpp/`)

- **CMakeLists.txt**: CMake build configuration
  - C++17 standard
  - Compiler flags and optimization
  - NDK library linking (log, android, vulkan)
  - Debug/Release configurations
  - Optional AddressSanitizer support

- **edge_veda_jni.cpp**: JNI C++ implementation
  - JNI native method implementations
  - EdgeVedaInstance native structure
  - Native lifecycle management
  - String conversion helpers (jstring ↔ std::string)
  - Exception handling and logging
  - Android logging integration
  - Placeholder implementations (TODO: link to EdgeVeda core)

### Tests (`src/test/kotlin/com/edgeveda/sdk/`)

- **EdgeVedaTest.kt**: Comprehensive unit tests
  - SDK creation and lifecycle tests
  - Configuration validation tests
  - Backend enum tests
  - Generate options tests
  - Exception type tests
  - Data class equality and copy tests
  - State management tests
  - 30+ test cases

## Key Design Patterns

### Coroutines & Flow
- All I/O operations are suspend functions
- Streaming uses Kotlin Flow for reactive programming
- Proper dispatchers: Dispatchers.IO for init, Dispatchers.Default for generation

### Resource Management
- Implements Closeable for automatic resource cleanup
- Use with `use { }` block for automatic disposal
- Atomic state tracking (initialized, closed)

### Thread Safety
- Atomic boolean flags for state
- Mutex in native layer
- Dispatcher-based concurrency control

### Error Handling
- Sealed class exception hierarchy
- Type-safe error handling
- Native exceptions translated to Kotlin

### Builder Pattern
- Fluent configuration with withX() methods
- Immutable data classes with copy()
- Preset configurations

## Dependencies

### Runtime
- Kotlin stdlib 1.9.22
- Kotlinx coroutines 1.7.3 (core + android)
- AndroidX core-ktx 1.12.0
- AndroidX annotation 1.7.1

### Testing
- JUnit 4.13.2
- Kotlinx coroutines-test 1.7.3
- MockK 1.13.8
- AndroidX test libraries

### Native
- Android NDK
- CMake 3.22.1+
- C++17 compiler
- Vulkan headers (optional)

## Build Targets

### Gradle Tasks
- `./gradlew build` - Build debug and release variants
- `./gradlew test` - Run unit tests
- `./gradlew assembleRelease` - Build release AAR
- `./gradlew publish` - Publish to Maven

### NDK ABI Filters
- arm64-v8a (primary)
- armeabi-v7a
- x86_64 (emulator)
- x86 (emulator)

## Integration Points

The SDK is designed to integrate with:
1. EdgeVeda Core C++ library (to be linked in CMakeLists.txt)
2. Android applications via Gradle dependency
3. Maven repositories for distribution

## Next Steps

1. Implement actual EdgeVeda C++ core integration
2. Add real model loading and inference
3. Implement device capability detection
4. Add instrumentation tests
5. Create sample Android app
6. Set up CI/CD pipeline
7. Publish to Maven Central
