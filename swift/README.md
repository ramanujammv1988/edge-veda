# EdgeVeda Swift SDK

Native Swift SDK for EdgeVeda — high-performance on-device LLM inference for iOS and macOS.

## Features

- **Modern Swift API**: Async/await and Actor-based concurrency
- **Streaming Support**: Real-time token-by-token generation
- **Chat Sessions**: Multi-turn conversations with context summarization
- **Vision Inference**: Image description and continuous vision processing
- **Runtime Supervision**: Budget control, thermal/battery monitoring, scheduling policies
- **Model Management**: Download, cache, and registry for model lifecycle
- **Camera Utilities**: Native camera frame capture for vision pipelines
- **Observability**: Performance tracing and structured native error codes
- **Multiple Backends**: CPU and Metal GPU acceleration
- **Type-Safe**: Comprehensive error handling and Swift types
- **Memory Efficient**: Configurable memory management options
- **Platform Support**: iOS 15+, macOS 12+

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/edge-veda-swift", from: "1.2.0")
]
```

Or add via Xcode: File > Add Package Dependencies > Enter repository URL

## Quick Start

```swift
import EdgeVeda

// Initialize with a model
let edgeVeda = try await EdgeVeda(
    modelPath: "/path/to/model.gguf",
    config: .default
)

// Generate text
let response = try await edgeVeda.generate("Hello, how are you?")
print(response)

// Streaming generation
for try await token in edgeVeda.generateStream("Tell me a story") {
    print(token, terminator: "")
}

// Cleanup
await edgeVeda.unloadModel()
```

## Configuration

### Preset Configurations

```swift
// Auto-detect best backend
let config = EdgeVedaConfig.default

// CPU-only inference
let cpuConfig = EdgeVedaConfig.cpu

// Metal GPU acceleration
let metalConfig = EdgeVedaConfig.metal

// Low memory usage
let lowMemConfig = EdgeVedaConfig.lowMemory

// High performance
let highPerfConfig = EdgeVedaConfig.highPerformance
```

### Custom Configuration

```swift
let config = EdgeVedaConfig(
    backend: .metal,
    threads: 4,
    contextSize: 4096,
    gpuLayers: -1,
    batchSize: 512,
    useMemoryMapping: true,
    lockMemory: false,
    verbose: true
)
```

## Generation Options

### Preset Options

```swift
// Balanced generation
let options = GenerateOptions.default

// Creative writing
let creative = GenerateOptions.creative

// Precise/factual
let precise = GenerateOptions.precise

// Deterministic
let greedy = GenerateOptions.greedy
```

### Custom Options

```swift
let options = GenerateOptions(
    maxTokens: 256,
    temperature: 0.8,
    topP: 0.95,
    topK: 40,
    repeatPenalty: 1.1,
    stopSequences: ["</s>", "\n\n"]
)

let response = try await edgeVeda.generate(prompt, options: options)
```

## Chat Sessions

Multi-turn conversation management with automatic context handling.

```swift
import EdgeVeda

// Create a chat session
let session = ChatSession(
    systemPrompt: "You are a helpful assistant.",
    template: .llama3
)

// Add messages and generate replies
session.addMessage(.user("What is Swift?"))
let reply = try await edgeVeda.generate(session.buildPrompt())
session.addMessage(.assistant(reply))

// Continue the conversation
session.addMessage(.user("How does it compare to Kotlin?"))
let reply2 = try await edgeVeda.generate(session.buildPrompt())

// Context summarization to manage token budgets
let summary = try await session.summarize(using: edgeVeda, maxTokens: 200)

// Clear history
session.clearHistory()
```

### Chat Templates

Built-in templates for popular model families:

```swift
let llama = ChatTemplate.llama3
let mistral = ChatTemplate.mistral
let chatml = ChatTemplate.chatml
let phi = ChatTemplate.phi3
let gemma = ChatTemplate.gemma
let custom = ChatTemplate(
    systemPrefix: "<|system|>",
    systemSuffix: "<|end|>",
    userPrefix: "<|user|>",
    userSuffix: "<|end|>",
    assistantPrefix: "<|assistant|>",
    assistantSuffix: "<|end|>"
)
```

## Vision Inference

Process images and video frames with multimodal models.

```swift
import EdgeVeda

// One-shot image description
let worker = VisionWorker(edgeVeda: edgeVeda)
let description = try await worker.describeImage(imageData, prompt: "What do you see?")

