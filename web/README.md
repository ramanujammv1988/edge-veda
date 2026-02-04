# Edge Veda Web SDK

Browser-based Large Language Model inference using WebGPU and WebAssembly.

## Features

- **WebGPU Acceleration**: Automatic GPU detection and usage for high-performance inference
- **WASM Fallback**: CPU-based inference when WebGPU is unavailable
- **Model Caching**: Automatic model caching in IndexedDB for faster subsequent loads
- **Streaming Support**: Real-time token streaming for responsive UX
- **Web Worker Architecture**: Non-blocking inference using Web Workers
- **TypeScript**: Full type safety and excellent IDE support
- **Zero Dependencies**: Lightweight and self-contained

## Installation

```bash
npm install @edgeveda/web
```

Or via CDN:

```html
<script src="https://unpkg.com/@edgeveda/web/dist/edgeveda.min.js"></script>
```

## Quick Start

### Basic Usage

```typescript
import { EdgeVeda } from '@edgeveda/web';

// Create instance
const ai = new EdgeVeda({
  modelId: 'llama-3.2-1b',
  device: 'auto', // 'webgpu', 'wasm', or 'auto'
  precision: 'fp16',
});

// Initialize (downloads and loads model)
await ai.init();

// Generate text
const result = await ai.generate({
  prompt: 'What is the capital of France?',
  maxTokens: 100,
  temperature: 0.7,
});

console.log(result.text);
console.log(`Generated ${result.tokensGenerated} tokens in ${result.timeMs}ms`);
console.log(`Speed: ${result.tokensPerSecond.toFixed(2)} tokens/second`);

// Clean up
await ai.terminate();
```

### Streaming Generation

```typescript
import { EdgeVeda } from '@edgeveda/web';

const ai = new EdgeVeda({
  modelId: 'llama-3.2-1b',
});

await ai.init();

// Stream tokens as they're generated
for await (const chunk of ai.generateStream({
  prompt: 'Write a short story about a robot:',
  maxTokens: 200,
})) {
  process.stdout.write(chunk.token);

  if (chunk.done) {
    console.log('\n\nGeneration complete!');
    console.log(`Stats: ${chunk.stats?.tokensPerSecond.toFixed(2)} tokens/sec`);
  }
}

await ai.terminate();
```

### Progress Tracking

```typescript
const ai = new EdgeVeda({
  modelId: 'llama-3.2-1b',
  onProgress: (progress) => {
    console.log(`${progress.stage}: ${progress.progress.toFixed(1)}%`);
    if (progress.message) {
      console.log(progress.message);
    }
  },
  onError: (error) => {
    console.error('Error:', error.message);
  },
});

await ai.init();
```

### Convenience Functions

For one-off generations, use the convenience functions:

```typescript
import { generate, generateStream } from '@edgeveda/web';

// Non-streaming
const result = await generate(
  { modelId: 'llama-3.2-1b' },
  { prompt: 'Hello, world!', maxTokens: 50 }
);

// Streaming
for await (const chunk of generateStream(
  { modelId: 'llama-3.2-1b' },
  { prompt: 'Tell me a joke', maxTokens: 100 }
)) {
  console.log(chunk.token);
}
```

## Configuration

### EdgeVedaConfig

```typescript
interface EdgeVedaConfig {
  // Model identifier or URL to model files
  modelId: string;

  // Device to run inference on (default: 'auto')
  device?: 'webgpu' | 'wasm' | 'auto';

  // Model precision (default: 'fp16')
  precision?: 'fp32' | 'fp16' | 'int8' | 'int4';

  // Path to WASM binary (optional)
  wasmPath?: string;

  // Maximum context length (default: 2048)
  maxContextLength?: number;

  // Number of threads for WASM (default: auto-detected)
  numThreads?: number;

  // Enable model caching (default: true)
  enableCache?: boolean;

  // Cache name for IndexedDB (default: 'edgeveda-models')
  cacheName?: string;

  // Progress callback
  onProgress?: (progress: LoadProgress) => void;

  // Error callback
  onError?: (error: Error) => void;
}
```

### GenerateOptions

```typescript
interface GenerateOptions {
  // The input prompt
  prompt: string;

  // Maximum tokens to generate (default: 512)
  maxTokens?: number;

  // Sampling temperature 0.0-2.0 (default: 0.7)
  temperature?: number;

  // Top-p sampling (default: 0.9)
  topP?: number;

  // Top-k sampling (default: 40)
  topK?: number;

  // Repetition penalty (default: 1.1)
  repetitionPenalty?: number;

  // Stop sequences
  stopSequences?: string[];

  // Random seed for reproducibility
  seed?: number;
}
```

## Advanced Usage

### WebGPU Detection

