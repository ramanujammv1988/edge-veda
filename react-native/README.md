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

- React Native >= 0.68.0
- iOS >= 13.0
- Android minSdkVersion >= 21
- Expo SDK >= 49 (with development builds only)

### Architecture Support

This package supports both React Native architectures:

- **Old Architecture (Bridge)**: React Native 0.68 - 0.72
- **New Architecture (TurboModules)**: React Native 0.73+

Architecture detection is automatic at build time - no configuration needed. The appropriate native module implementation is selected based on your app's architecture settings.

### Expo Support

Edge Veda works with Expo using **development builds** (not Expo Go):

```bash
# Install in Expo project
npx expo install @edgeveda/react-native

# Create development build
eas build --profile development --platform ios
eas build --profile development --platform android
```

**Important**: Edge Veda **does NOT work with Expo Go** because it requires native C++ code (llama.cpp) that cannot be bundled in Expo Go. You must create a development build or bare workflow project.

The package includes an Expo config plugin that automatically configures your project during `expo prebuild`.

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

## Architecture Configuration

### Dual Architecture Support

This package supports both React Native architectures with automatic detection:

- **Old Architecture (Bridge)**: Default for React Native 0.68-0.72
- **New Architecture (TurboModules)**: Default for React Native 0.73+

No code changes needed - the package automatically uses the appropriate implementation based on your app's architecture setting.

### Enabling New Architecture

The New Architecture provides better performance through synchronous native calls (TurboModules) and improved rendering (Fabric).

#### React Native (Bare Workflow)

**iOS** - In your `Podfile`:
```ruby
use_frameworks!
ENV['RCT_NEW_ARCH_ENABLED'] = '1'
```

Then run:
```bash
cd ios && pod install
```

**Android** - In `android/gradle.properties`:
```properties
newArchEnabled=true
```

#### Expo with Development Builds

Add to your `app.json` or `app.config.js`:
```json
{
  "expo": {
    "plugins": [
      [
        "@edgeveda/react-native"
      ]
    ]
  },
  "android": {
    "newArchEnabled": true
  },
  "ios": {
    "newArchEnabled": true
  }
}
```

Then create a development build:
```bash
npx expo prebuild
eas build --profile development
```

### Verifying Architecture

You can verify which architecture is being used:

**iOS**: Check Xcode build logs for "Building for New Architecture" or presence of `RCT_NEW_ARCH_ENABLED` flag

**Android**: Check `android/gradle.properties` for `newArchEnabled=true`

### Architecture Differences

| Feature | Old Architecture | New Architecture |
|---------|-----------------|------------------|
| Module Type | ReactContextBaseJavaModule | TurboModule |
| Method Calls | Asynchronous | Synchronous |
| Performance | Good | Excellent |
| JSI Support | No | Yes |
| React Native | 0.68-0.72 | 0.73+ |

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
