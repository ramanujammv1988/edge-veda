# EdgeVeda SDK for Android (Kotlin)

Modern Kotlin SDK for running large language models on Android devices with hardware acceleration.

## Features

- **Modern Kotlin API** with Coroutines and Flow support
- **Hardware Acceleration** via Vulkan, NNAPI, and CPU backends
- **Streaming Generation** for real-time text output
- **Memory Efficient** with optimized model loading
- **Type Safe** with comprehensive Kotlin type system usage
- **Well Tested** with comprehensive unit tests

## Requirements

- Android SDK 26+ (Android 8.0 Oreo)
- Kotlin 1.9+
- NDK for native compilation
- Gradle 8.0+

## Installation

### Gradle (Kotlin DSL)

```kotlin
dependencies {
    implementation("com.edgeveda:sdk:1.0.0")
}
```

### Gradle (Groovy)

```groovy
dependencies {
    implementation 'com.edgeveda:sdk:1.0.0'
}
```

## Quick Start

```kotlin
import com.edgeveda.sdk.*

// Create and initialize
val edgeVeda = EdgeVeda.create()
val config = EdgeVedaConfig.mobile() // Optimized for mobile devices

edgeVeda.init("/path/to/model.gguf", config)

// Generate text (blocking)
val response = edgeVeda.generate("What is the meaning of life?")
println(response)

// Generate with streaming (Flow)
edgeVeda.generateStream("Explain quantum physics")
    .collect { token ->
        print(token) // Print each token as it's generated
    }

// Check memory usage
println("Memory: ${edgeVeda.memoryUsage / (1024 * 1024)} MB")

// Cleanup
edgeVeda.close()
```

## Configuration

### Preset Configurations

```kotlin
// Mobile devices - balanced performance and memory
val mobileConfig = EdgeVedaConfig.mobile()

// High quality - best output quality (uses more resources)
val highQualityConfig = EdgeVedaConfig.highQuality()

// Fast - optimized for speed
val fastConfig = EdgeVedaConfig.fast()
```

### Custom Configuration

```kotlin
val config = EdgeVedaConfig(
    backend = Backend.AUTO,        // Auto-select best backend
    numThreads = 4,                 // Number of CPU threads
    maxTokens = 512,                // Max tokens to generate
    contextSize = 2048,             // Context window size
    temperature = 0.7f,             // Sampling temperature
    topP = 0.9f,                    // Top-p sampling
    topK = 40,                      // Top-k sampling
    useGpu = true,                  // Enable GPU acceleration
    useMmap = true                  // Use memory mapping
)
```

### Builder Pattern

```kotlin
val config = EdgeVedaConfig()
    .withBackend(Backend.VULKAN)
    .withNumThreads(8)
    .withMaxTokens(1024)
    .withTemperature(0.8f)
```

## Backend Options

- `Backend.AUTO` - Automatically select best available backend (recommended)
- `Backend.VULKAN` - Use Vulkan GPU acceleration
- `Backend.NNAPI` - Use Android Neural Networks API
- `Backend.CPU` - CPU-only inference

## Generation Options

```kotlin
// Use defaults
edgeVeda.generate("prompt")

// Custom options
val options = GenerateOptions(
    maxTokens = 100,
    temperature = 0.9f,
    stopSequences = listOf("END", "\n\n")
)
edgeVeda.generate("prompt", options)

// Presets
GenerateOptions.creative()       // High creativity
GenerateOptions.deterministic()  // Factual/consistent
GenerateOptions.balanced()       // Balanced (default)
```

## Streaming Generation

```kotlin
import kotlinx.coroutines.flow.collect

suspend fun generateWithProgress(prompt: String) {
    edgeVeda.generateStream(prompt)
        .collect { token ->
            // Update UI with each token
            updateTextView(token)
        }
}
```

## Error Handling

```kotlin
try {
    edgeVeda.init("/path/to/model.gguf", config)
} catch (e: EdgeVedaException.ModelLoadError) {
    // Handle model loading errors
    Log.e(TAG, "Failed to load model", e)
} catch (e: EdgeVedaException.NativeLibraryError) {
    // Handle native library errors
    Log.e(TAG, "Native library not available", e)
}
```

### Exception Types

- `EdgeVedaException.ModelLoadError` - Model loading failed
- `EdgeVedaException.GenerationError` - Text generation failed
- `EdgeVedaException.InvalidConfiguration` - Invalid config
- `EdgeVedaException.NativeLibraryError` - Native library issues
- `EdgeVedaException.OutOfMemoryError` - Insufficient memory
- `EdgeVedaException.CancelledException` - Operation cancelled

## Resource Management

```kotlin
// Using 'use' for automatic cleanup
EdgeVeda.create().use { edgeVeda ->
    edgeVeda.init(modelPath, config)
    val result = edgeVeda.generate(prompt)
    // Automatically closed when block exits
}

// Manual management
val edgeVeda = EdgeVeda.create()
try {
    edgeVeda.init(modelPath, config)
    // ... use edgeVeda
} finally {
    edgeVeda.close()
}
```

## Model Management

```kotlin
// Load model
edgeVeda.init("/path/to/model.gguf", config)

// Use model
val result = edgeVeda.generate("prompt")

// Unload model (keeps SDK alive)
edgeVeda.unloadModel()

// Load different model
edgeVeda.init("/path/to/other-model.gguf", config)

// Completely dispose
edgeVeda.close()
```

## Building from Source

```bash
# Clone the repository
git clone https://github.com/edgeveda/sdk.git
cd sdk/kotlin

# Build the library
./gradlew build

# Run tests
./gradlew test

# Build release AAR
./gradlew assembleRelease
```

## Architecture

```
kotlin/
├── src/main/
│   ├── kotlin/com/edgeveda/sdk/
│   │   ├── EdgeVeda.kt          # Main API
│   │   ├── Config.kt             # Configuration
│   │   ├── Types.kt              # Data types & exceptions
│   │   └── internal/
│   │       └── NativeBridge.kt   # JNI bridge
│   ├── cpp/
│   │   ├── edge_veda_jni.cpp     # JNI implementation
│   │   └── CMakeLists.txt        # CMake build config
│   └── AndroidManifest.xml
└── src/test/
    └── kotlin/com/edgeveda/sdk/
        └── EdgeVedaTest.kt       # Unit tests
```

## Performance Tips

1. **Use AUTO backend** for automatic optimization
2. **Enable memory mapping** (`useMmap = true`) for faster loading
3. **Adjust thread count** based on device (typically 4-8 threads)
4. **Use streaming** for better perceived performance
5. **Profile memory usage** with `memoryUsage` property
6. **Unload models** when not in use to free memory

## License

Apache License 2.0

## Support

- Documentation: https://docs.edgeveda.com
- Issues: https://github.com/edgeveda/sdk/issues
- Email: support@edgeveda.com
