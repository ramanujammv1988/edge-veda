# EdgeVeda SDK for Android (Kotlin)

Modern Kotlin SDK for running large language models on Android devices with hardware acceleration.

## Features

- **Modern Kotlin API** with Coroutines and Flow support
- **Hardware Acceleration** via Vulkan, NNAPI, and CPU backends
- **Streaming Generation** for real-time text output
- **Chat Sessions**: Multi-turn conversations with context summarization and chat templates
- **Vision Inference**: Image description and continuous vision processing
- **Runtime Supervision**: Budget control, thermal/battery monitoring, latency tracking, scheduling policies
- **Model Management**: Download, cache, and registry for model lifecycle
- **Camera Utilities**: Native camera frame capture for vision pipelines
- **Observability**: Performance tracing and structured native error codes
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
    implementation("com.edgeveda:sdk:1.2.0")
}
```

### Gradle (Groovy)

```groovy
dependencies {
    implementation 'com.edgeveda:sdk:1.2.0'
}
```

## Quick Start

```kotlin
import com.edgeveda.sdk.*

// Create and initialize
val edgeVeda = EdgeVeda.create()
val config = EdgeVedaConfig.mobile()

edgeVeda.init("/path/to/model.gguf", config)

// Generate text
val response = edgeVeda.generate("What is the meaning of life?")
println(response)

// Generate with streaming (Flow)
edgeVeda.generateStream("Explain quantum physics")
    .collect { token ->
        print(token)
    }

// Check memory usage
println("Memory: ${edgeVeda.memoryUsage / (1024 * 1024)} MB")