```typescript
import { detectWebGPU } from '@edgeveda/web';

const capabilities = await detectWebGPU();

if (capabilities.supported) {
  console.log('WebGPU is supported!');
  console.log('Adapter:', capabilities.adapter);
  console.log('Features:', capabilities.features);
} else {
  console.log('WebGPU not available:', capabilities.error);
}
```

### Cache Management

```typescript
import {
  listCachedModels,
  getCacheSize,
  deleteCachedModel,
  clearCache,
  estimateStorageQuota,
} from '@edgeveda/web';

// List cached models
const models = await listCachedModels();
console.log('Cached models:', models);

// Get cache size
const size = await getCacheSize();
console.log(`Cache size: ${(size / 1024 / 1024).toFixed(2)} MB`);

// Delete a specific model
await deleteCachedModel('llama-3.2-1b');

// Clear all cache
await clearCache();

// Check storage quota
const quota = await estimateStorageQuota();
console.log(`Used: ${(quota.usage / 1024 / 1024).toFixed(2)} MB`);
console.log(`Available: ${(quota.available / 1024 / 1024).toFixed(2)} MB`);
```

### Custom Model URLs

```typescript
const ai = new EdgeVeda({
  modelId: 'https://example.com/models/custom-model.bin',
  wasmPath: 'https://example.com/wasm/edgeveda.wasm',
  precision: 'fp16',
});
```

### Thread Configuration

```typescript
import { getOptimalThreadCount, supportsWasmThreads } from '@edgeveda/web';

console.log('WASM threads supported:', supportsWasmThreads());
console.log('Optimal thread count:', getOptimalThreadCount());

const ai = new EdgeVeda({
  modelId: 'llama-3.2-1b',
  numThreads: 4, // Override auto-detection
});
```

## Browser Requirements

### WebGPU Mode (Recommended)
- Chrome 113+
- Edge 113+
- Safari 18+ (macOS Sonoma+)
- Firefox (experimental, requires flags)

### WASM Mode (Fallback)
- Any modern browser with WebAssembly support
- SharedArrayBuffer support for multi-threading
- Requires COOP/COEP headers for threading:
  ```
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: require-corp
  ```

## Performance Tips

1. **Use WebGPU**: Enable WebGPU for 10-50x faster inference
2. **Enable Caching**: Keep `enableCache: true` to avoid re-downloading models
3. **Choose Appropriate Precision**: Use `int4` or `int8` for smaller models and faster inference
4. **Optimize Context Length**: Set `maxContextLength` to only what you need
5. **Use Streaming**: Implement streaming for better perceived performance

## Example: Chat Interface

```typescript
import { EdgeVeda } from '@edgeveda/web';

class ChatBot {
  private ai: EdgeVeda;

  constructor() {
    this.ai = new EdgeVeda({
      modelId: 'llama-3.2-1b',
      onProgress: (progress) => {
        this.updateLoadingUI(progress);
      },
    });
  }

  async initialize() {
    await this.ai.init();
    console.log('Chat bot ready!');
  }

  async chat(message: string): Promise<string> {
    const result = await this.ai.generate({
      prompt: `User: ${message}\nAssistant:`,
      maxTokens: 200,
      temperature: 0.8,
    });

    return result.text.trim();
  }

  async *chatStream(message: string) {
    for await (const chunk of this.ai.generateStream({
      prompt: `User: ${message}\nAssistant:`,
      maxTokens: 200,
      temperature: 0.8,
    })) {
      yield chunk;
    }
  }

  async cleanup() {
    await this.ai.terminate();
  }

  private updateLoadingUI(progress: any) {
    // Update your UI with progress
    document.getElementById('progress').textContent =
      `${progress.stage}: ${progress.progress.toFixed(1)}%`;
  }
}

// Usage
const bot = new ChatBot();
await bot.initialize();

const response = await bot.chat('What is machine learning?');
console.log('Bot:', response);

await bot.cleanup();
```

## Troubleshooting

### WebGPU Not Available
- Ensure you're using a supported browser
- Check that hardware acceleration is enabled in browser settings
- Some browsers require experimental flags to be enabled

### SharedArrayBuffer Errors
- Set proper COOP/COEP headers on your server
- Or use single-threaded mode: `numThreads: 1`

### Model Loading Errors
- Check network connectivity
- Verify model URL is accessible
- Ensure sufficient storage quota is available

### Performance Issues
- Use WebGPU if available
- Reduce `maxContextLength` if not needed
- Use quantized models (int8/int4)
- Ensure WASM threads are enabled

## API Reference

See the [TypeScript definitions](./src/types.ts) for complete API documentation.

## License

MIT

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](../CONTRIBUTING.md) for details.

## Support

- GitHub Issues: https://github.com/edgeveda/sdk/issues
- Documentation: https://docs.edgeveda.dev
- Discord: https://discord.gg/edgeveda