// Continuous vision with frame queue
let frameQueue = FrameQueue(maxSize: 10)
frameQueue.push(frame1)
frameQueue.push(frame2)

worker.startContinuousVision(frameQueue: frameQueue) { result in
    print("Frame analysis: \(result)")
}

// Stop processing
worker.stopContinuousVision()
```

## Runtime Supervision

Monitor and control resource usage during inference.

### Budget Control

```swift
let budget = Budget(
    maxTokensPerMinute: 1000,
    maxConcurrentRequests: 3,
    maxMemoryBytes: 512 * 1024 * 1024
)

guard budget.canProceed() else {
    print("Budget exceeded, waiting...")
    return
}
budget.recordTokens(150)
```

### Latency Tracking

```swift
let tracker = LatencyTracker()
let span = tracker.startSpan(name: "generate")
// ... perform work ...
span.end()

let stats = tracker.getStats(name: "generate")
print("P50: \(stats.p50)ms, P99: \(stats.p99)ms")
```

### Thermal & Battery Monitoring

```swift
let thermal = ThermalMonitor()
thermal.startMonitoring { state in
    if state == .critical {
        print("Throttling due to thermal pressure")
    }
}

let battery = BatteryDrainTracker()
battery.startTracking()
let drainRate = battery.currentDrainRate  // mW
```

### Resource Monitor

```swift
let monitor = ResourceMonitor()
let snapshot = monitor.snapshot()
print("CPU: \(snapshot.cpuUsage)%")
print("Memory: \(snapshot.memoryUsed / 1_048_576) MB")
```

### Scheduler & Runtime Policy

```swift
let scheduler = Scheduler(maxConcurrent: 2, strategy: .fifo)
try await scheduler.submit(priority: .high) {
    try await edgeVeda.generate(prompt)
}

let policy = RuntimePolicy(
    budget: budget,
    thermalMonitor: thermal,
    batteryTracker: battery
)
let decision = policy.evaluate()  // .proceed, .throttle, .pause, .abort
```

### Telemetry

```swift
let telemetry = Telemetry()
telemetry.record(event: "generation_complete", properties: [
    "tokens": 150,
    "latency_ms": 320
])
let report = telemetry.flush()
```

## Model Management

Download, cache, and manage models across sessions.

```swift
// ModelManager – download and cache
let manager = ModelManager(cacheDirectory: .cachesDirectory)
let localPath = try await manager.download(
    from: modelURL,
    identifier: "llama-3.2-1b-q4"
) { progress in
    print("Download: \(Int(progress * 100))%")
}

let cached = manager.cachedModels()
try manager.delete(identifier: "llama-3.2-1b-q4")

// ModelRegistry – metadata catalog
let registry = ModelRegistry()
registry.register(ModelInfo(
    id: "llama-3.2-1b-q4",
    name: "Llama 3.2 1B Q4",
    size: 780_000_000,
    quantization: .q4_0,
    architecture: .llama
))
let models = registry.listModels()
let match = registry.findBestModel(maxSize: 1_000_000_000)
```

## Camera Utilities

Capture frames from the device camera for vision pipelines.

```swift
let camera = CameraUtils()
try await camera.start(position: .back, resolution: .hd720p)

// Grab a single frame
let frame = try await camera.captureFrame()
let description = try await worker.describeImage(frame)

// Continuous feed into a FrameQueue
camera.streamFrames(to: frameQueue)

camera.stop()
```

## Observability

### Performance Tracing

```swift
let trace = PerfTrace(name: "chat_turn")
trace.addEvent("prompt_built")
// ... work ...
trace.addEvent("generation_done")
trace.end()

print("Duration: \(trace.durationMs)ms")
print("Events: \(trace.events)")
```

### Native Error Codes

```swift
do {
    try await edgeVeda.generate(prompt)
} catch let error as EdgeVedaError {
    let nativeCode = NativeErrorCode.from(error)
    print("Code: \(nativeCode.code)")        // e.g. 1001
    print("Domain: \(nativeCode.domain)")    // e.g. "inference"
    print("Message: \(nativeCode.message)")  // human-readable
}
```

## Advanced Usage

### Cancel Generation

```swift
let task = Task {
    for try await token in edgeVeda.generateStream("Long story...") {
        print(token, terminator: "")
    }
}

