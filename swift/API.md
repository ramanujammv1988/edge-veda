# EdgeVeda Swift SDK API Reference

Complete API documentation for EdgeVeda Swift SDK.

## Table of Contents

- [EdgeVeda Actor](#edgeveda-actor)
- [EdgeVedaConfig](#edgevedaconfig)
- [GenerateOptions](#generateoptions)
- [Backend](#backend)
- [EdgeVedaError](#edgevedaerror)
- [Types](#types)

---

## EdgeVeda Actor

Main interface for LLM inference operations.

### Declaration

```swift
@available(iOS 15.0, macOS 12.0, *)
public actor EdgeVeda
```

### Initialization

#### `init(modelPath:config:)`

Initialize EdgeVeda with a model file and configuration.

```swift
public init(modelPath: String, config: EdgeVedaConfig = .default) async throws
```

**Parameters:**
- `modelPath`: Absolute path to the GGUF model file
- `config`: Configuration options (defaults to `.default`)

**Throws:**
- `EdgeVedaError.modelNotFound`: Model file doesn't exist
- `EdgeVedaError.loadFailed`: Failed to load model
- `EdgeVedaError.outOfMemory`: Insufficient memory
- `EdgeVedaError.unsupportedBackend`: Backend not available

**Example:**
```swift
let edgeVeda = try await EdgeVeda(
    modelPath: "/path/to/model.gguf",
    config: .metal
)
```

### Text Generation Methods

#### `generate(_:)`

Generate text completion synchronously.

```swift
public func generate(_ prompt: String) async throws -> String
```

**Parameters:**
- `prompt`: Input prompt text

**Returns:** Generated text completion

**Throws:** `EdgeVedaError.generationFailed` on failure

**Example:**
```swift
let response = try await edgeVeda.generate("Hello, how are you?")
```

#### `generate(_:options:)`

Generate text with custom options.

```swift
public func generate(_ prompt: String, options: GenerateOptions) async throws -> String
```

**Parameters:**
- `prompt`: Input prompt text
- `options`: Generation parameters

**Returns:** Generated text completion

**Example:**
```swift
let response = try await edgeVeda.generate(
    "Write a poem",
    options: .creative
)
```

#### `generateStream(_:)`

Generate text with streaming token-by-token output.

```swift
public func generateStream(_ prompt: String) -> AsyncThrowingStream<String, Error>
```

**Parameters:**
- `prompt`: Input prompt text

**Returns:** AsyncThrowingStream yielding tokens

**Example:**
```swift
for try await token in edgeVeda.generateStream("Tell me a story") {
    print(token, terminator: "")
}
```

#### `generateStream(_:options:)`

Generate text with streaming and custom options.

```swift
public func generateStream(
    _ prompt: String,
    options: GenerateOptions
) -> AsyncThrowingStream<String, Error>
```

**Example:**
```swift
for try await token in edgeVeda.generateStream(
    "Explain AI",
    options: .precise
) {
    processToken(token)
}
```

### Model Information

#### `memoryUsage`

Current memory usage in bytes.

```swift
public var memoryUsage: UInt64 { get async }
```

**Example:**
```swift
let memoryMB = await edgeVeda.memoryUsage / 1_024_000
print("Memory: \(memoryMB) MB")
```

#### `getModelInfo()`

Get model metadata information.

```swift
public func getModelInfo() async throws -> [String: String]
```

**Returns:** Dictionary of model metadata

**Example:**
```swift
let info = try await edgeVeda.getModelInfo()
print("Architecture: \(info["architecture"] ?? "unknown")")
```

### Model Management

#### `unloadModel()`

Unload the model and free resources.

```swift
public func unloadModel() async
```

**Example:**
```swift
await edgeVeda.unloadModel()
```

#### `resetContext()`

Reset conversation context.

```swift
public func resetContext() async throws
```

**Example:**
```swift
try await edgeVeda.resetContext()
```

---

## EdgeVedaConfig

Configuration options for EdgeVeda initialization.

### Declaration

```swift
public struct EdgeVedaConfig: Sendable
```

### Properties

```swift
public let backend: Backend
public let threads: Int
public let contextSize: Int
public let gpuLayers: Int
public let batchSize: Int
public let useMemoryMapping: Bool
public let lockMemory: Bool
public let verbose: Bool
```

### Initialization

```swift
public init(
    backend: Backend = .auto,
    threads: Int = 0,
    contextSize: Int = 2048,
    gpuLayers: Int = -1,
    batchSize: Int = 512,
    useMemoryMapping: Bool = true,
    lockMemory: Bool = false,
    verbose: Bool = false
)
```

**Parameters:**
- `backend`: Computation backend (default: `.auto`)
- `threads`: CPU threads, 0 = auto-detect (default: 0)
- `contextSize`: Context window size (default: 2048)
- `gpuLayers`: GPU layers to offload, -1 = all (default: -1)
- `batchSize`: Batch size for processing (default: 512)
- `useMemoryMapping`: Enable mmap (default: true)
- `lockMemory`: Lock memory (default: false)
- `verbose`: Verbose logging (default: false)

### Preset Configurations

#### `.default`

Auto-detect best backend with balanced settings.

```swift
public static let `default`: EdgeVedaConfig
```

#### `.cpu`

CPU-only inference.

```swift
public static let cpu: EdgeVedaConfig
```

#### `.metal`

Metal GPU acceleration (Apple Silicon).

```swift
public static let metal: EdgeVedaConfig
```

#### `.lowMemory`

Reduced memory usage.

```swift
public static let lowMemory: EdgeVedaConfig
```

#### `.highPerformance`

Maximum performance settings.

```swift
public static let highPerformance: EdgeVedaConfig
```

**Example:**
```swift
// Use preset
let config = EdgeVedaConfig.metal

// Custom configuration
let config = EdgeVedaConfig(
    backend: .auto,
    threads: 4,
    contextSize: 4096,
    gpuLayers: 20,
    batchSize: 512
)
```

---

## GenerateOptions

Options for text generation.

### Declaration

```swift
public struct GenerateOptions: Sendable
```

### Properties

```swift
public let maxTokens: Int
public let temperature: Float
public let topP: Float
public let topK: Int
public let repeatPenalty: Float
public let stopSequences: [String]
```

### Initialization

```swift
public init(
    maxTokens: Int = 512,
    temperature: Float = 0.7,
    topP: Float = 0.9,
    topK: Int = 40,
    repeatPenalty: Float = 1.1,
    stopSequences: [String] = []
)
```

**Parameters:**
- `maxTokens`: Maximum tokens to generate (default: 512)
- `temperature`: Sampling temperature, 0.0-2.0 (default: 0.7)
- `topP`: Nucleus sampling threshold, 0.0-1.0 (default: 0.9)
- `topK`: Top-K sampling limit (default: 40)
- `repeatPenalty`: Repetition penalty, 1.0+ (default: 1.1)
- `stopSequences`: Sequences to stop generation (default: [])

### Preset Options

#### `.default`

Balanced generation settings.

```swift
public static let `default`: GenerateOptions
```

#### `.creative`

Higher temperature for creative output.

```swift
public static let creative: GenerateOptions
```

#### `.precise`

Lower temperature for factual output.

```swift
public static let precise: GenerateOptions
```

#### `.greedy`

Deterministic decoding.

```swift
public static let greedy: GenerateOptions
```

**Example:**
```swift
// Use preset
let options = GenerateOptions.creative

// Custom options
let options = GenerateOptions(
    maxTokens: 256,
    temperature: 0.8,
    topP: 0.95,
    topK: 50,
    repeatPenalty: 1.15,
    stopSequences: ["</s>", "\n\n"]
)
```

---

## Backend

Computation backend for inference.

### Declaration

```swift
public enum Backend: String, Sendable
```

### Cases

#### `.cpu`

CPU-only inference.

```swift
case cpu = "CPU"
```

#### `.metal`

Metal GPU acceleration (Apple Silicon).

```swift
case metal = "Metal"
```

#### `.auto`

Auto-detect best available backend.

```swift
case auto = "Auto"
```

**Example:**
```swift
let backend: Backend = .metal
print(backend.rawValue) // "Metal"
```

---

## EdgeVedaError

Errors that can occur during EdgeVeda operations.

### Declaration

```swift
public enum EdgeVedaError: LocalizedError, Sendable
```

### Cases

#### `.modelNotFound(path:)`

Model file not found at specified path.

```swift
case modelNotFound(path: String)
```

#### `.modelNotLoaded`

Model not loaded (operation requires loaded model).

```swift
case modelNotLoaded
```

#### `.loadFailed(reason:)`

Failed to load model.

```swift
case loadFailed(reason: String)
```

#### `.generationFailed(reason:)`

Text generation failed.

```swift
case generationFailed(reason: String)
```

#### `.invalidParameter(name:value:)`

Invalid parameter value.

```swift
case invalidParameter(name: String, value: String)
```

#### `.outOfMemory`

Out of memory.

```swift
case outOfMemory
```

#### `.unsupportedBackend(_:)`

Backend not supported on this device.

```swift
case unsupportedBackend(Backend)
```

#### `.ffiError(message:)`

FFI/C interop error.

```swift
case ffiError(message: String)
```

#### `.unknown(message:)`

Unknown error.

```swift
case unknown(message: String)
```

### Properties

#### `errorDescription`

Localized error description.

```swift
public var errorDescription: String? { get }
```

#### `recoverySuggestion`

Suggested recovery action.

```swift
public var recoverySuggestion: String? { get }
```

**Example:**
```swift
do {
    let edgeVeda = try await EdgeVeda(modelPath: path, config: .metal)
} catch EdgeVedaError.modelNotFound(let path) {
    print("Model not found: \(path)")
} catch EdgeVedaError.outOfMemory {
    print("Out of memory - try lowMemory config")
} catch EdgeVedaError.unsupportedBackend(let backend) {
    print("\(backend) not supported")
} catch {
    print("Error: \(error.localizedDescription)")
    if let suggestion = (error as? EdgeVedaError)?.recoverySuggestion {
        print("Suggestion: \(suggestion)")
    }
}
```

---

## Types

### StreamToken

Individual token from streaming generation.

```swift
public struct StreamToken: Sendable {
    public let text: String
    public let position: Int
    public let probability: Float?
    public let isFinal: Bool
}
```

### ModelInfo

Information about a loaded model.

```swift
public struct ModelInfo: Sendable {
    public let architecture: String
    public let parameterCount: UInt64
    public let contextSize: Int
    public let vocabularySize: Int
    public let metadata: [String: String]
}
```

### PerformanceMetrics

Performance metrics for generation.

```swift
public struct PerformanceMetrics: Sendable {
    public let tokensPerSecond: Double
    public let promptProcessingTime: Double
    public let generationTime: Double
    public let totalTime: Double
    public let tokenCount: Int
    public let peakMemoryUsage: UInt64
}
```

### GenerationResult

Result of a text generation operation.

```swift
public struct GenerationResult: Sendable {
    public let text: String
    public let metrics: PerformanceMetrics
    public let stopReason: StopReason
}
```

### StopReason

Reason why generation stopped.

```swift
public enum StopReason: String, Sendable {
    case maxTokens = "max_tokens"
    case stopSequence = "stop_sequence"
    case endOfText = "end_of_text"
    case cancelled = "cancelled"
    case error = "error"
}
```

### DeviceInfo

Information about the compute device.

```swift
public struct DeviceInfo: Sendable {
    public let name: String
    public let availableBackends: [Backend]
    public let totalMemory: UInt64
    public let availableMemory: UInt64
    public let recommendedBackend: Backend

    public static func current() -> DeviceInfo
}
```

**Example:**
```swift
let deviceInfo = DeviceInfo.current()
print("Device: \(deviceInfo.name)")
print("Recommended: \(deviceInfo.recommendedBackend)")
print("Available: \(deviceInfo.availableBackends)")
print("Memory: \(deviceInfo.totalMemory / 1_024_000_000) GB")
```

---

## Version Information

**SDK Version:** 1.0.0
**Minimum Swift Version:** 5.9
**Minimum iOS Version:** 15.0
**Minimum macOS Version:** 12.0
**Concurrency:** Strict concurrency enabled

## See Also

- [README](README.md) - Getting started guide
- [INTEGRATION](INTEGRATION.md) - Integration guide
- [Examples](Examples/) - Code examples
