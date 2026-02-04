# Quick Start Guide - Edge Veda Web SDK

## Installation

```bash
cd /Users/ram/Documents/explore/edge/web
npm install
```

## Build

```bash
npm run build
```

This will create:
- `dist/index.js` - ESM bundle
- `dist/index.cjs` - UMD bundle
- `dist/worker.js` - Web Worker bundle
- `dist/edgeveda.min.js` - Minified UMD bundle
- `dist/*.d.ts` - TypeScript definitions

## Development

```bash
npm run dev
```

Watch mode for development with auto-rebuild.

## Project Structure

```
web/
├── src/
│   ├── index.ts          - Main SDK entry point, EdgeVeda class
│   ├── worker.ts         - Web Worker for inference execution
│   ├── types.ts          - TypeScript type definitions
│   ├── wasm-loader.ts    - WASM module loading & WebGPU detection
│   └── model-cache.ts    - IndexedDB model caching
├── examples/
│   ├── basic.html        - Interactive browser demo
│   ├── streaming.ts      - Streaming generation example
│   └── cache-management.ts - Cache utilities example
├── dist/                 - Built bundles (generated)
├── package.json          - NPM package configuration
├── tsconfig.json         - TypeScript configuration
├── rollup.config.js      - Rollup bundler configuration
├── README.md             - Full documentation
└── QUICKSTART.md         - This file
```

## Core Components

### 1. EdgeVeda Class (`src/index.ts`)
Main SDK interface that:
- Creates and manages Web Worker
- Handles initialization with progress tracking
- Provides `generate()` for non-streaming inference
- Provides `generateStream()` for streaming inference
- Manages cleanup and resource disposal

### 2. Web Worker (`src/worker.ts`)
Background thread that:
- Loads WASM module
- Downloads and caches models
- Detects WebGPU capabilities
- Executes inference without blocking UI
- Streams tokens back to main thread

### 3. Type Definitions (`src/types.ts`)
Complete TypeScript definitions for:
- Configuration interfaces
- Generation options
- Worker message protocol
- Results and streaming chunks
- Progress tracking

### 4. WASM Loader (`src/wasm-loader.ts`)
Utilities for:
- WebGPU capability detection
- WASM module loading with progress
- Thread support detection
- Memory management helpers

### 5. Model Cache (`src/model-cache.ts`)
IndexedDB-based caching for:
- Model download with progress
- Persistent storage
- Cache invalidation
- Storage quota management

## Usage Examples

### Basic Generation

```typescript
import { EdgeVeda } from '@edgeveda/web';

const ai = new EdgeVeda({ modelId: 'llama-3.2-1b' });
await ai.init();

const result = await ai.generate({
  prompt: 'Hello, world!',
  maxTokens: 100,
});

console.log(result.text);
await ai.terminate();
```

### Streaming

```typescript
for await (const chunk of ai.generateStream({
  prompt: 'Write a story:',
  maxTokens: 200,
})) {
  process.stdout.write(chunk.token);
}
```

### Progress Tracking

```typescript
const ai = new EdgeVeda({
  modelId: 'llama-3.2-1b',
  onProgress: (progress) => {
    console.log(`${progress.stage}: ${progress.progress}%`);
  },
});
```

## Architecture

```
┌─────────────────────────────────────────┐
│         Browser Main Thread             │
│                                         │
│  ┌────────────────────────────────┐    │
│  │      EdgeVeda Instance         │    │
│  │  - Configuration               │    │
│  │  - Worker management           │    │
│  │  - Message handling            │    │
│  └────────────┬───────────────────┘    │
│               │ postMessage()           │
└───────────────┼─────────────────────────┘
                │
                ▼
┌─────────────────────────────────────────┐
│           Web Worker Thread             │
│                                         │
│  ┌────────────────────────────────┐    │
│  │      Worker Handler            │    │
│  │  - Model loading               │    │
│  │  - WASM initialization         │    │
│  │  - Inference execution         │    │
│  └────────────┬───────────────────┘    │
│               │                         │
│  ┌────────────▼───────────────────┐    │
│  │      WASM Module               │    │
│  │  - WebGPU compute (if avail.)  │    │
│  │  - CPU fallback                │    │
│  │  - Token generation            │    │
│  └────────────────────────────────┘    │
│                                         │
└─────────────────────────────────────────┘
        │                    │
        ▼                    ▼
┌─────────────┐    ┌──────────────────┐
│  IndexedDB  │    │   WebGPU/WASM    │
│  (Models)   │    │   (Compute)      │
└─────────────┘    └──────────────────┘
```

## Browser Requirements

### For WebGPU (Recommended)
- Chrome/Edge 113+
- Safari 18+ (macOS Sonoma+)
- Experimental Firefox

### For WASM Fallback
- Any modern browser with WebAssembly
- SharedArrayBuffer for multi-threading
- Requires COOP/COEP headers:
  ```
  Cross-Origin-Opener-Policy: same-origin
  Cross-Origin-Embedder-Policy: require-corp
  ```

## Next Steps

1. **Build the SDK**: `npm run build`
2. **Open examples**: Open `examples/basic.html` in a browser
3. **Integrate WASM**: Add actual WASM binaries to connect to real inference
4. **Test**: Try the TypeScript examples
5. **Customize**: Modify configuration for your use case

## Development Notes

### Current Status
This is a complete scaffold with:
- Full TypeScript implementation
- Worker-based architecture
- Comprehensive type safety
- Progress tracking
- Caching infrastructure
- Streaming support

### To Complete
1. Add actual WASM binaries for inference
2. Implement real WASM API bindings in worker.ts
3. Add model tokenizer
4. Add comprehensive tests
5. Add performance benchmarks
6. Add more example applications

### Key Design Decisions

1. **Web Worker Architecture**: Prevents blocking UI during inference
2. **IndexedDB Caching**: Persistent model storage across sessions
3. **WebGPU First**: Automatic GPU acceleration when available
4. **Streaming API**: AsyncGenerator for natural token streaming
5. **Type Safety**: Full TypeScript for better DX
6. **Zero Dependencies**: Self-contained for minimal bundle size

## Troubleshooting

### Build Issues
```bash
# Clean and rebuild
npm run clean
npm install
npm run build
```

### Type Errors
```bash
# Check types without building
npm run typecheck
```

### Worker Loading Issues
- Ensure CORS is configured for worker files
- Check browser console for detailed errors
- Verify COOP/COEP headers for SharedArrayBuffer

## Resources

- Main README: `README.md`
- Type Definitions: `src/types.ts`
- Examples: `examples/`
- Build Config: `rollup.config.js`

## Support

For issues and questions:
- GitHub Issues: https://github.com/edgeveda/sdk/issues
- Documentation: Full API docs in `README.md`