// Cancel at any time — triggers C-level abort + Swift Task cancellation
task.cancel()
```

### Model Information

```swift
let memoryUsage = await edgeVeda.memoryUsage
print("Memory: \(memoryUsage / 1_024_000) MB")

let info = try await edgeVeda.getModelInfo()
print("Architecture: \(info["architecture"] ?? "unknown")")
```

### Context Management

```swift
try await edgeVeda.resetContext()
```

### Device Information

```swift
let deviceInfo = DeviceInfo.current()
print("Recommended backend: \(deviceInfo.recommendedBackend)")
print("Available backends: \(deviceInfo.availableBackends)")
print("Total memory: \(deviceInfo.totalMemory / 1_024_000_000) GB")
```

## Error Handling

```swift
do {
    let edgeVeda = try await EdgeVeda(
        modelPath: modelPath,
        config: .metal
    )
    let response = try await edgeVeda.generate(prompt)
} catch EdgeVedaError.modelNotFound(let path) {
    print("Model not found: \(path)")
} catch EdgeVedaError.outOfMemory {
    print("Out of memory - try lowMemory config")
} catch EdgeVedaError.unsupportedBackend(let backend) {
    print("\(backend) not supported on this device")
} catch {
    print("Error: \(error.localizedDescription)")
}
```

## Architecture

### Components

| Module | Description |
|--------|-------------|
| `EdgeVeda.swift` | Main public API (Actor-based) |
| `Config.swift` | Configuration types and presets |
| `Types.swift` | Error types, results, and metadata |
| `FFIBridge.swift` | C interop layer with memory safety |
| `ChatSession.swift` | Multi-turn conversation management |
| `ChatTemplate.swift` | Prompt formatting for model families |
| `ChatTypes.swift` | Message and role type definitions |
| `VisionWorker.swift` | Image and continuous vision inference |
| `VisionTypes.swift` | Vision-specific data types |
| `FrameQueue.swift` | Thread-safe frame buffer |
| `Budget.swift` | Token and resource budget enforcement |
| `LatencyTracker.swift` | Percentile latency statistics |
| `ResourceMonitor.swift` | CPU/memory usage snapshots |
| `ThermalMonitor.swift` | Device thermal state observer |
| `BatteryDrainTracker.swift` | Battery drain rate tracking |
| `Scheduler.swift` | Concurrent request scheduling |
| `RuntimePolicy.swift` | Composite go/no-go policy engine |
| `Telemetry.swift` | Event recording and reporting |
| `ModelManager.swift` | Model download and caching |
| `ModelRegistry.swift` | Model metadata catalog |
| `CameraUtils.swift` | Native camera frame capture |
| `PerfTrace.swift` | Span-based performance tracing |
| `NativeErrorCode.swift` | Structured error code mapping |

### Concurrency Model

EdgeVeda uses Swift's actor model for thread-safe concurrent access:

```swift
Task {
    let response1 = try await edgeVeda.generate("Prompt 1")
}
Task {
    let response2 = try await edgeVeda.generate("Prompt 2")
}
```

## Requirements

- Swift 5.9+
- iOS 15.0+ / macOS 12.0+
- Xcode 15.0+
- Edge Veda C library

## Building

```bash
cd swift
swift build
swift test
```

### Xcode

1. Open `Package.swift` in Xcode
2. Build and run tests: Cmd+U
3. Add to your app project

## Examples

See the `Examples/` directory for sample code:

- **SimpleExample.swift**: Basic text generation
- **StreamingExample.swift**: Real-time streaming
- **ConfigExample.swift**: Configuration presets
- **RuntimeSupervisionExample.swift**: Budget, scheduling, and monitoring

## Performance Tips

1. **Use Metal on Apple Silicon**: Significantly faster than CPU
2. **Adjust Context Size**: Smaller = less memory, faster loading
3. **Enable Memory Mapping**: Faster model loading
4. **Tune Batch Size**: Balance between speed and memory
5. **Use Streaming**: Better user experience for long generations
6. **Monitor Thermals**: Throttle inference under thermal pressure
7. **Use Budget Control**: Prevent runaway token generation

## License

MIT License — see LICENSE file for details

## Contributing

Contributions welcome! Please read CONTRIBUTING.md first.

## Support

- **Issues**: GitHub Issues
- **Discussions**: GitHub Discussions
- **Documentation**: https://edgeveda.dev/docs/swift