// Cleanup
edgeVeda.close()
```

## Configuration

### Preset Configurations

```kotlin
val mobileConfig = EdgeVedaConfig.mobile()        // Balanced for mobile
val highQualityConfig = EdgeVedaConfig.highQuality() // Best quality
val fastConfig = EdgeVedaConfig.fast()              // Speed optimized
```

### Custom Configuration

```kotlin
val config = EdgeVedaConfig(
    backend = Backend.AUTO,
    numThreads = 4,
    maxTokens = 512,
    contextSize = 2048,
    temperature = 0.7f,
    topP = 0.9f,
    topK = 40,
    useGpu = true,
    useMmap = true
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

- `Backend.AUTO` — Automatically select best available backend (recommended)
- `Backend.VULKAN` — Use Vulkan GPU acceleration
- `Backend.NNAPI` — Use Android Neural Networks API
- `Backend.CPU` — CPU-only inference

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
GenerateOptions.creative()
GenerateOptions.deterministic()
GenerateOptions.balanced()
```

## Streaming Generation

```kotlin
import kotlinx.coroutines.flow.collect

suspend fun generateWithProgress(prompt: String) {
    edgeVeda.generateStream(prompt)
        .collect { token ->
            updateTextView(token)
        }
}
```

## Chat Sessions

Multi-turn conversation management with automatic context handling.

```kotlin
import com.edgeveda.sdk.*

// Create a chat session
val session = ChatSession(
    systemPrompt = "You are a helpful assistant.",
    template = ChatTemplate.llama3()
)

// Add messages and generate replies
session.addMessage(ChatMessage.user("What is Kotlin?"))
val reply = edgeVeda.generate(session.buildPrompt())
session.addMessage(ChatMessage.assistant(reply))

// Continue the conversation
session.addMessage(ChatMessage.user("How does it compare to Swift?"))
val reply2 = edgeVeda.generate(session.buildPrompt())

// Context summarization to manage token budgets
val summary = session.summarize(edgeVeda, maxTokens = 200)

// Clear history
session.clearHistory()
```

### Chat Templates

Built-in templates for popular model families:

```kotlin
val llama = ChatTemplate.llama3()
val mistral = ChatTemplate.mistral()
val chatml = ChatTemplate.chatml()
val phi = ChatTemplate.phi3()
val gemma = ChatTemplate.gemma()
val custom = ChatTemplate(
    systemPrefix = "<|system|>",
    systemSuffix = "<|end|>",
    userPrefix = "<|user|>",
    userSuffix = "<|end|>",
    assistantPrefix = "<|assistant|>",
    assistantSuffix = "<|end|>"
)
```

## Vision Inference

Process images and video frames with multimodal models.

```kotlin
import com.edgeveda.sdk.*

// One-shot image description
val worker = VisionWorker(edgeVeda)
val description = worker.describeImage(imageBytes, prompt = "What do you see?")

// Continuous vision with frame queue
val frameQueue = FrameQueue(maxSize = 10)
frameQueue.push(frame1)
frameQueue.push(frame2)

worker.startContinuousVision(frameQueue) { result ->
    println("Frame analysis: $result")
}

// Stop processing
worker.stopContinuousVision()
```

## Runtime Supervision

Monitor and control resource usage during inference.

### Budget Control

```kotlin
val budget = Budget(
    maxTokensPerMinute = 1000,
    maxConcurrentRequests = 3,
    maxMemoryBytes = 512L * 1024 * 1024
)

if (!budget.canProceed()) {
    println("Budget exceeded, waiting...")
    return
}
budget.recordTokens(150)
```

### Latency Tracking

```kotlin
val tracker = LatencyTracker()
val span = tracker.startSpan("generate")
// ... perform work ...
span.end()

val stats = tracker.getStats("generate")
println("P50: ${stats.p50}ms, P99: ${stats.p99}ms")
```

### Thermal & Battery Monitoring

```kotlin
val thermal = ThermalMonitor(context)
thermal.startMonitoring { state ->
    if (state == ThermalState.CRITICAL) {
        println("Throttling due to thermal pressure")
    }
}

val battery = BatteryDrainTracker(context)
battery.startTracking()
val drainRate = battery.currentDrainRate  // mW
```

### Resource Monitor

```kotlin
val monitor = ResourceMonitor()
val snapshot = monitor.snapshot()
println("CPU: ${snapshot.cpuUsage}%")
println("Memory: ${snapshot.memoryUsed / (1024 * 1024)} MB")
```

### Scheduler & Runtime Policy

```kotlin
val scheduler = Scheduler(maxConcurrent = 2, strategy = Strategy.FIFO)
scheduler.submit(priority = Priority.HIGH) {
    edgeVeda.generate(prompt)
}

val policy = RuntimePolicy(
    budget = budget,
    thermalMonitor = thermal,
    batteryTracker = battery
)
val decision = policy.evaluate()  // PROCEED, THROTTLE, PAUSE, ABORT
```

### Telemetry

```kotlin
val telemetry = Telemetry()
telemetry.record("generation_complete", mapOf(
    "tokens" to 150,
    "latency_ms" to 320
))
val report = telemetry.flush()
```

## Model Management

Download, cache, and manage models across sessions.

```kotlin
// ModelManager – download and cache
val manager = ModelManager(context.cacheDir)
val localPath = manager.download(
    url = modelUrl,
    identifier = "llama-3.2-1b-q4"
) { progress ->
    println("Download: ${(progress * 100).toInt()}%")
}

val cached = manager.cachedModels()
manager.delete("llama-3.2-1b-q4")

// ModelRegistry – metadata catalog
val registry = ModelRegistry()
registry.register(ModelInfo(
    id = "llama-3.2-1b-q4",
    name = "Llama 3.2 1B Q4",
    size = 780_000_000L,
    quantization = Quantization.Q4_0,
    architecture = Architecture.LLAMA
))
val models = registry.listModels()
val match = registry.findBestModel(maxSize = 1_000_000_000L)
```

## Camera Utilities

Capture frames from the device camera for vision pipelines.

```kotlin
val camera = CameraUtils(context)
camera.start(facing = CameraFacing.BACK, resolution = Resolution.HD_720P)

// Grab a single frame
val frame = camera.captureFrame()
val description = worker.describeImage(frame)

// Continuous feed into a FrameQueue
camera.streamFrames(frameQueue)

camera.stop()
```

## Observability

### Performance Tracing

```kotlin
val trace = PerfTrace("chat_turn")
trace.addEvent("prompt_built")
// ... work ...
trace.addEvent("generation_done")
trace.end()

println("Duration: ${trace.durationMs}ms")
println("Events: ${trace.events}")
```

### Native Error Codes

```kotlin
try {
    edgeVeda.generate(prompt)
} catch (e: EdgeVedaException) {
    val nativeCode = NativeErrorCode.from(e)
    println("Code: ${nativeCode.code}")        // e.g. 1001
    println("Domain: ${nativeCode.domain}")    // e.g. "inference"
    println("Message: ${nativeCode.message}")  // human-readable
}
```

## Advanced Usage

### Cancel Generation

```kotlin
val job = scope.launch {
    edgeVeda.generateStream(prompt).collect { token ->
        print(token)
    }
}

// Cancel at any time — triggers C-level abort + coroutine Job cancellation
job.cancel()
```

### Resource Management

```kotlin
// Using 'use' for automatic cleanup
EdgeVeda.create().use { edgeVeda ->
    edgeVeda.init(modelPath, config)
    val result = edgeVeda.generate(prompt)
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

### Model Swapping

```kotlin
edgeVeda.init("/path/to/model-a.gguf", config)
val resultA = edgeVeda.generate("prompt")

edgeVeda.unloadModel()
edgeVeda.init("/path/to/model-b.gguf", config)
val resultB = edgeVeda.generate("prompt")

edgeVeda.close()
```

## Error Handling

```kotlin
try {
    edgeVeda.init("/path/to/model.gguf", config)
} catch (e: EdgeVedaException.ModelLoadError) {
    Log.e(TAG, "Failed to load model", e)
} catch (e: EdgeVedaException.NativeLibraryError) {
    Log.e(TAG, "Native library not available", e)
}
```

### Exception Types

- `EdgeVedaException.ModelLoadError` — Model loading failed
- `EdgeVedaException.GenerationError` — Text generation failed
- `EdgeVedaException.InvalidConfiguration` — Invalid config
- `EdgeVedaException.NativeLibraryError` — Native library issues
- `EdgeVedaException.OutOfMemoryError` — Insufficient memory
- `EdgeVedaException.CancelledException` — Operation cancelled

## Architecture

### Components

| Module | Description |
|--------|-------------|
| `EdgeVeda.kt` | Main public API with Coroutines |
| `Config.kt` | Configuration types and presets |
| `Types.kt` | Data types, exceptions, and metadata |
| `NativeBridge.kt` | JNI bridge to C core |
| `ChatSession.kt` | Multi-turn conversation management |
| `ChatTemplate.kt` | Prompt formatting for model families |
| `ChatTypes.kt` | Message and role type definitions |
| `VisionWorker.kt` | Image and continuous vision inference |
| `VisionTypes.kt` | Vision-specific data types |
| `FrameQueue.kt` | Thread-safe frame buffer |
| `Budget.kt` | Token and resource budget enforcement |
| `LatencyTracker.kt` | Percentile latency statistics |
| `ResourceMonitor.kt` | CPU/memory usage snapshots |
| `ThermalMonitor.kt` | Device thermal state observer |
| `BatteryDrainTracker.kt` | Battery drain rate tracking |
| `Scheduler.kt` | Concurrent request scheduling |
| `RuntimePolicy.kt` | Composite go/no-go policy engine |
| `Telemetry.kt` | Event recording and reporting |
| `ModelManager.kt` | Model download and caching |
| `ModelRegistry.kt` | Model metadata catalog |
| `CameraUtils.kt` | Native camera frame capture |
| `PerfTrace.kt` | Span-based performance tracing |
| `NativeErrorCode.kt` | Structured error code mapping |

## Building from Source

```bash
cd kotlin

# Build the library
./gradlew build

# Run tests
./gradlew test

# Build release AAR
./gradlew assembleRelease
```

## Performance Tips

1. **Use AUTO backend** for automatic optimization
2. **Enable memory mapping** (`useMmap = true`) for faster loading
3. **Adjust thread count** based on device (typically 4–8 threads)
4. **Use streaming** for better perceived performance
5. **Profile memory usage** with `memoryUsage` property
6. **Unload models** when not in use to free memory
7. **Monitor thermals** — throttle inference under thermal pressure
8. **Use Budget control** — prevent runaway token generation

## License

Apache License 2.0

## Support

- Documentation: https://docs.edgeveda.com
- Issues: https://github.com/edgeveda/sdk/issues
- Email: support@edgeveda.com