# Edge Veda Web SDK - API Reference

## Table of Contents

1. [EdgeVeda Class](#edgeveda-class)
2. [Configuration](#configuration)
3. [Generation Options](#generation-options)
4. [Results and Streaming](#results-and-streaming)
5. [Utility Functions](#utility-functions)
6. [Cache Management](#cache-management)
7. [Types](#types)

---

## EdgeVeda Class

Main class for browser-based LLM inference.

### Constructor

```typescript
new EdgeVeda(config: EdgeVedaConfig)
```

Creates a new EdgeVeda instance with the specified configuration.

**Parameters:**
- `config` - Configuration object (see [Configuration](#configuration))

**Example:**
```typescript
const ai = new EdgeVeda({
  modelId: 'llama-3.2-1b',
  device: 'auto',
  precision: 'fp16',
});
```

### Methods

#### `init(): Promise<void>`

Initializes the inference engine. Must be called before `generate()` or `generateStream()`.

**Returns:** Promise that resolves when initialization is complete

**Throws:** Error if initialization fails

**Example:**
```typescript
await ai.init();
```

---

#### `generate(options: GenerateOptions): Promise<GenerateResult>`

Generates text synchronously (non-streaming).

**Parameters:**
- `options` - Generation options (see [Generation Options](#generation-options))

**Returns:** Promise resolving to GenerateResult

**Throws:** Error if not initialized or generation fails

**Example:**
```typescript
const result = await ai.generate({
  prompt: 'What is TypeScript?',
  maxTokens: 100,
  temperature: 0.7,
});

console.log(result.text);
console.log(`${result.tokensPerSecond.toFixed(2)} tokens/sec`);
```

---

#### `generateStream(options: GenerateOptions): AsyncGenerator<StreamChunk>`

Generates text with streaming (tokens arrive in real-time).

**Parameters:**
- `options` - Generation options (see [Generation Options](#generation-options))

**Returns:** AsyncGenerator yielding StreamChunk objects

**Throws:** Error if not initialized or generation fails

**Example:**
```typescript
for await (const chunk of ai.generateStream({
  prompt: 'Tell me a story:',
  maxTokens: 200,
})) {
  process.stdout.write(chunk.token);

  if (chunk.done) {
    console.log(`\n\nSpeed: ${chunk.stats.tokensPerSecond} tok/s`);
  }
}
```

---

#### `terminate(): Promise<void>`

Terminates the worker and cleans up resources.

**Returns:** Promise that resolves when cleanup is complete

**Example:**
```typescript
await ai.terminate();
```

---

#### `isInitialized(): boolean`

Checks if the engine is initialized and ready.

**Returns:** true if initialized, false otherwise

**Example:**
```typescript
if (ai.isInitialized()) {
  await ai.generate({ prompt: 'Hello!' });
}
```

---

#### `getConfig(): Readonly<EdgeVedaConfig>`

Gets the current configuration (read-only).

**Returns:** Configuration object

**Example:**
```typescript
const config = ai.getConfig();
console.log(`Model: ${config.modelId}`);
console.log(`Device: ${config.device}`);
```

---

## Configuration

### EdgeVedaConfig

Configuration interface for EdgeVeda initialization.

```typescript
interface EdgeVedaConfig {
  modelId: string;
  device?: DeviceType;
  precision?: PrecisionType;
  wasmPath?: string;
  maxContextLength?: number;
  numThreads?: number;
  enableCache?: boolean;
  cacheName?: string;
  onProgress?: (progress: LoadProgress) => void;
  onError?: (error: Error) => void;
}
```

#### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `modelId` | `string` | *required* | Model identifier or URL to model files |
| `device` | `'webgpu' \| 'wasm' \| 'auto'` | `'auto'` | Device to run inference on |
| `precision` | `'fp32' \| 'fp16' \| 'int8' \| 'int4'` | `'fp16'` | Model precision/quantization |
| `wasmPath` | `string` | `undefined` | Path to WASM binary (for custom builds) |
| `maxContextLength` | `number` | `2048` | Maximum context length in tokens |
| `numThreads` | `number` | *auto* | Number of threads for WASM execution |
| `enableCache` | `boolean` | `true` | Enable model caching in IndexedDB |
| `cacheName` | `string` | `'edgeveda-models'` | Cache name for IndexedDB |
| `onProgress` | `(progress: LoadProgress) => void` | `undefined` | Progress callback for model loading |
| `onError` | `(error: Error) => void` | `undefined` | Error callback |

#### Example

```typescript
const config: EdgeVedaConfig = {
  modelId: 'llama-3.2-1b',
  device: 'webgpu',
  precision: 'int8',
  maxContextLength: 4096,
  enableCache: true,
  onProgress: (progress) => {
    console.log(`${progress.stage}: ${progress.progress}%`);
  },
  onError: (error) => {
    console.error('Init error:', error);
  },
};
```

---

## Generation Options

### GenerateOptions

Options for controlling text generation.

```typescript
interface GenerateOptions {
  prompt: string;
  maxTokens?: number;
  temperature?: number;
  topP?: number;
  topK?: number;
  repetitionPenalty?: number;
  stopSequences?: string[];
  seed?: number;
}
```

#### Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `prompt` | `string` | *required* | The input prompt text |
| `maxTokens` | `number` | `512` | Maximum number of tokens to generate |
| `temperature` | `number` | `0.7` | Sampling temperature (0.0-2.0) |
| `topP` | `number` | `0.9` | Top-p (nucleus) sampling |
| `topK` | `number` | `40` | Top-k sampling |
| `repetitionPenalty` | `number` | `1.1` | Repetition penalty (1.0 = none) |
| `stopSequences` | `string[]` | `[]` | Sequences that stop generation |
| `seed` | `number` | `undefined` | Random seed for reproducibility |

#### Example

```typescript
const options: GenerateOptions = {
  prompt: 'Explain quantum computing in simple terms:',
  maxTokens: 300,
  temperature: 0.8,
  topP: 0.95,
  topK: 50,
  repetitionPenalty: 1.2,
  stopSequences: ['\n\n', 'END'],
  seed: 42,
};
```

---

## Results and Streaming

### GenerateResult

Result object returned by `generate()`.

```typescript
interface GenerateResult {
  text: string;
  tokensGenerated: number;
  timeMs: number;
  tokensPerSecond: number;
  stopped: boolean;
  stopReason?: 'max_tokens' | 'stop_sequence' | 'error';
}
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `text` | `string` | Generated text |
| `tokensGenerated` | `number` | Number of tokens generated |
| `timeMs` | `number` | Time taken in milliseconds |
| `tokensPerSecond` | `number` | Generation speed |
| `stopped` | `boolean` | Whether generation stopped early |
| `stopReason` | `string` | Reason for stopping (if applicable) |

---

### StreamChunk

Chunk object yielded by `generateStream()`.

```typescript
interface StreamChunk {
  token: string;
  text: string;
  tokensGenerated: number;
  done: boolean;
  stats?: {
    timeMs: number;
    tokensPerSecond: number;
    stopReason?: 'max_tokens' | 'stop_sequence' | 'error';
  };
}
```

#### Properties

| Property | Type | Description |
|----------|------|-------------|
| `token` | `string` | Current token or text chunk |
| `text` | `string` | Cumulative generated text so far |
| `tokensGenerated` | `number` | Number of tokens generated so far |
| `done` | `boolean` | Whether this is the final chunk |
| `stats` | `object` | Statistics (only present in final chunk) |

---

### LoadProgress

Progress information during model loading.

```typescript
interface LoadProgress {
  stage: 'downloading' | 'caching' | 'loading' | 'initializing' | 'ready';
  progress: number;
  loaded?: number;
  total?: number;
  message?: string;
}
```

---

## Utility Functions

### `detectWebGPU(): Promise<WebGPUCapabilities>`

Detects WebGPU support and capabilities.

**Returns:** Promise resolving to WebGPUCapabilities

**Example:**
```typescript
import { detectWebGPU } from '@edgeveda/web';

const caps = await detectWebGPU();

if (caps.supported) {
  console.log('WebGPU available!');
  console.log('Adapter:', caps.adapter);
  console.log('Features:', caps.features);
} else {
  console.log('WebGPU not available:', caps.error);
}
```

---

### `supportsWasmThreads(): boolean`

Checks if WASM with threads is supported.

**Returns:** true if threading is supported

**Example:**
```typescript
import { supportsWasmThreads } from '@edgeveda/web';

if (supportsWasmThreads()) {
  console.log('Multi-threaded WASM is available');
}
```

---

### `getOptimalThreadCount(): number`

Gets the optimal number of threads for WASM execution.

**Returns:** Recommended thread count

**Example:**
```typescript
import { getOptimalThreadCount } from '@edgeveda/web';

const threads = getOptimalThreadCount();
console.log(`Using ${threads} threads`);
```

---

## Cache Management

### `listCachedModels(): Promise<CachedModelMetadata[]>`

Lists all cached models.

**Returns:** Promise resolving to array of model metadata

**Example:**
```typescript
import { listCachedModels } from '@edgeveda/web';

const models = await listCachedModels();
for (const model of models) {
  console.log(`${model.modelId}: ${(model.size / 1024 / 1024).toFixed(2)} MB`);
}
```

---

### `getCachedModel(modelId: string): Promise<CachedModel | null>`

Retrieves a specific cached model.

**Parameters:**
- `modelId` - Model identifier

**Returns:** Promise resolving to cached model or null

---

### `deleteCachedModel(modelId: string): Promise<void>`

Deletes a specific model from cache.

**Parameters:**
- `modelId` - Model identifier

**Returns:** Promise that resolves when deletion is complete

**Example:**
```typescript
import { deleteCachedModel } from '@edgeveda/web';

await deleteCachedModel('llama-3.2-1b');
```

---

### `clearCache(): Promise<void>`

Clears all cached models.

**Returns:** Promise that resolves when cache is cleared

**Example:**
```typescript
import { clearCache } from '@edgeveda/web';

await clearCache();
console.log('All models cleared');
```

---

### `getCacheSize(): Promise<number>`

Gets the total size of all cached models.

**Returns:** Promise resolving to total size in bytes

**Example:**
```typescript
import { getCacheSize } from '@edgeveda/web';

const size = await getCacheSize();
console.log(`Cache size: ${(size / 1024 / 1024).toFixed(2)} MB`);
```

---

### `estimateStorageQuota(): Promise<{usage, quota, available}>`

Estimates available storage quota.

**Returns:** Promise resolving to storage information

**Example:**
```typescript
import { estimateStorageQuota } from '@edgeveda/web';

const quota = await estimateStorageQuota();
console.log(`Used: ${(quota.usage / 1024 / 1024).toFixed(2)} MB`);
console.log(`Total: ${(quota.quota / 1024 / 1024).toFixed(2)} MB`);
console.log(`Available: ${(quota.available / 1024 / 1024).toFixed(2)} MB`);
```

---

## Convenience Functions

### `init(config: EdgeVedaConfig): Promise<EdgeVeda>`

Creates and initializes an EdgeVeda instance in one call.

**Parameters:**
- `config` - Configuration object

**Returns:** Promise resolving to initialized EdgeVeda instance

**Example:**
```typescript
import { init } from '@edgeveda/web';

const ai = await init({ modelId: 'llama-3.2-1b' });
const result = await ai.generate({ prompt: 'Hello!' });
await ai.terminate();
```

---

### `generate(config, options): Promise<GenerateResult>`

One-off text generation (creates, uses, and terminates instance).

**Parameters:**
- `config` - Configuration object
- `options` - Generation options

**Returns:** Promise resolving to GenerateResult

**Example:**
```typescript
import { generate } from '@edgeveda/web';

const result = await generate(
  { modelId: 'llama-3.2-1b' },
  { prompt: 'What is AI?', maxTokens: 100 }
);
console.log(result.text);
```

---

### `generateStream(config, options): AsyncGenerator<StreamChunk>`

One-off streaming generation.

**Parameters:**
- `config` - Configuration object
- `options` - Generation options

**Returns:** AsyncGenerator yielding StreamChunk objects

**Example:**
```typescript
import { generateStream } from '@edgeveda/web';

for await (const chunk of generateStream(
  { modelId: 'llama-3.2-1b' },
  { prompt: 'Tell me a joke', maxTokens: 100 }
)) {
  console.log(chunk.token);
}
```

---

## Types

### DeviceType

```typescript
type DeviceType = 'webgpu' | 'wasm' | 'auto';
```

### PrecisionType

```typescript
type PrecisionType = 'fp32' | 'fp16' | 'int8' | 'int4';
```

### WebGPUCapabilities

```typescript
interface WebGPUCapabilities {
  supported: boolean;
  adapter?: {
    vendor: string;
    architecture: string;
    device: string;
    description: string;
  };
  features?: string[];
  limits?: {
    maxBufferSize: number;
    maxStorageBufferBindingSize: number;
    maxComputeWorkgroupSizeX: number;
    maxComputeWorkgroupSizeY: number;
    maxComputeWorkgroupSizeZ: number;
  };
  error?: string;
}
```

### CachedModelMetadata

```typescript
interface CachedModelMetadata {
  modelId: string;
  timestamp: number;
  size: number;
  version: string;
  precision: PrecisionType;
  checksum?: string;
}
```

---

## Error Handling

All async methods can throw errors. Always use try-catch:

```typescript
try {
  const ai = new EdgeVeda({ modelId: 'llama-3.2-1b' });
  await ai.init();
  const result = await ai.generate({ prompt: 'Hello' });
  console.log(result.text);
} catch (error) {
  console.error('Error:', error.message);
} finally {
  await ai.terminate();
}
```

For initialization errors, use the `onError` callback:

```typescript
const ai = new EdgeVeda({
  modelId: 'llama-3.2-1b',
  onError: (error) => {
    console.error('Init error:', error.message);
    // Handle error (e.g., show UI notification)
  },
});
```

---

## Browser Compatibility

- **WebGPU**: Chrome/Edge 113+, Safari 18+, Firefox (experimental)
- **WASM**: All modern browsers
- **Threading**: Requires SharedArrayBuffer and COOP/COEP headers

---

## Performance Tips

1. Use `device: 'webgpu'` for 10-50x faster inference
2. Use lower precision (`int8`, `int4`) for smaller models
3. Keep `enableCache: true` to avoid re-downloading
4. Set `maxContextLength` to only what you need
5. Use streaming for better perceived performance

---

For more examples, see the [examples/](./examples/) directory and [README.md](./README.md).
