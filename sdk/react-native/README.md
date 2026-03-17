# @edgeveda/react-native

On-device AI inference for React Native — LLM, Vision, Speech, and Image Generation.

## Features

- TypeScript API with full type safety
- TurboModule (New Architecture) native modules
- Streaming token generation with callbacks
- iOS (Metal GPU) and Android (Vulkan) support
- Model management and memory stats

## Installation

```bash
npm install @edgeveda/react-native
cd ios && pod install
```

## Quick Start

```typescript
import { EdgeVeda } from '@edgeveda/react-native';

// Load model
const model = await EdgeVeda.loadModel({
  modelPath: '/path/to/model.gguf',
  maxTokens: 512,
});

// Single-shot generation
const response = await model.generate('What is AI?');
console.log(response.text);

// Streaming
const { cancel } = model.generateStream('Explain quantum computing', {
  onToken: (event) => process.stdout.write(event.token),
  onComplete: (response) => console.log('\nDone:', response.tokensPerSecond, 'tok/s'),
});

// Embeddings
const embedding = await model.embed('Hello world');
console.log('Dimensions:', embedding.dimensions);

// Cleanup
model.dispose();
```

## Architecture

```
TypeScript API
    ↓ TurboModule / Bridge
Native Module (Obj-C++ / Kotlin)
    ↓ ev_* C functions
C++ Core (llama.cpp)
    ↓
Metal (iOS) / Vulkan (Android)
```

## Platforms

- iOS 15+ (Metal GPU acceleration)
- Android API 24+ (Vulkan GPU acceleration)

## License

MIT
