# Edge Veda Flutter SDK - API Reference

Complete API documentation for Edge Veda SDK.

## Table of Contents

- [Core Classes](#core-classes)
  - [EdgeVeda](#edgeveda)
  - [ModelManager](#modelmanager)
- [Configuration](#configuration)
  - [EdgeVedaConfig](#edgevedaconfig)
  - [GenerateOptions](#generateoptions)
- [Response Types](#response-types)
  - [GenerateResponse](#generateresponse)
  - [TokenChunk](#tokenchunk)
  - [DownloadProgress](#downloadprogress)
  - [ModelInfo](#modelinfo)
- [Exceptions](#exceptions)
- [Model Registry](#model-registry)

---

## Core Classes

### EdgeVeda

Main class for LLM inference operations.

#### Constructor

```dart
EdgeVeda()
```

Creates a new EdgeVeda instance. You should typically create one instance per app session.

#### Properties

##### `isInitialized` → `bool`

Whether the SDK has been initialized.

```dart
if (edgeVeda.isInitialized) {
  // SDK is ready to use
}
```

##### `config` → `EdgeVedaConfig?`

Current configuration, or null if not initialized.

#### Methods

##### `init(EdgeVedaConfig config)` → `Future<void>`

Initialize the SDK with given configuration.

**Parameters:**
- `config`: Configuration object

**Throws:**
- `InitializationException`: If already initialized or initialization fails
- `ModelLoadException`: If model loading fails
- `ConfigurationException`: If configuration is invalid

**Example:**
```dart
await edgeVeda.init(EdgeVedaConfig(
  modelPath: '/path/to/model.gguf',
  useGpu: true,
));
```

##### `generate(String prompt, {GenerateOptions options})` → `Future<GenerateResponse>`

Generate text synchronously.

**Parameters:**
- `prompt`: Input text prompt
- `options`: Optional generation parameters (defaults to `GenerateOptions()`)

**Returns:** `GenerateResponse` containing generated text and metadata

**Throws:**
- `GenerationException`: If generation fails
- `InitializationException`: If SDK not initialized

**Example:**
```dart
final response = await edgeVeda.generate(
  'What is AI?',
  options: GenerateOptions(
    maxTokens: 100,
    temperature: 0.7,
  ),
);
print(response.text);
```

##### `generateStream(String prompt, {GenerateOptions options})` → `Stream<TokenChunk>`

Generate text with streaming token-by-token responses.

**Parameters:**
- `prompt`: Input text prompt
- `options`: Optional generation parameters

**Returns:** Stream of `TokenChunk` objects

**Throws:**
- `GenerationException`: If streaming fails to start

**Example:**
```dart
final stream = edgeVeda.generateStream('Tell me a story');
await for (final chunk in stream) {
  if (!chunk.isFinal) {
    print(chunk.token);
  }
}
```

##### `stopStream()` → `Future<void>`

Stop active streaming generation.

**Example:**
```dart
await edgeVeda.stopStream();
```

##### `getMemoryUsage()` → `int`

Get current memory usage in bytes.

**Returns:** Memory usage in bytes

**Example:**
```dart
final bytes = edgeVeda.getMemoryUsage();
print('Memory: ${bytes / (1024 * 1024)} MB');
```

##### `getMemoryUsageMb()` → `double`

Get current memory usage in megabytes.

**Returns:** Memory usage in MB

##### `isMemoryLimitExceeded()` → `bool`

Check if memory usage exceeds configured limit.

**Returns:** `true` if limit exceeded

**Example:**
```dart
if (edgeVeda.isMemoryLimitExceeded()) {
  print('Warning: Memory limit exceeded!');
}
```

##### `dispose()` → `Future<void>`

Release all resources and free native memory.

**Example:**
```dart
await edgeVeda.dispose();
```

---

### ModelManager

Manages model downloads, caching, and verification.

#### Constructor

```dart
ModelManager()
```

#### Properties

##### `downloadProgress` → `Stream<DownloadProgress>`

Stream of download progress updates.

**Example:**
```dart
modelManager.downloadProgress.listen((progress) {
  print('${progress.progressPercent}%');
});
```

#### Methods

##### `downloadModel(ModelInfo model, {bool verifyChecksum = true})` → `Future<String>`

Download a model with progress tracking.

**Parameters:**
- `model`: Model information object
- `verifyChecksum`: Whether to verify SHA-256 checksum (default: true)

**Returns:** Path to downloaded model file

**Throws:**
- `DownloadException`: If download fails
- `ChecksumException`: If checksum verification fails

**Example:**
```dart
final path = await modelManager.downloadModel(
  ModelRegistry.llama32_1b,
  verifyChecksum: true,
);
```

##### `isModelDownloaded(String modelId)` → `Future<bool>`

Check if a model is already downloaded.

**Parameters:**
- `modelId`: Model identifier

**Returns:** `true` if model exists locally

##### `getModelPath(String modelId)` → `Future<String>`

Get local path for a model.

**Parameters:**
- `modelId`: Model identifier

**Returns:** Absolute file path

##### `getModelSize(String modelId)` → `Future<int?>`

Get downloaded model file size.

**Parameters:**
- `modelId`: Model identifier

**Returns:** File size in bytes, or null if not downloaded

##### `deleteModel(String modelId)` → `Future<void>`

Delete a downloaded model.

##### `getDownloadedModels()` → `Future<List<String>>`

Get list of all downloaded model IDs.

**Returns:** List of model IDs

##### `getTotalModelsSize()` → `Future<int>`

Get total size of all downloaded models.

**Returns:** Total size in bytes

##### `clearAllModels()` → `Future<void>`

Delete all downloaded models.

##### `dispose()` → `void`

Release resources and close streams.

---

## Configuration

### EdgeVedaConfig

Configuration for initializing Edge Veda SDK.

#### Constructor

```dart
const EdgeVedaConfig({
  required String modelPath,
  int numThreads = 4,
  int contextLength = 2048,
  bool useGpu = true,
  int maxMemoryMb = 1536,
  bool verbose = false,
})
```

#### Properties

- **`modelPath`** (`String`, required): Path to GGUF model file
- **`numThreads`** (`int`, default: 4): Number of CPU threads for inference
- **`contextLength`** (`int`, default: 2048): Maximum context window in tokens
- **`useGpu`** (`bool`, default: true): Enable GPU acceleration (Metal/Vulkan)
- **`maxMemoryMb`** (`int`, default: 1536): Memory limit in MB
- **`verbose`** (`bool`, default: false): Enable verbose logging

#### Example

```dart
const config = EdgeVedaConfig(
  modelPath: '/models/llama.gguf',
  numThreads: 4,
  contextLength: 2048,
  useGpu: true,
  maxMemoryMb: 1536,
  verbose: true,
);
```

---

### GenerateOptions

Options for text generation.

#### Constructor

```dart
const GenerateOptions({
  String? systemPrompt,
  int maxTokens = 512,
  double temperature = 0.7,
  double topP = 0.9,
  int topK = 40,
  double repeatPenalty = 1.1,
  List<String> stopSequences = const [],
  bool jsonMode = false,
  bool stream = false,
})
```

#### Properties

- **`systemPrompt`** (`String?`): System prompt for context/behavior
- **`maxTokens`** (`int`, default: 512): Maximum tokens to generate
- **`temperature`** (`double`, default: 0.7): Sampling temperature (0.0-1.0)
  - 0.0 = deterministic
  - 1.0 = very creative
- **`topP`** (`double`, default: 0.9): Nucleus sampling threshold
- **`topK`** (`int`, default: 40): Top-k sampling parameter
- **`repeatPenalty`** (`double`, default: 1.1): Repetition penalty
- **`stopSequences`** (`List<String>`): Stop generation on these strings
- **`jsonMode`** (`bool`, default: false): Force valid JSON output
- **`stream`** (`bool`, default: false): Enable streaming

#### Methods

##### `copyWith({...})` → `GenerateOptions`

Create a copy with modified fields.

#### Example

```dart
const options = GenerateOptions(
  systemPrompt: 'You are a helpful assistant.',
  maxTokens: 256,
  temperature: 0.8,
  topP: 0.95,
  jsonMode: false,
);
```

---

## Response Types

### GenerateResponse

Response from text generation.

#### Properties

- **`text`** (`String`): Generated text content
- **`promptTokens`** (`int`): Number of tokens in prompt
- **`completionTokens`** (`int`): Number of tokens generated
- **`totalTokens`** (`int`): Total tokens (prompt + completion)
- **`latencyMs`** (`int?`): Generation time in milliseconds
- **`tokensPerSecond`** (`double?`): Throughput in tokens/sec

#### Example

```dart
print('Generated: ${response.text}');
print('Speed: ${response.tokensPerSecond} tokens/sec');
```

---

### TokenChunk

Individual token in streaming response.

#### Properties

- **`token`** (`String`): Token text
- **`index`** (`int`): Token position in sequence
- **`isFinal`** (`bool`): Whether this is the final token

---

### DownloadProgress

Model download progress information.

#### Properties

- **`totalBytes`** (`int`): Total file size
- **`downloadedBytes`** (`int`): Bytes downloaded so far
- **`progress`** (`double`): Progress as 0.0-1.0
- **`progressPercent`** (`int`): Progress as 0-100
- **`speedBytesPerSecond`** (`double?`): Download speed
- **`estimatedSecondsRemaining`** (`int?`): ETA in seconds

---

### ModelInfo

Model metadata and download information.

#### Properties

- **`id`** (`String`): Unique identifier
- **`name`** (`String`): Human-readable name
- **`sizeBytes`** (`int`): File size in bytes
- **`description`** (`String?`): Model description
- **`downloadUrl`** (`String`): Download URL
- **`checksum`** (`String?`): SHA-256 hash for verification
- **`format`** (`String`): File format (e.g., "GGUF")
- **`quantization`** (`String?`): Quantization level (e.g., "Q4_K_M")

#### Methods

##### `fromJson(Map<String, dynamic> json)` → `ModelInfo`

Create from JSON map.

##### `toJson()` → `Map<String, dynamic>`

Convert to JSON map.

---

## Exceptions

All exceptions extend `EdgeVedaException`.

### Exception Hierarchy

```
EdgeVedaException (abstract)
├── InitializationException
├── ModelLoadException
├── GenerationException
├── DownloadException
├── ChecksumException
├── MemoryException
└── ConfigurationException
```

### EdgeVedaException

Base exception class.

#### Properties

- **`message`** (`String`): Error message
- **`details`** (`String?`): Additional details
- **`originalError`** (`dynamic`): Original error if wrapped

#### Example

```dart
try {
  await edgeVeda.init(config);
} on InitializationException catch (e) {
  print('Init failed: ${e.message}');
  if (e.details != null) {
    print('Details: ${e.details}');
  }
}
```

---

## Model Registry

Pre-configured models available for download.

### ModelRegistry

Static class containing popular models.

#### Available Models

##### `llama32_1b` → `ModelInfo`

Llama 3.2 1B Instruct (Q4_K_M)
- Size: 668 MB
- Best for: General chat, Q&A

##### `phi35_mini` → `ModelInfo`

Phi 3.5 Mini Instruct (Q4_K_M)
- Size: 2.3 GB
- Best for: Complex reasoning, coding

##### `gemma2_2b` → `ModelInfo`

Gemma 2 2B Instruct (Q4_K_M)
- Size: 1.6 GB
- Best for: Versatile general-purpose

##### `tinyLlama` → `ModelInfo`

TinyLlama 1.1B Chat (Q4_K_M)
- Size: 669 MB
- Best for: Resource-constrained devices

#### Methods

##### `getAllModels()` → `List<ModelInfo>`

Get list of all available models.

##### `getModelById(String id)` → `ModelInfo?`

Get model by ID, or null if not found.

#### Example

```dart
// Use predefined model
final model = ModelRegistry.llama32_1b;

// Or find by ID
final model = ModelRegistry.getModelById('llama-3.2-1b-instruct-q4');
if (model != null) {
  await modelManager.downloadModel(model);
}
```

---

## Complete Example

```dart
import 'package:edge_veda/edge_veda.dart';

Future<void> main() async {
  // Initialize model manager
  final modelManager = ModelManager();

  // Download model with progress tracking
  modelManager.downloadProgress.listen((progress) {
    print('Download: ${progress.progressPercent}%');
  });

  final modelPath = await modelManager.downloadModel(
    ModelRegistry.llama32_1b,
  );

  // Initialize Edge Veda
  final edgeVeda = EdgeVeda();
  await edgeVeda.init(EdgeVedaConfig(
    modelPath: modelPath,
    useGpu: true,
  ));

  // Generate text
  final response = await edgeVeda.generate(
    'What is artificial intelligence?',
    options: const GenerateOptions(
      maxTokens: 200,
      temperature: 0.7,
    ),
  );

  print(response.text);
  print('Speed: ${response.tokensPerSecond} tokens/sec');

  // Stream tokens
  final stream = edgeVeda.generateStream('Tell me a joke');
  await for (final chunk in stream) {
    if (!chunk.isFinal) {
      print(chunk.token);
    }
  }

  // Check memory usage
  print('Memory: ${edgeVeda.getMemoryUsageMb()} MB');

  // Cleanup
  await edgeVeda.dispose();
  modelManager.dispose();
}
```

---

## Best Practices

1. **Initialize Once**: Create one EdgeVeda instance per session
2. **Check Initialization**: Always check `isInitialized` before operations
3. **Handle Errors**: Use try-catch with specific exception types
4. **Monitor Memory**: Check memory usage on low-end devices
5. **Dispose Resources**: Always call `dispose()` when done
6. **Use Streaming**: For better UX in interactive apps
7. **GPU Acceleration**: Keep `useGpu: true` for best performance

## Performance Tips

- Start with Llama 3.2 1B for best speed/quality balance
- Keep context length ≤ 2048 on mobile devices
- Use streaming for responsive UI
- Monitor memory usage with `getMemoryUsageMb()`
- Enable GPU acceleration (Metal/Vulkan)
- Use appropriate temperature (0.7 for balanced, 0.3 for focused)

---

For more information, see the [README](../README.md) and [example app](../example/).
