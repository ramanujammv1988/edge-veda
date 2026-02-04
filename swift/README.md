# EdgeVeda Swift SDK

Native Swift SDK for EdgeVeda - High-performance on-device LLM inference for iOS and macOS.

## Features

- **Modern Swift API**: Async/await and Actor-based concurrency
- **Streaming Support**: Real-time token-by-token generation
- **Multiple Backends**: CPU and Metal GPU acceleration
- **Type-Safe**: Comprehensive error handling and Swift types
- **Memory Efficient**: Configurable memory management options
- **Platform Support**: iOS 15+, macOS 12+

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/edge-veda-swift", from: "1.0.0")
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

## Advanced Usage

### Streaming with Custom Handling

```swift
let stream = edgeVeda.generateStream("Write a poem", options: .creative)

for try await token in stream {
    // Process each token as it arrives
    updateUI(with: token)
}
```

### Model Information

```swift
// Get memory usage
let memoryUsage = await edgeVeda.memoryUsage
print("Memory: \(memoryUsage / 1_024_000) MB")

// Get model metadata
let info = try await edgeVeda.getModelInfo()
print("Architecture: \(info["architecture"] ?? "unknown")")
```

### Context Management

```swift
// Reset conversation context
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

## Backend Selection

### Auto-Detection (Recommended)

```swift
let edgeVeda = try await EdgeVeda(
    modelPath: modelPath,
    config: .default  // Auto-detects best backend
)
```

### Manual Selection

```swift
// Force CPU
let cpuVeda = try await EdgeVeda(
    modelPath: modelPath,
    config: .cpu
)

// Force Metal (Apple Silicon only)
let metalVeda = try await EdgeVeda(
    modelPath: modelPath,
    config: .metal
)
```

## Performance Tips

1. **Use Metal on Apple Silicon**: Significantly faster than CPU
2. **Adjust Context Size**: Smaller = less memory, faster loading
3. **Enable Memory Mapping**: Faster model loading
4. **Tune Batch Size**: Balance between speed and memory
5. **Use Streaming**: Better user experience for long generations

## Architecture

### Components

- **EdgeVeda.swift**: Main public API (Actor-based)
- **Config.swift**: Configuration types and presets
- **Types.swift**: Error types, results, and metadata
- **FFIBridge.swift**: C interop layer with memory safety

### Concurrency Model

EdgeVeda uses Swift's actor model for thread-safe concurrent access:

```swift
// Safe concurrent usage
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

See the `Examples/` directory for complete sample projects:

- **SimpleChat**: Basic chat interface
- **StreamingDemo**: Real-time streaming example
- **MultiModel**: Loading and switching between models
- **PerformanceTest**: Benchmarking different configurations

## License

MIT License - see LICENSE file for details

## Contributing

Contributions welcome! Please read CONTRIBUTING.md first.

## Support

- **Issues**: GitHub Issues
- **Discussions**: GitHub Discussions
- **Documentation**: https://edgeveda.dev/docs/swift

## Roadmap

- [ ] Vision model support
- [ ] LoRA adapter loading
- [ ] Quantization options
- [ ] watchOS support
- [ ] Swift 6.0 strict concurrency
- [ ] Pre-built XCFramework distribution
