# Edge Veda SDK for React Native

On-device LLM inference for React Native with TurboModule support and the New Architecture.

## Features

- **TurboModule Support**: Built with React Native's New Architecture for maximum performance
- **On-Device Inference**: Run LLMs locally without internet connection
- **Streaming Generation**: Real-time token streaming with callbacks
- **Cross-Platform**: iOS and Android support with native implementations
- **Type-Safe**: Full TypeScript support with comprehensive type definitions
- **Memory Efficient**: Monitor and control memory usage
- **GPU Acceleration**: Automatic GPU acceleration when available (Metal on iOS, Vulkan on Android)

## Installation

```bash
npm install @edgeveda/react-native
# or
yarn add @edgeveda/react-native
```

### iOS

```bash
cd ios && pod install
```

### Android

No additional setup required. The package automatically links with autolinking.

## Requirements

- React Native >= 0.73.0
- iOS >= 13.0
- Android minSdkVersion >= 21

## Usage

### Initialize the Model

```typescript
import EdgeVeda from '@edgeveda/react-native';

// Initialize with model path
await EdgeVeda.init('/path/to/model.gguf', {
  maxTokens: 512,
  temperature: 0.7,
  useGpu: true,
  numThreads: 4,
});
```

### Generate Text

```typescript
// Simple generation
const response = await EdgeVeda.generate('What is the capital of France?');
console.log(response);

// With options
const response = await EdgeVeda.generate(
  'Explain quantum computing',
  {
    temperature: 0.8,
    maxTokens: 1024,
    systemPrompt: 'You are a helpful AI assistant.',
  }
);
```

### Streaming Generation

```typescript
await EdgeVeda.generateStream(
  'Write a short story',
  (token, isComplete) => {
    if (!isComplete) {
      // Handle each token
      console.log(token);
    } else {
      // Generation complete
      console.log('Done!');
    }
  },
  {
    temperature: 0.9,
    maxTokens: 2048,
  }
);
```

### Monitor Memory Usage

```typescript
const memoryUsage = EdgeVeda.getMemoryUsage();
console.log('Total memory:', memoryUsage.totalBytes);
console.log('Model memory:', memoryUsage.modelBytes);
console.log('KV cache:', memoryUsage.kvCacheBytes);
console.log('Available:', memoryUsage.availableBytes);
```

### Get Model Information

```typescript
const modelInfo = EdgeVeda.getModelInfo();
console.log('Model:', modelInfo.name);
console.log('Architecture:', modelInfo.architecture);
console.log('Parameters:', modelInfo.parameters);
console.log('Context length:', modelInfo.contextLength);
console.log('Quantization:', modelInfo.quantization);
```

### Unload Model

```typescript
await EdgeVeda.unloadModel();
```

## Configuration Options

### EdgeVedaConfig

```typescript
interface EdgeVedaConfig {
  maxTokens?: number;          // Default: 512
  temperature?: number;        // Default: 0.7 (0.0 - 2.0)
  topP?: number;              // Default: 0.9 (0.0 - 1.0)
  topK?: number;              // Default: 40
  repetitionPenalty?: number; // Default: 1.1
  numThreads?: number;        // Default: 4
  useGpu?: boolean;           // Default: true
  contextSize?: number;       // Default: 2048
  batchSize?: number;         // Default: 512
}
```

### GenerateOptions

```typescript
interface GenerateOptions {
  systemPrompt?: string;
  temperature?: number;
  maxTokens?: number;
  topP?: number;
  topK?: number;
  stopSequences?: string[];
}
```

## Error Handling

```typescript
import { EdgeVedaError, EdgeVedaErrorCode } from '@edgeveda/react-native';

try {
  await EdgeVeda.generate('Hello');
} catch (error) {
  if (error instanceof EdgeVedaError) {
    switch (error.code) {
      case EdgeVedaErrorCode.MODEL_NOT_LOADED:
        console.error('Model not loaded');
        break;
      case EdgeVedaErrorCode.OUT_OF_MEMORY:
        console.error('Out of memory');
        break;
      // Handle other error codes
    }
  }
}
```

## New Architecture

This package is built with React Native's New Architecture (TurboModules). It automatically works with both the old and new architecture.

To enable the New Architecture in your app:

### iOS
In your `Podfile`:
```ruby
use_frameworks!
ENV['RCT_NEW_ARCH_ENABLED'] = '1'
```

### Android
In your `gradle.properties`:
```properties
newArchEnabled=true
```

## Performance Tips

1. **Use GPU acceleration** when available by setting `useGpu: true`
2. **Adjust thread count** based on device capabilities
3. **Use streaming** for long-form generation to improve perceived latency
4. **Monitor memory usage** and unload models when not in use
5. **Choose appropriate quantization** - smaller models (Q4) are faster but less accurate

## Model Support

Edge Veda supports GGUF format models with various quantization levels:
- Q4_0, Q4_1 - 4-bit quantization (smallest, fastest)
- Q5_0, Q5_1 - 5-bit quantization (balanced)
- Q8_0 - 8-bit quantization (larger, more accurate)
- F16 - 16-bit floating point (largest, most accurate)

## Example App

See the [example](./example) directory for a complete React Native app demonstrating all features.

## Roadmap

- [ ] Web support via WebGPU
- [ ] Model download and caching utilities
- [ ] Chat conversation management
- [ ] Function calling support
- [ ] LoRA adapter support

## License

Apache-2.0

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](../../CONTRIBUTING.md) for details.

## Support

- GitHub Issues: https://github.com/edgeveda/edgeveda-sdk/issues
- Documentation: https://docs.edgeveda.com
- Email: support@edgeveda.com
